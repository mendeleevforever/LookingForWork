-- Collect.lua
-- Profession data about people who DON'T run Looking For Work ("collected"
-- data, kept in LookingForWorkDB.seen, separate from what members share):
--
--   * Profession links (option 2)
--       - links posted in chat are noticed automatically: who has which
--         profession, plus the link so it can be opened later (WoW Forever's
--         links only carry "trade:GUID:spell:skillLine", no recipes)
--       - opening a link reads the person's full recipe list, including the
--         recipes they don't know
--   * The game's guild directory (option 3)
--       - which guild members have which profession and their skill, offline
--         members included (the nine main professions; Cooking, First Aid and
--         Fishing aren't listed)
--   (On WoW Forever the directory's skill values are always 1, so they're
--   ignored; its "open this member's profession" doesn't open anything; and
--   its "who knows this recipe?" question stops being answered after a few
--   minutes of use, so none of these are used.)
--
-- Every collected entry records how it was obtained, who collected it and when,
-- and the ruleset (PvE, PvP, RP, Hardcore) and faction the person plays on.
-- Only people on the same ruleset and faction as the character you're logged
-- in on are shown (or shared): nobody else can trade or craft with you.
-- The owner's own shared data always wins over collected data (Core.lua
-- SourceFor). Data about people OUTSIDE the guild is shared with guild mates
-- (Comm.lua "X" messages); data about guild members isn't, because each
-- member's own addon or the guild directory is the better source.

local ADDON_NAME, ns = ...
local LFW = ns.LFW

-- How each entry was obtained
local SOURCES = {
    link      = "profession link",          -- a link that was opened: full recipe list
    member    = "guild directory recipes",  -- a guild member's profession opened from the directory
    directory = "guild directory",          -- guild directory: profession, skill, recipe checks
    chat      = "linked in chat",           -- seen a link in chat: profession only
}
ns.SOURCES = SOURCES

local MAX_OUTSIDE        = 3000   -- people outside the guild kept at most
local LINK_REPEAT        = 600    -- ignore the same person re-linking within 10 min
local CLICK_WINDOW       = 120    -- a link click and the window it opens belong together
local MEMBER_WINDOW      = 60
local DIR_REFRESH        = 600    -- re-read the directory's profession list every 10 min at most

local function Now() return time() end

local function Secret(v)
    return issecretvalue and v ~= nil and issecretvalue(v) or false
end

-------------------------------------------------------------------------------
-- Collected records
-------------------------------------------------------------------------------
function LFW:GetSeen(guid, create)
    local rec = self.db.seen[guid]
    if not rec and create then
        rec = { guid = guid, seen = true, profs = {}, updated = Now() }
        self.db.seen[guid] = rec
    end
    return rec
end

-- Name, realm and class from the game, when it knows them
local function PlayerInfo(guid)
    if not GetPlayerInfoByGUID then return nil end
    local ok, _, class, _, race, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
    if not ok or Secret(name) then return nil end
    return name, realm, class, race
end

-------------------------------------------------------------------------------
-- Ruleset and faction
-------------------------------------------------------------------------------
local RULESETS = { PvE = true, PvP = true, RP = true, Hardcore = true }
local FACTIONS = { Alliance = true, Horde = true }
ns.RULESETS, ns.FACTIONS = RULESETS, FACTIONS

local RACE_FACTION = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Draenei = "Alliance", Worgen = "Alliance",
    Orc = "Horde", Scourge = "Horde", Undead = "Horde", Tauren = "Horde", Troll = "Horde",
    BloodElf = "Horde", Goblin = "Horde",
}

-- The ruleset of the realm I'm on: Hardcore, RP, PvP, otherwise PvE
local function DetectRuleset()
    if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule) then return nil end
    local function on(rule)
        if rule == nil then return false end
        local ok, active = pcall(C_GameRules.IsGameRuleActive, rule)
        return ok and active and true or false
    end
    local g = Enum.GameRule
    if on(g.HardcoreRuleset) then return "Hardcore" end
    if on(g.RPRuleset) then return "RP" end
    if on(g.PvPRuleset) then return "PvP" end
    return "PvE"
end

local myContext
-- { rs = "PvP", fa = "Alliance" } for the character I'm logged in on
function LFW:MyContext()
    if not myContext or not myContext.rs or not myContext.fa then
        myContext = { rs = DetectRuleset(), fa = UnitFactionGroup and UnitFactionGroup("player") }
        if not FACTIONS[myContext.fa] then myContext.fa = nil end
    end
    return myContext
end

local function ServerOf(guid)
    return type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
end

-- Remember which ruleset each server belongs to (learned from my characters)
function LFW:LearnRealmRuleset()
    local ctx = self:MyContext()
    local server = ServerOf(UnitGUID("player"))
    if ctx.rs and server then self.db.realmRules[server] = ctx.rs end
end

-- The ruleset and faction a collected person plays on (nil when unknown)
function LFW:ContextOf(rec)
    local rs = rec.rs or self.db.realmRules[ServerOf(rec.guid) or ""]
    local fa = rec.fa
    if not fa then
        local _, _, _, race = PlayerInfo(rec.guid)
        fa = race and RACE_FACTION[race]
        if fa then rec.fa = fa end
    end
    return rs, fa
end

-- Can the character I'm logged in on trade and craft with this person?
-- People whose ruleset or faction isn't known are left out.
function LFW:ContextMatches(rec)
    local ctx = self:MyContext()
    local rs, fa = self:ContextOf(rec)
    if ctx.rs and rs ~= ctx.rs then return false end
    if ctx.fa and fa ~= ctx.fa then return false end
    return true
end

-- Tag someone I just saw: same ruleset as me (only people on my realms can
-- show up in my chat or links), faction from their race when the game knows
-- it, otherwise mine (chat and links only reach the same faction)
function LFW:TagContext(rec, unitFaction)
    local ctx = self:MyContext()
    rec.rs = ctx.rs or rec.rs
    local _, _, _, race = PlayerInfo(rec.guid)
    local fa = FACTIONS[unitFaction] and unitFaction or (race and RACE_FACTION[race]) or ctx.fa
    rec.fa = fa or rec.fa
end

-- Split "First Last-Realm" into name and realm, only when it really is a realm
-- (so a hyphenated last name like "Smith-Jones" is never cut):
--   * my own realm, or the realm the game reports for that GUID
--   * otherwise, for someone from another server, a last part without spaces
local function SplitRealm(full, knownRealm, guid)
    if type(full) ~= "string" then return nil end
    local name = ns.StripRealm(full)
    if not name then return nil end
    if name ~= full then return name, nil end                 -- it was my realm
    local candidates = {}
    if type(knownRealm) == "string" and knownRealm ~= "" then
        candidates[1] = knownRealm
        candidates[2] = (knownRealm:gsub("[%s%-']", ""))
    end
    for _, realm in ipairs(candidates) do
        local suffix = "-" .. realm
        if #full > #suffix and full:sub(-#suffix):lower() == suffix:lower() then
            return ns.CleanName(full:sub(1, -#suffix - 1)), realm
        end
    end
    local myServer = ServerOf(UnitGUID("player"))
    if guid and ServerOf(guid) and ServerOf(guid) ~= myServer then
        local base, realm = full:match("^(.+)%-([^%s%-]+)$")
        if base then return ns.CleanName(base), realm end
    end
    return ns.CleanName(full), nil
end

-- Keep the most complete name ("First Last" beats "First")
function LFW:SetSeenIdentity(rec, name, realm, class)
    name = ns.CleanName(name)
    if name and (not rec.name or #name >= #rec.name or not rec.name:find(" ", 1, true)) then rec.name = name end
    if type(realm) == "string" and realm ~= "" then
        local mine = GetNormalizedRealmName and GetNormalizedRealmName()
        if realm ~= mine and realm ~= GetRealmName() then rec.realm = realm end
    end
    if type(class) == "string" and class:match("^%u+$") then rec.class = class end
    local m = ns.roster.byGuid[rec.guid]
    if m then
        rec.gkey, rec.gname, rec.gnone = self.guildKey, self.guildName, nil
        rec.name, rec.class = m.name or rec.name, m.class or rec.class
    end
end

-- My own observation. Observations of people outside the guild are shared
-- with guild mates; each gets the next number of my collection revision so
-- guild mates can ask for "everything after number N".
function LFW:NoteObservation(rec, p)
    p.by, p.obs = ns.NameFromUnit("player"), self.db.sync.observer
    rec.updated = math.max(rec.updated or 0, p.t or Now())
    if not self:InMyGuild(rec.guid) then
        self.db.sync.collectRev = (self.db.sync.collectRev or 0) + 1
        p.cr = self.db.sync.collectRev
        if self.ScheduleSeenShare then self:ScheduleSeenShare() end
    else
        p.cr = nil
    end
end

local function IsMyCharacter(self, guid)
    if guid == UnitGUID("player") then return true end
    local own = self.db.players[guid]
    return own and own.mine or false
end

-- Members of my guild keep their guild info current; leaving the guild makes
-- them "outside" (their collected data can then be shared)
function LFW:SyncSeenGuild()
    if not ns.roster.loaded then return end
    for guid, rec in pairs(self.db.seen) do
        if ns.roster.byGuid[guid] then
            local m = ns.roster.byGuid[guid]
            rec.gkey, rec.gname, rec.gnone = self.guildKey, self.guildName, nil
            rec.name, rec.class = m.name or rec.name, m.class or rec.class
        elseif rec.gkey and rec.gkey == self.guildKey then
            rec.gkey, rec.gname = nil, nil       -- left the guild; guild unknown now
        end
    end
end

-- Keep at most MAX_OUTSIDE people from outside the guild (oldest go first)
function LFW:PruneOutside()
    local list = {}
    for guid, rec in pairs(self.db.seen) do
        if not self:InMyGuild(guid) then list[#list + 1] = rec end
    end
    if #list <= MAX_OUTSIDE then return end
    table.sort(list, function(a, b) return (a.updated or 0) < (b.updated or 0) end)
    for i = 1, #list - MAX_OUTSIDE do self.db.seen[list[i].guid] = nil end
    self:DataChanged(false)
end

function LFW:ForgetOutsideData()
    for guid in pairs(self.db.seen) do
        if not self:InMyGuild(guid) then self.db.seen[guid] = nil end
    end
    wipe(self.db.sync.collectSeen)     -- so guild mates' collections are fetched again
    self:DataChanged(false)
end

-- returns: shown (same ruleset and faction), found by me (of those), hidden
function LFW:OutsideCounts()
    local total, mine, hidden = 0, 0, 0
    local me = self.db.sync.observer
    for guid, rec in pairs(self.db.seen) do
        if not self:InMyGuild(guid) and not self.db.players[guid] then
            if self:ContextMatches(rec) then
                total = total + 1
                for _, p in pairs(rec.profs) do
                    if p.obs == me then mine = mine + 1; break end
                end
            else
                hidden = hidden + 1
            end
        end
    end
    return total, mine, hidden
end

-------------------------------------------------------------------------------
-- Opened profession windows (links, guild directory)
-------------------------------------------------------------------------------
local function ParseTradeLink(text)
    if type(text) ~= "string" then return nil end
    local guid, spell, line = text:match("trade:(Player%-%d+%-%x+):(%d+):(%d+)")
    if not guid then return nil end
    return guid, tonumber(spell), tonumber(line), ("trade:%s:%s:%s"):format(guid, spell, line)
end
ns.ParseTradeLink = ParseTradeLink

-- Called by the scan in Core.lua when a profession window shows someone else's
-- profession (a link, or a guild member opened from the guild directory)
function LFW:StoreObservedProfession(linkedName, prof, known, lvl, max, isGuildMember)
    local guid, link
    local q = self.lastMemberQuery
    if isGuildMember and q and GetTime() - q.time < MEMBER_WINDOW and q.key == prof.key then
        guid, q.answered = q.guid, true
        self.memberViewWorks = true
    end
    local l = self.lastTradeLink
    if not guid and l and GetTime() - l.time < CLICK_WINDOW and l.key == prof.key then guid, link = l.guid, l.link end
    local m
    if not guid and type(linkedName) == "string" then
        m = ns.roster.byName[ns.NameKey(ns.StripRealm(linkedName)) or ""]
        guid = m and m.guid
    end
    if not ns.ValidGuid(guid) or guid == UnitGUID("player") then return end

    -- one of my own alts: that's owner data
    local own = self.db.players[guid]
    if own and own.mine then
        local p = own.profs[prof.key] or {}
        p.k, p.n = ns.EncodeIds(known), ns.CountKeys(known)
        if lvl > 0 then p.lvl = lvl end
        if max > 0 then p.max = max end
        p.scanned = Now()
        own.profs[prof.key] = p
        self:BumpRecord(own)
        return
    end

    local rec = self:GetSeen(guid, true)
    local pname, prealm, pclass = PlayerInfo(guid)
    local name, realm = SplitRealm(linkedName, prealm, guid)
    self:SetSeenIdentity(rec, name or pname, realm or prealm, pclass)
    self:TagContext(rec)
    local p = rec.profs[prof.key] or {}
    local encoded = ns.EncodeIds(known)
    local src = isGuildMember and "member" or "link"
    -- the game refreshes an open profession window often; only a real change
    -- is saved again (and shared), otherwise the date is just confirmed
    local changed = p.k ~= encoded or p.partial or p.src ~= src
        or (lvl > 0 and p.lvl ~= lvl) or (max > 0 and p.max ~= max) or (link and p.link ~= link)
    p.t = Now()
    rec.updated = math.max(rec.updated or 0, p.t)
    rec.profs[prof.key] = p
    if not changed then return end
    p.k, p.n, p.partial = encoded, ns.CountKeys(known), nil
    if lvl > 0 then p.lvl = lvl end
    if max > 0 then p.max = max end
    p.src = src
    p.link = link or p.link
    self:NoteObservation(rec, p)
    self:DataChanged(false)
    self:Debug(("Saved %s's %s (%d recipes known) from a %s."):format(rec.name or "?", prof.name, p.n, SOURCES[p.src]))
end

-- Open someone's profession: from the guild directory for guild members,
-- or from a saved profession link for anyone else
-- Open someone's profession from their saved profession link. (The guild
-- directory's "open this member's profession" doesn't open anything on WoW
-- Forever, so links are the only way.)
function LFW:OpenProfessionOf(rec, key)
    if not rec or not ns.PROF_BY_KEY[key] then return false end
    local seen = self.db.seen[rec.guid]
    local p = seen and seen.profs[key]
    if p and p.link and SetItemRef then
        local text = "|H" .. p.link .. "|h[" .. ns.ProfName(key) .. "]|h"
        return pcall(SetItemRef, p.link, text, "LeftButton") and true or false
    end
    return false
end

function LFW:CanOpenProfessionOf(rec, key)
    local seen = rec and self.db.seen[rec.guid]
    return seen and seen.profs[key] and seen.profs[key].link and true or false
end

-------------------------------------------------------------------------------
-- Profession links in chat (option 2)
-------------------------------------------------------------------------------
local CHAT_EVENTS = {
    CHAT_MSG_CHANNEL = false,                 -- uses the channel's own name (Trade, General...)
    CHAT_MSG_GUILD = "Guild", CHAT_MSG_OFFICER = "Officer", CHAT_MSG_WHISPER = "Whisper",
    CHAT_MSG_SAY = "Say", CHAT_MSG_YELL = "Yell",
    CHAT_MSG_PARTY = "Party", CHAT_MSG_PARTY_LEADER = "Party",
    CHAT_MSG_RAID = "Raid", CHAT_MSG_RAID_LEADER = "Raid",
    CHAT_MSG_INSTANCE_CHAT = "Instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "Instance",
}

function LFW:NoteChatLink(guid, spell, line, link, sender, senderGuid, channel)
    local prof = ns.ResolveProfession(line)
    if not prof or not ns.ValidGuid(guid) or IsMyCharacter(self, guid) then return end
    local rec = self:GetSeen(guid, true)
    local p = rec.profs[prof.key]
    local now = Now()
    if p and p.linkedAt and now - p.linkedAt < LINK_REPEAT and p.link == link then return end
    local isNew = p == nil
    p = p or { src = "chat", t = now }
    p.link, p.linkedAt, p.ch = link, now, channel
    rec.profs[prof.key] = p
    self:TagContext(rec)
    local pname, prealm, pclass = PlayerInfo(guid)
    if senderGuid == guid then
        local name, realm = SplitRealm(sender, prealm, guid)
        self:SetSeenIdentity(rec, name, realm, nil)
    end
    self:SetSeenIdentity(rec, (not rec.name) and pname or nil, prealm, pclass)
    if isNew then self:NoteObservation(rec, p) end     -- new: they have this profession
    rec.updated = math.max(rec.updated or 0, now)
    if isNew then
        self:DataChanged(false)
        self.outsideAdded = (self.outsideAdded or 0) + 1
        if self.outsideAdded >= 50 then self.outsideAdded = 0; self:PruneOutside() end
    end
end

function LFW:OnChatMessage(event, text, sender, _, _, _, _, _, _, channelBaseName, _, _, senderGuid)
    if type(text) ~= "string" or Secret(text) or Secret(sender) or Secret(senderGuid) then return end
    if not text:find("|Htrade:", 1, true) then return end
    local channel = CHAT_EVENTS[event]
    if not channel then channel = (type(channelBaseName) == "string" and channelBaseName ~= "") and channelBaseName or "Channel" end
    for linkText in text:gmatch("|H(trade:[^|]+)|h") do
        local guid, spell, line, link = ParseTradeLink(linkText)
        if guid then self:NoteChatLink(guid, spell, line, link, sender, senderGuid, channel) end
    end
end

-- Their guild, when I target or mouse over someone I have collected data for
function LFW:CheckUnitGuild(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or Secret(guid) then return end
    local rec = self.db.seen[guid]
    if not rec or ns.roster.byGuid[guid] then return end
    local gname = GetGuildInfo(unit)
    if Secret(gname) then return end
    rec.gname, rec.gnone = gname, (gname == nil) or nil
    self:TagContext(rec, UnitFactionGroup and UnitFactionGroup(unit))
    local name = ns.NameFromUnit(unit)
    if name then self:SetSeenIdentity(rec, name, nil, select(2, UnitClass(unit))) end
end

-------------------------------------------------------------------------------
-- Guild directory: who has which profession (option 3)
-------------------------------------------------------------------------------
function LFW:CanReadDirectory()
    return IsInGuild() and GetNumGuildTradeSkill and GetGuildTradeSkillInfo and true or false
end

function LFW:RequestGuildDirectory(force)
    if not self:CanReadDirectory() then return end
    if not force and self.dirReadAt and GetTime() - self.dirReadAt < DIR_REFRESH then return end
    if QueryGuildRecipes then pcall(QueryGuildRecipes) end
    C_Timer.After(3, function() LFW:ReadGuildDirectory() end)
end

-- Read the directory one profession at a time. Expanding one profession can
-- collapse the others, so each is expanded, read and put back on its own.
-- A profession is only removed from a member when that profession's whole
-- member list was read (its count matched), so a half-loaded directory can
-- never wipe data.
function LFW:ReadGuildDirectory()
    if self.readingDirectory or not self:CanReadDirectory() or not self.guildKey or not ns.roster.loaded then return end
    self.readingDirectory = true
    -- offline members are only listed while "show offline members" is on
    local showOffline = GetGuildRosterShowOffline and GetGuildRosterShowOffline()
    local switched = false
    if not showOffline and SetGuildRosterShowOffline then switched = pcall(SetGuildRosterShowOffline, true) end
    local ok, err = pcall(function()
        local headers = {}
        for i = 1, GetNumGuildTradeSkill() or 0 do
            local skillID, isCollapsed, _, headerName = GetGuildTradeSkillInfo(i)
            if headerName and skillID then
                headers[#headers + 1] = { id = skillID, name = headerName, collapsed = isCollapsed and true or false }
            end
        end
        local now, changed = Now(), false
        for _, h in ipairs(headers) do
            local prof = ns.ResolveProfession(h.id, h.name)
            if prof then
                if h.collapsed and ExpandGuildTradeSkillHeader then pcall(ExpandGuildTradeSkillHeader, h.id) end
                local inside, total, rows, listed = false, nil, 0, {}
                for i = 1, GetNumGuildTradeSkill() or 0 do
                    local skillID, _, _, headerName, _, _, numPlayers, playerName, playerNameWithRealm, _, _, _, skill, classFileName = GetGuildTradeSkillInfo(i)
                    if headerName then
                        inside = skillID == h.id
                        if inside then total = tonumber(numPlayers) end
                    elseif inside then
                        rows = rows + 1
                        local m = ns.roster.byName[ns.NameKey(ns.StripRealm(playerNameWithRealm or playerName)) or ""]
                        if m and m.guid and not IsMyCharacter(self, m.guid) then
                            listed[m.guid] = true
                            local rec = self:GetSeen(m.guid, true)
                            self:SetSeenIdentity(rec, m.name, nil, classFileName or m.class)
                            local p = rec.profs[prof.key]
                            if not p then p = { src = "directory", t = now }; rec.profs[prof.key] = p; changed = true end
                            -- WoW Forever reports skill 1 for everyone: only a real
                            -- value is kept, and never over a better source's level
                            skill = tonumber(skill)
                            if skill and skill > 1 and p.src == "directory" and p.lvl ~= skill then p.lvl, changed = skill, true end
                            p.checked = now
                        end
                    end
                end
                if h.collapsed and CollapseGuildTradeSkillHeader then pcall(CollapseGuildTradeSkillHeader, h.id) end
                -- the whole list was read: members no longer listed lost the profession
                if total and rows == total then
                    for guid, rec in pairs(self.db.seen) do
                        local p = rec.profs[prof.key]
                        if p and p.src == "directory" and not p.k and ns.roster.byGuid[guid] and not listed[guid] then
                            rec.profs[prof.key] = nil
                            changed = true
                        end
                    end
                end
            end
        end
        -- guild members with nothing left
        for guid, rec in pairs(self.db.seen) do
            if next(rec.profs) == nil and ns.roster.byGuid[guid] then self.db.seen[guid] = nil end
        end
        if changed then self:DataChanged(false) end
    end)
    if switched then pcall(SetGuildRosterShowOffline, false) end
    self.readingDirectory = false
    self.dirReadAt = GetTime()
    self.dirReadTime = Now()
    if not ok then self:Debug("guild directory: " .. tostring(err)) end
end

-- Guild members whose professions the directory lists, and when it was read
function LFW:DirectoryStatus()
    local n = 0
    for guid, rec in pairs(self.db.seen) do
        if ns.roster.byGuid[guid] then
            for _, p in pairs(rec.profs) do
                if p.src == "directory" or p.checked then n = n + 1; break end
            end
        end
    end
    return n, self.dirReadTime
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    if not LFW.db then return end
    if CHAT_EVENTS[event] ~= nil then
        local ok, err = pcall(LFW.OnChatMessage, LFW, event, ...)
        if not ok then LFW:Debug("chat link: " .. tostring(err)) end
    elseif event == "GUILD_TRADESKILL_UPDATE" then
        if LFW.readingDirectory or (LFW.dirReadAt and GetTime() - LFW.dirReadAt < 2) then return end
        if LFW.dirReadTimer then LFW.dirReadTimer:Cancel() end
        LFW.dirReadTimer = C_Timer.NewTimer(1, function() LFW.dirReadTimer = nil; LFW:ReadGuildDirectory() end)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        LFW:CheckUnitGuild("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        LFW:CheckUnitGuild("target")
    end
end)

function LFW:InitCollect()
    myContext = nil
    self:LearnRealmRuleset()
    -- my own earlier observations without a ruleset/faction: if I made them on
    -- this character, they share its ruleset and faction
    local me = ns.NameFromUnit("player")
    for guid, rec in pairs(self.db.seen) do
        if not (rec.rs and rec.fa) and not self:InMyGuild(guid) then
            for _, p in pairs(rec.profs) do
                if p.by and p.by == me and p.obs == self.db.sync.observer then
                    local ctx = self:MyContext()
                    rec.rs, rec.fa = rec.rs or ctx.rs, rec.fa or ctx.fa
                    break
                end
            end
        end
    end
    for event in pairs(CHAT_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    for _, event in ipairs({ "GUILD_TRADESKILL_UPDATE",
                             "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    -- remember which profession link was clicked, so the window it opens can
    -- be matched to the right person (by GUID, not by name)
    if hooksecurefunc and SetItemRef then
        hooksecurefunc("SetItemRef", function(link)
            if Secret(link) then return end
            local guid, _, line, clean = ParseTradeLink(link)
            local prof = guid and ns.ResolveProfession(line)
            if prof then LFW.lastTradeLink = { guid = guid, key = prof.key, link = clean, time = GetTime() } end
        end)
    end
    C_Timer.After(45, function()
        LFW:RequestGuildDirectory(true)
        LFW:PruneOutside()
    end)
end
