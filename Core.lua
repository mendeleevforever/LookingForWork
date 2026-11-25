local addonName, ns = ...
-- Core.lua
-- Looking For Work: collects profession data (every recipe of every profession
-- plus which recipes each character knows) and keeps it in LookingForWorkDB.
--
--   * Opening a profession window saves its full recipe list (learned AND
--     unlearned recipes, with reagents) and the recipes this character knows.
--   * Learning a new recipe is picked up straight away (NEW_RECIPE_LEARNED).
--   * Guild members who also use Looking For Work share their data over the
--     GUILD addon channel (see Comm.lua). The window lives in UI.lua.
--
-- WoW Forever names are "First-name Last-name", so names can contain spaces.
-- Players are stored by their whole GUID (never parsed: no realm or layer is
-- read from it). Whether a player GUID stays the same across sessions on
-- WoW Forever isn't verified yet.

local LFW = {}
ns.LFW = LFW
_G.LookingForWork = LFW

LFW.VERSION = "1.7.0"
LFW.PREFIX  = "|cffe6b422Looking For Work:|r "

local T = C_TradeSkillUI

-------------------------------------------------------------------------------
-- Professions (WoW Forever has the 12 original Classic professions; every one,
-- gathering professions included, has a crafting window)
-------------------------------------------------------------------------------
local PROFESSIONS = {
    { key = "alchemy", crafters = "Alchemists",        name = "Alchemy",        skillLine = 171, primary = true, icon = "Interface\\Icons\\Trade_Alchemy",       short = "Alc" },
    { key = "blacksmithing", crafters = "Blacksmiths",  name = "Blacksmithing",  skillLine = 164, primary = true, icon = "Interface\\Icons\\Trade_BlackSmithing",  short = "BS" },
    { key = "enchanting", crafters = "Enchanters",     name = "Enchanting",     skillLine = 333, primary = true, icon = "Interface\\Icons\\Trade_Engraving",      short = "Enc" },
    { key = "engineering", crafters = "Engineers",    name = "Engineering",    skillLine = 202, primary = true, icon = "Interface\\Icons\\Trade_Engineering",    short = "Eng" },
    { key = "herbalism", crafters = "Herbalists",      name = "Herbalism",      skillLine = 182, primary = true, icon = "Interface\\Icons\\Trade_Herbalism",      short = "Herb" },
    { key = "leatherworking", crafters = "Leatherworkers", name = "Leatherworking", skillLine = 165, primary = true, icon = "Interface\\Icons\\Trade_LeatherWorking", short = "LW" },
    { key = "mining", crafters = "Miners",         name = "Mining",         skillLine = 186, primary = true, icon = "Interface\\Icons\\Trade_Mining",         short = "Min" },
    { key = "skinning", crafters = "Skinners",       name = "Skinning",       skillLine = 393, primary = true, icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", short = "Skin" },
    { key = "tailoring", crafters = "Tailors",      name = "Tailoring",      skillLine = 197, primary = true, icon = "Interface\\Icons\\Trade_Tailoring",      short = "Tail" },
    { key = "cooking", crafters = "Chefs",        name = "Cooking",        skillLine = 185, icon = "Interface\\Icons\\INV_Misc_Food_15",          short = "Cook" },
    { key = "firstaid", crafters = "Physicians",       name = "First Aid",      skillLine = 129, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", short = "FA" },
    { key = "fishing", crafters = "Anglers",        name = "Fishing",        skillLine = 356, icon = "Interface\\Icons\\Trade_Fishing",             short = "Fish" },
}
ns.PROFESSIONS = PROFESSIONS

local PROF_BY_KEY, PROF_BY_LINE, PROF_BY_NAME = {}, {}, {}
for i, p in ipairs(PROFESSIONS) do
    p.order = i
    PROF_BY_KEY[p.key] = p
    PROF_BY_LINE[p.skillLine] = p
    PROF_BY_NAME[p.name:lower()] = p
end
PROF_BY_NAME["first-aid"] = PROF_BY_KEY.firstaid
PROF_BY_NAME["firstaid"]  = PROF_BY_KEY.firstaid
PROF_BY_NAME["smelting"]  = PROF_BY_KEY.mining
ns.PROF_BY_KEY = PROF_BY_KEY

-- Limits (also used to validate data received from other players)
ns.MAX_RECIPES_PER_PROF = 3000
ns.MAX_NAME_LEN         = 80

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------
local function Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
ns.Trim = Trim

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end
ns.SafeCall = SafeCall

-- Some APIs return a list, older ones return several values; accept both.
local function PackList(...)
    local first = ...
    if select("#", ...) == 1 and type(first) == "table" then return first end
    return { ... }
end
ns.PackList = PackList

local function tbl(v) return type(v) == "table" and v or {} end

-- Values from unit and chat APIs can be "secret" (Midnight's addon rules):
-- they can't be compared, branched on, concatenated or printed. Check first.
local function IsSecret(v)
    return issecretvalue ~= nil and v ~= nil and issecretvalue(v) or false
end
ns.IsSecret = IsSecret

-- My character's whole GUID (nil if the game won't say)
function ns.MyGuid()
    local guid = UnitGUID("player")
    if guid == nil or IsSecret(guid) then return nil end
    return guid
end

-- Tidy a player name: trim, collapse runs of spaces into one.
local function CleanName(name)
    if type(name) ~= "string" then return nil end
    name = Trim((name:gsub("%s+", " ")))
    if name == "" then return nil end
    return name
end
ns.CleanName = CleanName

-- Lookup key for a name (case-insensitive).
local function NameKey(name)
    name = CleanName(name)
    return name and name:lower() or nil
end
ns.NameKey = NameKey

-- Is this one of WoW Forever's internal server labels ("CAMWOWUS1Realm5PvE")?
-- Character names can never contain digits, so a "-..." ending with a digit
-- in it is never part of a name. WoW Forever doesn't use realms the way older
-- versions did: everyone on a ruleset is reached by name alone.
local function IsServerLabel(s)
    return type(s) == "string" and s ~= "" and not s:find(" ", 1, true) and s:find("%d") ~= nil
end
ns.IsServerLabel = IsServerLabel

-- Remove a "-Realm" suffix, but only when it really is a realm name, so a
-- hyphenated last name (e.g. "Anna Smith-Jones") is never cut.
-- (WoW Forever has no realms; realm names come back empty, so they're never
-- used. Only the labels above are removed.)
local function StripRealm(name)
    name = CleanName(name)
    if not name then return nil end
    -- an internal server label ("Bugs Frosty-CAMWOWUS1Realm5PvE" -> "Bugs Frosty")
    local base, label = name:match("^(.-)%-([^%-]+)$")
    if base and base ~= "" and IsServerLabel(label) then return CleanName(base) end
    return name
end
ns.StripRealm = StripRealm

-- On WoW Forever, UnitName(unit) returns TWO values: first name and surname.
-- GetUnitName(unit) returns the complete "First Surname" as one string.
-- Use both so the surname is always kept.
local function NameFromUnit(unit)
    if not unit then return nil end
    local exists, isPlayer = UnitExists(unit), UnitIsPlayer(unit)
    if IsSecret(exists) or IsSecret(isPlayer) or not exists or not isPlayer then return nil end
    local first, surname = UnitName(unit)
    if IsSecret(first) or IsSecret(surname) then return nil end
    if not first or first == "" or first == UNKNOWNOBJECT or first == UNKNOWN then return nil end
    if type(surname) == "string" and surname ~= "" then
        return CleanName(first .. " " .. surname)
    end
    if GetUnitName then
        local full = GetUnitName(unit, false)
        if type(full) == "string" and not IsSecret(full) then
            if FOREIGN_SERVER_LABEL and FOREIGN_SERVER_LABEL ~= "" then
                local label = FOREIGN_SERVER_LABEL
                if full:sub(-#label) == label then full = full:sub(1, -#label - 1) end
            end
            full = CleanName(full)
            if full and full:lower():find(first:lower(), 1, true) == 1 then return full end
        end
    end
    return CleanName(first)
end
ns.NameFromUnit = NameFromUnit

local function ColorName(name, class)
    name = name or "?"
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = class and colors and colors[class]
    if c then
        return ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name)
    end
    return "|cffe6d6ae" .. name .. "|r"
end
ns.ColorName = ColorName

function ns.FormatAgo(t)
    if type(t) ~= "number" or t <= 0 then return "never" end
    local d = time() - t
    if d < 60 then return "just now" end
    if d < 3600 then return ("%d min ago"):format(math.floor(d / 60)) end
    if d < 86400 then
        local h = math.floor(d / 3600)
        return h == 1 and "1 hour ago" or ("%d hours ago"):format(h)
    end
    local days = math.floor(d / 86400)
    return days == 1 and "1 day ago" or ("%d days ago"):format(days)
end

-- "Oct 16, 2026"
function ns.FormatDate(t)
    if type(t) ~= "number" or t <= 0 then return "unknown date" end
    return date("%b %d, %Y", t)
end

-- The last part of a player GUID. Only used to read requests from versions
-- before 1.7.0, which sent that instead of the whole GUID.
function ns.ShortId(guid)
    if type(guid) ~= "string" then return nil end
    return guid:match("%-(%x+)$") or guid
end

function ns.ValidGuid(guid)
    return type(guid) == "string" and #guid < 64 and guid:match("^Player%-[%w]+%-[%w]+$") ~= nil
end

function ns.CountKeys(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

-------------------------------------------------------------------------------
-- Compact encodings (used for saved data sent to guild members)
-------------------------------------------------------------------------------
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function ToB36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = B36:sub(d + 1, d + 1) .. s
        n = (n - d) / 36
    end
    return s
end
ns.ToB36 = ToB36

-- {[id]=true} -> sorted ids, each as the difference to the previous id, base 36
function ns.EncodeIds(set)
    local ids = {}
    for id in pairs(set or {}) do
        if type(id) == "number" and id > 0 then ids[#ids + 1] = math.floor(id) end
    end
    table.sort(ids)
    local out, prev = {}, 0
    for _, id in ipairs(ids) do
        if id ~= prev then
            out[#out + 1] = ToB36(id - prev)
            prev = id
        end
    end
    return table.concat(out, ".")
end

-- Returns a set, or nil if the string is malformed / too long
function ns.DecodeIds(s, max)
    local set, n, prev = {}, 0, 0
    if s == nil or s == "" then return set end
    if type(s) ~= "string" then return nil end
    for tok in s:gmatch("[^%.]+") do
        local d = tonumber(tok, 36)
        if not d or d < 0 then return nil end
        prev = prev + d
        n = n + 1
        if n > (max or ns.MAX_RECIPES_PER_PROF) then return nil end
        if prev > 0 and prev < 2147483647 then set[prev] = true end
    end
    return set
end

-- Known recipes are stored in this compact form too (about 2 KB per member
-- instead of about 40 KB as a Lua table). These read it without decoding it.
function ns.CountIds(s)
    if type(s) ~= "string" or s == "" then return 0 end
    local _, dots = s:gsub("%.", "")
    return dots + 1
end

-- Is this recipe in the list? (ids are sorted, so it stops early)
function ns.IdsHas(s, id)
    if type(s) ~= "string" or s == "" then return false end
    local prev = 0
    for tok in s:gmatch("[^%.]+") do
        prev = prev + (tonumber(tok, 36) or 0)
        if prev >= id then return prev == id end
    end
    return false
end

-- {{itemID, qty}, ...} <-> "itemB36:qty,itemB36:qty"
function ns.EncodeReagents(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, r in ipairs(list) do
        if type(r[1]) == "number" then out[#out + 1] = ToB36(r[1]) .. ":" .. math.floor(tonumber(r[2]) or 1) end
    end
    return #out > 0 and table.concat(out, ",") or nil
end

function ns.DecodeReagents(s)
    if type(s) ~= "string" or s == "" then return nil end
    local out = {}
    for item, qty in s:gmatch("([%w]+):(%d+)") do
        local id = tonumber(item, 36)
        if id and id > 0 and #out < 12 then out[#out + 1] = { id, math.min(tonumber(qty) or 1, 9999) } end
    end
    return #out > 0 and out or nil
end

-------------------------------------------------------------------------------
-- Game data helpers (spells, items)
-------------------------------------------------------------------------------
function ns.SpellName(id)
    if not id or not (C_Spell and C_Spell.GetSpellName) then return nil end
    local n = SafeCall(C_Spell.GetSpellName, id)
    if IsSecret(n) then return nil end
    return n
end

function ns.SpellIcon(id)
    if not id or not (C_Spell and C_Spell.GetSpellTexture) then return nil end
    return (SafeCall(C_Spell.GetSpellTexture, id))
end

function ns.ItemName(id)
    if not id or not C_Item then return nil end
    local n
    if C_Item.GetItemNameByID then n = SafeCall(C_Item.GetItemNameByID, id) end
    if not n and C_Item.GetItemInfo then n = (SafeCall(C_Item.GetItemInfo, id)) end
    if IsSecret(n) then return nil end
    return n
end

function ns.ItemIcon(id)
    if not id or not (C_Item and C_Item.GetItemIconByID) then return nil end
    return (SafeCall(C_Item.GetItemIconByID, id))
end

function ns.ItemLink(id)
    if not id or not (C_Item and C_Item.GetItemInfo) then return nil end
    local _, link = SafeCall(C_Item.GetItemInfo, id)
    return link
end

function ns.ItemQualityHex(id)
    local q
    if C_Item and C_Item.GetItemQualityByID then q = SafeCall(C_Item.GetItemQualityByID, id) end
    local c = q and not IsSecret(q) and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex end
    return "|cffffffff"
end

function ns.ItemCount(id)
    if not id or not (C_Item and C_Item.GetItemCount) then return 0 end
    return SafeCall(C_Item.GetItemCount, id, true, false, true) or 0
end

-- Item and spell data arrive later than they're asked for: request the load
-- and run the callbacks on ITEM_DATA_LOAD_RESULT / SPELL_DATA_LOAD_RESULT
-- (handled in the event table at the bottom of this file)
local itemWaiters, spellWaiters = {}, {}
ns.itemWaiters, ns.spellWaiters = itemWaiters, spellWaiters

-- Calls cb() once the item's data is in the client cache
function ns.LoadItem(id, cb)
    if not id or ns.ItemName(id) then return end
    local list = itemWaiters[id]
    if not list then
        list = {}
        itemWaiters[id] = list
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    if cb then list[#list + 1] = cb end
end

-- Calls cb() once the spell's data is in the client cache
function ns.LoadSpell(id, cb)
    if not id then return end
    local list = spellWaiters[id]
    if not list then
        list = {}
        spellWaiters[id] = list
        if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
    end
    if cb then list[#list + 1] = cb end
end

local function RunWaiters(waiters, id)
    local list = waiters[id]
    if not list then return end
    waiters[id] = nil
    for _, cb in ipairs(list) do pcall(cb) end
end
ns.RunItemWaiters = function(id) RunWaiters(itemWaiters, id) end
ns.RunSpellWaiters = function(id) RunWaiters(spellWaiters, id) end

-------------------------------------------------------------------------------
-- Tooltip text, so search can find recipes by what they do
-- ("defense" finds Enchant Bracer - Minor Deflect, "intellect" finds food
-- whose tooltip says it gives Intellect). Built once per recipe per session.
-------------------------------------------------------------------------------
local tipCache, tipPending = {}, {}
ns.tipCache = tipCache
local RETRIEVING = (RETRIEVING_ITEM_INFO or "Retrieving item information"):lower()

local function CleanTipText(s)
    if type(s) ~= "string" or s == "" then return nil end
    if issecretvalue and issecretvalue(s) then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|n", " "):gsub("[\r\n]", " "):gsub("%s+", " ")
    s = Trim(s)
    return s ~= "" and s or nil
end

-- C_TooltipInfo data (the modern API) -> plain lines
local function AddTooltipDataLines(data, out)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    for _, line in ipairs(data.lines) do
        if type(line) == "table" then
            if line.args and line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
                pcall(TooltipUtil.SurfaceArgs, line)
            end
            local l, r = CleanTipText(line.leftText), CleanTipText(line.rightText)
            if l then out[#out + 1] = l end
            if r then out[#out + 1] = r end
        end
    end
    return true
end

-- Fallback: read a hidden tooltip line by line
local scanTip
local function AddScanTooltipLines(setter, arg, out)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "LookingForWorkScanTooltip", nil, "GameTooltipTemplate")
    end
    if not scanTip or not scanTip[setter] then return false end
    scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not pcall(scanTip[setter], scanTip, arg) then scanTip:Hide(); return false end
    for i = 1, (scanTip:NumLines() or 0) do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G["LookingForWorkScanTooltipText" .. side .. i]
            local t = fs and CleanTipText(fs:GetText())
            if t then out[#out + 1] = t end
        end
    end
    scanTip:Hide()
    return true
end

local function TooltipLoaded(id)
    tipPending[id] = nil
    local c = tipCache[id]
    if c then c.incomplete, c.built = true, 0 end      -- rebuild on next search
    if LFW.OnSearchDataLoaded then LFW:OnSearchDataLoaded() end
end

local function SpellReady(id)
    if not (C_Spell and C_Spell.IsSpellDataCached) then return true end
    if SafeCall(C_Spell.IsSpellDataCached, id) then return true end
    if not tipPending[id] then
        tipPending[id] = true
        ns.LoadSpell(id, function() TooltipLoaded(id) end)
    end
    return false
end

-- The text of an item's "Use:" effect ("...well fed and gain 6 Stamina and
-- Spirit"). It belongs to a spell the game loads separately from the item, so
-- an item's tooltip can be read before it's there. It's read on its own here;
-- returns the text, or nil (and asks the game to load it) when it isn't ready.
local function Secret(v)
    return issecretvalue and v ~= nil and issecretvalue(v) or false
end

local function ItemEffectText(recipeID, itemID)
    local _, spellID = SafeCall(C_Item and C_Item.GetItemSpell, itemID)
    if not spellID or Secret(spellID) then return "" end    -- no "Use:" effect
    local desc = SafeCall(C_Spell and C_Spell.GetSpellDescription, spellID)
    if type(desc) == "string" and desc ~= "" and not Secret(desc) then return desc end
    local key = "effect" .. spellID
    if not tipPending[key] then
        tipPending[key] = true
        ns.LoadSpell(spellID, function()
            tipPending[key] = nil
            TooltipLoaded(recipeID)
        end)
    end
    return nil
end

local function ItemReady(recipeID, itemID)
    if ns.ItemName(itemID) then return true end
    if not tipPending[recipeID] then
        tipPending[recipeID] = true
        ns.LoadItem(itemID, function() TooltipLoaded(recipeID) end)
    end
    return false
end

local function BuildTooltipLines(id, e, lines)
    local incomplete = false
    if e then
        for _, saved in ipairs({ e.d or false, e.q or false }) do
            local t = saved and CleanTipText(saved)
            if t then lines[#lines + 1] = t end
        end
    end
    -- the recipe spell ("Permanently enchant bracers to increase Defense by 1")
    if SpellReady(id) then
        local got = C_TooltipInfo and C_TooltipInfo.GetSpellByID
            and AddTooltipDataLines(SafeCall(C_TooltipInfo.GetSpellByID, id), lines)
        if not got then AddScanTooltipLines("SetSpellByID", id, lines) end
    else
        incomplete = true
    end
    -- the item it makes ("Use: ... well fed and gain 6 Intellect")
    if e and e.o then
        if ItemReady(id, e.o) then
            local got = C_TooltipInfo and C_TooltipInfo.GetItemByID
                and AddTooltipDataLines(SafeCall(C_TooltipInfo.GetItemByID, e.o), lines)
            if not got then AddScanTooltipLines("SetItemByID", e.o, lines) end
            -- its "Use:" effect, which may not have been in the tooltip yet
            local effect = ItemEffectText(id, e.o)
            if effect == nil then
                incomplete = true
            elseif effect ~= "" then
                local t = CleanTipText(effect)
                if t then lines[#lines + 1] = t end
            end
        else
            incomplete = true
        end
    end
    return incomplete
end

-- Returns { lines = {...}, lower = {...} } for a recipe
function ns.GetTooltipSearch(id, e)
    local c = tipCache[id]
    if c and (not c.incomplete or GetTime() - c.built < 3) then return c end
    local tries = c and c.incomplete and (c.tries or 0) + 1 or 0
    c = { lines = {}, lower = {}, built = GetTime(), tries = tries }
    local ok, incomplete = pcall(BuildTooltipLines, id, e, c.lines)
    c.incomplete = (not ok or incomplete) and tries < 5      -- give up after a few tries
    for i, line in ipairs(c.lines) do
        local low = line:lower()
        if low:find(RETRIEVING, 1, true) and tries < 5 then c.incomplete = true end
        c.lower[i] = low
    end
    tipCache[id] = c
    return c
end

function ns.HasTooltipSearch(id)
    local c = tipCache[id]
    return c ~= nil and not c.incomplete
end

-------------------------------------------------------------------------------
-- Auction prices from Auctionator (same sources as AH Lookup)
--   1) Auctionator.API.v1.GetAuctionPriceByItemID / GetVendorPriceByItemID
--   2) fallback: Auctionator's saved price table, entry .m (latest minimum price)
-------------------------------------------------------------------------------
local AH_CUT = 0.95        -- the auction house keeps 5% of the sale price
ns.AH_CUT = AH_CUT
local CALLER = "LookingForWork"

local function API()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

function ns.AuctionatorLoaded()
    if API() then return true end
    return type(AUCTIONATOR_PRICE_DATABASE) == "table"
end

-- A realm price table maps "12345" to entries like { m = 1234, h = {...}, l = {...} }
local function IsPriceTable(t)
    if type(t) ~= "table" then return false end
    local checked = 0
    for _, v in pairs(t) do
        if type(v) == "table" and (v.m or v.h or v.l) then return true end
        checked = checked + 1
        if checked >= 25 then break end
    end
    return false
end

local priceDB, priceDBTime = nil, 0
-- Auctionator's price table for where I'm playing: its live database, or the
-- one plain table in its saved data (Auctionator keeps the current one as a
-- plain table while you play; others are packed strings). Realm names aren't
-- used: WoW Forever gives addons none.
local function FindPriceDB()
    if Auctionator and type(Auctionator.Database) == "table" and IsPriceTable(Auctionator.Database.db) then
        return Auctionator.Database.db
    end
    local root = AUCTIONATOR_PRICE_DATABASE
    if type(root) ~= "table" then return nil end
    local found
    for _, t in pairs(root) do
        if IsPriceTable(t) then
            if found then return nil end      -- more than one: can't tell which, use the API only
            found = t
        end
    end
    return found
end

local function PriceDB()
    if not priceDB and GetTime() - priceDBTime > 30 then
        priceDB, priceDBTime = FindPriceDB(), GetTime()
    end
    return priceDB
end

-- Auctionator's saved price table ({ ["itemID"] = { m = price } }), if found
function ns.AuctionatorPriceTable()
    return PriceDB()
end

function ns.ResetPriceCache()
    priceDB, priceDBTime = nil, 0
end

local function Positive(n) return type(n) == "number" and n > 0 and n or nil end

-- Latest auction price of one item, in copper (nil if Auctionator hasn't seen it)
function ns.AuctionPrice(itemID)
    if not itemID then return nil end
    local api = API()
    if api and api.GetAuctionPriceByItemID then
        local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
        if ok and Positive(price) then return price end
    end
    local db = PriceDB()
    if db then
        local v = db[tostring(itemID)] or db[itemID]
        if type(v) == "table" and Positive(v.m) then return v.m end
    end
    return nil
end

-- What a vendor sells it for (Auctionator remembers vendor prices it has seen)
function ns.VendorPrice(itemID)
    local api = API()
    if itemID and api and api.GetVendorPriceByItemID then
        local ok, price = pcall(api.GetVendorPriceByItemID, CALLER, itemID)
        if ok and Positive(price) then return price end
    end
    return nil
end

-- Days since Auctionator last saw the item on the auction house
function ns.AuctionAge(itemID)
    local api = API()
    if itemID and api and api.GetAuctionAgeByItemID then
        local ok, age = pcall(api.GetAuctionAgeByItemID, CALLER, itemID)
        if ok and type(age) == "number" then return age end
    end
    return nil
end

-- Cheapest way to get one reagent: vendor or auction house
function ns.ReagentPrice(itemID)
    local vendor, auction = ns.VendorPrice(itemID), ns.AuctionPrice(itemID)
    if vendor and (not auction or vendor <= auction) then return vendor, "vendor" end
    if auction then return auction, "auction" end
    return nil
end

-- Cost to craft a recipe and profit from selling what it makes
--   { cost, parts = { {itemID, qty, unit, total, source} }, missing = {itemID...},
--     outItem, outQty, outPrice, sale, profit, oldest }
function ns.CraftEconomics(e)
    if not e or not e.r then return nil end
    local info = { cost = 0, parts = {}, missing = {} }
    for _, r in ipairs(e.r) do
        local unit, source = ns.ReagentPrice(r[1])
        local part = { itemID = r[1], qty = r[2], unit = unit, source = source }
        if unit then
            part.total = unit * r[2]
            info.cost = info.cost + part.total
            if source == "auction" then
                local age = ns.AuctionAge(r[1])
                if age and (not info.oldest or age > info.oldest) then info.oldest = age end
            end
        else
            info.missing[#info.missing + 1] = r[1]
        end
        info.parts[#info.parts + 1] = part
    end
    info.cost = math.floor(info.cost + 0.5)
    if e.o then
        info.outItem = e.o
        info.outQty = (e.qmin and e.qmax) and ((e.qmin + e.qmax) / 2) or 1
        info.outPrice = ns.AuctionPrice(e.o)
        if info.outPrice then
            info.sale = info.outPrice * info.outQty
            info.profit = math.floor(info.sale * AH_CUT - info.cost + 0.5)
            local age = ns.AuctionAge(e.o)
            if age and (not info.oldest or age > info.oldest) then info.oldest = age end
        end
    end
    return info
end

-- Money with coin icons, like the game's own price displays
function ns.Coins(copper)
    if type(copper) ~= "number" then return "|cff9d9d9d—|r" end
    local negative = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local text
    if GetCoinTextureString then
        local ok, s = pcall(GetCoinTextureString, copper, 12)
        if ok and type(s) == "string" then text = s end
    end
    if not text then
        local g, sv, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
        local parts = {}
        if g > 0 then parts[#parts + 1] = ("|cffffd700%dg|r"):format(g) end
        if sv > 0 then parts[#parts + 1] = ("|cffc0c0c0%ds|r"):format(sv) end
        if c > 0 or #parts == 0 then parts[#parts + 1] = ("|cffb87333%dc|r"):format(c) end
        text = table.concat(parts, " ")
    end
    if negative then return "|cffff4040-|r" .. text end
    return text
end

-------------------------------------------------------------------------------
-- Profession lookup
-------------------------------------------------------------------------------
function ns.ProfName(p)
    if type(p) == "string" then p = PROF_BY_KEY[p] end
    return p and (p.display or p.name) or "?"
end

function ns.ProfIcon(p)
    if type(p) == "string" then p = PROF_BY_KEY[p] end
    if not p then return nil end
    local saved = LFW.db and LFW.db.icons[p.key]
    return saved or p.icon
end

-- Use the client's own (possibly localized) profession names as well
function ns.LocalizeProfessions()
    if not (T and T.GetTradeSkillDisplayName) then return end
    for _, p in ipairs(PROFESSIONS) do
        local n = SafeCall(T.GetTradeSkillDisplayName, p.skillLine)
        if type(n) == "string" and n ~= "" then
            PROF_BY_NAME[n:lower()] = p
            if GetLocale and GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then p.display = n end
        end
    end
end

-- Skill line ID and/or name -> profession entry
function ns.ResolveProfession(id, name)
    local db = LFW.db
    if type(id) == "number" and id > 0 then
        if db and db.skillLines[id] and PROF_BY_KEY[db.skillLines[id]] then return PROF_BY_KEY[db.skillLines[id]] end
        if PROF_BY_LINE[id] then return PROF_BY_LINE[id] end
    end
    if type(name) == "string" and name ~= "" then
        local lower = Trim(name):lower()
        local p = PROF_BY_NAME[lower]
        if not p then
            -- names such as "Classic Enchanting" or "Enchanting (Forever)"
            for n, prof in pairs(PROF_BY_NAME) do
                if #n > 3 and lower:find(n, 1, true) then p = prof; break end
            end
        end
        if p then
            if type(id) == "number" and id > 0 and db and not PROF_BY_LINE[id] then db.skillLines[id] = p.key end
            return p
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------
--[[
LookingForWorkDB = {
    settings  = { ignoreQueries = false, showUnowned = true, onlineOnly = false },
    catalog   = { [profKey] = { rev, scanned, cats = { [categoryName] = order },
                                recipes = { [recipeID] = { n = name, c = category, i = icon,
                                            r = { {itemID, qty}, ... }, o = outputItemID, oq = its quality,
                                            ri = recipe item that teaches it, rs = skill to learn it,
                                            st = where it's learned (the game's text),
                                            q = "Anvil", d = description, full = true } } } },
    players   = { [guid] = { guid, name, class, guild, rev, updated, mine,
                             profs = { [profKey] = { lvl, max, scanned,
                                       k = "known recipe ids, compact (nil = not scanned)",
                                       n = number of known recipes } } } },
    seen      = {   -- COLLECTED data about people (not shared by their own addon), by GUID
        [guid] = { guid, name = "First Last", realm, class, gname = "Their Guild" (nil = unknown),
                   gnone = true (known to have no guild), gt = when their guild was checked,
                   rs = "PvE"/"PvP"/"RP"/"Hardcore", fa = "Alliance"/"Horde",
                   gkey = "Realm|Guild" when they were in my guild, updated,
                   profs = { [profKey] = { lvl, max, k (nil = recipes not seen), n, partial,
                                           t = when this was observed, src = how,
                                           by = "First Last" who collected it, obs = their addon id,
                                           cr = my collection revision (my own observations),
                                           link = "trade:...", linkedAt, ch = channel } } } },
    sync      = { lastQuery, lastSent = { [guid] = rev }, lastAutoShare,
                  observer = "my addon id", collectRev, collectSent, collectSeen = { [observer] = rev } },
    minimap   = { minimapPos, hide },       -- minimap button (LibDBIcon)
    collapsed = { [profKey] = { [categoryName] = true } },
    icons, skillLines, positions
}
]]
local DEFAULT_SETTINGS = {
    ignoreQueries = false,   -- the Options "Ignore Queries" checkbox (default unchecked)
    showUnowned   = true,    -- list recipes nobody in the guild has
    onlineOnly    = false,   -- list only recipes with an online crafter
    showOutside   = true,    -- include crafters outside the guild (collected data)
    showKnown     = true,    -- recipes the character I'm on knows
    showUnknown   = true,    -- ...and doesn't know
    sortBy        = "name",  -- name, skill, price (to buy the recipe), craft (cost to craft), rarity, deprofit, vendorprofit
    groupByCategory = true,
    debug         = false,
}

function LFW:InitDB()
    local db = type(LookingForWorkDB) == "table" and LookingForWorkDB or {}
    LookingForWorkDB = db
    db.dbVersion  = 1
    db.settings   = tbl(db.settings)
    for k, v in pairs(DEFAULT_SETTINGS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    -- rarity filter: [0] Poor .. [5] Legendary, none = recipes that make no item
    db.settings.rarity = tbl(db.settings.rarity)
    for q = 0, 5 do if db.settings.rarity[q] == nil then db.settings.rarity[q] = true end end
    if db.settings.rarity.none == nil then db.settings.rarity.none = true end
    db.recipeVendors = tbl(db.recipeVendors)   -- [recipe item ID] = { c = copper, x = {currencies}, v = vendor, z = zone, t }
    db.positions  = tbl(db.positions)
    db.minimap    = tbl(db.minimap)        -- minimap button: { minimapPos = angle, hide = bool }
    db.collapsed  = tbl(db.collapsed)
    db.catalog    = tbl(db.catalog)
    db.players    = tbl(db.players)
    db.sync       = tbl(db.sync)
    db.sync.lastSent = tbl(db.sync.lastSent)
    db.icons      = tbl(db.icons)
    db.skillLines = tbl(db.skillLines)
    db.seen       = tbl(db.seen)
    db.realmRules = nil                     -- (removed in 1.7.0: rulesets aren't worked out from realms)
    db.guildNames = tbl(db.guildNames)      -- [guild key] = guild name, only for showing it
    db.dirChecked = nil      -- recipe questions to the guild directory aren't answered on WoW Forever
    db.sync.collectSeen = tbl(db.sync.collectSeen)
    db.sync.collectRev  = tonumber(db.sync.collectRev) or 0
    db.sync.collectSent = tonumber(db.sync.collectSent) or 0
    -- a random id for my collected data (12 hex digits; small numbers keep %x safe)
    if type(db.sync.observer) ~= "string" or not db.sync.observer:match("^%x+$") or #db.sync.observer > 16 then
        db.sync.observer = ("%04x%04x%04x"):format(math.random(0, 0xffff), math.random(0, 0xffff), math.random(0, 0xffff))
    end

    for key, cat in pairs(db.catalog) do
        if not PROF_BY_KEY[key] or type(cat) ~= "table" then
            db.catalog[key] = nil
        else
            cat.recipes = tbl(cat.recipes)
            cat.cats    = tbl(cat.cats)
            cat.rev     = tonumber(cat.rev) or 0
            for id, e in pairs(cat.recipes) do
                if type(id) ~= "number" or type(e) ~= "table" then
                    cat.recipes[id] = nil
                elseif e.full == 1 and not e.r and not e.o and not e.c then
                    e.full = nil      -- a name-only placeholder saved by an earlier version
                end
            end
        end
    end
    for guid, rec in pairs(db.players) do
        if type(rec) ~= "table" or not ns.ValidGuid(guid) then
            db.players[guid] = nil
        else
            rec.guid  = guid
            rec.rev   = tonumber(rec.rev) or 0
            rec.profs = tbl(rec.profs)
            for k, p in pairs(rec.profs) do
                if not PROF_BY_KEY[k] or type(p) ~= "table" then
                    rec.profs[k] = nil
                else
                    -- before 1.3.0 known recipes were a Lua table; now a compact string
                    if type(p.known) == "table" then
                        p.k = ns.EncodeIds(p.known)
                        p.n = ns.CountKeys(p.known)
                    end
                    p.known = nil
                    if type(p.k) ~= "string" then p.k = nil end
                    p.n = p.k and (tonumber(p.n) or ns.CountIds(p.k)) or nil
                end
            end
        end
    end
    -- seen (collected) records
    for guid, rec in pairs(db.seen) do
        if type(rec) ~= "table" or not ns.ValidGuid(guid) then
            db.seen[guid] = nil
        else
            rec.guid, rec.seen = guid, true
            rec.profs = tbl(rec.profs)
            for k, p in pairs(rec.profs) do
                if not PROF_BY_KEY[k] or type(p) ~= "table" then
                    rec.profs[k] = nil
                else
                    if type(p.k) ~= "string" then p.k = nil end
                    p.n = p.k and (tonumber(p.n) or ns.CountIds(p.k)) or nil
                    -- the guild directory's skill is always 1 on WoW Forever
                    if p.lvl == 1 and (p.src == "directory" or p.checked) then p.lvl = nil end
                end
            end
            if next(rec.profs) == nil then db.seen[guid] = nil end
        end
    end
    -- WoW Forever has no realms: realm fields aren't kept (1.7.0), and internal
    -- server labels are removed from saved names (1.5.1)
    for _, list in ipairs({ db.seen, db.players }) do
        for _, rec in pairs(list) do
            if type(rec) == "table" then
                rec.realm = nil
                if type(rec.name) == "string" then rec.name = StripRealm(rec.name) or rec.name end
            end
        end
    end

    -- Before 1.4.0, recipes read from a guild member's profession link were kept
    -- with the data members share themselves. They are collected data, so they
    -- move to db.seen (owner data always came with a "received" time).
    for guid, rec in pairs(db.players) do
        if not rec.mine and not rec.received and not db.seen[guid] then
            local moved = { guid = guid, seen = true, name = rec.name, class = rec.class,
                            gkey = rec.guild, updated = rec.updated, profs = {} }
            for k, p in pairs(rec.profs) do
                moved.profs[k] = { lvl = p.lvl, max = p.max, k = p.k, n = p.n,
                                   t = p.scanned or rec.updated, src = "link" }
            end
            db.seen[guid] = moved
            db.players[guid] = nil
        end
    end

    self.db = db
    self.index = {}
    self.crafterCache = {}
    self.indexDirty = true
end

function LFW:GetCatalog(key)
    local cat = self.db.catalog[key]
    if not cat then
        cat = { rev = 0, cats = {}, recipes = {} }
        self.db.catalog[key] = cat
    end
    return cat
end

function LFW:CatalogCount(key)
    local cat = self.db.catalog[key]
    return cat and ns.CountKeys(cat.recipes) or 0
end

-- How complete a recipe list is, for comparing with guild members: recipes
-- read from a profession window (they have a category). Placeholder entries
-- made when a recipe is learned (name only) don't count, so a list of three
-- learned recipes never looks "as good" as a full list.
function LFW:CatalogScore(key)
    local cat = self.db.catalog[key]
    if not cat then return 0 end
    local n = 0
    for _, e in pairs(cat.recipes) do
        if e.c then n = n + 1 end
    end
    return n
end

function LFW:Debug(msg)
    if self.db and self.db.settings.debug then print(self.PREFIX .. "|cff9c8d70" .. tostring(msg) .. "|r") end
end

-------------------------------------------------------------------------------
-- Guild
-------------------------------------------------------------------------------
-- Ruleset and region, read exactly as the WoW Forever addon guidelines say
-- (WoW Forever has regions and rulesets, no realms).
local REGION_CODES = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }

local function GetRegion()
  if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
    local info = C_BattleNet.GetGameAccountInfoByGUID(UnitGUID("player"))
    local id = info and info.regionID
    if id and REGION_CODES[id] then return REGION_CODES[id] end
  end
  if GetCurrentRegionName then
    local name = GetCurrentRegionName()
    if name and name ~= "" then return name end
  end
  if GetCurrentRegion then
    return REGION_CODES[GetCurrentRegion()] -- nil for unknown IDs; tell the user
  end
  return nil
end

local function GetRuleset()
  if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule) then
    return nil -- API missing on this build; tell the user
  end
  local function active(name)
    local id = Enum.GameRule[name]
    return id ~= nil and C_GameRules.IsGameRuleActive(id)
  end
  if active("HardcoreRuleset") then return "Hardcore" end
  if active("RPRuleset") then return "RP" end
  if active("PvPRuleset") then return "PvP" end
  return "PvE"
end

ns.GetRegion = function()
    local ok, r = pcall(GetRegion)
    return ok and r or nil
end
ns.GetRuleset = function()
    local ok, r = pcall(GetRuleset)
    return ok and r or nil
end

-- My guild's key: region + guild club ID ("US-503726411"). Guild data is
-- never keyed by guild name. The club ID can be nil until guild data loads
-- after login; then there's no key yet and it's read again on
-- PLAYER_GUILD_UPDATE / GUILD_ROSTER_UPDATE (a nil is never cached).
local function GuildKeyNow()
    if not (C_Club and C_Club.GetGuildClubId) then return nil end
    local ok, clubId = pcall(C_Club.GetGuildClubId)
    if not ok or clubId == nil or IsSecret(clubId) then return nil end
    return (ns.GetRegion() or "?") .. "-" .. tostring(clubId)
end

-- Data saved under this guild's older keys moves to the current key:
--   * "Realm|Guild Name" (before 1.6.2) and "Ruleset|Guild Name" (1.6.2),
--     matched by the guild's name once, unless the old key names a different
--     ruleset (e.g. "...PvP|..." while playing PvE)
--   * "?-<club ID>" saved while the region wasn't known yet
local function OldKeyRuleset(prefix)
    if type(prefix) ~= "string" then return nil end
    if prefix:find("Hardcore", 1, true) then return "Hardcore" end
    if prefix:find("PvP", 1, true) then return "PvP" end
    if prefix:find("PvE", 1, true) then return "PvE" end
    if prefix == "RP" or prefix:find("RP$") then return "RP" end
    return nil
end

function LFW:MigrateGuildKeys(key, guildName)
    local rs = ns.GetRuleset()
    local clubPart = key:match("%-(.+)$")
    local moved = 0
    local function convert(old)
        if type(old) ~= "string" or old == key then return nil end
        local prefix, name = old:match("^(.-)|(.+)$")
        if name then
            if name ~= guildName then return nil end
            local oldRs = OldKeyRuleset(prefix)
            if oldRs and rs and oldRs ~= rs then return nil end
            moved = moved + 1
            return key
        end
        if clubPart and old:match("%-(.+)$") == clubPart then
            moved = moved + 1
            return key
        end
        return nil
    end
    for _, rec in pairs(self.db.players) do
        local new = convert(rec.guild)
        if new then rec.guild = new end
    end
    for _, rec in pairs(self.db.seen or {}) do
        local new = convert(rec.gkey)
        if new then rec.gkey = new end
    end
    if moved > 0 then self:Debug(("Moved %d guild records to %s."):format(moved, key)) end
end

function LFW:RefreshGuild()
    if not IsInGuild() then
        self.guildKey, self.guildName = nil, nil
        return
    end
    local name = GetGuildInfo("player")
    if type(name) ~= "string" or name == "" or IsSecret(name) then name = nil end
    local key = GuildKeyNow()
    if not key then return end            -- guild data not loaded yet: try again later
    if name then self.db.guildNames[key] = name end   -- for showing it, never for matching
    local changed = key ~= self.guildKey
    if changed then
        self.guildKey, self.guildName = key, name or self.db.guildNames[key]
        self.indexDirty = true
    end
    -- move older saved keys over (again once the guild's name is known, since
    -- keys from before 1.7.0 were built from it)
    if changed or (self.guildName and self.guildName ~= self.migratedFor) then
        self:MigrateGuildKeys(key, self.guildName)
        self.migratedFor = self.guildName
    end
end

-- Online status comes from the guild roster (it lists offline members too)
local roster = { byGuid = {}, byName = {}, total = 0, online = 0, loaded = false }
ns.roster = roster

function LFW:RequestRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then
        pcall(GuildRoster)
    end
end

local function LastOnlineSeconds(index)
    if not GetGuildRosterLastOnline then return nil end
    local y, mo, d, h = GetGuildRosterLastOnline(index)
    if not y then return nil end
    return (((y * 365 + mo * 30 + d) * 24) + h) * 3600
end

function LFW:UpdateRoster()
    wipe(roster.byGuid)
    wipe(roster.byName)
    roster.total, roster.online, roster.loaded = 0, 0, false
    if not IsInGuild() or not GetNumGuildMembers then return end
    local total = GetNumGuildMembers() or 0
    local myGuid = ns.MyGuid()
    for i = 1, total do
        local name, rank, _, level, _, zone, _, _, online, _, class, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
        if IsSecret(name) or IsSecret(guid) or IsSecret(online) then name = nil end
        if name then
            local clean = StripRealm(name) or name
            local m = {
                raw = name, name = clean, rank = rank, level = level, zone = zone, class = class,
                online = online and not isMobile and true or false, mobile = (online and isMobile) and true or false,
                guid = guid,
            }
            if not m.online then m.offlineFor = LastOnlineSeconds(i) end
            if guid == myGuid then m.online, m.mobile = true, false end
            if guid then roster.byGuid[guid] = m end
            local key = NameKey(clean)
            if key then roster.byName[key] = m end
            roster.total = roster.total + 1
            if m.online then roster.online = roster.online + 1 end
        end
    end
    roster.loaded = roster.total > 0
    -- did someone join or leave (not just log on or off)? whole GUIDs compared
    local changed = roster.members == nil
    if roster.members then
        for guid in pairs(roster.byGuid) do
            if not roster.members[guid] then changed = true; break end
        end
        if not changed then
            for guid in pairs(roster.members) do
                if not roster.byGuid[guid] then changed = true; break end
            end
        end
    end
    roster.membershipChanged = roster.members ~= nil and changed
    roster.members = {}
    for guid in pairs(roster.byGuid) do roster.members[guid] = true end

    -- Keep stored names / classes in step with the roster
    for guid, rec in pairs(self.db.players) do
        local m = roster.byGuid[guid]
        if m and not rec.mine then
            rec.name = m.name or rec.name
            rec.class = m.class or rec.class
        end
    end
end

function LFW:MemberInfo(rec)
    if not rec then return nil end
    return (rec.guid and roster.byGuid[rec.guid]) or (rec.name and roster.byName[NameKey(rec.name)])
end

function LFW:IsMe(rec)
    return rec and rec.guid ~= nil and rec.guid == ns.MyGuid()
end

function LFW:IsOnline(rec)
    if self:IsMe(rec) then return true end
    local m = self:MemberInfo(rec)
    return m and m.online or false
end

-- Is this record one of the people we should list for the current guild?
function LFW:IsCurrentGuildRecord(rec)
    if self:IsMe(rec) then return true end
    if not self.guildKey then return rec.mine and true or false end
    if rec.guild ~= self.guildKey then return false end
    if roster.loaded and not self:MemberInfo(rec) then return false end   -- left the guild
    return true
end

-------------------------------------------------------------------------------
-- My character
-------------------------------------------------------------------------------
function LFW:GetMe()
    local guid = ns.MyGuid()
    if not guid or not self.db then return nil end
    local rs, fa, region = ns.GetRuleset(), UnitFactionGroup("player"), ns.GetRegion()
    if IsSecret(fa) then fa = nil end
    local rec = self.db.players[guid]
    if not rec then
        rec = { guid = guid, profs = {}, rev = 0, updated = time() }
        self.db.players[guid] = rec
        -- the same character saved under another ID (if the game ever gives a
        -- character a new ID): carry its data over instead of keeping two. A
        -- bare name may not be unique, so ruleset, faction and region must match.
        local myName = NameFromUnit("player")
        if myName and rs and fa then
            for oldGuid, old in pairs(self.db.players) do
                if oldGuid ~= guid and old.mine and old.name and NameKey(old.name) == NameKey(myName)
                    and old.rs == rs and old.fa == fa and old.region == region then
                    rec.profs, rec.rev, rec.guild = old.profs, (old.rev or 0) + 1, old.guild
                    self.db.players[oldGuid] = nil
                    break
                end
            end
        end
    end
    rec.mine = true
    rec.rs, rec.fa, rec.region = rs or rec.rs, fa or rec.fa, region or rec.region
    rec.name = NameFromUnit("player") or rec.name
    local _, class = UnitClass("player")
    if not IsSecret(class) then rec.class = class or rec.class end
    if IsInGuild() then
        if self.guildKey then rec.guild = self.guildKey end
    else
        rec.guild = nil
    end
    return rec
end

function LFW:BumpRecord(rec)
    rec.rev = (rec.rev or 0) + 1
    rec.updated = time()
    self:DataChanged(rec.mine)
end

-- Something changed: rebuild the crafter index, refresh the window, and if it
-- was my own data, share it with the guild a little later (see Comm.lua)
function LFW:DataChanged(mine)
    self.indexDirty = true
    if mine and self.ScheduleAutoShare then self:ScheduleAutoShare() end
    if self.RequestUIRefresh then self:RequestUIRefresh(false, mine and 0.15 or 1.5) end
end

-- Profession levels from the profession list (works without opening windows)
function LFW:UpdateProfessionLevels(allowRemove)
    if not GetProfessions or not GetProfessionInfo then return end
    local me = self:GetMe()
    if not me then return end
    local indices = { GetProfessions() }
    local found, primaries, changed = 0, {}, false
    for i = 1, select("#", GetProfessions()) do
        local idx = indices[i]
        if idx then
            local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
            local prof = ns.ResolveProfession(skillLine, name)
            if prof then
                found = found + 1
                if icon then self.db.icons[prof.key] = icon end
                if prof.primary then primaries[prof.key] = true end
                local p = me.profs[prof.key]
                if not p then
                    p = {}
                    me.profs[prof.key] = p
                    changed = true
                end
                if p.lvl ~= rank or p.max ~= maxRank then
                    p.lvl, p.max = rank, maxRank
                    changed = true
                end
            end
        end
    end
    -- A primary profession that is no longer listed was unlearned.
    -- (Secondary professions can't be unlearned, so they are never removed.)
    if allowRemove and found > 0 then
        for key in pairs(me.profs) do
            local prof = PROF_BY_KEY[key]
            if prof and prof.primary and not primaries[key] then
                me.profs[key] = nil
                changed = true
            end
        end
    end
    if changed then self:BumpRecord(me) end
end

-------------------------------------------------------------------------------
-- Scanning the open profession window
-------------------------------------------------------------------------------
local function BuildCategoryOrder()
    local order, n = {}, 0
    local function walk(list, depth)
        if type(list) ~= "table" or depth > 4 then return end
        for _, id in ipairs(list) do
            if type(id) == "number" and not order[id] then
                n = n + 1
                order[id] = n
                if T.GetSubCategories then
                    local ok, a = pcall(function() return PackList(T.GetSubCategories(id)) end)
                    if ok then walk(a, depth + 1) end
                end
            end
        end
    end
    if T.GetCategories then
        local ok, list = pcall(function() return PackList(T.GetCategories()) end)
        if ok then walk(list, 0) end
    end
    return order
end

local function ReadRecipeDetails(recipeID, entry)
    local got = false
    -- Reagents (basic, required slots) and the item it makes
    if T.GetRecipeSchematic then
        local s = SafeCall(T.GetRecipeSchematic, recipeID, false)
        if type(s) == "table" and type(s.reagentSlotSchematics) == "table" then
            got = true
            local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
            local list = {}
            for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                local isBasic = (basic == nil or slot.reagentType == nil or slot.reagentType == basic)
                if isBasic and slot.required ~= false and type(slot.reagents) == "table" and slot.reagents[1] then
                    local itemID = slot.reagents[1].itemID
                    if itemID then list[#list + 1] = { itemID, slot.quantityRequired or 1 } end
                end
            end
            entry.r = #list > 0 and list or nil
            if s.outputItemID and s.outputItemID > 0 then entry.o = s.outputItemID end
            if s.quantityMax and s.quantityMax > 1 then
                entry.qmin, entry.qmax = s.quantityMin, s.quantityMax
            elseif s.quantityMin and s.quantityMin > 1 then
                entry.qmin, entry.qmax = s.quantityMin, s.quantityMin
            end
        end
    end
    -- Tools / stations ("Anvil", "Blacksmith Hammer")
    if T.GetRecipeRequirements then
        local req = SafeCall(T.GetRecipeRequirements, recipeID)
        if type(req) == "table" then
            local names = {}
            for _, r in ipairs(req) do
                if type(r) == "table" and type(r.name) == "string" and r.name ~= "" then names[#names + 1] = r.name end
            end
            entry.q = #names > 0 and table.concat(names, ", ") or nil
        end
    end
    if T.GetRecipeDescription then
        local d = SafeCall(T.GetRecipeDescription, recipeID, {})
        if type(d) == "string" and d ~= "" then entry.d = d:sub(1, 400) end
    end
    if got then entry.full = true end
    return got
end

local function ResolveOpenProfession()
    local base  = T.GetBaseProfessionInfo and SafeCall(T.GetBaseProfessionInfo)
    local child = T.GetChildProfessionInfo and SafeCall(T.GetChildProfessionInfo)
    local candidates = {}
    if type(base) == "table" then
        candidates[#candidates + 1] = { base.professionID, base.professionName }
        candidates[#candidates + 1] = { base.parentProfessionID, base.parentProfessionName }
    end
    if type(child) == "table" then
        candidates[#candidates + 1] = { child.parentProfessionID, child.parentProfessionName }
        candidates[#candidates + 1] = { child.professionID, child.professionName }
    end
    for _, c in ipairs(candidates) do
        local p = ns.ResolveProfession(c[1], c[2])
        if p then return p, base, child end
    end
    return nil, base, child
end

local function Levels(base, child)
    local lvl, max = 0, 0
    for _, info in ipairs({ base, child }) do
        if type(info) == "table" then
            if (info.skillLevel or 0) > lvl then lvl = info.skillLevel end
            if (info.maxSkillLevel or 0) > max then max = info.maxSkillLevel end
        end
    end
    return lvl, max
end

function LFW:ScanOpenTradeSkill()
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) or not self.db then return end
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return end
    if T.IsNPCCrafting and SafeCall(T.IsNPCCrafting) then return end
    -- a guild member's recipes opened from the guild directory read like a link
    local isGuildMember = T.IsTradeSkillGuildMember and SafeCall(T.IsTradeSkillGuildMember) and true or false
    if not isGuildMember and T.IsTradeSkillGuild and SafeCall(T.IsTradeSkillGuild) then return end
    if T.IsRuneforging and SafeCall(T.IsRuneforging) then return end

    local isLinked, linkedName = false, nil
    if T.IsTradeSkillLinked then isLinked, linkedName = SafeCall(T.IsTradeSkillLinked) end
    if isGuildMember then isLinked = true end

    local ids = SafeCall(T.GetAllRecipeIDs)
    if type(ids) ~= "table" or #ids == 0 then return end

    local prof, base, child = ResolveOpenProfession()
    if not prof then
        -- last resort: ask which skill line the first recipe belongs to
        if T.GetTradeSkillLineForRecipe then
            local line, lineName, parent = SafeCall(T.GetTradeSkillLineForRecipe, ids[1])
            prof = ns.ResolveProfession(parent) or ns.ResolveProfession(line, lineName)
        end
    end
    if not prof then
        self:Debug("Could not tell which profession is open.")
        return
    end

    local cat = self:GetCatalog(prof.key)
    local catOrder = BuildCategoryOrder()
    local catNames = {}
    local added, upgraded, known, budget = 0, 0, {}, 0

    for _, id in ipairs(ids) do
        local info = SafeCall(T.GetRecipeInfo, id)
        if type(info) == "table" and not info.isDummyRecipe and not info.isRecraft
            and (info.learned or not info.hiddenUnlessLearned) then
            local entry = cat.recipes[id]
            if not entry then
                entry = {}
                cat.recipes[id] = entry
                added = added + 1
            end
            if type(info.name) == "string" and info.name ~= "" then entry.n = info.name end
            if info.icon then entry.i = info.icon end
            local catID = info.categoryID
            if catID then
                local cname = catNames[catID]
                if cname == nil then
                    local ci = T.GetCategoryInfo and SafeCall(T.GetCategoryInfo, catID)
                    cname = (type(ci) == "table" and type(ci.name) == "string" and ci.name ~= "") and ci.name or false
                    catNames[catID] = cname
                    if cname then
                        local o = catOrder[catID] or 900
                        if not cat.cats[cname] or cat.cats[cname] > o or cat.cats[cname] >= 900 then cat.cats[cname] = o end
                    end
                end
                if cname then
                    if not entry.c then upgraded = upgraded + 1 end
                    entry.c = cname
                end
            end
            -- where it's learned ("Trainer", "Vendor: ... Cost: ..."), once per recipe
            if entry.st == nil and T.GetRecipeSourceText then
                local st = SafeCall(T.GetRecipeSourceText, id)
                entry.st = (type(st) == "string" and st ~= "" and not (issecretvalue and issecretvalue(st))) and st:sub(1, 400) or false
            end
            -- Reagents etc. are read once per recipe (the list update event fires often)
            -- (entry.full == 1 means the details came from a guild member; read our own)
            if entry.full ~= true and budget < 2000 then
                ReadRecipeDetails(id, entry)
                budget = budget + 1
            end
            if info.learned then known[id] = true end
        end
    end
    if added > 0 or upgraded > 0 then cat.rev = (cat.rev or 0) + 1 end
    if not isLinked then cat.scanned = time() end

    local lvl, max = Levels(base, child)
    if isLinked then
        if self.StoreObservedProfession then
            self:StoreObservedProfession(linkedName, prof, known, lvl, max, isGuildMember)
        end
    else
        local me = self:GetMe()
        if me then
            local p = me.profs[prof.key] or {}
            local encoded = ns.EncodeIds(known)
            local changed = not me.profs[prof.key] or p.k ~= encoded
                or (lvl > 0 and p.lvl ~= lvl) or (max > 0 and p.max ~= max)
            p.k, p.n = encoded, ns.CountKeys(known)
            if lvl > 0 then p.lvl = lvl end
            if max > 0 then p.max = max end
            p.scanned = time()
            me.profs[prof.key] = p
            -- New recipes in the list (or placeholders filled in) also count as a
            -- change: sharing my data tells guild members my list grew, and
            -- they ask me for it.
            local improved = added > 0 or upgraded > 0
            if changed or improved then
                self:BumpRecord(me)
            end
        end
    end
    if (added > 0 or upgraded > 0) and isLinked then self:DataChanged(false) end
    self:Debug(("Scanned %s: %d recipes listed, %d known%s."):format(prof.name, #ids, ns.CountKeys(known),
        isLinked and (" (linked by " .. tostring(linkedName) .. ")") or ""))
end

local scanTimer
function LFW:QueueScan(delay)
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(delay or 0.7, function()
        scanTimer = nil
        local ok, err = pcall(LFW.ScanOpenTradeSkill, LFW)
        if not ok then LFW:Debug("scan error: " .. tostring(err)) end
    end)
end

-- A recipe was learned (works even when the profession window is closed)
function LFW:OnRecipeLearned(recipeID)
    if type(recipeID) ~= "number" then return end
    local prof
    if T and T.GetTradeSkillLineForRecipe then
        local line, lineName, parent = SafeCall(T.GetTradeSkillLineForRecipe, recipeID)
        prof = ns.ResolveProfession(parent) or ns.ResolveProfession(line, lineName)
    end
    if not prof then return end
    local me = self:GetMe()
    if not me then return end
    local p = me.profs[prof.key] or {}
    me.profs[prof.key] = p
    local cat = self:GetCatalog(prof.key)
    if not cat.recipes[recipeID] then
        local entry = { n = ns.SpellName(recipeID) }
        cat.recipes[recipeID] = entry
        cat.rev = (cat.rev or 0) + 1
        -- the game can often describe a recipe even with the window closed
        local info = T.GetRecipeInfo and SafeCall(T.GetRecipeInfo, recipeID)
        if type(info) == "table" then
            if type(info.name) == "string" and info.name ~= "" then entry.n = info.name end
            entry.i = info.icon or entry.i
            local ci = info.categoryID and T.GetCategoryInfo and SafeCall(T.GetCategoryInfo, info.categoryID)
            if type(ci) == "table" and type(ci.name) == "string" and ci.name ~= "" then entry.c = ci.name end
        end
        pcall(ReadRecipeDetails, recipeID, entry)
    end
    if ns.IdsHas(p.k, recipeID) then return end
    local set = ns.DecodeIds(p.k or "") or {}
    set[recipeID] = true
    p.k, p.n = ns.EncodeIds(set), ns.CountKeys(set)
    self:BumpRecord(me)
end

-------------------------------------------------------------------------------
-- Who knows what
-------------------------------------------------------------------------------
-- Two kinds of data describe a person:
--   * db.players: what their own addon shared (or my own characters)
--   * db.seen:    what was COLLECTED about them (profession links, the guild
--                 directory, or guild mates' collections) - see Collect.lua
-- The owner's own data always wins. Collected data is used for a profession
-- only where the owner hasn't shared a recipe list for it.
function LFW:SourceFor(guid, key)
    local own = self.db.players[guid]
    local op = own and own.profs[key]
    if op and op.k then return own, op end
    local seen = self.db.seen[guid]
    local sp = seen and seen.profs[key]
    if sp and (sp.k or not op) then return seen, sp end
    if op then return own, op end
    return nil
end

-- Is this person in my guild right now?
function LFW:InMyGuild(guid)
    if guid ~= nil and guid == ns.MyGuid() then return true end
    local own = self.db.players[guid]
    if own and own.mine and not self.guildKey then return true end
    if not self.guildKey then return false end
    if roster.loaded then return roster.byGuid[guid] ~= nil end
    if own and own.guild == self.guildKey then return true end
    local seen = self.db.seen[guid]
    return seen ~= nil and seen.gkey == self.guildKey
end

-- Everyone with data: owner records first, then collected-only people
local function ForEachPerson(db, fn)
    for guid in pairs(db.players) do fn(guid) end
    for guid in pairs(db.seen) do
        if not db.players[guid] then fn(guid) end
    end
end

function LFW:ForEachPerson(fn)
    ForEachPerson(self.db, fn)
end

-- The record to show for a guild member / outsider with this profession
function LFW:PersonFor(guid, key)
    local rec, p = self:SourceFor(guid, key)
    if not rec then return nil end
    local inGuild = self:InMyGuild(guid)
    if rec.seen then
        if not inGuild then
            if self.db.settings.showOutside == false then return nil end
            -- only people this character can trade and craft with
            if self.ContextMatches and not self:ContextMatches(rec) then return nil end
        end
        return rec, p, inGuild
    end
    if inGuild and self:IsCurrentGuildRecord(rec) then return rec, p, true end
    return nil          -- owner data of someone who left the guild
end

-- Per profession, only a few numbers per recipe are kept: how many guild
-- members know it, how many of them are online, and how many people outside
-- the guild. The names behind a recipe are looked up when you click or hover
-- it (GetCrafters), which keeps memory small even in very large guilds.
--   { n = {[id] = count}, on = {[id] = online}, x = {[id] = outside count},
--     members = {[guid] = true}, outside = {[guid] = true}, online = {[guid] = true} }
function LFW:InvalidateIndex()
    self.indexDirty = true
end

function LFW:GetRecipeCounts(key)
    if self.indexDirty then
        wipe(self.index)
        wipe(self.crafterCache)
        self.indexDirty = false
    end
    local idx = self.index[key]
    if idx then return idx end
    idx = { n = {}, on = {}, x = {}, members = {}, outside = {}, online = {} }
    ForEachPerson(self.db, function(guid)
        local rec, p, inGuild = self:PersonFor(guid, key)
        if not (p and p.k and p.k ~= "") then return end
        local isOnline = inGuild and self:IsOnline(rec)
        if inGuild then
            idx.members[guid] = true
            if isOnline then idx.online[guid] = true end
        else
            idx.outside[guid] = true
        end
        local prev = 0
        for tok in p.k:gmatch("[^%.]+") do
            prev = prev + (tonumber(tok, 36) or 0)
            if inGuild then
                idx.n[prev] = (idx.n[prev] or 0) + 1
                if isOnline then idx.on[prev] = (idx.on[prev] or 0) + 1 end
            else
                idx.x[prev] = (idx.x[prev] or 0) + 1
            end
        end
    end)
    self.index[key] = idx
    return idx
end

-- Someone came online or went offline: adjust the online counts of the
-- professions already counted instead of recounting everything.
function LFW:UpdateOnlineCounts()
    if self.indexDirty then return end
    if roster.membershipChanged then         -- someone joined or left: recount
        self.indexDirty = true
        return
    end
    for key, idx in pairs(self.index) do
        for guid in pairs(idx.members) do
            local rec, p = self:SourceFor(guid, key)
            if rec and p and p.k and p.k ~= "" then
                local isOnline = self:IsOnline(rec) and true or nil
                if isOnline ~= idx.online[guid] then
                    local delta = isOnline and 1 or -1
                    local prev = 0
                    for tok in p.k:gmatch("[^%.]+") do
                        prev = prev + (tonumber(tok, 36) or 0)
                        idx.on[prev] = math.max(0, (idx.on[prev] or 0) + delta)
                    end
                    idx.online[guid] = isOnline
                end
            end
        end
    end
end

-- Who knows one recipe: guild members, and people outside the guild
-- (cached until data changes)
function LFW:GetCrafters(key, id)
    local idx = self:GetRecipeCounts(key)            -- clears the cache if data changed
    local cacheKey = key .. ":" .. id
    local c = self.crafterCache[cacheKey]
    if c then return c.guild, c.outside end
    local guild, outside = {}, {}
    for guid in pairs(idx.members) do
        local rec, p = self:SourceFor(guid, key)
        if p and ns.IdsHas(p.k, id) then guild[#guild + 1] = rec end
    end
    for guid in pairs(idx.outside) do
        local rec, p = self:SourceFor(guid, key)
        if p and ns.IdsHas(p.k, id) then outside[#outside + 1] = rec end
    end
    self.crafterCache[cacheKey] = { guild = guild, outside = outside }
    return guild, outside
end

-- Guild members who have the profession (with or without a known recipe list)
function LFW:GetProfessionMembers(key)
    local out = {}
    ForEachPerson(self.db, function(guid)
        local rec, _, inGuild = self:PersonFor(guid, key)
        if rec and inGuild then out[#out + 1] = rec end
    end)
    return out
end

-- People outside the guild known to have the profession
function LFW:GetOutsideMembers(key)
    local out = {}
    if self.db.settings.showOutside == false then return out end
    for guid, rec in pairs(self.db.seen) do
        if rec.profs[key] and not self:InMyGuild(guid) and not self.db.players[guid]
            and (not self.ContextMatches or self:ContextMatches(rec)) then
            out[#out + 1] = rec
        end
    end
    return out
end

function LFW:GuildRecords()
    local out = {}
    for _, rec in pairs(self.db.players) do
        if self:IsCurrentGuildRecord(rec) then out[#out + 1] = rec end
    end
    return out
end

function LFW:ForgetGuildData()
    for guid, rec in pairs(self.db.players) do
        if not rec.mine and (not self.guildKey or rec.guild == self.guildKey) then self.db.players[guid] = nil end
    end
    self:DataChanged(false)
end

-------------------------------------------------------------------------------
-- Events: the addon's one event frame and its handler table, keyed by event
-- name. Other files add their handlers with ns.On(event, fn).
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
ns.eventFrame = events
local handlers = {}        -- [event] = { fn, ... }

function ns.On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        pcall(events.RegisterEvent, events, event)
    end
    list[#list + 1] = fn
end

local core = {}            -- this file's handlers

function core.ADDON_LOADED(name)
    if name ~= addonName or LFW.db then return end
    LFW:InitDB()          -- SavedVariables are read here, never at file scope
end

function core.PLAYER_LOGIN()
    ns.LocalizeProfessions()
    LFW:RefreshGuild()
    LFW:GetMe()
    LFW:UpdateProfessionLevels(false)
    local ok, err = pcall(function()
        if LFW.InitComm then LFW:InitComm() end
        if LFW.InitCollect then LFW:InitCollect() end
        if LFW.InitRecipes then LFW:InitRecipes() end
        if LFW.InitUI then LFW:InitUI() end
    end)
    if not ok then print(LFW.PREFIX .. "|cffff4040load error:|r " .. tostring(err)) end
    LFW:RequestRoster()
    C_Timer.After(25, function()
        LFW:RefreshGuild()
        LFW:GetMe()
        if LFW.LoginShare then LFW:LoginShare() end
    end)
    print(("|cffe6b422Looking For Work %s|r loaded  —  /lfw to find guild crafters"):format(LFW.VERSION))
end

function core.PLAYER_GUILD_UPDATE()
    LFW:RefreshGuild()
    LFW:GetMe()
    LFW:RequestRoster()
    LFW:DataChanged(false)
end

function core.GUILD_ROSTER_UPDATE()
    LFW:RefreshGuild()
    LFW:GetMe()
    LFW:UpdateRoster()
    if LFW.SyncSeenGuild then LFW:SyncSeenGuild() end
    LFW:UpdateOnlineCounts()
    if LFW.RequestUIRefresh then LFW:RequestUIRefresh() end
end

function core.TRADE_SKILL_SHOW() LFW:QueueScan(1.0) end
function core.TRADE_SKILL_LIST_UPDATE() LFW:QueueScan(0.8) end
function core.TRADE_SKILL_DATA_SOURCE_CHANGED() LFW:QueueScan(0.8) end

function core.NEW_RECIPE_LEARNED(recipeID)
    LFW:OnRecipeLearned(recipeID)
end

function core.SKILL_LINES_CHANGED()
    if LFW.skillTimer then LFW.skillTimer:Cancel() end
    LFW.skillTimer = C_Timer.NewTimer(2, function()
        LFW.skillTimer = nil
        LFW:UpdateProfessionLevels(true)
    end)
end

function core.PLAYER_REGEN_ENABLED()
    if LFW.FlushCombatQueue then LFW:FlushCombatQueue() end
end

-- New auction scan data: look up the price table again and refresh the window
function core.AUCTION_HOUSE_CLOSED()
    ns.ResetPriceCache()
    if LFW.RequestUIRefresh then LFW:RequestUIRefresh(true) end
end

function core.ITEM_DATA_LOAD_RESULT(itemID, success)
    if success then ns.RunItemWaiters(itemID) end
    if LFW.RequestUIRefresh then LFW:RequestUIRefresh(true) end
end

function core.SPELL_DATA_LOAD_RESULT(spellID, success)
    if success then ns.RunSpellWaiters(spellID) end
end

for event, fn in pairs(core) do ns.On(event, fn) end
events:SetScript("OnEvent", function(_, event, ...)
    if event ~= "ADDON_LOADED" and not LFW.db then return end
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then LFW:Debug(event .. ": " .. tostring(err)) end
    end
end)
