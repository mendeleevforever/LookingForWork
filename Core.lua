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
-- Players are stored by GUID, which is reliable no matter how a name is shown.

local ADDON_NAME, ns = ...

local LFW = {}
ns.LFW = LFW
_G.LookingForWork = LFW

LFW.VERSION = "1.3.0-alpha"
LFW.PREFIX  = "|cffe6b422Looking For Work:|r "

local T = C_TradeSkillUI

-------------------------------------------------------------------------------
-- Professions (WoW Forever has the 12 original Classic professions; every one,
-- gathering professions included, has a crafting window)
-------------------------------------------------------------------------------
local PROFESSIONS = {
    { key = "alchemy",        name = "Alchemy",        skillLine = 171, primary = true, icon = "Interface\\Icons\\Trade_Alchemy",       short = "Alc" },
    { key = "blacksmithing",  name = "Blacksmithing",  skillLine = 164, primary = true, icon = "Interface\\Icons\\Trade_BlackSmithing",  short = "BS" },
    { key = "enchanting",     name = "Enchanting",     skillLine = 333, primary = true, icon = "Interface\\Icons\\Trade_Engraving",      short = "Enc" },
    { key = "engineering",    name = "Engineering",    skillLine = 202, primary = true, icon = "Interface\\Icons\\Trade_Engineering",    short = "Eng" },
    { key = "herbalism",      name = "Herbalism",      skillLine = 182, primary = true, icon = "Interface\\Icons\\Trade_Herbalism",      short = "Herb" },
    { key = "leatherworking", name = "Leatherworking", skillLine = 165, primary = true, icon = "Interface\\Icons\\Trade_LeatherWorking", short = "LW" },
    { key = "mining",         name = "Mining",         skillLine = 186, primary = true, icon = "Interface\\Icons\\Trade_Mining",         short = "Min" },
    { key = "skinning",       name = "Skinning",       skillLine = 393, primary = true, icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", short = "Skin" },
    { key = "tailoring",      name = "Tailoring",      skillLine = 197, primary = true, icon = "Interface\\Icons\\Trade_Tailoring",      short = "Tail" },
    { key = "cooking",        name = "Cooking",        skillLine = 185, icon = "Interface\\Icons\\INV_Misc_Food_15",          short = "Cook" },
    { key = "firstaid",       name = "First Aid",      skillLine = 129, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", short = "FA" },
    { key = "fishing",        name = "Fishing",        skillLine = 356, icon = "Interface\\Icons\\Trade_Fishing",             short = "Fish" },
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

-- Remove a "-Realm" suffix, but only when it really is a realm name, so a
-- hyphenated last name (e.g. "Anna Smith-Jones") is never cut.
local function StripRealm(name, server)
    name = CleanName(name)
    if not name then return nil end
    local realms = {}
    if type(server) == "string" and server ~= "" then realms[#realms + 1] = server end
    if GetRealmName then realms[#realms + 1] = GetRealmName() end
    if GetNormalizedRealmName then realms[#realms + 1] = GetNormalizedRealmName() end
    for _, realm in ipairs(realms) do
        if type(realm) == "string" and realm ~= "" then
            local suffix = ("-" .. realm):lower()
            if #name > #suffix and name:sub(-#suffix):lower() == suffix then
                return CleanName(name:sub(1, -#suffix - 1))
            end
        end
    end
    return name
end
ns.StripRealm = StripRealm

-- On WoW Forever, UnitName(unit) returns TWO values: first name and surname.
-- GetUnitName(unit) returns the complete "First Surname" as one string.
-- Use both so the surname is always kept.
local function NameFromUnit(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local first, surname = UnitName(unit)
    if not first or first == "" or first == UNKNOWNOBJECT or first == UNKNOWN then return nil end
    if type(surname) == "string" and surname ~= "" then
        return CleanName(first .. " " .. surname)
    end
    if GetUnitName then
        local full = GetUnitName(unit, false)
        if type(full) == "string" then
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

-- The unique part of a player GUID ("Player-1234-0ABCDEF1" -> "0ABCDEF1")
function ns.ShortId(guid)
    if type(guid) ~= "string" then return nil end
    return guid:match("%-(%x+)$") or guid
end

function ns.ValidGuid(guid)
    return type(guid) == "string" and #guid < 40 and guid:match("^Player%-%d+%-%x+$") ~= nil
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
    if C_Spell and C_Spell.GetSpellName then
        local n = SafeCall(C_Spell.GetSpellName, id)
        if n then return n end
    end
    if GetSpellInfo then return (SafeCall(GetSpellInfo, id)) end
end

function ns.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local t = SafeCall(C_Spell.GetSpellTexture, id)
        if t then return t end
    end
    if GetSpellTexture then return (SafeCall(GetSpellTexture, id)) end
end

function ns.ItemName(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local n = SafeCall(C_Item.GetItemNameByID, id)
        if n then return n end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return (SafeCall(getInfo, id))
end

function ns.ItemIcon(id)
    if not id then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local t = SafeCall(C_Item.GetItemIconByID, id)
        if t then return t end
    end
    if GetItemIcon then return (SafeCall(GetItemIcon, id)) end
end

function ns.ItemLink(id)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = SafeCall(getInfo, id)
    return link
end

function ns.ItemQualityHex(id)
    local q
    if C_Item and C_Item.GetItemQualityByID then q = SafeCall(C_Item.GetItemQualityByID, id) end
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex end
    return "|cffffffff"
end

function ns.ItemCount(id)
    if C_Item and C_Item.GetItemCount then
        local n = SafeCall(C_Item.GetItemCount, id, true, false, true)
        if n then return n end
    end
    if GetItemCount then return SafeCall(GetItemCount, id, true) or 0 end
    return 0
end

-- Calls cb() once the item's data is in the client cache
function ns.LoadItem(id, cb)
    if not id then return end
    if ns.ItemName(id) then return end
    if Item and Item.CreateFromItemID then
        local ok, item = pcall(Item.CreateFromItemID, Item, id)
        if ok and item and item.ContinueOnItemLoad then
            pcall(item.ContinueOnItemLoad, item, cb)
        end
    end
end

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
    if not tipPending[id] and Spell and Spell.CreateFromSpellID then
        tipPending[id] = true
        local ok, spell = pcall(Spell.CreateFromSpellID, Spell, id)
        if ok and spell and spell.ContinueOnSpellLoad then
            pcall(spell.ContinueOnSpellLoad, spell, function() TooltipLoaded(id) end)
        end
    end
    return false
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
    c = { lines = {}, lower = {}, built = GetTime() }
    local ok, incomplete = pcall(BuildTooltipLines, id, e, c.lines)
    c.incomplete = not ok or incomplete
    for i, line in ipairs(c.lines) do
        local low = line:lower()
        if low:find(RETRIEVING, 1, true) then c.incomplete = true end
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
local function FindPriceDB()
    if Auctionator and type(Auctionator.Database) == "table" and IsPriceTable(Auctionator.Database.db) then
        return Auctionator.Database.db
    end
    local root = AUCTIONATOR_PRICE_DATABASE
    if type(root) ~= "table" then return nil end
    local realm   = GetRealmName() or ""
    local nrealm  = (GetNormalizedRealmName and GetNormalizedRealmName()) or (realm:gsub("[%s%-]", ""))
    local faction = UnitFactionGroup("player") or ""
    local candidates = { realm .. " " .. faction, nrealm .. " " .. faction, realm, nrealm, realm .. "-" .. faction }
    if Auctionator and Auctionator.Variables and Auctionator.Variables.GetConnectedRealmRoot then
        local ok, r = pcall(Auctionator.Variables.GetConnectedRealmRoot)
        if ok and type(r) == "string" then table.insert(candidates, 1, r) end
    end
    for _, key in ipairs(candidates) do
        if IsPriceTable(root[key]) then return root[key] end
    end
    local lrealm = realm:lower()
    for key, t in pairs(root) do
        if type(key) == "string" and lrealm ~= "" and key:lower():find(lrealm, 1, true) and IsPriceTable(t) then
            return t
        end
    end
    return nil
end

local function PriceDB()
    if not priceDB and GetTime() - priceDBTime > 30 then
        priceDB, priceDBTime = FindPriceDB(), GetTime()
    end
    return priceDB
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
                                            r = { {itemID, qty}, ... }, o = outputItemID,
                                            q = "Anvil", d = description, full = true } } } },
    players   = { [guid] = { guid, name, class, guild, rev, updated, mine,
                             profs = { [profKey] = { lvl, max, scanned, known = { [recipeID] = true } } } } },
    sync      = { lastQuery, lastSent = { [guid] = rev }, lastAutoShare },
    collapsed = { [profKey] = { [categoryName] = true } },
    icons, skillLines, positions
}
]]
local DEFAULT_SETTINGS = {
    ignoreQueries = false,   -- the Options "Ignore Queries" checkbox (default unchecked)
    showUnowned   = true,    -- list recipes nobody in the guild has
    onlineOnly    = false,   -- list only recipes with an online crafter
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
    db.positions  = tbl(db.positions)
    db.collapsed  = tbl(db.collapsed)
    db.catalog    = tbl(db.catalog)
    db.players    = tbl(db.players)
    db.sync       = tbl(db.sync)
    db.sync.lastSent = tbl(db.sync.lastSent)
    db.icons      = tbl(db.icons)
    db.skillLines = tbl(db.skillLines)

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
                    if p.known ~= nil then p.known = tbl(p.known) end
                end
            end
        end
    end
    self.db = db
    self.index = {}
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
function LFW:RefreshGuild()
    if not IsInGuild() then
        self.guildKey, self.guildName = nil, nil
        return
    end
    local name, _, _, realm = GetGuildInfo("player")
    if name and name ~= "" then
        realm = (type(realm) == "string" and realm ~= "") and realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
        local key = realm .. "|" .. name
        if key ~= self.guildKey then
            self.guildKey, self.guildName = key, name
            self.indexDirty = true
        end
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
    local myGuid = UnitGUID("player")
    for i = 1, total do
        local name, rank, _, level, _, zone, _, _, online, _, class, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
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
    return rec and rec.guid == UnitGUID("player")
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
    local guid = UnitGUID("player")
    if not guid or not self.db then return nil end
    local rec = self.db.players[guid]
    if not rec then
        rec = { guid = guid, profs = {}, rev = 0, updated = time() }
        self.db.players[guid] = rec
    end
    rec.mine = true
    rec.name = NameFromUnit("player") or rec.name
    local _, class = UnitClass("player")
    rec.class = class or rec.class
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
    if self.RequestUIRefresh then self:RequestUIRefresh() end
end

local function SetsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
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
    if T.IsTradeSkillGuild and SafeCall(T.IsTradeSkillGuild) then return end
    if T.IsRuneforging and SafeCall(T.IsRuneforging) then return end

    local isLinked, linkedName = false, nil
    if T.IsTradeSkillLinked then isLinked, linkedName = SafeCall(T.IsTradeSkillLinked) end

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
        self:StoreLinkedProfession(linkedName, prof, known, lvl, max)
    else
        local me = self:GetMe()
        if me then
            local p = me.profs[prof.key] or {}
            local changed = not me.profs[prof.key] or not SetsEqual(p.known, known)
                or (lvl > 0 and p.lvl ~= lvl) or (max > 0 and p.max ~= max)
            p.known = known
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

-- A profession link a guild member posted in chat: save which recipes they know
function LFW:StoreLinkedProfession(linkedName, prof, known, lvl, max)
    if type(linkedName) ~= "string" then return end
    local m = roster.byName[NameKey(StripRealm(linkedName)) or ""]
    if not m or not m.guid or not ns.ValidGuid(m.guid) or m.guid == UnitGUID("player") then return end
    local rec = self.db.players[m.guid]
    if not rec then
        rec = { guid = m.guid, rev = 0, profs = {}, updated = time() }
        self.db.players[m.guid] = rec
    end
    rec.name, rec.class = m.name, m.class or rec.class
    if self.guildKey then rec.guild = self.guildKey end
    local p = rec.profs[prof.key] or {}
    p.known = known
    if lvl > 0 then p.lvl = lvl end
    if max > 0 then p.max = max end
    p.scanned = time()
    rec.profs[prof.key] = p
    if rec.mine then
        self:BumpRecord(rec)    -- one of my own alts: share it like my own data
    else
        rec.updated = math.max(rec.updated or 0, time())
        self:DataChanged(false)
    end
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
    if p.known and p.known[recipeID] then return end
    p.known = p.known or {}
    p.known[recipeID] = true
    self:BumpRecord(me)
end

-------------------------------------------------------------------------------
-- Who knows what
-------------------------------------------------------------------------------
-- recipeID -> { record, ... } for the current guild (rebuilt when data changes)
function LFW:GetCrafterIndex(key)
    if self.indexDirty then
        wipe(self.index)
        self.indexDirty = false
    end
    local idx = self.index[key]
    if idx then return idx end
    idx = {}
    for _, rec in pairs(self.db.players) do
        if self:IsCurrentGuildRecord(rec) then
            local p = rec.profs[key]
            if p and p.known then
                for id in pairs(p.known) do
                    local list = idx[id]
                    if not list then list = {}; idx[id] = list end
                    list[#list + 1] = rec
                end
            end
        end
    end
    self.index[key] = idx
    return idx
end

-- Guild records that have the profession (with or without a shared recipe list)
function LFW:GetProfessionMembers(key)
    local out = {}
    for _, rec in pairs(self.db.players) do
        if self:IsCurrentGuildRecord(rec) and rec.profs[key] then out[#out + 1] = rec end
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
-- Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    LFW:InitDB()
    events:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
    ns.LocalizeProfessions()
    LFW:RefreshGuild()
    LFW:GetMe()
    LFW:UpdateProfessionLevels(false)
    local ok, err = pcall(function()
        if LFW.InitComm then LFW:InitComm() end
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

function handlers.PLAYER_GUILD_UPDATE()
    LFW:RefreshGuild()
    LFW:GetMe()
    LFW:RequestRoster()
    LFW:DataChanged(false)
end

function handlers.GUILD_ROSTER_UPDATE()
    LFW:RefreshGuild()
    LFW:GetMe()
    LFW:UpdateRoster()
    LFW.indexDirty = true
    if LFW.RequestUIRefresh then LFW:RequestUIRefresh() end
end

function handlers.TRADE_SKILL_SHOW() LFW:QueueScan(1.0) end
function handlers.TRADE_SKILL_LIST_UPDATE() LFW:QueueScan(0.8) end
function handlers.TRADE_SKILL_DATA_SOURCE_CHANGED() LFW:QueueScan(0.8) end

function handlers.NEW_RECIPE_LEARNED(recipeID)
    LFW:OnRecipeLearned(recipeID)
end

function handlers.SKILL_LINES_CHANGED()
    if LFW.skillTimer then LFW.skillTimer:Cancel() end
    LFW.skillTimer = C_Timer.NewTimer(2, function()
        LFW.skillTimer = nil
        LFW:UpdateProfessionLevels(true)
    end)
end

function handlers.PLAYER_REGEN_ENABLED()
    if LFW.FlushCombatQueue then LFW:FlushCombatQueue() end
end

-- New auction scan data: look up the price table again and refresh the window
function handlers.AUCTION_HOUSE_CLOSED()
    ns.ResetPriceCache()
    if LFW.RequestUIRefresh then LFW:RequestUIRefresh(true) end
end

function handlers.GET_ITEM_INFO_RECEIVED()
    if LFW.RequestUIRefresh then LFW:RequestUIRefresh(true) end
end

for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h and (event == "ADDON_LOADED" or LFW.db) then h(...) end
end)
