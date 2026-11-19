-- Recipes.lua
-- Buying and learning recipes, and the rarity of what they make:
--
--   * Which item teaches a recipe ("Pattern: Linen Cloak"). The game doesn't
--     say, so recipe items are matched to recipes by name (the part after
--     "Pattern:", "Plans:", "Formula:", "Recipe:", "Schematic:"...) within the
--     profession the item belongs to. Recipe items are found in Auctionator's
--     price list, at every vendor you open, and in any item tooltip you see.
--   * What it costs: Auctionator's auction price for the recipe item, and the
--     vendor price seen at a vendor, including non-gold currencies.
--   * The skill needed to learn it, from the recipe item's tooltip
--     ("Requires Tailoring (75)").
--   * Where it's learned, from the profession window's own source text
--     (saved when the window is read, see Core.lua).
--   * The rarity (quality) of the item a recipe makes.

local ADDON_NAME, ns = ...
local LFW = ns.LFW
local SafeCall = ns.SafeCall

local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
-- recipe item subclass -> profession
local SUBCLASS_PROF = {
    [1] = "leatherworking", [2] = "tailoring", [3] = "engineering", [4] = "blacksmithing",
    [5] = "cooking", [6] = "alchemy", [7] = "firstaid", [8] = "enchanting", [9] = "fishing",
}

ns.QUALITIES = {
    { q = 0, name = "Poor" }, { q = 1, name = "Common" }, { q = 2, name = "Uncommon" },
    { q = 3, name = "Rare" }, { q = 4, name = "Epic" }, { q = 5, name = "Legendary" },
}

LFW.unmatchedRecipeItems = {}   -- recipe items with no matching recipe (this session)

local function Secret(v)
    return issecretvalue and v ~= nil and issecretvalue(v) or false
end

local function ItemInstant(itemID)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f or not itemID then return nil end
    local ok, _, _, _, _, _, classID, subclassID = pcall(f, itemID)
    if ok then return classID, subclassID end
    return nil
end

local function ItemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-------------------------------------------------------------------------------
-- Rarity of the item a recipe makes
-------------------------------------------------------------------------------
-- returns the quality (0 Poor .. 5 Legendary), false when the recipe makes no
-- item (most enchants), or nil while the item hasn't loaded yet
function ns.RecipeQuality(e)
    if not e then return nil end
    if not e.o then
        if e.full then return false end      -- read from a window: really makes no item
        return nil
    end
    if e.oq then return e.oq end
    local q = C_Item and C_Item.GetItemQualityByID and SafeCall(C_Item.GetItemQualityByID, e.o)
    if type(q) == "number" and not Secret(q) then
        e.oq = q
        return q
    end
    ns.LoadItem(e.o, function() if LFW.RequestUIRefresh then LFW:RequestUIRefresh() end end)
    return nil
end

-------------------------------------------------------------------------------
-- Which item teaches which recipe
-------------------------------------------------------------------------------
local nameIndex = {}     -- profKey -> { count, map = { [lower name] = recipeID } }

local function RecipeByName(key, name)
    local cat = LFW.db.catalog[key]
    if not cat then return nil end
    local count = ns.CountKeys(cat.recipes)
    local idx = nameIndex[key]
    if not idx or idx.count ~= count then
        idx = { count = count, map = {} }
        for id, e in pairs(cat.recipes) do
            local k = e.n and ns.NameKey(e.n)
            if k then idx.map[k] = id end
        end
        nameIndex[key] = idx
    end
    return idx.map[ns.NameKey(name) or ""]
end

-- Link a recipe item to its recipe by name. Returns the profession and recipe.
function LFW:LinkRecipeItem(itemID, itemName)
    if not itemID or type(itemName) ~= "string" or Secret(itemName) then return nil end
    local classID, subclassID = ItemInstant(itemID)
    if classID ~= RECIPE_CLASS then return nil end
    local taught = itemName:match("^[^:]+:%s*(.+)$") or itemName
    local keys = {}
    if SUBCLASS_PROF[subclassID] then
        keys[1] = SUBCLASS_PROF[subclassID]
    else
        for _, p in ipairs(ns.PROFESSIONS) do keys[#keys + 1] = p.key end
    end
    for _, key in ipairs(keys) do
        local id = RecipeByName(key, taught)
        if id then
            local e = self.db.catalog[key].recipes[id]
            if e.ri ~= itemID then
                e.ri, e.rs = itemID, nil      -- skill is read from the new item
                self.unmatchedRecipeItems[itemID] = nil
                if self.RequestUIRefresh then self:RequestUIRefresh(true) end
            end
            return key, id
        end
    end
    self.unmatchedRecipeItems[itemID] = true
    return nil
end

local function LinkWhenLoaded(itemID)
    local name = ns.ItemName(itemID)
    if name then
        LFW:LinkRecipeItem(itemID, name)
    else
        ns.LoadItem(itemID, function() LFW:LinkRecipeItem(itemID, ns.ItemName(itemID)) end)
    end
end

-- Recipe items in Auctionator's price list (a few hundred items at a time)
function LFW:ScanAuctionatorRecipeItems()
    if self.recipeScanTicker or not ns.AuctionatorPriceTable then return end
    local db = ns.AuctionatorPriceTable()
    if type(db) ~= "table" then return end
    local linked = {}
    for _, cat in pairs(self.db.catalog) do
        for _, e in pairs(cat.recipes) do if e.ri then linked[e.ri] = true end end
    end
    local queue = {}
    for k in pairs(db) do
        local id = tonumber(k)
        if id and not linked[id] and not self.unmatchedRecipeItems[id] then queue[#queue + 1] = id end
    end
    if #queue == 0 then return end
    local pos, done, ticker = 1, false, nil
    ticker = C_Timer.NewTicker(0.1, function()
        if done then return end
        for _ = 1, 300 do
            local id = queue[pos]
            if not id then
                done = true
                if ticker then ticker:Cancel() end
                self.recipeScanTicker = nil
                return
            end
            pos = pos + 1
            if ItemInstant(id) == RECIPE_CLASS then LinkWhenLoaded(id) end
        end
    end)
    self.recipeScanTicker = (not done) and ticker or nil
end

-------------------------------------------------------------------------------
-- Vendors: recipe items and their exact cost (gold and other currencies)
-------------------------------------------------------------------------------
function LFW:ScanMerchant()
    if not GetMerchantNumItems or not GetMerchantItemLink then return end
    local vendor = (GetUnitName and GetUnitName("npc", false)) or UnitName("npc")
    local zone = GetRealZoneText and GetRealZoneText() or nil
    for i = 1, GetMerchantNumItems() or 0 do
        local link = GetMerchantItemLink(i)
        local itemID = ItemIDFromLink(link)
        if itemID and ItemInstant(itemID) == RECIPE_CLASS then
            local name, price, extended
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local info = SafeCall(C_MerchantFrame.GetItemInfo, i)
                if type(info) == "table" then name, price, extended = info.name, info.price, info.hasExtendedCost end
            end
            if name == nil and GetMerchantItemInfo then
                local n, _, p, _, _, _, _, ext = GetMerchantItemInfo(i)
                name, price, extended = n, p, ext
            end
            local cost = { c = tonumber(price) or 0, v = (not Secret(vendor)) and vendor or nil, z = zone, t = time(), x = {} }
            if extended and GetMerchantItemCostInfo and GetMerchantItemCostItem then
                for j = 1, GetMerchantItemCostInfo(i) or 0 do
                    local icon, amount, costLink, currencyName = GetMerchantItemCostItem(i, j)
                    if amount and amount > 0 then
                        local cname = currencyName
                        if not cname and costLink then cname = costLink:match("%[(.-)%]") end
                        cost.x[#cost.x + 1] = { icon = icon, n = amount, name = cname }
                    end
                end
            end
            if #cost.x == 0 then cost.x = nil end
            self.db.recipeVendors[itemID] = cost
            LFW:LinkRecipeItem(itemID, name or ns.ItemName(itemID) or (link and link:match("%[(.-)%]")))
        end
    end
end

-------------------------------------------------------------------------------
-- Prices and skill
-------------------------------------------------------------------------------
-- What the recipe costs to buy, for sorting: the auction price of the recipe
-- item, otherwise its vendor price in gold. nil when unknown (or only sold
-- for other currencies).
function ns.RecipePrice(e)
    if not e or not e.ri then return nil end
    local ah = ns.AuctionPrice(e.ri)
    if ah then return ah, "auction" end
    local v = LFW.db.recipeVendors[e.ri]
    if v and v.c and v.c > 0 and not v.x then return v.c, "vendor" end
    local vp = ns.VendorPrice(e.ri)
    if vp then return vp, "vendor" end
    return nil
end

function ns.RecipeVendorCost(e)
    return e and e.ri and LFW.db.recipeVendors[e.ri] or nil
end

-- "1 [badge] Mark of Honor + 50s"
function ns.FormatVendorCost(v)
    local parts = {}
    for _, x in ipairs(v.x or {}) do
        local icon = x.icon and ("|T" .. x.icon .. ":14:14|t ") or ""
        parts[#parts + 1] = x.n .. " " .. icon .. (x.name or "")
    end
    if v.c and v.c > 0 then parts[#parts + 1] = ns.Coins(v.c) end
    return table.concat(parts, "  +  ")
end

-- Skill needed to learn the recipe, from the recipe item's tooltip
-- ("Requires Tailoring (75)"). nil when unknown.
function ns.RecipeSkill(e, key)
    if not e then return nil end
    if e.rs ~= nil then return e.rs or nil end
    if not e.ri then return nil end
    if not ns.ItemName(e.ri) then
        ns.LoadItem(e.ri, function() if LFW.RequestUIRefresh then LFW:RequestUIRefresh() end end)
        return nil
    end
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and SafeCall(C_TooltipInfo.GetItemByID, e.ri)
    if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines < 2 then return nil end
    local prof = ns.PROF_BY_KEY[key]
    local names = { (prof and prof.name or ""):lower(), ns.ProfName(key):lower() }
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not Secret(text) then
            local what, level = text:match("Requires (.-) %((%d+)%)")
            if what then
                what = what:lower()
                for _, n in ipairs(names) do
                    if n ~= "" and what:find(n, 1, true) then
                        e.rs = tonumber(level)
                        return e.rs
                    end
                end
            end
        end
    end
    e.rs = false
    return nil
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    if not LFW.db then return end
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        if LFW.merchantTimer then LFW.merchantTimer:Cancel() end
        LFW.merchantTimer = C_Timer.NewTimer(0.3, function()
            LFW.merchantTimer = nil
            local ok, err = pcall(LFW.ScanMerchant, LFW)
            if not ok then LFW:Debug("vendor: " .. tostring(err)) end
        end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        C_Timer.After(2, function() LFW:ScanAuctionatorRecipeItems() end)
    end
end)

function LFW:InitRecipes()
    self.db.recipeVendors = type(self.db.recipeVendors) == "table" and self.db.recipeVendors or {}
    for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "AUCTION_HOUSE_CLOSED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    -- any recipe item shown in a tooltip
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(_, data)
            local id = type(data) == "table" and data.id
            if type(id) == "number" and not Secret(id) and not LFW.unmatchedRecipeItems[id] then
                local name = ns.ItemName(id)
                if name and ItemInstant(id) == RECIPE_CLASS then LFW:LinkRecipeItem(id, name) end
            end
        end)
    end
    C_Timer.After(60, function() LFW:ScanAuctionatorRecipeItems() end)
end
