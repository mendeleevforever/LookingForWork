-- Comm.lua
-- Sharing profession data with guild members who also use Looking For Work.
--
-- Everything goes over the GUILD addon channel only (never whispers, raids or
-- public channels), through AceComm-3.0 / ChatThrottleLib, which split long
-- messages and keep the send rate under the game's limits.
--
-- Messages (AceSerializer tables, all carry v = protocol, from = sender id):
--   Q  query      "send me your data"; lists the data revision I already have
--                 for every member, and how many recipes each of my recipe
--                 lists holds. Sent by the Update button, at most once a minute.
--   D  data       a member's own characters: professions, skill, known recipes.
--                 Only sent by a character's owner, and only if the asker's copy
--                 is out of date. Every addon user in the guild stores it, so one
--                 reply serves everybody.
--   I  intent     "I am about to send the Alchemy recipe list" (tiny). Others
--                 who planned to send the same list stand down.
--   C  catalog    a full recipe list (names, categories, reagents, icons) for
--                 one profession; only sent when the asker's list is smaller.
--   R  request    "please send your Tailoring recipe list" to one member. Sent
--                 automatically when their data arrives (D carries the size of
--                 the sender's recipe lists) and my list for that profession is
--                 smaller or is missing recipes they know.
--
-- "Ignore Queries" (Options) stops you (all your characters) from answering Q messages and
-- from sharing automatically; it still receives what others send.

local ADDON_NAME, ns = ...
local LFW = ns.LFW

local AceComm    = LibStub("AceComm-3.0")
local Serializer = LibStub("AceSerializer-3.0")
AceComm:Embed(LFW)

local COMM_PREFIX             = "LookingForWork"   -- max 16 characters
local PROTOCOL                = 1
LFW.QUERY_COOLDOWN            = 60     -- seconds between Update presses
local REPLY_DELAY_MIN         = 1      -- answers are spread over a few seconds
local REPLY_DELAY_MAX         = 6
local CATALOG_DELAY_MIN       = 4
local CATALOG_DELAY_MAX       = 15
local CATALOG_QUIET           = 120    -- don't resend a recipe list seen this recently
local REBROADCAST_WINDOW      = 45     -- don't resend unchanged data this quickly
local AUTO_SHARE_DELAY        = 60     -- wait after my data changes before sharing
local AUTO_SHARE_MIN_INTERVAL = 300    -- at most one automatic share per 5 minutes
local MAX_CHARS_PER_MSG       = 12
local CATALOG_CHUNK           = 120    -- recipes per C message
local MAX_MSG_BYTES           = 250000
local REQUEST_DELAY_MIN       = 2      -- wait before asking for a recipe list...
local REQUEST_DELAY_MAX       = 6      -- ...so someone else's ask can cover it
local REQUEST_RETRY           = 600    -- ask for the same recipe list at most every 10 min
local TARGETED_DELAY_MIN      = 1      -- answering a request addressed to me
local TARGETED_DELAY_MAX      = 3

LFW.recentSends     = {}   -- guid -> { rev, time } (what I broadcast lately)
LFW.recentCatalogs  = {}   -- profKey -> time a full list went out (by anyone)
LFW.pendingCatalogs = {}   -- profKey -> { timer }
LFW.pendingData     = {}   -- guid -> true (my characters to send soon)
LFW.pendingRequests = {}   -- profKey -> member short id to ask for its recipe list
LFW.lastRequested   = {}   -- profKey -> time I last asked for its recipe list

local function MyId() return ns.ShortId(UnitGUID("player")) end

-------------------------------------------------------------------------------
-- Sending
-------------------------------------------------------------------------------
local combatQueue, combatOrder = {}, {}

function LFW:InitComm()
    self:RegisterComm(COMM_PREFIX, "OnCommReceived")
    self.commReady = true
end

-- Addon messages can be blocked in combat, so they wait until combat ends.
function LFW:SendGuild(msg, prio, queueKey)
    if not self.commReady or not IsInGuild() then return false end
    msg.v, msg.from = PROTOCOL, MyId()
    if InCombatLockdown() then
        queueKey = queueKey or tostring(msg)
        if not combatQueue[queueKey] then combatOrder[#combatOrder + 1] = queueKey end
        combatQueue[queueKey] = { msg, prio }
        return true
    end
    local ok, data = pcall(Serializer.Serialize, Serializer, msg)
    if not ok or type(data) ~= "string" then return false end
    self:SendCommMessage(COMM_PREFIX, data, "GUILD", nil, prio or "NORMAL")
    return true
end

function LFW:FlushCombatQueue()
    local order = combatOrder
    combatOrder = {}
    for _, key in ipairs(order) do
        local item = combatQueue[key]
        combatQueue[key] = nil
        if item then self:SendGuild(item[1], item[2], key) end
    end
end

-------------------------------------------------------------------------------
-- Packing / unpacking records
-------------------------------------------------------------------------------
local function CleanText(s, maxLen)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s:sub(1, maxLen or ns.MAX_NAME_LEN)
end

local function ClampNum(n, lo, hi)
    n = tonumber(n)
    if not n then return nil end
    n = math.floor(n)
    if n < lo then n = lo elseif n > hi then n = hi end
    return n
end

local function PackRecord(rec)
    local p = {}
    for key, prof in pairs(rec.profs) do
        p[key] = {
            l = prof.lvl, m = prof.max, s = prof.scanned,
            k = prof.known and ns.EncodeIds(prof.known) or nil,   -- nil = recipes not scanned yet
        }
    end
    return { id = rec.guid, n = rec.name, c = rec.class, r = rec.rev, u = rec.updated, p = p }
end

local function UnpackProfs(p)
    local out = {}
    if type(p) ~= "table" then return out end
    for key, d in pairs(p) do
        if ns.PROF_BY_KEY[key] and type(d) == "table" then
            local prof = {
                lvl = ClampNum(d.l, 0, 1000),
                max = ClampNum(d.m, 0, 1000),
                scanned = ClampNum(d.s, 0, time() + 60),
            }
            local ok = true
            if d.k ~= nil then
                prof.known = ns.DecodeIds(d.k)
                ok = prof.known ~= nil
            end
            if ok then out[key] = prof end
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- My data -> guild
-------------------------------------------------------------------------------
-- only: optional set of my character GUIDs to send (default: all of them)
function LFW:BroadcastMyData(only)
    if not self.guildKey then return 0 end
    local now, chars = time(), {}
    for guid, rec in pairs(self.db.players) do
        if rec.mine and rec.guild == self.guildKey and (not only or only[guid]) then
            local last = self.recentSends[guid]
            if not (last and last.rev == rec.rev and now - last.time < REBROADCAST_WINDOW) then
                chars[#chars + 1] = PackRecord(rec)
                self.recentSends[guid] = { rev = rec.rev, time = now }
                self.db.sync.lastSent[guid] = rec.rev
            end
        end
    end
    for i = 1, #chars, MAX_CHARS_PER_MSG do
        local slice = {}
        for j = i, math.min(i + MAX_CHARS_PER_MSG - 1, #chars) do slice[#slice + 1] = chars[j] end
        self:SendGuild({ t = "D", ch = slice, c = self:CatalogCounts() }, "NORMAL", "D" .. i)
    end
    if #chars > 0 then self:Debug(("Shared data for %d character(s)."):format(#chars)) end
    return #chars
end

-- My characters in this guild whose data changed since I last shared it
function LFW:ChangedSinceShared()
    local set, any = {}, false
    if not self.guildKey then return set, false end
    for guid, rec in pairs(self.db.players) do
        if rec.mine and rec.guild == self.guildKey and self.db.sync.lastSent[guid] ~= rec.rev then
            set[guid], any = true, true
        end
    end
    return set, any
end

function LFW:ScheduleAutoShare(delay)
    if self.autoShareTimer or not self.commReady then return end
    self.autoShareTimer = C_Timer.NewTimer(delay or AUTO_SHARE_DELAY, function()
        self.autoShareTimer = nil
        self:AutoShare()
    end)
end

function LFW:AutoShare()
    if self.db.settings.ignoreQueries or not self.guildKey then return end
    local since = time() - (self.db.sync.lastAutoShare or 0)
    if since < AUTO_SHARE_MIN_INTERVAL then
        self:ScheduleAutoShare(AUTO_SHARE_MIN_INTERVAL - since + 1)
        return
    end
    local changed, any = self:ChangedSinceShared()
    if any and self:BroadcastMyData(changed) > 0 then
        self.db.sync.lastAutoShare = time()
    end
end

function LFW:LoginShare()
    self:AutoShare()
end

-------------------------------------------------------------------------------
-- Update button
-------------------------------------------------------------------------------
function LFW:QueryCooldown()
    local wait = self.QUERY_COOLDOWN - (time() - (self.db.sync.lastQuery or 0))
    return wait > 0 and wait or 0
end

function LFW:RequestUpdate()
    if not IsInGuild() then return false, "You are not in a guild." end
    self:RefreshGuild()
    if not self.guildKey then return false, "Guild information is still loading. Try again in a moment." end
    if not self.commReady then return false, "Still loading. Try again in a moment." end
    local wait = self:QueryCooldown()
    if wait > 0 then return false, ("You can ask again in %d seconds."):format(wait) end

    local have = {}
    for guid, rec in pairs(self.db.players) do
        if not rec.mine and rec.guild == self.guildKey then have[ns.ShortId(guid)] = rec.rev or 0 end
    end
    self:SendGuild({ t = "Q", h = have, c = self:CatalogCounts() }, "NORMAL", "Q")
    self.db.sync.lastQuery = time()
    self.queryState = { time = time(), replies = {} }
    self:RequestRoster()

    -- While asking, also hand out my own data if it changed (one message serves all)
    if not self.db.settings.ignoreQueries then
        local changed, any = self:ChangedSinceShared()
        if any then self:BroadcastMyData(changed) end
    end
    return true
end

function LFW:QueryReplies()
    local q = self.queryState
    if not q then return nil end
    return ns.CountKeys(q.replies), q.time
end

-------------------------------------------------------------------------------
-- Recipe lists
-------------------------------------------------------------------------------
function LFW:CatalogCounts()
    local counts = {}
    for _, p in ipairs(ns.PROFESSIONS) do
        local n = self:CatalogCount(p.key)
        if n > 0 then counts[p.key] = n end
    end
    return counts
end

-- targeted: answering a request addressed to me (shorter wait)
function LFW:ScheduleCatalog(key, targeted)
    if self.pendingCatalogs[key] then return end
    local last = self.recentCatalogs[key]
    if last and time() - last < CATALOG_QUIET then return end
    local lo, hi = CATALOG_DELAY_MIN, CATALOG_DELAY_MAX
    if targeted then lo, hi = TARGETED_DELAY_MIN, TARGETED_DELAY_MAX end
    local delay = lo + math.random() * (hi - lo)
    self.pendingCatalogs[key] = {
        timer = C_Timer.NewTimer(delay, function() self:SendCatalog(key) end),
    }
end

function LFW:CancelCatalog(key, theirCount)
    local p = self.pendingCatalogs[key]
    if p and (tonumber(theirCount) or 0) >= self:CatalogCount(key) then
        p.timer:Cancel()
        self.pendingCatalogs[key] = nil
    end
end

-- A recipe list for this profession is on its way (or was just sent): no need to ask
function LFW:DropCatalogRequest(key)
    self.pendingRequests[key] = nil
end

-- Data arrived from a member: ask them for any recipe list I'm missing.
-- theirCounts: the sender's recipe list sizes (nil from older versions)
function LFW:CheckMissingCatalogs(chars, theirCounts, from)
    if type(from) ~= "string" or #from > 20 then return end
    theirCounts = type(theirCounts) == "table" and theirCounts or {}
    local now = time()
    for _, rec in ipairs(chars) do
        for key, prof in pairs(rec.profs) do
            local mine = self:CatalogCount(key)
            local want = (tonumber(theirCounts[key]) or 0) > mine
            if not want and prof.known then
                local recipes = self.db.catalog[key] and self.db.catalog[key].recipes or {}
                for id in pairs(prof.known) do
                    if not recipes[id] then want = true; break end
                end
            end
            local recent = self.recentCatalogs[key] and now - self.recentCatalogs[key] < CATALOG_QUIET
            local asked = self.lastRequested[key] and now - self.lastRequested[key] < REQUEST_RETRY
            if want and not recent and not asked and not self.pendingRequests[key] then
                self.pendingRequests[key] = from
            end
        end
    end
    if next(self.pendingRequests) and not self.requestTimer then
        local delay = REQUEST_DELAY_MIN + math.random() * (REQUEST_DELAY_MAX - REQUEST_DELAY_MIN)
        self.requestTimer = C_Timer.NewTimer(delay, function()
            self.requestTimer = nil
            self:SendCatalogRequests()
        end)
    end
end

function LFW:SendCatalogRequests()
    local byMember = {}
    for key, member in pairs(self.pendingRequests) do
        byMember[member] = byMember[member] or {}
        table.insert(byMember[member], key)
        self.lastRequested[key] = time()
    end
    wipe(self.pendingRequests)
    for member, keys in pairs(byMember) do
        self:SendGuild({ t = "R", to = member, p = keys }, "NORMAL", "R" .. member)
        self:Debug(("Asked for recipe lists: %s"):format(table.concat(keys, ", ")))
    end
end

function LFW:HandleRequest(msg)
    if type(msg.p) ~= "table" then return end
    for i, key in ipairs(msg.p) do
        if i > #ns.PROFESSIONS then break end
        if ns.PROF_BY_KEY[key] then
            if msg.to == ns.ShortId(UnitGUID("player")) then
                if not self.db.settings.ignoreQueries and self:CatalogCount(key) > 0 then
                    self:ScheduleCatalog(key, true)
                end
            else
                -- someone else asked for this list; their answer reaches me too
                self:DropCatalogRequest(key)
            end
        end
    end
end

local function EntryString(id, e, catIndex)
    local fields = {
        ns.ToB36(id),
        (CleanText(e.n, 80) or ""):gsub(";", ","),
        catIndex or "",
        ns.EncodeReagents(e.r) or "",
        e.o and ns.ToB36(e.o) or "",
        (CleanText(e.q, 80) or ""):gsub(";", ","),
        e.qmin or "",
        e.qmax or "",
        type(e.i) == "number" and e.i > 0 and ns.ToB36(e.i) or "",
    }
    return table.concat(fields, ";")
end

function LFW:SendCatalog(key)
    self.pendingCatalogs[key] = nil
    if self.db.settings.ignoreQueries then return end
    local cat = self.db.catalog[key]
    local count = self:CatalogCount(key)
    if not cat or count == 0 then return end

    self:SendGuild({ t = "I", p = key, n = count }, "NORMAL", "I" .. key)
    self.recentCatalogs[key] = time()

    local ids = {}
    for id in pairs(cat.recipes) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids, CATALOG_CHUNK do
        local cats, catIndex, entries = {}, {}, {}
        for j = i, math.min(i + CATALOG_CHUNK - 1, #ids) do
            local id = ids[j]
            local e = cat.recipes[id]
            local ci
            if e.c then
                ci = catIndex[e.c]
                if not ci then
                    cats[#cats + 1] = (CleanText(e.c, 60) or "?"):gsub(";", ",") .. ";" .. (cat.cats[e.c] or 900)
                    ci = #cats
                    catIndex[e.c] = ci
                end
            end
            entries[#entries + 1] = EntryString(id, e, ci)
        end
        self:SendGuild({ t = "C", p = key, n = count, cats = cats, e = entries }, "BULK", "C" .. key .. i)
    end
    self:Debug(("Sent the %s recipe list (%d recipes)."):format(ns.ProfName(key), count))
end

-------------------------------------------------------------------------------
-- Receiving
-------------------------------------------------------------------------------
function LFW:HandleQuery(msg)
    if self.db.settings.ignoreQueries or not self.guildKey then return end
    local have = type(msg.h) == "table" and msg.h or {}
    local any = false
    for guid, rec in pairs(self.db.players) do
        if rec.mine and rec.guild == self.guildKey then
            if have[ns.ShortId(guid)] ~= rec.rev then
                self.pendingData[guid] = true
                any = true
            end
        end
    end
    if any and not self.replyTimer then
        local delay = REPLY_DELAY_MIN + math.random() * (REPLY_DELAY_MAX - REPLY_DELAY_MIN)
        self.replyTimer = C_Timer.NewTimer(delay, function()
            self.replyTimer = nil
            local only = self.pendingData
            self.pendingData = {}
            if not self.db.settings.ignoreQueries then self:BroadcastMyData(only) end
        end)
    end

    local theirs = type(msg.c) == "table" and msg.c or {}
    for _, p in ipairs(ns.PROFESSIONS) do
        local mine = self:CatalogCount(p.key)
        if mine > 0 and mine > (tonumber(theirs[p.key]) or 0) then self:ScheduleCatalog(p.key) end
    end
end

function LFW:HandleData(msg)
    if not self.guildKey or type(msg.ch) ~= "table" then return end
    local myGuid, roster = UnitGUID("player"), ns.roster
    local changed, received = false, {}
    for i, c in ipairs(msg.ch) do
        if i > MAX_CHARS_PER_MSG then break end
        if type(c) == "table" and ns.ValidGuid(c.id) and c.id ~= myGuid then
            local existing = self.db.players[c.id]
            local m = roster.byGuid[c.id]
            local allowed = not (existing and existing.mine) and (m or not roster.loaded)
            if allowed then
                local rev = ClampNum(c.r, 0, 2 ^ 30) or 0
                if not existing or rev > (existing.rev or 0) or existing.guild ~= self.guildKey then
                    local class = type(c.c) == "string" and c.c:match("^%u+$") and #c.c < 20 and c.c or nil
                    self.db.players[c.id] = {
                        guid    = c.id,
                        name    = (m and m.name) or CleanText(c.n) or (existing and existing.name) or "?",
                        class   = (m and m.class) or class,
                        guild   = self.guildKey,
                        rev     = rev,
                        updated = ClampNum(c.u, 0, time()) or time(),
                        received = time(),
                        profs   = UnpackProfs(c.p),
                    }
                    changed = true
                end
                if self.db.players[c.id] then received[#received + 1] = self.db.players[c.id] end
                if self.queryState then self.queryState.replies[c.id] = true end
            end
        end
    end
    if changed then self:DataChanged(false) end
    if #received > 0 then self:CheckMissingCatalogs(received, msg.c, msg.from) end
end

function LFW:HandleCatalog(msg)
    local key = msg.p
    if not ns.PROF_BY_KEY[key] or type(msg.e) ~= "table" then return end
    self:CancelCatalog(key, msg.n)
    self:DropCatalogRequest(key)
    self.recentCatalogs[key] = time()

    local cat = self:GetCatalog(key)
    local catNames = {}
    if type(msg.cats) == "table" then
        for i, s in ipairs(msg.cats) do
            if i > 300 then break end
            if type(s) == "string" then
                local name, order = s:match("^(.-);(%d+)$")
                name = CleanText(name, 60)
                if name then
                    catNames[i] = name
                    order = tonumber(order) or 900
                    if not cat.cats[name] then cat.cats[name] = order end
                end
            end
        end
    end

    local added, total = 0, ns.CountKeys(cat.recipes)
    for i, s in ipairs(msg.e) do
        if i > CATALOG_CHUNK * 2 or total >= ns.MAX_RECIPES_PER_PROF then break end
        if type(s) == "string" and #s < 600 then
            local f = {}
            for field in (s .. ";"):gmatch("([^;]*);") do f[#f + 1] = field end
            local id = tonumber(f[1] or "", 36)
            if id and id > 0 and id < 2147483647 then
                local e = cat.recipes[id]
                if not e then
                    e = {}
                    cat.recipes[id] = e
                    added, total = added + 1, total + 1
                end
                if not e.n then e.n = CleanText(f[2]) end
                if not e.c then e.c = catNames[tonumber(f[3] or "")] end
                if not e.i then
                    local icon = tonumber(f[9] or "", 36)
                    if icon and icon > 0 and icon < 2147483647 then e.i = icon end
                end
                if not e.full then
                    e.r = ns.DecodeReagents(f[4])
                    local out = tonumber(f[5] or "", 36)
                    e.o = (out and out > 0) and out or nil
                    e.q = CleanText(f[6], 80)
                    e.qmin, e.qmax = ClampNum(f[7], 1, 1000), ClampNum(f[8], 1, 1000)
                    e.full = 1          -- details came from a guild member
                end
            end
        end
    end
    if added > 0 then cat.rev = (cat.rev or 0) + 1 end
    self:DataChanged(false)      -- new recipes, categories, icons or reagents
end

function LFW:OnCommReceived(prefix, data, distribution, sender)
    if prefix ~= COMM_PREFIX or distribution ~= "GUILD" or not self.db then return end
    if type(data) ~= "string" or #data > MAX_MSG_BYTES then return end
    local ok, msg = Serializer:Deserialize(data)
    if not ok or type(msg) ~= "table" then return end
    if msg.v ~= PROTOCOL then
        if tonumber(msg.v) and msg.v > PROTOCOL and not self.warnedProtocol then
            self.warnedProtocol = true
            print(self.PREFIX .. "A guild member uses a newer version of Looking For Work. Update the addon to keep sharing with them.")
        end
        return
    end
    if msg.from == MyId() then return end     -- my own message coming back

    local handler = (msg.t == "Q" and self.HandleQuery)
        or (msg.t == "D" and self.HandleData)
        or (msg.t == "C" and self.HandleCatalog)
        or (msg.t == "R" and self.HandleRequest)
        or nil
    if msg.t == "I" then
        if ns.PROF_BY_KEY[msg.p] then
            self:CancelCatalog(msg.p, msg.n)
            self:DropCatalogRequest(msg.p)
            self.recentCatalogs[msg.p] = time()
        end
        return
    end
    if handler then
        local okH, err = pcall(handler, self, msg, sender)
        if not okH then self:Debug("message error: " .. tostring(err)) end
    end
end
