local addonName, ns = ...
-- Disenchant.lua
-- Disenchanting value of the item a recipe makes, for the "Disenchant profit"
-- sort and line: the average auction value of what disenchanting it gives,
-- minus the cost of crafting it.
--
-- The yield tables and rules are taken from DEValueTooltip 2.0.0 (Data.lua and
-- Disenchant.lua, by MendeleevForever): results depend on the item's quality,
-- item level and whether it's a weapon or armor, with WoW Forever's own
-- weapon essence rule. If a patch changes yields, update the tables below
-- (and DEValueTooltip's) together.

local LFW = ns.LFW

local DE = {}
ns.DE = DE

local M = {
    STRANGE_DUST     = 10940,
    SOUL_DUST        = 11083,
    VISION_DUST      = 11137,
    DREAM_DUST       = 11176,
    ILLUSION_DUST    = 16204,

    LESSER_MAGIC     = 10938,
    GREATER_MAGIC    = 10939,
    LESSER_ASTRAL    = 10998,
    GREATER_ASTRAL   = 11082,
    LESSER_MYSTIC    = 11134,
    GREATER_MYSTIC   = 11135,
    LESSER_NETHER    = 11174,
    GREATER_NETHER   = 11175,
    LESSER_ETERNAL   = 16202,
    GREATER_ETERNAL  = 16203,

    SMALL_GLIMMERING = 10978,
    LARGE_GLIMMERING = 11084,
    SMALL_GLOWING    = 11138,
    LARGE_GLOWING    = 11139,
    SMALL_RADIANT    = 11177,
    LARGE_RADIANT    = 11178,
    SMALL_BRILLIANT  = 14343,
    LARGE_BRILLIANT  = 14344,

    NEXUS_CRYSTAL    = 20725,
}

-- English fallback names (used only until the client has the item cached) and
-- item qualities (dusts common, essences uncommon, shards rare, crystal epic).
DE.MATERIALS = {
    [M.STRANGE_DUST]     = { name = "Strange Dust",            quality = 1 },
    [M.SOUL_DUST]        = { name = "Soul Dust",               quality = 1 },
    [M.VISION_DUST]      = { name = "Vision Dust",             quality = 1 },
    [M.DREAM_DUST]       = { name = "Dream Dust",              quality = 1 },
    [M.ILLUSION_DUST]    = { name = "Illusion Dust",           quality = 1 },
    [M.LESSER_MAGIC]     = { name = "Lesser Magic Essence",    quality = 2 },
    [M.GREATER_MAGIC]    = { name = "Greater Magic Essence",   quality = 2 },
    [M.LESSER_ASTRAL]    = { name = "Lesser Astral Essence",   quality = 2 },
    [M.GREATER_ASTRAL]   = { name = "Greater Astral Essence",  quality = 2 },
    [M.LESSER_MYSTIC]    = { name = "Lesser Mystic Essence",   quality = 2 },
    [M.GREATER_MYSTIC]   = { name = "Greater Mystic Essence",  quality = 2 },
    [M.LESSER_NETHER]    = { name = "Lesser Nether Essence",   quality = 2 },
    [M.GREATER_NETHER]   = { name = "Greater Nether Essence",  quality = 2 },
    [M.LESSER_ETERNAL]   = { name = "Lesser Eternal Essence",  quality = 2 },
    [M.GREATER_ETERNAL]  = { name = "Greater Eternal Essence", quality = 2 },
    [M.SMALL_GLIMMERING] = { name = "Small Glimmering Shard",  quality = 3 },
    [M.LARGE_GLIMMERING] = { name = "Large Glimmering Shard",  quality = 3 },
    [M.SMALL_GLOWING]    = { name = "Small Glowing Shard",     quality = 3 },
    [M.LARGE_GLOWING]    = { name = "Large Glowing Shard",     quality = 3 },
    [M.SMALL_RADIANT]    = { name = "Small Radiant Shard",     quality = 3 },
    [M.LARGE_RADIANT]    = { name = "Large Radiant Shard",     quality = 3 },
    [M.SMALL_BRILLIANT]  = { name = "Small Brilliant Shard",   quality = 3 },
    [M.LARGE_BRILLIANT]  = { name = "Large Brilliant Shard",   quality = 3 },
    [M.NEXUS_CRYSTAL]    = { name = "Nexus Crystal",           quality = 4 },
}

-------------------------------------------------------------------------------
-- Uncommon (green) armor and weapons
-- dust/essence = { itemID, minQty, maxQty }, shard = itemID (always 1x)
-- armor/weapon = { dust %, essence %, shard % }   (each set sums to 100)
-------------------------------------------------------------------------------
DE.UNCOMMON = {
    -- The original table starts at item level 5; greens below that are rare and
    -- can only fall into the first bracket, so the row is extended down to 1.
    { lo = 1,  hi = 15, dust = { M.STRANGE_DUST, 1, 2 },  essence = { M.LESSER_MAGIC, 1, 2 },
      shard = nil,                armor = { 80, 20, 0 },  weapon = { 20, 80, 0 } },
    { lo = 16, hi = 20, dust = { M.STRANGE_DUST, 2, 3 },  essence = { M.GREATER_MAGIC, 1, 2 },
      shard = M.SMALL_GLIMMERING, armor = { 75, 20, 5 },  weapon = { 20, 75, 5 } },
    { lo = 21, hi = 25, dust = { M.STRANGE_DUST, 4, 6 },  essence = { M.LESSER_ASTRAL, 1, 2 },
      shard = M.SMALL_GLIMMERING, armor = { 75, 15, 10 }, weapon = { 15, 75, 10 } },
    { lo = 26, hi = 30, dust = { M.SOUL_DUST, 1, 2 },     essence = { M.GREATER_ASTRAL, 1, 2 },
      shard = M.LARGE_GLIMMERING, armor = { 75, 20, 5 },  weapon = { 20, 75, 5 } },
    { lo = 31, hi = 35, dust = { M.SOUL_DUST, 2, 5 },     essence = { M.LESSER_MYSTIC, 1, 2 },
      shard = M.SMALL_GLOWING,    armor = { 75, 20, 5 },  weapon = { 20, 75, 5 } },
    { lo = 36, hi = 40, dust = { M.VISION_DUST, 1, 2 },   essence = { M.GREATER_MYSTIC, 1, 2 },
      shard = M.LARGE_GLOWING,    armor = { 75, 20, 5 },  weapon = { 20, 75, 5 } },
    { lo = 41, hi = 45, dust = { M.VISION_DUST, 2, 5 },   essence = { M.LESSER_NETHER, 1, 2 },
      shard = M.SMALL_RADIANT,    armor = { 75, 20, 5 },  weapon = { 20, 75, 5 } },
    { lo = 46, hi = 50, dust = { M.DREAM_DUST, 1, 2 },    essence = { M.GREATER_NETHER, 1, 2 },
      shard = M.LARGE_RADIANT,    armor = { 75, 20, 5 },  weapon = { 20, 75, 5 } },
    { lo = 51, hi = 55, dust = { M.DREAM_DUST, 2, 5 },    essence = { M.LESSER_ETERNAL, 1, 2 },
      shard = M.SMALL_BRILLIANT,  armor = { 75, 20, 5 },  weapon = { 22, 75, 3 } },
    { lo = 56, hi = 60, dust = { M.ILLUSION_DUST, 1, 2 }, essence = { M.GREATER_ETERNAL, 1, 2 },
      shard = M.LARGE_BRILLIANT,  armor = { 75, 20, 5 },  weapon = { 22, 75, 3 } },
    { lo = 61, hi = 65, dust = { M.ILLUSION_DUST, 2, 5 }, essence = { M.GREATER_ETERNAL, 2, 3 },
      shard = M.LARGE_BRILLIANT,  armor = { 75, 20, 5 },  weapon = { 22, 75, 3 } },
}

-- Forever-specific: uncommon WEAPONS of item level 21-30 yield Greater Magic
-- Essence instead of the classic Astral essences (Disenchantry 1.1.9, citing
-- Wowhead's Forever disenchant data). Armor keeps the classic essences.
DE.FOREVER_WEAPON_ESSENCE = {
    { lo = 21, hi = 30, itemID = M.GREATER_MAGIC },
}

-------------------------------------------------------------------------------
-- Rare (blue): one shard; Large Brilliant brackets have a 0.5% Nexus Crystal
-------------------------------------------------------------------------------
DE.RARE = {
    { lo = 1,  hi = 25, results = { { M.SMALL_GLIMMERING, 100, 1, 1 } } },
    { lo = 26, hi = 30, results = { { M.LARGE_GLIMMERING, 100, 1, 1 } } },
    { lo = 31, hi = 35, results = { { M.SMALL_GLOWING,    100, 1, 1 } } },
    { lo = 36, hi = 40, results = { { M.LARGE_GLOWING,    100, 1, 1 } } },
    { lo = 41, hi = 45, results = { { M.SMALL_RADIANT,    100, 1, 1 } } },
    { lo = 46, hi = 50, results = { { M.LARGE_RADIANT,    100, 1, 1 } } },
    { lo = 51, hi = 55, results = { { M.SMALL_BRILLIANT,  100, 1, 1 } } },
    { lo = 56, hi = 80, results = { { M.LARGE_BRILLIANT, 99.5, 1, 1 }, { M.NEXUS_CRYSTAL, 0.5, 1, 1 } } },
}

-------------------------------------------------------------------------------
-- Epic (purple)
-- result = { itemID, chance, minQty, maxQty, avgQty (optional) }
-- weaponAvg overrides the average quantity for weapons inside [weaponLo, weaponHi]
-------------------------------------------------------------------------------
DE.EPIC = {
    { lo = 40, hi = 45, results = { { M.SMALL_RADIANT,   100, 2, 4 } } },
    { lo = 46, hi = 50, results = { { M.LARGE_RADIANT,   100, 2, 4 } } },
    { lo = 51, hi = 55, results = { { M.SMALL_BRILLIANT, 100, 2, 4 } } },
    { lo = 56, hi = 60, results = { { M.NEXUS_CRYSTAL,   100, 1, 1 } } },
    -- 61-88: 50% 1x / 50% 2x, except item level 76-80 weapons: 33% 1x / 67% 2x.
    { lo = 61, hi = 88, results = { { M.NEXUS_CRYSTAL,   100, 1, 2 } },
      weaponLo = 76, weaponHi = 80, weaponAvg = 5 / 3 },
    -- Original-era epics above 88 (late raid items) are not in the published
    -- tables; the next published bracket uses later-expansion materials that
    -- Forever does not have. Shown as an estimate.
    { lo = 89, hi = 100, results = { { M.NEXUS_CRYSTAL,  100, 1, 2 } }, estimated = true },
}

-------------------------------------------------------------------------------
-- Items that match the quality/class rules but cannot be disenchanted.
-- Enchanter-crafted wands (Disenchantry 1.1.9, Docs/DisenchantExclusions.md).
-------------------------------------------------------------------------------
DE.EXCLUDED = {
    [11287]  = true, -- Lesser Magic Wand
    [11288]  = true, -- Greater Magic Wand
    [11289]  = true, -- Lesser Mystic Wand
    [11290]  = true, -- Greater Mystic Wand
    [247789] = true, -- Novice's Practice Wand (Forever)
    [249144] = true, -- Twisted Nether Wand (Forever)
    [249234] = true, -- Dreambough Wand (Forever)
    [249232] = true, -- Lesser Eternal Wand (Forever)
    [249237] = true, -- Greater Eternal Wand (Forever)
    [249385] = true, -- Brilliant Wand (Forever)
}

-- Equip locations that are never disenchantable.
DE.BLOCKED_EQUIPLOC = {
    [""]                  = true,
    ["INVTYPE_NON_EQUIP"] = true,
    ["INVTYPE_NON_EQUIP_IGNORE"] = true,
    ["INVTYPE_BODY"]      = true, -- shirts
    ["INVTYPE_TABARD"]    = true,
    ["INVTYPE_BAG"]       = true,
    ["INVTYPE_QUIVER"]    = true,
    ["INVTYPE_AMMO"]      = true,
}


local ItemClass = Enum and Enum.ItemClass
local ArmorSub  = Enum and Enum.ItemArmorSubclass
local WeaponSub = Enum and Enum.ItemWeaponSubclass
local CLASS_WEAPON = (ItemClass and ItemClass.Weapon) or 2
local CLASS_ARMOR  = (ItemClass and ItemClass.Armor) or 4
local BLOCKED_SUBCLASS = {
    [CLASS_ARMOR]  = { [(ArmorSub and ArmorSub.Cosmetic) or 5] = true },
    [CLASS_WEAPON] = { [(WeaponSub and WeaponSub.Fishingpole) or 20] = true },
}

local function Secret(v)
    return issecretvalue and v ~= nil and issecretvalue(v) or false
end

local function FindRow(rows, itemLevel)
    for _, row in ipairs(rows) do
        if itemLevel >= row.lo and itemLevel <= row.hi then return row end
    end
    return nil
end

local function Outcome(itemID, chance, minQty, maxQty, avgQty)
    minQty = minQty or 1
    maxQty = maxQty or minQty
    return { itemID = itemID, chance = chance, minQty = minQty, maxQty = maxQty, avgQty = avgQty or (minQty + maxQty) / 2 }
end

-- What disenchanting an item can give: a list of outcomes (chance in %,
-- average quantity), or nil when it can't be disenchanted, isn't loaded yet
-- (it's asked for), or isn't covered by the tables
function DE.Outcomes(itemID)
    if not itemID or DE.EXCLUDED[itemID] then return nil end
    local instant = C_Item and C_Item.GetItemInfoInstant
    local getInfo = C_Item and C_Item.GetItemInfo
    if not instant or not getInfo then return nil end
    local okI, _, _, _, equipLoc, _, classID, subclassID = pcall(instant, itemID)
    if not okI or (classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR) then return nil end
    if equipLoc == nil or DE.BLOCKED_EQUIPLOC[equipLoc] then return nil end
    local blocked = BLOCKED_SUBCLASS[classID]
    if blocked and subclassID and blocked[subclassID] then return nil end
    local ok, name, _, quality, itemLevel = pcall(getInfo, itemID)
    if not ok or not name or Secret(quality) or Secret(itemLevel) then
        ns.LoadItem(itemID, function() if LFW.RequestUIRefresh then LFW:RequestUIRefresh() end end)
        return nil, "loading"
    end
    if not quality or quality < 2 or quality > 4 or not itemLevel or itemLevel < 1 then return nil end

    local isWeapon = classID == CLASS_WEAPON
    local list, estimated = {}, false
    if quality == 2 then
        local row = FindRow(DE.UNCOMMON, itemLevel)
        if not row then return nil end
        local odds = isWeapon and row.weapon or row.armor
        local essenceID = row.essence[1]
        if isWeapon then
            local override = FindRow(DE.FOREVER_WEAPON_ESSENCE, itemLevel)
            if override then essenceID = override.itemID end
        end
        list[#list + 1] = Outcome(row.dust[1], odds[1], row.dust[2], row.dust[3])
        list[#list + 1] = Outcome(essenceID, odds[2], row.essence[2], row.essence[3])
        if row.shard and odds[3] > 0 then list[#list + 1] = Outcome(row.shard, odds[3], 1, 1) end
    else
        local row = FindRow(quality == 3 and DE.RARE or DE.EPIC, itemLevel)
        if not row then return nil end
        for _, r in ipairs(row.results) do
            local avg = r[5]
            if isWeapon and row.weaponAvg and itemLevel >= row.weaponLo and itemLevel <= row.weaponHi then avg = row.weaponAvg end
            list[#list + 1] = Outcome(r[1], r[2], r[3], r[4], avg)
        end
        estimated = row.estimated and true or false
    end
    return list, estimated
end

-- Average auction value of disenchanting one item (copper, before the
-- auction house cut). Outcomes are exclusive: value = sum(chance * avgQty * price).
-- Returns value, outcomes (with .price/.value filled in), anyMissing, estimated;
-- nil when it can't be disenchanted or no material has a price.
-- true, false (can't be disenchanted), or nil while the item is loading
function DE.CanDisenchant(itemID)
    if not itemID then return false end
    local outcomes, why = DE.Outcomes(itemID)
    if outcomes then return true end
    if why == "loading" then return nil end
    return false
end

function DE.Value(itemID)
    local outcomes, estimated = DE.Outcomes(itemID)
    if not outcomes then return nil end
    local total, anyPriced, anyMissing = 0, false, false
    for _, o in ipairs(outcomes) do
        local price = ns.AuctionPrice(o.itemID)
        o.price = price
        if price then
            o.value = (o.chance / 100) * o.avgQty * price
            total = total + o.value
            anyPriced = true
        else
            o.value = nil
            if o.chance > 0 then anyMissing = true end
        end
    end
    if not anyPriced then return nil end
    return total, outcomes, anyMissing, estimated
end

function DE.MaterialName(itemID)
    return ns.ItemName(itemID) or (DE.MATERIALS[itemID] and DE.MATERIALS[itemID].name) or ("Item #" .. itemID)
end

-------------------------------------------------------------------------------
-- Profits of crafting an item to disenchant it, or to sell it to a vendor
-------------------------------------------------------------------------------
-- info: ns.CraftEconomics(e) (needs every reagent priced). Fills in and returns:
--   info.deValue (per item, before cut), info.deOutcomes, info.deMissing,
--   info.deEstimated, info.deProfit = value * qty * (1 - AH cut) - cost
--   info.sell (per item), info.vendorProfit = sell * qty - cost
function DE.CraftProfits(info)
    if not info or not info.outItem then return info end
    local qty = info.outQty or 1
    local value, outcomes, missing, estimated = DE.Value(info.outItem)
    if value then
        info.deValue, info.deOutcomes, info.deMissing, info.deEstimated = value, outcomes, missing, estimated
        if #info.missing == 0 then
            info.deProfit = math.floor(value * qty * ns.AH_CUT - info.cost + 0.5)
        end
    end
    local ok, name, _, _, _, _, _, _, _, _, _, sellPrice = pcall(C_Item and C_Item.GetItemInfo, info.outItem)
    if ok and name and type(sellPrice) == "number" and not Secret(sellPrice) and sellPrice > 0 then
        info.sell = sellPrice
        if #info.missing == 0 then info.vendorProfit = sellPrice * qty - info.cost end
    end
    return info
end
