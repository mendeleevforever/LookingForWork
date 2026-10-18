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
--   Z  compressed a recipe list (C) compressed with LibCompress (Deflate, done by
--                 the game itself through C_EncodingUtil). Only sent when every
--                 request that triggered the list said it can read it (z = 1),
--                 so older versions keep getting plain C messages.
--   X  collected  profession data I collected about people OUTSIDE the guild
--                 (from profession links). Each entry says who it's about
--                 (name, realm, guild), how and when it was obtained and who
--                 collected it. Sent as "everything after collection number N":
--                 Q carries the number I have from each collector. Receivers
--                 keep an entry only if it's newer than what they have, so old
--                 data never replaces new data. Always compressed.
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
local LibCompress = LibStub("LibCompress", true)
local Encoder     = LibCompress and LibCompress:GetAddonEncodeTable()   -- escapes \000 for the addon channel
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
local COMPRESSED_MARK         = "Z:"   -- compressed messages start with this (AceSerializer output starts with "^1")
local MAX_COMPRESSED_BYTES    = 49152  -- a 600-recipe list is about 12 KB compressed
local MAX_DECOMPRESSED_BYTES  = 524288
local SEEN_PER_MSG            = 20     -- collected people per X message
local SEEN_REPLY_MIN          = 2
local SEEN_REPLY_MAX          = 7
local REQUEST_DELAY_MIN       = 2      -- wait before asking for a recipe list...
local REQUEST_DELAY_MAX       = 6      -- ...so someone else's ask can cover it
local REQUEST_RETRY           = 600    -- ask for the same recipe list at most every 10 min
local TARGETED_DELAY_MIN      = 1      -- answering a request addressed to me
local TARGETED_DELAY_MAX      = 3

LFW.recentSends     = {}   -- guid -> { rev, time } (what I broadcast lately)
LFW.recentCatalogs  = {}   -- profKey -> { t = time, n = size } of the last list sent (by anyone)
LFW.pendingCatalogs = {}   -- profKey -> { timer }
LFW.pendingData     = {}   -- guid -> true (my characters to send soon)
LFW.pendingRequests = {}   -- profKey -> member short id to ask for its recipe list
LFW.lastRequested   = {}   -- profKey -> { t = time, n = size advertised } when I last asked

local function MyId() return ns.ShortId(UnitGUID("player")) end

-------------------------------------------------------------------------------
-- Sending
-------------------------------------------------------------------------------
local combatQueue, combatOrder = {}, {}

function LFW:InitComm()
    self:RegisterComm(COMM_PREFIX, "OnCommReceived")
    self.commReady = true
end

-- Can this client compress and decompress recipe lists?
function LFW:CanCompress()
    return (LibCompress and Encoder and LibCompress.HasZlibCodecs and LibCompress:HasZlibCodecs()) and true or false
end

-- Addon messages can be blocked in combat, so they wait until combat ends.
-- compress: send it compressed (only for receivers known to read it)
function LFW:SendGuild(msg, prio, queueKey, compress)
    if not self.commReady or not IsInGuild() then return false end
    msg.v, msg.from = PROTOCOL, MyId()
    if InCombatLockdown() then
        queueKey = queueKey or tostring(msg)
        if not combatQueue[queueKey] then combatOrder[#combatOrder + 1] = queueKey end
        combatQueue[queueKey] = { msg, prio, compress }
        return true
    end
    local ok, data = pcall(Serializer.Serialize, Serializer, msg)
    if not ok or type(data) ~= "string" then return false end
    if compress and self:CanCompress() then
        local packed = LibCompress:CompressDeflate(data)
        local encoded = packed and Encoder:Encode(packed)
        if encoded and #encoded + #COMPRESSED_MARK < #data then
            self:Debug(("Compressed %s: %.1f KB -> %.1f KB"):format(tostring(msg.t), #data / 1024, (#encoded + 2) / 1024))
            data = COMPRESSED_MARK .. encoded
        end
    end
    -- Everything goes out at one priority. AceComm puts long messages back
    -- together per sender, and ChatThrottleLib can interleave the pieces of
    -- messages sent at different priorities, which would garble both. One
    -- priority keeps every piece in order.
    self:SendCommMessage(COMM_PREFIX, data, "GUILD", nil, "NORMAL")
    return true
end

function LFW:FlushCombatQueue()
    local order = combatOrder
    combatOrder = {}
    for _, key in ipairs(order) do
        local item = combatQueue[key]
        combatQueue[key] = nil
        if item then self:SendGuild(item[1], item[2], key, item[3]) end
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
            k = prof.k,                 -- compact known-recipe list; nil = recipes not scanned yet
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
                -- check it, then store it in the same compact (sorted) form we use
                local set = ns.DecodeIds(d.k)
                ok = set ~= nil
                if ok then prof.k, prof.n = ns.EncodeIds(set), ns.CountKeys(set) end
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
    local x, nx = {}, 0              -- collected data I already have, per collector
    for obs, rev in pairs(self.db.sync.collectSeen) do
        if nx < 100 then x[obs], nx = rev, nx + 1 end
    end
    self:SendGuild({ t = "Q", h = have, c = self:CatalogCounts(), z = self:CanCompress() and 1 or nil, x = x },
        "NORMAL", "Q")
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
-- Sizes of my recipe lists, as compared with guild members (see CatalogScore)
function LFW:CatalogCounts()
    local counts = {}
    for _, p in ipairs(ns.PROFESSIONS) do
        local n = self:CatalogScore(p.key)
        if n > 0 then counts[p.key] = n end
    end
    return counts
end

-- A list of this size (or bigger) went out recently, so mine adds nothing yet.
-- A list that has grown since it was last sent is never held back.
function LFW:CatalogRecentlySent(key, size)
    local r = self.recentCatalogs[key]
    return r and time() - r.t < CATALOG_QUIET and (size or self:CatalogScore(key)) <= r.n
end

function LFW:NoteCatalogSent(key, size)
    size = tonumber(size) or 0
    local r = self.recentCatalogs[key]
    if r and time() - r.t < CATALOG_QUIET and r.n > size then size = r.n end
    self.recentCatalogs[key] = { t = time(), n = size }
end

-- targeted: answering a request addressed to me (shorter wait)
-- readsCompressed: the asker can read compressed lists. If anyone who asked for
-- this list can't, it goes out uncompressed so they can read it too.
function LFW:ScheduleCatalog(key, targeted, readsCompressed)
    local pending = self.pendingCatalogs[key]
    if pending then
        if not readsCompressed then pending.compress = false end
        return
    end
    if self:CatalogRecentlySent(key) then return end
    local lo, hi = CATALOG_DELAY_MIN, CATALOG_DELAY_MAX
    if targeted then lo, hi = TARGETED_DELAY_MIN, TARGETED_DELAY_MAX end
    local delay = lo + math.random() * (hi - lo)
    self.pendingCatalogs[key] = {
        timer = C_Timer.NewTimer(delay, function() self:SendCatalog(key) end),
        compress = readsCompressed and true or false,
    }
end

function LFW:CancelCatalog(key, theirCount)
    local p = self.pendingCatalogs[key]
    if p and (tonumber(theirCount) or 0) >= self:CatalogScore(key) then
        p.timer:Cancel()
        self.pendingCatalogs[key] = nil
    end
end

-- A recipe list for this profession is on its way (or was just sent): no need to ask
-- size: how big the list on its way is (nil: drop regardless)
function LFW:DropCatalogRequest(key, size)
    local req = self.pendingRequests[key]
    if req and (size == nil or (tonumber(size) or 0) >= req.n) then
        self.pendingRequests[key] = nil
    end
end

-- Ask a member for a recipe list if theirs is bigger than mine, unless that
-- list is already on its way or I asked for a list this size recently.
function LFW:WantCatalog(key, theirSize, from, missingKnown)
    theirSize = tonumber(theirSize) or 0
    local mine = self:CatalogScore(key)
    if theirSize <= mine and not missingKnown then return end
    if self.pendingRequests[key] then return end
    if theirSize > 0 and self:CatalogRecentlySent(key, theirSize) then return end
    local r = self.lastRequested[key]
    if r and time() - r.t < REQUEST_RETRY and theirSize <= r.n then return end
    self.pendingRequests[key] = { from = from, n = theirSize }
    if not self.requestTimer then
        local delay = REQUEST_DELAY_MIN + math.random() * (REQUEST_DELAY_MAX - REQUEST_DELAY_MIN)
        self.requestTimer = C_Timer.NewTimer(delay, function()
            self.requestTimer = nil
            self:SendCatalogRequests()
        end)
    end
end

-- Data arrived from a member: ask them for any recipe list I'm missing.
-- theirCounts: the sender's recipe list sizes (nil from older versions)
function LFW:CheckMissingCatalogs(chars, theirCounts, from)
    if type(from) ~= "string" or #from > 20 then return end
    theirCounts = type(theirCounts) == "table" and theirCounts or {}
    for _, rec in ipairs(chars) do
        for key, prof in pairs(rec.profs) do
            -- recipes they know that my list lacks, or only has as a placeholder
            local missing = false
            if prof.k and prof.k ~= "" then
                local recipes = self.db.catalog[key] and self.db.catalog[key].recipes or {}
                local id = 0
                for tok in prof.k:gmatch("[^%.]+") do
                    id = id + (tonumber(tok, 36) or 0)
                    if not recipes[id] or not recipes[id].c then missing = true; break end
                end
            end
            self:WantCatalog(key, theirCounts[key], from, missing)
        end
    end
end

function LFW:SendCatalogRequests()
    local byMember = {}
    for key, req in pairs(self.pendingRequests) do
        byMember[req.from] = byMember[req.from] or {}
        table.insert(byMember[req.from], key)
        self.lastRequested[key] = { t = time(), n = req.n }
    end
    wipe(self.pendingRequests)
    for member, keys in pairs(byMember) do
        self:SendGuild({ t = "R", to = member, p = keys, z = self:CanCompress() and 1 or nil }, "NORMAL", "R" .. member)
        self:Debug(("Asked for recipe lists: %s"):format(table.concat(keys, ", ")))
    end
end

function LFW:HandleRequest(msg)
    if type(msg.p) ~= "table" then return end
    for i, key in ipairs(msg.p) do
        if i > #ns.PROFESSIONS then break end
        if ns.PROF_BY_KEY[key] then
            if msg.to == ns.ShortId(UnitGUID("player")) then
                if not self.db.settings.ignoreQueries and self:CatalogScore(key) > 0 then
                    self:ScheduleCatalog(key, true, msg.z == 1)
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
        e.full and "1" or "0",      -- "0": only a name (recipe learned, window not opened yet)
    }
    return table.concat(fields, ";")
end

function LFW:SendCatalog(key)
    local pending = self.pendingCatalogs[key]
    local compress = pending and pending.compress and self:CanCompress()
    self.pendingCatalogs[key] = nil
    if self.db.settings.ignoreQueries then return end
    local cat = self.db.catalog[key]
    local count = self:CatalogScore(key)
    if not cat or count == 0 then return end

    self:SendGuild({ t = "I", p = key, n = count }, "NORMAL", "I" .. key)
    self:NoteCatalogSent(key, count)

    local ids = {}
    for id in pairs(cat.recipes) do ids[#ids + 1] = id end
    table.sort(ids)
    -- compressed: the whole list in one message (it compresses better that way)
    local chunk = compress and math.max(#ids, 1) or CATALOG_CHUNK
    for i = 1, #ids, chunk do
        local cats, catIndex, entries = {}, {}, {}
        for j = i, math.min(i + chunk - 1, #ids) do
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
        self:SendGuild({ t = "C", p = key, n = count, cats = cats, e = entries }, "BULK", "C" .. key .. i, compress)
    end
    self:Debug(("Sent the %s recipe list (%d recipes%s)."):format(ns.ProfName(key), count, compress and ", compressed" or ""))
end

-------------------------------------------------------------------------------
-- Receiving
-------------------------------------------------------------------------------
function LFW:HandleQuery(msg)
    if not self.guildKey then return end
    if self.db.settings.ignoreQueries then
        -- not answering, but I can still ask the asker for lists better than mine
        local theirs = type(msg.c) == "table" and msg.c or {}
        for _, p in ipairs(ns.PROFESSIONS) do
            local their = tonumber(theirs[p.key]) or 0
            if their > self:CatalogScore(p.key) then self:WantCatalog(p.key, their, msg.from) end
        end
        return
    end
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

    -- my collected data the asker doesn't have yet (only versions that ask for it)
    if type(msg.x) == "table" then
        local have = tonumber(msg.x[self.db.sync.observer]) or 0
        if (self.db.sync.collectRev or 0) > have then self:ScheduleSeenSend(have) end
    end

    local theirs = type(msg.c) == "table" and msg.c or {}
    for _, p in ipairs(ns.PROFESSIONS) do
        local mine, their = self:CatalogScore(p.key), tonumber(theirs[p.key]) or 0
        if mine > 0 and mine > their then self:ScheduleCatalog(p.key, false, msg.z == 1) end
        -- the asker has a better list than mine: ask them for it
        if their > mine then self:WantCatalog(p.key, their, msg.from) end
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

-- compressed: arrived as one compressed message, so it may hold the whole list
function LFW:HandleCatalog(msg, sender, compressed)
    local key = msg.p
    if not ns.PROF_BY_KEY[key] or type(msg.e) ~= "table" then return end
    self:CancelCatalog(key, msg.n)
    self:DropCatalogRequest(key, msg.n)
    self:NoteCatalogSent(key, msg.n)

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
        if (not compressed and i > CATALOG_CHUNK * 2) or total >= ns.MAX_RECIPES_PER_PROF then break end
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
                -- Does the sender's entry have real details? (older versions
                -- don't say; then it does if it has a category, reagents or an item)
                local detailed
                if f[10] == "1" then detailed = true
                elseif f[10] == "0" then detailed = false
                else detailed = (f[3] or "") ~= "" or (f[4] or "") ~= "" or (f[5] or "") ~= "" end
                if detailed and e.full ~= true and (not e.full or (not e.r and not e.o)) then
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

-------------------------------------------------------------------------------
-- Collected data about people outside the guild
-------------------------------------------------------------------------------
local function PackSeen(rec, since, me)
    local p, any = {}, false
    for key, d in pairs(rec.profs) do
        if d.obs == me and d.cr and d.cr > since then
            p[key] = { l = d.lvl, m = d.max, k = d.k, pa = d.partial and 1 or nil, t = d.t, s = d.src,
                       b = d.by, lk = d.link, la = d.linkedAt, ch = d.ch }
            any = true
        end
    end
    if not any then return nil end
    return { id = rec.guid, n = rec.name, rl = rec.realm, c = rec.class, g = rec.gname, gn = rec.gnone and 1 or nil,
             rs = rec.rs, fa = rec.fa, p = p }
end

-- Send my own observations of people outside the guild made after number `since`
function LFW:SendSeen(since)
    if self.db.settings.ignoreQueries or not self.guildKey then return 0 end
    since = tonumber(since) or 0
    local me, entries = self.db.sync.observer, {}
    for guid, rec in pairs(self.db.seen) do
        -- only people my guild mates can deal with: same ruleset and faction as
        -- the character I'm on (which is in their guild)
        if not self:InMyGuild(guid) and not self.db.players[guid] and self:ContextMatches(rec) then
            local e = PackSeen(rec, since, me)
            if e then entries[#entries + 1] = e end
        end
    end
    local rev = self.db.sync.collectRev or 0
    if #entries == 0 then
        -- nothing (left) to send, but let others know they're up to date
        self:SendGuild({ t = "X", o = me, s = since, r = rev, e = {} }, "NORMAL", "X0", true)
        return 0
    end
    for i = 1, #entries, SEEN_PER_MSG do
        local slice = {}
        for j = i, math.min(i + SEEN_PER_MSG - 1, #entries) do slice[#slice + 1] = entries[j] end
        local last = i + SEEN_PER_MSG > #entries
        -- only the last message moves the receiver's "I have up to N" forward
        self:SendGuild({ t = "X", o = me, s = since, r = last and rev or nil, e = slice }, "BULK", "X" .. i, true)
    end
    if since <= (self.db.sync.collectSent or 0) then self.db.sync.collectSent = rev end
    self:Debug(("Shared %d collected people (after #%d)."):format(#entries, since))
    return #entries
end

-- Someone asked: answer after a short random wait (several askers -> one answer)
function LFW:ScheduleSeenSend(since)
    local p = self.pendingSeen
    if p then
        if since < p.since then p.since = since end
        return
    end
    p = { since = since }
    self.pendingSeen = p
    local delay = SEEN_REPLY_MIN + math.random() * (SEEN_REPLY_MAX - SEEN_REPLY_MIN)
    C_Timer.After(delay, function()
        self.pendingSeen = nil
        self:SendSeen(p.since)
    end)
end

-- New observations of my own: share them a minute later, at most every 5 minutes
function LFW:ScheduleSeenShare(delay)
    if self.seenShareTimer or not self.commReady then return end
    self.seenShareTimer = C_Timer.NewTimer(delay or AUTO_SHARE_DELAY, function()
        self.seenShareTimer = nil
        if self.db.settings.ignoreQueries or not self.guildKey then return end
        local since = time() - (self.db.sync.lastSeenShare or 0)
        if since < AUTO_SHARE_MIN_INTERVAL then
            self:ScheduleSeenShare(AUTO_SHARE_MIN_INTERVAL - since + 1)
            return
        end
        if (self.db.sync.collectRev or 0) > (self.db.sync.collectSent or 0) then
            self:SendSeen(self.db.sync.collectSent or 0)
            self.db.sync.lastSeenShare = time()
        end
    end)
end

local VALID_SOURCES = { link = true, member = true, directory = true, chat = true }

function LFW:HandleSeen(msg)
    local obs = msg.o
    if type(obs) ~= "string" or #obs > 16 or not obs:match("^%x+$") or obs == self.db.sync.observer then return end
    if type(msg.e) ~= "table" or not self.guildKey then return end
    local now, changed = time(), false
    for i, e in ipairs(msg.e) do
        if i > SEEN_PER_MSG * 2 then break end
        local guid = type(e) == "table" and e.id
        local mine = guid and (guid == UnitGUID("player") or (self.db.players[guid] and self.db.players[guid].mine))
        -- only people outside my guild: guild members come from their own addon
        -- or the guild directory
        if ns.ValidGuid(guid) and not mine and not self:InMyGuild(guid) and type(e.p) == "table" then
            local rec = self.db.seen[guid]
            local accepted = false
            for key, d in pairs(e.p) do
                if ns.PROF_BY_KEY[key] and type(d) == "table" then
                    local t = ClampNum(d.t, 0, now) or 0          -- a future date can't block updates
                    local cur = rec and rec.profs[key]
                    if not cur or t > (cur.t or 0) then           -- only newer data replaces what I have
                        local entry = {
                            lvl = ClampNum(d.l, 0, 1000), max = ClampNum(d.m, 0, 1000), t = t,
                            src = VALID_SOURCES[d.s] and d.s or "link", by = CleanText(d.b), obs = obs,
                            ch = CleanText(d.ch, 30), partial = d.pa == 1 or nil,
                        }
                        local ok = true
                        if d.k ~= nil then
                            local set = ns.DecodeIds(d.k)
                            if set then entry.k, entry.n = ns.EncodeIds(set), ns.CountKeys(set) else ok = false end
                        end
                        local _, _, _, link = ns.ParseTradeLink(d.lk)
                        if link and link:find(guid, 1, true) then entry.link, entry.linkedAt = link, ClampNum(d.la, 0, now) end
                        if cur and cur.link and (cur.linkedAt or 0) > (entry.linkedAt or 0) then
                            entry.link, entry.linkedAt, entry.ch = cur.link, cur.linkedAt, cur.ch   -- keep a newer link
                        end
                        if ok then
                            rec = rec or self:GetSeen(guid, true)
                            rec.profs[key] = entry
                            accepted, changed = true, true
                        end
                    end
                end
            end
            if accepted then
                local class = type(e.c) == "string" and e.c:match("^%u+$") and #e.c < 20 and e.c or nil
                self:SetSeenIdentity(rec, CleanText(e.n), CleanText(e.rl, 40), class)
                if e.g then rec.gname, rec.gnone = CleanText(e.g, 60), nil
                elseif e.gn == 1 then rec.gname, rec.gnone = nil, true end
                -- ruleset and faction: as sent, otherwise mine (a guild mate on
                -- my ruleset and faction only sends people who match theirs)
                local ctx = self:MyContext()
                rec.rs = ns.RULESETS[e.rs] and e.rs or rec.rs or ctx.rs
                rec.fa = ns.FACTIONS[e.fa] and e.fa or rec.fa or ctx.fa
                for _, p in pairs(rec.profs) do rec.updated = math.max(rec.updated or 0, p.t or 0) end
            end
        end
    end
    -- "I now have this collector's data up to number r" (only without gaps)
    local r = ClampNum(msg.r, 0, 2 ^ 30)
    if r then
        local have = self.db.sync.collectSeen[obs] or 0
        if (ClampNum(msg.s, 0, 2 ^ 30) or 0) <= have and r > have then self.db.sync.collectSeen[obs] = r end
    end
    if changed then
        self:DataChanged(false)
        if self.PruneOutside then self:PruneOutside() end
    end
end

function LFW:OnCommReceived(prefix, data, distribution, sender)
    if prefix ~= COMM_PREFIX or distribution ~= "GUILD" or not self.db then return end
    if type(data) ~= "string" or #data > MAX_MSG_BYTES then return end
    local compressed = false
    if data:sub(1, #COMPRESSED_MARK) == COMPRESSED_MARK then
        -- a compressed recipe list; damaged or oversized ones are dropped
        if not self:CanCompress() or #data > MAX_COMPRESSED_BYTES then return end
        local okD, raw = pcall(function() return LibCompress:DecompressDeflate(Encoder:Decode(data:sub(#COMPRESSED_MARK + 1))) end)
        if not okD or type(raw) ~= "string" or #raw > MAX_DECOMPRESSED_BYTES then return end
        data, compressed = raw, true
    end
    local ok, msg = Serializer:Deserialize(data)
    if not ok or type(msg) ~= "table" then return end
    if compressed and msg.t ~= "C" and msg.t ~= "X" then return end   -- only these are ever compressed
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
        or (msg.t == "X" and self.HandleSeen)
        or nil
    if msg.t == "I" then
        if ns.PROF_BY_KEY[msg.p] then
            self:CancelCatalog(msg.p, msg.n)
            self:DropCatalogRequest(msg.p, msg.n)
            self:NoteCatalogSent(msg.p, msg.n)
        end
        return
    end
    if handler then
        local okH, err = pcall(handler, self, msg, sender, compressed)
        if not okH then self:Debug("message error: " .. tostring(err)) end
    end
end
