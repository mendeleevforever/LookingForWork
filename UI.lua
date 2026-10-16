-- UI.lua
-- The Looking For Work window, laid out like the WoW Forever profession window:
--   * a tab for every profession down the right-hand edge, Options tab on top
--   * left: search box, Filter button and the recipe list grouped by category
--     (every recipe, including the ones nobody in the guild has)
--   * right: the selected recipe, its reagents, and who in the guild has it
--     (First-name Last-name) with their online status
-- Drawn in the same palette as Player Notes (dark window, layered gold trim,
-- title plate on the top edge).

local ADDON_NAME, ns = ...
local LFW = ns.LFW

local W, H          = 880, 660
local TAB, TAB_GAP  = 40, 4
local HEADER_Y      = -44
local CONTENT_TOP   = -90
local CONTENT_BOT   = 52
local LEFT_X, LEFT_R = 16, 332           -- recipe list panel
local RIGHT_X       = 344                -- detail panel (to W - 16)
local LIST_X        = LEFT_X + 4
local LIST_TOP      = CONTENT_TOP - 30
local LIST_W        = LEFT_R - 24 - LIST_X
local ROW_H         = 22
local DW            = W - 16 - RIGHT_X   -- detail panel width
local CRAFT_ROW_H   = 22
local OTHER         = "Other"
local QUESTION      = "Interface\\Icons\\INV_Misc_QuestionMark"
local OPTIONS_ICON  = "Interface\\Icons\\INV_Misc_Gear_01"

-------------------------------------------------------------------------------
-- Palette and widgets (shared look with Player Notes)
-------------------------------------------------------------------------------
local C = {
    bg        = { 0.118, 0.082, 0.051 },
    gold      = { 0.541, 0.416, 0.173 },
    goldLight = { 0.722, 0.569, 0.235 },
    outline   = { 0.169, 0.118, 0.055 },
    inner     = { 0.290, 0.212, 0.094 },
    rule      = { 0.420, 0.314, 0.137 },
    header    = { 0.831, 0.627, 0.090 },
    text      = { 0.902, 0.839, 0.682 },
    muted     = { 0.612, 0.553, 0.439 },
    legend    = { 0.720, 0.650, 0.520 },
    plate     = { 0.165, 0.114, 0.063 },
    field     = { 0.071, 0.047, 0.027 },
    stripe    = { 0.353, 0.263, 0.125 },
    online    = { 0.25, 1.00, 0.25 },
    offline   = { 0.85, 0.65, 0.20 },
    none      = { 0.50, 0.47, 0.42 },
}
local DOT = "   |cff7d705a•|r   "
local GREEN, GREY, BLUE = "|cff40ff40", "|cff9d9d9d", "|cff69ccf0"

local function SetColor(obj, rgb, a) obj:SetTextColor(rgb[1], rgb[2], rgb[3], a or 1) end
local function Hex(rgb) return ("|cff%02x%02x%02x"):format(rgb[1] * 255, rgb[2] * 255, rgb[3] * 255) end

local function AddBorder(frame, layer, rgb, alpha, thickness, inset)
    local function edge()
        local t = frame:CreateTexture(nil, layer)
        t:SetColorTexture(rgb[1], rgb[2], rgb[3], alpha)
        return t
    end
    local top, bottom, left, right = edge(), edge(), edge(), edge()
    top:SetPoint("TOPLEFT", inset, -inset)
    top:SetPoint("TOPRIGHT", -inset, -inset)
    top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", inset, inset)
    bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", inset, -inset)
    left:SetPoint("BOTTOMLEFT", inset, inset)
    left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", -inset, -inset)
    right:SetPoint("BOTTOMRIGHT", -inset, inset)
    right:SetWidth(thickness)
    return { top, bottom, left, right }
end

local function SetEdgeColor(edges, rgb, a)
    for _, t in ipairs(edges) do t:SetColorTexture(rgb[1], rgb[2], rgb[3], a or 1) end
end

local function SetEdgesShown(edges, shown)
    for _, t in ipairs(edges) do t:SetShown(shown) end
end

local function SavePosition(f, posKey)
    local p, _, rp, x, y = f:GetPoint()
    if p and LFW.db then LFW.db.positions[posKey] = { p, rp, x, y } end
end

local function PlaceFrame(f, posKey)
    local pos = LFW.db and LFW.db.positions[posKey]
    f:ClearAllPoints()
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -20, 20)
    end
end

local function MakeWindow(globalName, w, h, posKey)
    local f = CreateFrame("Frame", globalName, UIParent)
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(self, posKey) end)
    PlaceFrame(f, posKey)
    f:Hide()
    tinsert(UISpecialFrames, globalName)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
    bg:SetAllPoints()
    AddBorder(f, "BORDER",  C.outline, 1, 2, -2)
    AddBorder(f, "BORDER",  C.gold,    1, 3,  0)
    AddBorder(f, "ARTWORK", C.inner,   1, 1,  3)

    local plate = CreateFrame("Frame", nil, f)
    plate:SetSize(300, 34)
    plate:SetPoint("TOP", 0, 18)
    plate:SetFrameLevel(f:GetFrameLevel() + 5)
    plate:EnableMouse(true)
    plate:RegisterForDrag("LeftButton")
    plate:SetScript("OnDragStart", function() f:StartMoving() end)
    plate:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePosition(f, posKey) end)
    local pbg = plate:CreateTexture(nil, "BACKGROUND")
    pbg:SetColorTexture(C.plate[1], C.plate[2], C.plate[3], 1)
    pbg:SetAllPoints()
    AddBorder(plate, "BORDER", C.outline,   1, 2, -2)
    AddBorder(plate, "BORDER", C.goldLight, 1, 2,  0)
    local title = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", 0, 0)
    title:SetTextColor(1, 0.82, 0)
    if title.SetWordWrap then title:SetWordWrap(false) end
    f.plate, f.title = plate, title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.info:SetPoint("TOP", 0, -24)
    SetColor(f.info, C.legend)
    return f
end

local function SetWindowTitle(f, text)
    f.title:SetText(text)
    f.plate:SetWidth(math.max(260, f.title:GetStringWidth() + 60))
end

local function AddFooterRule(f, y)
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.rule[1], C.rule[2], C.rule[3], 1)
    rule:SetPoint("BOTTOMLEFT", 20, y)
    rule:SetPoint("BOTTOMRIGHT", -20, y)
    rule:SetHeight(1)
    return rule
end

local function AddSection(parent, text, y, x1, x2)
    x1, x2 = x1 or 20, x2 or -20
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x1 + 2, y)
    fs:SetJustifyH("LEFT")
    SetColor(fs, C.header)
    fs:SetText(text)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.55)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", x1, y - 16)
    rule:SetPoint("TOPRIGHT", x2, y - 16)
    return fs, rule
end

local function AddLabel(parent, text, font, rgb)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    SetColor(fs, rgb or C.text)
    fs:SetText(text or "")
    return fs
end

local function AddFieldBox(parent, left, top, right, bottom)
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetColorTexture(C.field[1], C.field[2], C.field[3], 0.9)
    t:SetPoint("TOPLEFT", left, top)
    t:SetPoint("BOTTOMRIGHT", right, bottom)
    local edges = {}
    local function Edge(p1, p2, w, h)
        local e = parent:CreateTexture(nil, "BORDER")
        e:SetColorTexture(C.rule[1], C.rule[2], C.rule[3], 1)
        e:SetPoint(p1, t, p1)
        e:SetPoint(p2, t, p2)
        if w then e:SetWidth(w) end
        if h then e:SetHeight(h) end
        edges[#edges + 1] = e
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    return t, edges
end

local function AddPlaceholder(eb, text)
    local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ph:SetPoint("LEFT", 22, 0)
    SetColor(ph, C.muted)
    ph:SetText(text)
    local function Update()
        if eb:GetText() == "" and not eb:HasFocus() then ph:Show() else ph:Hide() end
    end
    eb:HookScript("OnTextChanged", Update)
    eb:HookScript("OnEditFocusGained", Update)
    eb:HookScript("OnEditFocusLost", Update)
    Update()
    return ph
end

-- Search box with a magnifying glass, like the profession window's
local function MakeSearchBox(globalName, parent, w)
    local eb = CreateFrame("EditBox", globalName, parent)
    eb:SetSize(w, 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal or GameFontHighlight)
    eb:SetTextInsets(20, 18, 0, 0)
    eb:SetMaxLetters(60)
    SetColor(eb, C.text)
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.02, 0.01, 0.95)
    local edges = AddBorder(eb, "BORDER", C.rule, 1, 1, 0)
    local glass = eb:CreateTexture(nil, "OVERLAY")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 4, -1)
    glass:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
    local clear = CreateFrame("Button", nil, eb)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", -3, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER")
    x:SetText("x")
    SetColor(x, C.muted)
    clear:SetScript("OnClick", function() eb:SetText(""); eb:ClearFocus() end)
    clear:Hide()
    eb:HookScript("OnTextChanged", function(self) clear:SetShown(self:GetText() ~= "") end)
    eb:HookScript("OnEditFocusGained", function() SetEdgeColor(edges, C.goldLight); glass:SetVertexColor(1, 0.82, 0) end)
    eb:HookScript("OnEditFocusLost", function() SetEdgeColor(edges, C.rule); glass:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

local function FlatButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 18)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.plate[1], C.plate[2], C.plate[3], 1)
    b.edges = AddBorder(b, "BORDER", C.gold, 1, 1, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0.25)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    SetColor(fs, C.header)
    fs:SetText(text)
    b.label = fs
    b:SetScript("OnMouseDown", function() fs:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
    return b
end

local function MenuButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
    b:SetSize(w or 110, 26)
    b:SetText(text)
    return b
end

local function AddHoverTip(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeScroll(globalName, parent, childWidth)
    local scroll = CreateFrame("ScrollFrame", globalName, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(childWidth, 10)
    scroll:SetScrollChild(child)
    return scroll, child
end

local function InsertChatLink(link)
    if not link then return false end
    local fn = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if fn then return pcall(fn, link) end
    return false
end

local function Whisper(target)
    if not target then return end
    local fn = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if fn then pcall(fn, target) end
end

-- "3 days", "5 hours", "2 months"
local function FormatDuration(sec)
    if not sec then return nil end
    if sec < 3600 then return "less than an hour" end
    if sec < 86400 then local h = math.floor(sec / 3600); return h == 1 and "1 hour" or (h .. " hours") end
    local d = math.floor(sec / 86400)
    if d < 30 then return d == 1 and "1 day" or (d .. " days") end
    local m = math.floor(d / 30)
    if m < 12 then return m == 1 and "1 month" or (m .. " months") end
    local y = math.floor(d / 365)
    return y <= 1 and "over a year" or (y .. " years")
end

local function GuildDisplayName(guildKey)
    if type(guildKey) ~= "string" then return nil end
    return guildKey:match("|(.+)$") or guildKey
end

-------------------------------------------------------------------------------
-- Status of a guild record
-------------------------------------------------------------------------------
-- returns: dot colour, status text, sort rank (0 = online)
local function MemberStatus(rec)
    if LFW:IsMe(rec) then return C.online, GREEN .. "Online|r " .. GREY .. "(you)|r", 0 end
    local m = LFW:MemberInfo(rec)
    if not m then
        if rec.mine then return C.none, GREY .. "Your character|r", 2 end
        return C.none, GREY .. "Not in guild roster|r", 3
    end
    if m.online then
        local zone = (type(m.zone) == "string" and m.zone ~= "") and (GREY .. "  •  " .. m.zone .. "|r") or ""
        return C.online, GREEN .. "Online|r" .. zone, 0
    end
    if m.mobile then return C.offline, BLUE .. "Mobile app|r", 1 end
    local ago = FormatDuration(m.offlineFor)
    return C.offline, GREY .. "Offline" .. (ago and ("  •  " .. ago) or "") .. "|r", 2
end

local function SortRecords(list)
    table.sort(list, function(a, b)
        local _, _, ra = MemberStatus(a)
        local _, _, rb = MemberStatus(b)
        if ra ~= rb then return ra < rb end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return list
end

local function SkillText(rec, key)
    local p = rec.profs[key]
    if not p or not p.lvl or p.lvl <= 0 then return "" end
    if p.max and p.max > 0 then return ("%d/%d"):format(p.lvl, p.max) end
    return tostring(p.lvl)
end

-------------------------------------------------------------------------------
-- Recipe list data
-------------------------------------------------------------------------------
local function RecipeName(id, e)
    return (e and e.n) or ns.SpellName(id) or ("Recipe #" .. id)
end

-- The item a recipe makes has the meaningful icon; many recipe spells only
-- have a generic placeholder icon, so the spell's icon is the last resort.
local function RecipeIcon(id, e)
    return (e and e.i) or (e and e.o and ns.ItemIcon(e.o)) or ns.SpellIcon(id) or QUESTION
end

-- Returns true plus the reason when it wasn't the name ("Tooltip: ...")
local function MatchSearch(search, id, name, e, crafters)
    if name:lower():find(search, 1, true) then return true end
    if e and e.o then
        local n = ns.ItemName(e.o)
        if n and n:lower():find(search, 1, true) then return true, "Creates: " .. n end
    end
    if e and e.r then
        for _, r in ipairs(e.r) do
            local n = ns.ItemName(r[1])
            if n and n:lower():find(search, 1, true) then return true, "Reagent: " .. n end
        end
    end
    -- tooltip text: stats and effects that aren't in the name
    local tip = ns.GetTooltipSearch(id, e)
    for i, low in ipairs(tip.lower) do
        if low:find(search, 1, true) then return true, "Tooltip: " .. tip.lines[i] end
    end
    if crafters then
        for _, rec in ipairs(crafters) do
            if rec.name and rec.name:lower():find(search, 1, true) then return true, "Crafter: " .. rec.name end
        end
    end
    return false
end

-- Flat list of headers + recipes for the virtual list, plus totals for the header bar
function LFW:BuildEntries(key, searchText)
    local cat = self.db.catalog[key]
    local recipes = cat and cat.recipes or {}
    local index = self:GetCrafterIndex(key)
    local s = self.db.settings
    local search = ns.Trim(searchText or ""):lower()
    local ids = {}
    for id in pairs(recipes) do ids[id] = true end
    for id in pairs(index) do ids[id] = true end

    local groups, total, known = {}, 0, 0
    for id in pairs(ids) do
        local e = recipes[id]
        local name = RecipeName(id, e)
        local crafters = index[id]
        local count, online = crafters and #crafters or 0, 0
        if crafters then
            for _, rec in ipairs(crafters) do if self:IsOnline(rec) then online = online + 1 end end
        end
        total = total + 1
        if count > 0 then known = known + 1 end
        local pass = true
        if not s.showUnowned and count == 0 then pass = false end
        if s.onlineOnly and online == 0 then pass = false end
        local why
        if pass and search ~= "" then pass, why = MatchSearch(search, id, name, e, crafters) end
        if pass then
            local cname = (e and e.c) or OTHER
            local g = groups[cname]
            if not g then g = {}; groups[cname] = g end
            g[#g + 1] = { id = id, name = name, count = count, online = online, crafters = crafters, match = why }
        end
    end

    local order = cat and cat.cats or {}
    local catList = {}
    for cname in pairs(groups) do catList[#catList + 1] = cname end
    table.sort(catList, function(a, b)
        local oa, ob = order[a] or (a == OTHER and 9999 or 999), order[b] or (b == OTHER and 9999 or 999)
        if oa ~= ob then return oa < ob end
        return a < b
    end)

    local collapsed = self.db.collapsed[key] or {}
    local entries = {}
    for _, cname in ipairs(catList) do
        local list = groups[cname]
        local isCollapsed = collapsed[cname] and search == ""
        entries[#entries + 1] = { header = true, cat = cname, n = #list, collapsed = isCollapsed }
        if not isCollapsed then
            table.sort(list, function(a, b) return a.name < b.name end)
            for _, r in ipairs(list) do entries[#entries + 1] = r end
        end
    end
    return entries, total, known
end

-------------------------------------------------------------------------------
-- Main window
-------------------------------------------------------------------------------
function LFW:CreateMainFrame()
    if self.frame then return self.frame end
    local f = MakeWindow("LookingForWorkFrame", W, H, "main")
    SetWindowTitle(f, "Looking For Work")
    if f.SetClampRectInsets then f:SetClampRectInsets(0, TAB + 6, 20, 0) end
    self.frame = f
    self.selected = {}

    self:CreateTabs(f)
    self:CreateProfessionView(f)
    self:CreateOptionsView(f)

    -- Footer
    AddFooterRule(f, 46)
    f.legend = AddLabel(f, "", "GameFontNormalSmall", C.legend)
    f.legend:SetPoint("BOTTOMLEFT", 22, 20)
    f.legend:SetWidth(W - 180)
    if f.legend.SetWordWrap then f.legend:SetWordWrap(false) end
    local closeBtn = MenuButton(f, "Close", 110)
    closeBtn:SetPoint("BOTTOMRIGHT", -20, 13)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnShow", function()
        LFW:RequestRoster()
        LFW:UpdateRoster()
        LFW.indexDirty = true
        LFW:SelectTab(LFW.currentTab or LFW:DefaultTab())
        f.ticker = C_Timer.NewTicker(1, function() LFW:OnTick() end)
    end)
    f:SetScript("OnHide", function()
        if f.ticker then f.ticker:Cancel(); f.ticker = nil end
        if f.search then f.search:ClearFocus() end
        if LFW.dropList then LFW.dropList:Hide() end
        if LFW.warmTicker then LFW.warmTicker:Cancel(); LFW.warmTicker, LFW.warmKey = nil, nil end
        GameTooltip:Hide()
    end)
    return f
end

function LFW:DefaultTab()
    local saved = self.db.settings.lastTab
    if saved and (saved == "options" or ns.PROF_BY_KEY[saved]) then return saved end
    local me = self:GetMe()
    if me then
        for _, p in ipairs(ns.PROFESSIONS) do
            if me.profs[p.key] then return p.key end
        end
    end
    return "options"
end

function LFW:Toggle()
    local f = self:CreateMainFrame()
    if f:IsShown() then f:Hide() else f:Show(); f:Raise() end
end

function LFW:Open(tab)
    local f = self:CreateMainFrame()
    if tab then self.currentTab = tab end
    if f:IsShown() then
        if tab then self:SelectTab(tab) end
    else
        f:Show()
    end
    f:Raise()
end

-- Every second while the window is open: Update cooldown, roster refresh
function LFW:OnTick()
    self.tickCount = (self.tickCount or 0) + 1
    if self.tickCount % 60 == 0 then self:RequestRoster() end
    if self.currentTab == "options" then self:UpdateOptionsButtons() end
end

local refreshPending, detailPending = false, false
function LFW:RequestUIRefresh(detailOnly)
    local f = self.frame
    if not f or not f:IsShown() then return end
    if detailOnly then detailPending = true else refreshPending = true end
    if self.refreshTimer then return end
    self.refreshTimer = C_Timer.NewTimer(0.15, function()
        self.refreshTimer = nil
        local full, detail = refreshPending, detailPending
        refreshPending, detailPending = false, false
        if not f:IsShown() then return end
        if self.currentTab == "options" then
            if full then self:RefreshOptions() end
        elseif full then
            self:RefreshProfession()
        elseif detail then
            self:UpdateDetail()
        end
        self:UpdateTabs()
    end)
end

-------------------------------------------------------------------------------
-- Tabs down the right edge
-------------------------------------------------------------------------------
local function CreateTab(f, key, icon, y)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(TAB, TAB)
    b.y = y
    b:SetPoint("TOPLEFT", f, "TOPRIGHT", 1, y)
    b:SetFrameLevel(f:GetFrameLevel() + 2)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.plate[1], C.plate[2], C.plate[3], 1)
    b.outline = AddBorder(b, "BORDER", C.outline, 1, 2, -2)
    b.edges = AddBorder(b, "BORDER", C.gold, 1, 2, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexture(icon)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 0.9, 0.6, 0.18)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetPoint("TOPLEFT", -3, 3)
    b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.glow:SetColorTexture(1, 0.82, 0.2, 0.18)
    b.glow:Hide()
    b.key = key
    b:SetScript("OnClick", function(self) LFW:SelectTab(self.key) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.key == "options" then
            GameTooltip:AddLine("Options", 1, 0.82, 0)
            GameTooltip:AddLine("Update guild data, Ignore Queries, your characters", 1, 1, 1, true)
        else
            GameTooltip:AddLine(ns.ProfName(self.key), 1, 0.82, 0)
            local n = LFW:CatalogCount(self.key)
            local members = LFW:GetProfessionMembers(self.key)
            local online = 0
            for _, rec in ipairs(members) do if LFW:IsOnline(rec) then online = online + 1 end end
            GameTooltip:AddLine(n > 0 and (n .. " recipes saved") or "No recipe list saved yet", C.text[1], C.text[2], C.text[3])
            GameTooltip:AddLine(("%d in the guild have it, %d online"):format(#members, online), C.muted[1], C.muted[2], C.muted[3])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function LFW:CreateTabs(f)
    f.tabs = {}
    local y = -22
    f.tabs.options = CreateTab(f, "options", OPTIONS_ICON, y)
    y = y - TAB - TAB_GAP - 8
    for _, p in ipairs(ns.PROFESSIONS) do
        f.tabs[p.key] = CreateTab(f, p.key, ns.ProfIcon(p), y)
        y = y - TAB - TAB_GAP
    end
end

function LFW:UpdateTabs()
    local f = self.frame
    if not f then return end
    for key, b in pairs(f.tabs) do
        local selected = key == self.currentTab
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPRIGHT", selected and -2 or 1, b.y)
        SetEdgeColor(b.edges, selected and { 1, 0.82, 0.25 } or C.gold)
        b.glow:SetShown(selected)
        if key ~= "options" then
            b.icon:SetTexture(ns.ProfIcon(key))
            local hasData = self:CatalogCount(key) > 0 or #self:GetProfessionMembers(key) > 0
            b.icon:SetDesaturated(not hasData and not selected)
            b.icon:SetAlpha((hasData or selected) and 1 or 0.6)
        end
    end
end

function LFW:SelectTab(key)
    local f = self:CreateMainFrame()
    if key ~= "options" and not ns.PROF_BY_KEY[key] then key = "options" end
    self.currentTab = key
    self.db.settings.lastTab = key
    if self.dropList then self.dropList:Hide() end
    GameTooltip:Hide()
    if key == "options" then
        f.profView:Hide()
        f.optionsView:Show()
        f.legend:SetText(("Looking For Work %s"):format(self.VERSION) .. DOT .. "Only guild members are asked" .. DOT .. "/lfw help")
        self:RefreshOptions()
    else
        f.optionsView:Hide()
        f.profView:Show()
        f.legend:SetText("Click a recipe to see reagents and crafters" .. DOT .. "Click a crafter to whisper" .. DOT .. "Shift-click to link")
        if f.search:GetText() ~= "" then f.search:SetText("") end   -- also refreshes
        self:RefreshProfession()
        f.listScroll:SetVerticalScroll(0)
    end
    self:UpdateGuildLine()
    self:UpdateTabs()
end

function LFW:UpdateGuildLine()
    local f = self.frame
    if not f then return end
    if not IsInGuild() then
        f.info:SetText("Not in a guild  —  showing your own characters")
        return
    end
    local r = ns.roster
    local name = self.guildName or (GetGuildInfo("player")) or "Guild"
    if r.loaded then
        f.info:SetText(("%s  —  %d of %d members online"):format(name, r.online, r.total))
    else
        f.info:SetText(name)
    end
end

-------------------------------------------------------------------------------
-- Profession view: header, recipe list, detail panel
-------------------------------------------------------------------------------
function LFW:CreateProfessionView(f)
    local pv = CreateFrame("Frame", nil, f)
    pv:SetAllPoints()
    f.profView = pv

    -- Header: profession icon, name and a "known in guild" bar (like the skill bar)
    local iconHolder = CreateFrame("Frame", nil, pv)
    iconHolder:SetSize(38, 38)
    iconHolder:SetPoint("TOPLEFT", 18, HEADER_Y + 1)
    AddBorder(iconHolder, "BORDER", C.gold, 1, 1, 0)
    pv.icon = iconHolder:CreateTexture(nil, "ARTWORK")
    pv.icon:SetPoint("TOPLEFT", 2, -2)
    pv.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    pv.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    pv.title = AddLabel(pv, "", "GameFontNormalLarge", C.header)
    pv.title:SetPoint("TOPLEFT", 66, HEADER_Y - 1)

    pv.stats = AddLabel(pv, "", "GameFontNormalSmall", C.legend)
    pv.stats:SetPoint("TOPRIGHT", -22, HEADER_Y - 4)
    pv.stats:SetJustifyH("RIGHT")

    local bar = CreateFrame("StatusBar", nil, pv)
    bar:SetPoint("TOPLEFT", 66, HEADER_Y - 22)
    bar:SetPoint("TOPRIGHT", -20, HEADER_Y - 22)
    bar:SetHeight(16)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.86, 0.36, 0.12)
    bar:SetMinMaxValues(0, 1)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.03, 0.02, 0.01, 0.95)
    AddBorder(bar, "OVERLAY", C.rule, 1, 1, -1)
    pv.barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pv.barText:SetPoint("CENTER", 0, 0)
    pv.bar = bar

    -- Left panel: search + filter + list
    AddFieldBox(pv, LEFT_X, CONTENT_TOP, -(W - LEFT_R), CONTENT_BOT)

    local search = MakeSearchBox("LookingForWorkSearchBox", pv, 214)
    search:SetPoint("TOPLEFT", LEFT_X + 6, CONTENT_TOP - 5)
    AddPlaceholder(search, "Search")
    search:HookScript("OnTextChanged", function() LFW:RefreshProfession(true) end)
    AddHoverTip(search, "Search", "Matches recipe names and their tooltip text (stats and effects, e.g. \"defense\" or \"intellect\"), what they make, reagents, and crafter names.")
    f.search = search

    local filter = FlatButton(pv, "Filter  |cffffd100>|r", 84, 22)
    filter:SetPoint("TOPLEFT", LEFT_X + 226, CONTENT_TOP - 5)
    filter:SetScript("OnClick", function(self) LFW:ToggleFilterMenu(self) end)
    f.filterBtn = filter

    local scroll, child = MakeScroll("LookingForWorkRecipeScroll", pv, LIST_W)
    scroll:SetPoint("TOPLEFT", LIST_X, LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", pv, "BOTTOMLEFT", LEFT_R - 24, CONTENT_BOT + 4)
    f.listScroll, f.listChild, f.rows = scroll, child, {}
    scroll:HookScript("OnVerticalScroll", function() LFW:RenderList() end)
    scroll:HookScript("OnSizeChanged", function() LFW:RenderList() end)
    -- Safety net: re-render whenever the scroll position changes for any reason
    scroll:HookScript("OnUpdate", function(self)
        local off = self:GetVerticalScroll()
        if off ~= self.lastOffset then self.lastOffset = off; LFW:RenderList() end
    end)

    f.listEmpty = AddLabel(pv, "", "GameFontNormal", C.muted)
    f.listEmpty:SetPoint("TOPLEFT", LIST_X + 10, LIST_TOP - 30)
    f.listEmpty:SetWidth(LIST_W - 20)
    f.listEmpty:SetJustifyH("CENTER")
    if f.listEmpty.SetSpacing then f.listEmpty:SetSpacing(3) end

    -- Right panel: recipe detail
    AddFieldBox(pv, RIGHT_X, CONTENT_TOP, -16, CONTENT_BOT)
    local d = CreateFrame("Frame", nil, pv)
    d:SetPoint("TOPLEFT", RIGHT_X, CONTENT_TOP)
    d:SetPoint("BOTTOMRIGHT", -16, CONTENT_BOT)
    f.detail = d
    self:CreateDetail(d)
end

-------------------------------------------------------------------------------
-- Recipe list rows (virtual list: only visible rows exist)
-------------------------------------------------------------------------------
local function GetListRow(f, i)
    if f.rows[i] then return f.rows[i] end
    local row = CreateFrame("Button", nil, f.listChild)
    row:SetSize(LIST_W, ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    -- header look: dark plate with gold edge, gold text and -/+ (like the category bars)
    row.hbg = row:CreateTexture(nil, "BACKGROUND")
    row.hbg:SetPoint("TOPLEFT", 0, -1)
    row.hbg:SetPoint("BOTTOMRIGHT", 0, 1)
    row.hbg:SetColorTexture(0.22, 0.14, 0.06, 1)
    row.hedges = {}
    local function hedge(p1, p2, w, h)
        local e = row:CreateTexture(nil, "BORDER")
        e:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
        e:SetPoint(p1, row.hbg, p1)
        e:SetPoint(p2, row.hbg, p2)
        if w then e:SetWidth(w) end
        if h then e:SetHeight(h) end
        row.hedges[#row.hedges + 1] = e
    end
    hedge("TOPLEFT", "TOPRIGHT", nil, 1)
    hedge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    hedge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    hedge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    row.htext = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.htext:SetPoint("LEFT", 8, 0)
    row.htext:SetPoint("RIGHT", -40, 0)
    row.htext:SetJustifyH("LEFT")
    SetColor(row.htext, C.header)
    row.htoggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.htoggle:SetPoint("RIGHT", -8, 0)
    SetColor(row.htoggle, C.header)
    row.hcount = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.hcount:SetPoint("RIGHT", -26, 0)
    SetColor(row.hcount, C.muted)

    -- recipe look
    row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0.32)
    row.selBar = row:CreateTexture(nil, "ARTWORK")
    row.selBar:SetPoint("TOPLEFT")
    row.selBar:SetPoint("BOTTOMLEFT")
    row.selBar:SetWidth(2)
    row.selBar:SetColorTexture(1, 0.82, 0.2, 1)
    row.dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.dot:SetPoint("LEFT", 10, 0)
    row.dot:SetText("•")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 24, 0)
    row.text:SetPoint("RIGHT", -30, 0)
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("RIGHT", -6, 0)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 0, -1)
    hl:SetPoint("BOTTOMRIGHT", 0, 1)
    hl:SetColorTexture(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0.16)

    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.header then
            LFW:ToggleCategory(e.cat)
        elseif IsModifiedClick and IsModifiedClick("CHATLINK") then
            LFW:LinkRecipe(e.id)
        else
            LFW:SelectRecipe(e.id)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e or e.header then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name, 1, 1, 1)
        if e.match then
            GameTooltip:AddLine("Found by search  —  " .. e.match, 1, 0.82, 0, true)
        end
        if e.count == 0 then
            GameTooltip:AddLine("Nobody in the guild has this recipe yet.", C.muted[1], C.muted[2], C.muted[3])
        else
            local list = SortRecords({ unpack(e.crafters) })
            for i, rec in ipairs(list) do
                if i > 8 then
                    GameTooltip:AddLine(("+ %d more"):format(#list - 8), C.muted[1], C.muted[2], C.muted[3])
                    break
                end
                local dot = MemberStatus(rec)
                GameTooltip:AddLine(Hex(dot) .. "•|r " .. ns.ColorName(rec.name, rec.class))
            end
        end
        GameTooltip:AddLine("Click for reagents and crafters", C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
    return row
end

local function FillRow(row, e, selectedId)
    row.entry = e
    local isHeader = e.header and true or false
    row.hbg:SetShown(isHeader)
    SetEdgesShown(row.hedges, isHeader)
    row.htext:SetShown(isHeader)
    row.htoggle:SetShown(isHeader)
    row.hcount:SetShown(isHeader)
    row.text:SetShown(not isHeader)
    row.count:SetShown(not isHeader)
    if isHeader then
        row.dot:Hide()
        row.sel:Hide()
        row.selBar:Hide()
        row.htext:SetText(e.cat)
        row.htoggle:SetText(e.collapsed and "+" or "–")
        row.hcount:SetText(e.collapsed and tostring(e.n) or "")
        return
    end
    local selected = e.id == selectedId
    row.sel:SetShown(selected)
    row.selBar:SetShown(selected)
    row.text:SetText(e.name)
    if e.count > 0 then
        SetColor(row.text, selected and { 1, 1, 1 } or C.text)
        row.dot:Show()
        SetColor(row.dot, e.online > 0 and C.online or C.offline)
        row.count:SetText(tostring(e.count))
        SetColor(row.count, e.online > 0 and { 0.55, 0.9, 0.55 } or C.muted)
    else
        SetColor(row.text, selected and { 0.85, 0.85, 0.85 } or C.none)
        row.dot:Hide()
        row.count:SetText("")
    end
end

function LFW:RenderList()
    local f = self.frame
    if not f or not f.profView:IsShown() then return end
    local entries = self.entries or {}
    local scroll = f.listScroll
    local offset = scroll:GetVerticalScroll() or 0
    local first = math.floor(offset / ROW_H) + 1
    local visible = math.ceil((scroll:GetHeight() or 400) / ROW_H) + 1
    local selectedId = self.selected[self.currentTab]
    for i = 1, visible do
        local row = GetListRow(f, i)
        local idx = first + i - 1
        local e = entries[idx]
        if e then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.listChild, "TOPLEFT", 0, -(idx - 1) * ROW_H)
            FillRow(row, e, selectedId)
            row:Show()
        else
            row:Hide()
            row.entry = nil
        end
    end
    for i = visible + 1, #f.rows do f.rows[i]:Hide() end
end

-- Rebuild the list (and header) for the current profession
-- Build tooltip search text a few recipes at a time, so typing in the search
-- box never has to wait for hundreds of tooltips
function LFW:WarmTooltipCache(key)
    if self.warmKey == key and self.warmTicker then return end
    if self.warmTicker then self.warmTicker:Cancel(); self.warmTicker = nil end
    local cat = self.db.catalog[key]
    local queue = {}
    for id in pairs(cat and cat.recipes or {}) do
        if not ns.HasTooltipSearch(id) then queue[#queue + 1] = id end
    end
    for id in pairs(self:GetCrafterIndex(key)) do
        if not ns.HasTooltipSearch(id) and not (cat and cat.recipes[id]) then queue[#queue + 1] = id end
    end
    if #queue == 0 then return end
    self.warmKey = key
    local pos = 1
    self.warmTicker = C_Timer.NewTicker(0.05, function()
        local recipes = self.db.catalog[key] and self.db.catalog[key].recipes or {}
        for _ = 1, 15 do
            local id = queue[pos]
            if not id then
                if self.warmTicker then self.warmTicker:Cancel() end
                self.warmTicker, self.warmKey = nil, nil
                return
            end
            ns.GetTooltipSearch(id, recipes[id])
            pos = pos + 1
        end
    end)
end

-- An item or spell finished loading: redo an active search so it can match
function LFW:OnSearchDataLoaded()
    local f = self.frame
    if f and f:IsShown() and f.profView:IsShown() and f.search:GetText() ~= "" then
        self:RequestUIRefresh()
    end
end

function LFW:RefreshProfession(fromSearch)
    local f = self.frame
    local key = self.currentTab
    if not f or not ns.PROF_BY_KEY[key] then return end
    self:WarmTooltipCache(key)

    local entries, total, known = self:BuildEntries(key, f.search:GetText())
    self.entries = entries
    f.listChild:SetHeight(math.max(10, #entries * ROW_H))
    f.listScroll.lastOffset = nil
    if fromSearch then f.listScroll:SetVerticalScroll(0) end

    -- header
    local pv = f.profView
    pv.icon:SetTexture(ns.ProfIcon(key))
    pv.title:SetText(ns.ProfName(key))
    pv.bar:SetValue(total > 0 and known / total or 0)
    if total > 0 and self:CatalogCount(key) == 0 then
        pv.barText:SetText(("%s   recipe list not received yet  —  showing the %d recipes guild members know"):format(ns.ProfName(key), total))
    elseif total > 0 then
        pv.barText:SetText(("%s   %d / %d recipes known in the guild"):format(ns.ProfName(key), known, total))
    else
        pv.barText:SetText(ns.ProfName(key) .. "   no recipe list saved yet")
    end
    local members = self:GetProfessionMembers(key)
    local online = 0
    for _, rec in ipairs(members) do if self:IsOnline(rec) then online = online + 1 end end
    pv.stats:SetText(("%d %s%s%d online"):format(#members, #members == 1 and "crafter" or "crafters", "   •   ", online))

    -- empty list message
    if #entries == 0 then
        local name = ns.ProfName(key)
        if total == 0 then
            f.listEmpty:SetText(("No %s recipes saved yet.\n\nOpen %s on any character that knows it, or press Update on the Options tab to get the recipe list from your guild."):format(name, name))
        else
            f.listEmpty:SetText("No recipes match your search or filter.")
        end
        f.listEmpty:Show()
    else
        f.listEmpty:Hide()
    end

    self:RenderList()
    self:UpdateDetail()
end

function LFW:ToggleCategory(cname)
    local key = self.currentTab
    self.db.collapsed[key] = self.db.collapsed[key] or {}
    local c = self.db.collapsed[key]
    c[cname] = not c[cname] or nil
    self:RefreshProfession()
end

function LFW:SetAllCollapsed(collapse)
    local key = self.currentTab
    if not ns.PROF_BY_KEY[key] then return end
    self.db.collapsed[key] = {}
    if collapse then
        local cat = self.db.catalog[key]
        for cname in pairs(cat and cat.cats or {}) do self.db.collapsed[key][cname] = true end
        self.db.collapsed[key][OTHER] = true
        for _, e in ipairs(self.entries or {}) do
            if e.header then self.db.collapsed[key][e.cat] = true end
        end
    end
    self:RefreshProfession()
end

function LFW:SelectRecipe(id)
    local key = self.currentTab
    if self.selected[key] == id then
        self.selected[key] = nil          -- click again: back to the profession overview
    else
        self.selected[key] = id
    end
    self:RenderList()
    self:UpdateDetail()
end

function LFW:LinkRecipe(id)
    local e = self.db.catalog[self.currentTab] and self.db.catalog[self.currentTab].recipes[id]
    local link
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink then link = ns.SafeCall(C_TradeSkillUI.GetRecipeLink, id) end
    if not link and e and e.o then link = ns.ItemLink(e.o) end
    if not link and C_Spell and C_Spell.GetSpellLink then link = ns.SafeCall(C_Spell.GetSpellLink, id) end
    if not link and GetSpellLink then link = ns.SafeCall(GetSpellLink, id) end
    InsertChatLink(link)
end

-------------------------------------------------------------------------------
-- Filter menu
-------------------------------------------------------------------------------
local FILTER_ITEMS = {
    { text = "Show recipes nobody has", setting = "showUnowned" },
    { text = "Only recipes with an online crafter", setting = "onlineOnly" },
    { separator = true },
    { text = "Expand all categories", action = function() LFW:SetAllCollapsed(false) end },
    { text = "Collapse all categories", action = function() LFW:SetAllCollapsed(true) end },
}

function LFW:CreateDropList()
    if self.dropList then return self.dropList end
    local l = CreateFrame("Frame", "LookingForWorkFilterMenu", UIParent)
    l:SetFrameStrata("FULLSCREEN_DIALOG")
    l:SetClampedToScreen(true)
    l:EnableMouse(true)
    l:Hide()
    local bg = l:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.98)
    AddBorder(l, "BORDER", C.outline, 1, 2, -2)
    AddBorder(l, "BORDER", C.gold, 1, 1, 0)

    -- clicking anywhere else closes the menu
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:Hide()
    catcher:SetScript("OnClick", function() l:Hide() end)
    l:SetScript("OnShow", function() catcher:Show() end)
    l:SetScript("OnHide", function() catcher:Hide() end)

    tinsert(UISpecialFrames, "LookingForWorkFilterMenu")

    l.items = {}
    local y, w = -6, 250
    for i, item in ipairs(FILTER_ITEMS) do
        if item.separator then
            local sep = l:CreateTexture(nil, "ARTWORK")
            sep:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.55)
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", 8, y - 4)
            sep:SetPoint("TOPRIGHT", -8, y - 4)
            y = y - 9
        else
            local b = CreateFrame("Button", nil, l)
            b:SetSize(w - 8, 20)
            b:SetPoint("TOPLEFT", 4, y)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0.22)
            b.check = b:CreateTexture(nil, "OVERLAY")
            b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            b.check:SetSize(16, 16)
            b.check:SetPoint("LEFT", 4, 0)
            b.box = b:CreateTexture(nil, "ARTWORK")
            b.box:SetSize(12, 12)
            b.box:SetPoint("CENTER", b.check, "CENTER", 0, 0)
            b.box:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 24, 0)
            b.text:SetText(item.text)
            SetColor(b.text, C.text)
            b.item = item
            b:SetScript("OnClick", function(self)
                local it = self.item
                if it.setting then
                    LFW.db.settings[it.setting] = not LFW.db.settings[it.setting]
                    LFW:UpdateDropList()
                    LFW:RefreshProfession()
                else
                    l:Hide()
                    it.action()
                end
            end)
            l.items[#l.items + 1] = b
            y = y - 20
        end
    end
    l:SetSize(w, -y + 6)
    self.dropList = l
    return l
end

function LFW:UpdateDropList()
    local l = self.dropList
    if not l then return end
    for _, b in ipairs(l.items) do
        local it = b.item
        if it.setting then
            b.box:Show()
            b.check:SetShown(self.db.settings[it.setting] and true or false)
        else
            b.box:Hide()
            b.check:Hide()
        end
    end
end

function LFW:ToggleFilterMenu(anchor)
    local l = self:CreateDropList()
    if l:IsShown() then l:Hide(); return end
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    self:UpdateDropList()
    l:Show()
    l:Raise()
end

-------------------------------------------------------------------------------
-- Detail panel
-------------------------------------------------------------------------------
local REAGENT_COLS, REAGENT_ROW_H, MAX_REAGENTS = 2, 38, 8

function LFW:CreateDetail(d)
    local ib = CreateFrame("Button", nil, d)
    ib:SetSize(44, 44)
    ib:SetPoint("TOPLEFT", 16, -16)
    AddBorder(ib, "OVERLAY", C.gold, 1, 1, 0)
    ib.tex = ib:CreateTexture(nil, "ARTWORK")
    ib.tex:SetPoint("TOPLEFT", 1, -1)
    ib.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    ib.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ib:SetScript("OnEnter", function(self)
        local id = self.recipeID
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if self.outItem then shown = pcall(GameTooltip.SetItemByID, GameTooltip, self.outItem) end
        if not shown then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, id) end
        if not shown then GameTooltip:AddLine(self.recipeName or "?", 1, 1, 1) end
        GameTooltip:Show()
    end)
    ib:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ib:SetScript("OnClick", function(self)
        if self.recipeID and IsModifiedClick and IsModifiedClick("CHATLINK") then LFW:LinkRecipe(self.recipeID) end
    end)
    d.iconBtn = ib

    d.name = AddLabel(d, "", "GameFontNormalLarge", { 1, 1, 1 })
    d.name:SetPoint("TOPLEFT", ib, "TOPRIGHT", 12, -3)
    d.name:SetWidth(DW - 16 - 44 - 12 - 16)
    if d.name.SetWordWrap then d.name:SetWordWrap(false) end

    d.sub = AddLabel(d, "", "GameFontNormalSmall", C.muted)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)
    d.sub:SetWidth(DW - 16 - 44 - 12 - 16)

    d.desc = AddLabel(d, "", "GameFontHighlight", C.text)
    d.desc:SetWidth(DW - 32)
    if d.desc.SetSpacing then d.desc:SetSpacing(2) end

    d.creates = AddLabel(d, "", "GameFontHighlight", C.text)
    d.creates:SetWidth(DW - 32)
    d.requires = AddLabel(d, "", "GameFontHighlight", C.text)
    d.requires:SetWidth(DW - 32)

    d.reagHeader = AddLabel(d, "Reagents:", "GameFontNormal", C.header)
    d.reagNote = AddLabel(d, "", "GameFontNormalSmall", C.muted)
    d.reagNote:SetWidth(DW - 32)

    d.reagents = {}
    local colW = math.floor((DW - 32) / REAGENT_COLS)
    for i = 1, MAX_REAGENTS do
        local b = CreateFrame("Button", nil, d)
        b:SetSize(colW - 6, 34)
        local slot = b:CreateTexture(nil, "BACKGROUND")
        slot:SetSize(34, 34)
        slot:SetPoint("LEFT")
        slot:SetColorTexture(0, 0, 0, 0.8)
        local holder = CreateFrame("Frame", nil, b)
        holder:SetSize(34, 34)
        holder:SetPoint("LEFT")
        AddBorder(holder, "OVERLAY", C.rule, 1, 1, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("LEFT", slot, "RIGHT", 8, 0)
        b.text:SetPoint("RIGHT", -2, 0)
        b.text:SetJustifyH("LEFT")
        if b.text.SetWordWrap then b.text:SetWordWrap(true) end
        b:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then
                GameTooltip:AddLine(ns.ItemName(self.itemID) or ("Item #" .. self.itemID), 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self.itemID and IsModifiedClick and IsModifiedClick("CHATLINK") then InsertChatLink(ns.ItemLink(self.itemID)) end
        end)
        b:Hide()
        d.reagents[i] = b
    end
    d.colW = colW

    -- Crafting cost and profit (Auctionator prices), like Auctionator's own lines
    d.costLine = AddLabel(d, "", "GameFontHighlight", C.text)
    d.costLine:SetWidth(DW - 32)
    d.profitLine = AddLabel(d, "", "GameFontHighlight", C.text)
    d.profitLine:SetWidth(DW - 32)
    d.costHover = CreateFrame("Frame", nil, d)
    d.costHover:EnableMouse(true)
    d.costHover:SetScript("OnEnter", function(self) LFW:ShowCostTooltip(self) end)
    d.costHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.costHover:Hide()

    d.craftHeader = AddLabel(d, "", "GameFontNormal", C.header)
    d.craftRule = d:CreateTexture(nil, "ARTWORK")
    d.craftRule:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.55)
    d.craftRule:SetHeight(1)
    d.craftHint = AddLabel(d, "", "GameFontNormalSmall", C.muted)
    d.craftHint:SetJustifyH("RIGHT")

    local scroll, child = MakeScroll("LookingForWorkCrafterScroll", d, DW - 32 - 24)
    d.craftScroll, d.craftChild, d.craftRows = scroll, child, {}
    d.craftEmpty = AddLabel(child, "", "GameFontNormal", C.muted)
    d.craftEmpty:SetPoint("TOPLEFT", 6, -8)
    d.craftEmpty:SetWidth(DW - 32 - 40)
end

local function GetCrafterRow(d, i)
    if d.craftRows[i] then return d.craftRows[i] end
    local cw = DW - 32 - 24
    local row = CreateFrame("Button", nil, d.craftChild)
    row:SetSize(cw, CRAFT_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * CRAFT_ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if i % 2 == 0 then bg:SetColorTexture(C.stripe[1], C.stripe[2], C.stripe[3], 0.22) else bg:SetColorTexture(0, 0, 0, 0) end
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0.18)
    row.dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.dot:SetPoint("LEFT", 6, 0)
    row.dot:SetText("•")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 20, 0)
    row.name:SetWidth(170)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetPoint("LEFT", 196, 0)
    row.status:SetWidth(cw - 196 - 70)
    row.status:SetJustifyH("LEFT")
    if row.status.SetWordWrap then row.status:SetWordWrap(false) end
    row.skill = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.skill:SetPoint("RIGHT", -6, 0)
    row.skill:SetJustifyH("RIGHT")
    SetColor(row.skill, C.legend)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        local rec = self.rec
        if not rec or LFW:IsMe(rec) then return end
        local m = LFW:MemberInfo(rec)
        Whisper((m and m.raw) or rec.name)
    end)
    row:SetScript("OnEnter", function(self)
        local rec = self.rec
        if not rec then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        LFW:AddMemberTooltip(rec, self.profKey)
        if not LFW:IsMe(rec) then GameTooltip:AddLine("Click to whisper", C.muted[1], C.muted[2], C.muted[3]) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.craftRows[i] = row
    return row
end

-- Shared tooltip body for a guild member
function LFW:AddMemberTooltip(rec, highlightKey)
    GameTooltip:AddLine(ns.ColorName(rec.name, rec.class))
    local _, status = MemberStatus(rec)
    GameTooltip:AddLine(status, 1, 1, 1)
    local m = self:MemberInfo(rec)
    if m and (m.rank or m.level) then
        GameTooltip:AddLine(("%s%s"):format(m.level and ("Level " .. m.level) or "", m.rank and ("  •  " .. m.rank) or ""),
            C.muted[1], C.muted[2], C.muted[3])
    end
    for _, p in ipairs(ns.PROFESSIONS) do
        local prof = rec.profs[p.key]
        if prof then
            local skill = SkillText(rec, p.key)
            local recipes = prof.known and (ns.CountKeys(prof.known) .. " recipes") or "recipes not shared yet"
            local r, g, b = C.text[1], C.text[2], C.text[3]
            if p.key == highlightKey then r, g, b = 1, 0.82, 0 end
            GameTooltip:AddDoubleLine(ns.ProfName(p) .. (skill ~= "" and ("  " .. skill) or ""), recipes, r, g, b,
                C.muted[1], C.muted[2], C.muted[3])
        end
    end
    if self:IsMe(rec) then
        GameTooltip:AddLine("Your current character", C.muted[1], C.muted[2], C.muted[3])
    elseif rec.mine then
        GameTooltip:AddLine("Your character  •  saved " .. ns.FormatAgo(rec.updated), C.muted[1], C.muted[2], C.muted[3])
    else
        GameTooltip:AddLine("Data from " .. ns.FormatAgo(rec.updated), C.muted[1], C.muted[2], C.muted[3])
    end
end

-- rows: { { rec = rec, note = optional status override }, ... }
local function FillCrafters(d, rows, key, emptyText)
    for i, r in ipairs(rows) do
        local row = GetCrafterRow(d, i)
        local rec = r.rec
        row.rec, row.profKey = rec, key
        local dot, status = MemberStatus(rec)
        SetColor(row.dot, dot)
        row.name:SetText(ns.ColorName(rec.name, rec.class))
        row.status:SetText(r.note and (status .. GREY .. "  •  " .. r.note .. "|r") or status)
        row.skill:SetText(SkillText(rec, key))
        row:Show()
    end
    for i = #rows + 1, #d.craftRows do
        d.craftRows[i]:Hide()
        d.craftRows[i].rec = nil
    end
    d.craftChild:SetHeight(math.max(10, #rows * CRAFT_ROW_H))
    if #rows == 0 then
        d.craftEmpty:SetText(emptyText or "")
        d.craftEmpty:Show()
    else
        d.craftEmpty:Hide()
    end
end

local function PlaceText(d, fs, text, y, gap)
    if text and text ~= "" then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 16, y)
        fs:SetText(text)
        fs:Show()
        return y - math.ceil(fs:GetStringHeight()) - (gap or 6)
    end
    fs:SetText("")
    fs:Hide()
    return y
end

local function PlaceCrafterSection(d, y, title, hint)
    d.craftHeader:ClearAllPoints()
    d.craftHeader:SetPoint("TOPLEFT", 18, y)
    d.craftHeader:SetText(title)
    d.craftHint:ClearAllPoints()
    d.craftHint:SetPoint("TOPRIGHT", -18, y - 2)
    d.craftHint:SetText(hint or "")
    d.craftRule:ClearAllPoints()
    d.craftRule:SetPoint("TOPLEFT", 16, y - 17)
    d.craftRule:SetPoint("TOPRIGHT", -16, y - 17)
    d.craftScroll:ClearAllPoints()
    d.craftScroll:SetPoint("TOPLEFT", 16, y - 22)
    d.craftScroll:SetPoint("BOTTOMRIGHT", -34, 10)
end

-------------------------------------------------------------------------------
-- To Craft / Profit lines (Auctionator prices)
-------------------------------------------------------------------------------
local GOLD_LABEL = "|cffffd100"

local function AgeText(days)
    if not days then return nil end
    if days <= 0 then return "today" end
    return days == 1 and "1 day ago" or (days .. " days ago")
end

-- Returns the new y
function LFW:PlaceCostLines(d, e, y)
    if not e or not e.r then return y end          -- reagents unknown: nothing to price
    local costText, profitText
    if not ns.AuctionatorLoaded() then
        costText = GOLD_LABEL .. "To Craft:|r " .. GREY .. "install Auctionator to see crafting cost and profit|r"
    else
        local info = ns.CraftEconomics(e)
        d.costHover.info = info
        local priced = #info.parts - #info.missing
        if #info.parts > 0 and priced == 0 then
            costText = GOLD_LABEL .. "To Craft:|r " .. GREY .. "no Auctionator prices for these reagents yet|r"
        else
            costText = GOLD_LABEL .. "To Craft:|r " .. ns.Coins(info.cost)
            if #info.missing > 0 then
                costText = costText .. GREY .. ("  + %d %s without a price|r"):format(#info.missing, #info.missing == 1 and "reagent" or "reagents")
            end
        end
        if info.outItem then
            if info.profit and #info.parts > 0 and priced == 0 then
                profitText = GOLD_LABEL .. "Profit:|r " .. GREY .. "unknown  •  sells for|r " .. ns.Coins(info.sale * ns.AH_CUT) .. GREY .. " after the auction house cut|r"
            elseif info.profit then
                profitText = GOLD_LABEL .. "Profit:|r " .. (info.profit < 0 and ("|cffff4040" .. ns.Coins(info.profit) .. "|r") or ns.Coins(info.profit))
                if #info.missing > 0 then
                    profitText = profitText .. GREY .. "  (estimate, some reagents unpriced)|r"
                end
            else
                profitText = GOLD_LABEL .. "Profit:|r " .. GREY .. "no auction price for what it makes|r"
            end
        end
    end

    local top = y - 2
    y = PlaceText(d, d.costLine, costText, top, 3)
    y = PlaceText(d, d.profitLine, profitText, y, 3)
    if d.costHover.info then
        d.costHover:ClearAllPoints()
        d.costHover:SetPoint("TOPLEFT", 16, top)
        d.costHover:SetPoint("BOTTOMRIGHT", d, "TOPRIGHT", -16, y)
        d.costHover:Show()
    end
    return y - 4
end

-- Breakdown when hovering the To Craft / Profit lines
function LFW:ShowCostTooltip(owner)
    local info = owner.info
    if not info then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Crafting cost", 1, 0.82, 0)
    for _, p in ipairs(info.parts) do
        local name = ns.ItemName(p.itemID) or ("Item #" .. p.itemID)
        local left = p.qty .. "x " .. ns.ItemQualityHex(p.itemID) .. name .. "|r"
        if p.unit then
            local each = p.qty > 1 and (GREY .. "  (" .. ns.Coins(p.unit) .. GREY .. " each)|r") or ""
            local src = p.source == "vendor" and (GREY .. " vendor|r") or ""
            GameTooltip:AddDoubleLine(left .. each, ns.Coins(p.total) .. src, 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine(left, GREY .. "no price|r", 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:AddDoubleLine("Total", ns.Coins(info.cost), 1, 0.82, 0, 1, 1, 1)
    if info.outItem then
        GameTooltip:AddLine(" ")
        local name = ns.ItemName(info.outItem) or ("Item #" .. info.outItem)
        local qty = info.outQty ~= 1 and (info.outQty .. "x ") or ""
        if info.sale then
            GameTooltip:AddDoubleLine("Sells for (" .. qty .. ns.ItemQualityHex(info.outItem) .. name .. "|r)", ns.Coins(info.sale), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("Auction house cut (5%)", "-" .. ns.Coins(info.sale - info.sale * ns.AH_CUT), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
            GameTooltip:AddDoubleLine("Profit", ns.Coins(info.profit), 1, 0.82, 0, 1, 1, 1)
        else
            GameTooltip:AddLine("No Auctionator price for " .. name .. ".", C.muted[1], C.muted[2], C.muted[3], true)
        end
    end
    local age = AgeText(info.oldest)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Prices from Auctionator" .. (age and (", oldest seen " .. age) or "") .. ". Scan the auction house to refresh them.",
        C.muted[1], C.muted[2], C.muted[3], true)
    GameTooltip:Show()
end

function LFW:UpdateDetail()
    local f = self.frame
    if not f or not f.profView:IsShown() then return end
    local d = f.detail
    local key = self.currentTab
    if not ns.PROF_BY_KEY[key] then return end
    local id = self.selected[key]
    local cat = self.db.catalog[key]
    local e = id and cat and cat.recipes[id]
    local index = self:GetCrafterIndex(key)
    if id and not e and not index[id] then id = nil; self.selected[key] = nil end

    for _, b in ipairs(d.reagents) do b:Hide() end
    d.reagNote:Hide()
    d.reagHeader:Hide()
    d.costLine:Hide()
    d.profitLine:Hide()
    d.costHover:Hide()
    d.costHover.info = nil

    local y
    if not id then
        -------------------------------------------------- profession overview
        d.iconBtn.recipeID, d.iconBtn.outItem = nil, nil
        d.iconBtn.tex:SetTexture(ns.ProfIcon(key))
        d.name:SetText(ns.ProfName(key))
        local members = SortRecords(self:GetProfessionMembers(key))
        d.sub:SetText(("%d guild %s this profession"):format(#members, #members == 1 and "member has" or "members have"))
        y = -72
        y = PlaceText(d, d.desc, "Select a recipe on the left to see its reagents and who in the guild can craft it.", y, 4)
        y = PlaceText(d, d.creates, nil, y)
        y = PlaceText(d, d.requires, nil, y)
        PlaceCrafterSection(d, y - 10, "Guild Members with " .. ns.ProfName(key), "skill")
        local rows = {}
        for _, rec in ipairs(members) do
            local p = rec.profs[key]
            rows[#rows + 1] = { rec = rec, note = p.known and (ns.CountKeys(p.known) .. " recipes") or "recipes not shared yet" }
        end
        FillCrafters(d, rows, key, ("Nobody in the guild has shared %s yet. Press Update on the Options tab to ask."):format(ns.ProfName(key)))
        return
    end

    -------------------------------------------------- one recipe
    local name = RecipeName(id, e)
    d.iconBtn.recipeID, d.iconBtn.outItem, d.iconBtn.recipeName = id, e and e.o, name
    d.iconBtn.tex:SetTexture(RecipeIcon(id, e))
    d.name:SetText(name)
    local crafters = index[id] and SortRecords({ unpack(index[id]) }) or {}
    local online = 0
    for _, rec in ipairs(crafters) do if self:IsOnline(rec) then online = online + 1 end end
    local catName = (e and e.c) or OTHER
    local known = #crafters == 0 and (GREY .. "nobody in the guild has it|r")
        or (("known by %d%s"):format(#crafters, online > 0 and (", " .. GREEN .. online .. " online|r") or ""))
    d.sub:SetText(catName .. DOT .. ns.ProfName(key) .. DOT .. known)

    y = -72
    y = PlaceText(d, d.desc, e and e.d, y, 6)
    local creates
    if e and e.o then
        local iname = ns.ItemName(e.o)
        if iname then
            local qty = ""
            if e.qmax and e.qmax > 1 then
                qty = (e.qmin and e.qmin ~= e.qmax) and (" x" .. e.qmin .. "-" .. e.qmax) or (" x" .. e.qmax)
            end
            creates = Hex(C.header) .. "Creates:|r " .. ns.ItemQualityHex(e.o) .. "[" .. iname .. "]|r" .. qty
        else
            ns.LoadItem(e.o, function() LFW:RequestUIRefresh(true) end)
        end
    end
    y = PlaceText(d, d.creates, creates, y, 4)
    y = PlaceText(d, d.requires, (e and e.q) and (Hex(C.header) .. "Requires:|r " .. e.q) or nil, y, 4)

    -- Reagents
    y = y - 6
    d.reagHeader:ClearAllPoints()
    d.reagHeader:SetPoint("TOPLEFT", 16, y)
    d.reagHeader:Show()
    y = y - 20
    local list = e and e.r
    if list and #list > 0 then
        for i, r in ipairs(list) do
            if i > MAX_REAGENTS then break end
            local b = d.reagents[i]
            local col, rowN = (i - 1) % REAGENT_COLS, math.floor((i - 1) / REAGENT_COLS)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 16 + col * d.colW, y - rowN * REAGENT_ROW_H)
            b.itemID = r[1]
            b.icon:SetTexture(ns.ItemIcon(r[1]) or QUESTION)
            local iname = ns.ItemName(r[1])
            if not iname then ns.LoadItem(r[1], function() LFW:RequestUIRefresh(true) end) end
            local have = ns.ItemCount(r[1]) or 0
            local haveText = (have >= r[2] and "|cffffffff" or GREY) .. have .. "/" .. r[2] .. "|r"
            b.text:SetText(haveText .. " " .. (iname and (ns.ItemQualityHex(r[1]) .. iname .. "|r") or (GREY .. "loading...|r")))
            b:Show()
        end
        local rowsUsed = math.ceil(math.min(#list, MAX_REAGENTS) / REAGENT_COLS)
        y = y - rowsUsed * REAGENT_ROW_H - 4
    else
        local note
        if e and e.full then
            note = "No reagents needed."
        else
            note = "Reagents not known yet: open " .. ns.ProfName(key) .. " on a character that has it, or press Update in Options."
        end
        d.reagNote:ClearAllPoints()
        d.reagNote:SetPoint("TOPLEFT", 18, y)
        d.reagNote:SetText(note)
        d.reagNote:Show()
        y = y - math.ceil(d.reagNote:GetStringHeight()) - 10
    end

    -- To Craft / Profit
    y = self:PlaceCostLines(d, e, y)

    -- Who has it
    PlaceCrafterSection(d, y - 6, ("Crafters (%d)"):format(#crafters), online > 0 and (online .. " online") or "")
    local rows = {}
    for _, rec in ipairs(crafters) do rows[#rows + 1] = { rec = rec } end
    -- members with the profession who haven't shared their recipe list yet
    for _, rec in ipairs(SortRecords(self:GetProfessionMembers(key))) do
        local p = rec.profs[key]
        if p and not p.known then rows[#rows + 1] = { rec = rec, note = "has " .. ns.ProfName(key) .. ", recipes unknown" } end
    end
    FillCrafters(d, rows, key, "Nobody in the guild has this recipe yet.")
end

-------------------------------------------------------------------------------
-- Options view
-------------------------------------------------------------------------------
local OPT_LEFT_R, OPT_RIGHT_X = 430, 450
local CHAR_ROW_H, MEMBER_ROW_H = 18, 20

function LFW:CreateOptionsView(f)
    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints()
    ov:Hide()
    f.optionsView = ov
    local LEFT_RULE = -(W - OPT_LEFT_R)

    local divider = ov:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(C.rule[1], C.rule[2], C.rule[3], 0.7)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", (OPT_LEFT_R + OPT_RIGHT_X) / 2, -46)
    divider:SetPoint("BOTTOMLEFT", (OPT_LEFT_R + OPT_RIGHT_X) / 2, 56)

    ---------------------------------------------------------------- Guild Updates
    AddSection(ov, "Guild Updates", -46, 20, LEFT_RULE)
    local intro = AddLabel(ov, "Ask guild members who use Looking For Work to send their professions and recipe lists. Only your guild is asked, at most once a minute, and only members whose data changed reply.", nil, C.muted)
    intro:SetPoint("TOPLEFT", 22, -70)
    intro:SetWidth(OPT_LEFT_R - 44)
    if intro.SetSpacing then intro:SetSpacing(2) end

    local update = MenuButton(ov, "Update", 130)
    update:SetPoint("TOPLEFT", 20, -114)
    update:SetScript("OnClick", function()
        local ok, err = LFW:RequestUpdate()
        if not ok then
            ov.updateStatus:SetText("|cffff6040" .. (err or "Could not ask.") .. "|r")
        else
            ov.updateStatus:SetText(GREEN .. "Asked your guild. Replies arrive over the next few seconds.|r")
        end
        LFW:UpdateOptionsButtons()
    end)
    AddHoverTip(update, "Update", "Sends one small request to your guild. Members using Looking For Work whose data you don't have yet (or have an old copy of) send it back, and recipe lists you are missing are filled in.")
    ov.update = update

    ov.updateStatus = AddLabel(ov, "", "GameFontNormalSmall", C.text)
    ov.updateStatus:SetPoint("LEFT", update, "RIGHT", 10, 0)
    ov.updateStatus:SetWidth(OPT_LEFT_R - 20 - 130 - 30)
    if ov.updateStatus.SetSpacing then ov.updateStatus:SetSpacing(2) end

    ---------------------------------------------------------------- Queries
    AddSection(ov, "Queries", -160, 20, LEFT_RULE)
    local cb = CreateFrame("CheckButton", nil, ov, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 18, -183)
    local cbText = AddLabel(cb, "Ignore Queries", "GameFontNormal", C.text)
    cbText:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetScript("OnClick", function(self)
        LFW.db.settings.ignoreQueries = self:GetChecked() and true or false
        if LFW.db.settings.ignoreQueries then
            print(LFW.PREFIX .. "Ignoring queries: you won't answer Update requests or share your professions automatically.")
        else
            print(LFW.PREFIX .. "Answering queries from your guild again.")
            LFW:ScheduleAutoShare(5)
        end
    end)
    AddHoverTip(cb, "Ignore Queries", "When checked, you don't answer other guild members' Update requests and your professions aren't shared automatically. You still receive what others share.")
    ov.ignoreCheck = cb
    local cbDesc = AddLabel(ov, "When checked, you won't answer guild members' Update requests and your professions won't be shared automatically. You can still press Update to receive other members' data.", nil, C.muted)
    cbDesc:SetPoint("TOPLEFT", 46, -210)
    cbDesc:SetWidth(OPT_LEFT_R - 66)
    if cbDesc.SetSpacing then cbDesc:SetSpacing(2) end

    ---------------------------------------------------------------- Your Characters
    AddSection(ov, "Your Characters", -262, 20, LEFT_RULE)
    local charHint = AddLabel(ov, "Open each profession window once on every character so its recipes are saved. New recipes you learn are added automatically.", nil, C.muted)
    charHint:SetPoint("TOPLEFT", 22, -286)
    charHint:SetWidth(OPT_LEFT_R - 44)
    if charHint.SetSpacing then charHint:SetSpacing(2) end

    local cscroll, cchild = MakeScroll("LookingForWorkCharScroll", ov, OPT_LEFT_R - 20 - 24 - 20)
    cscroll:SetPoint("TOPLEFT", 20, -322)
    cscroll:SetPoint("BOTTOMRIGHT", ov, "BOTTOMLEFT", OPT_LEFT_R - 24, 56)
    ov.charScroll, ov.charChild, ov.charRows = cscroll, cchild, {}

    ---------------------------------------------------------------- Guild Members
    ov.memberHeader = AddSection(ov, "Guild Members Sharing Data", -46, OPT_RIGHT_X, -20)
    local forget = FlatButton(ov, "Forget", 58, 18)
    forget:SetPoint("TOPRIGHT", -20, -42)
    forget:SetScript("OnClick", function() StaticPopup_Show("LOOKINGFORWORK_FORGET") end)
    AddHoverTip(forget, "Forget guild data", "Delete everything you have saved about other guild members. Your own characters and the recipe lists are kept. Press Update to fetch fresh data.")

    local mHint = AddLabel(ov, "Online members first. Hover a name for professions, click to whisper.", nil, C.muted)
    mHint:SetPoint("TOPLEFT", OPT_RIGHT_X + 2, -70)
    mHint:SetWidth(W - 20 - OPT_RIGHT_X - 2)

    local mscroll, mchild = MakeScroll("LookingForWorkMemberScroll", ov, W - 20 - OPT_RIGHT_X - 24)
    mscroll:SetPoint("TOPLEFT", OPT_RIGHT_X, -90)
    mscroll:SetPoint("BOTTOMRIGHT", ov, "TOPRIGHT", -44, -396)
    ov.memberScroll, ov.memberChild, ov.memberRows = mscroll, mchild, {}
    ov.memberEmpty = AddLabel(mchild, "", "GameFontNormal", C.muted)
    ov.memberEmpty:SetPoint("TOPLEFT", 6, -10)
    ov.memberEmpty:SetWidth(W - 20 - OPT_RIGHT_X - 40)

    ---------------------------------------------------------------- Recipe Lists
    AddSection(ov, "Recipe Lists", -412, OPT_RIGHT_X, -20)
    ov.catLabels = {}
    local colW = math.floor((W - 20 - OPT_RIGHT_X) / 2)
    for i, p in ipairs(ns.PROFESSIONS) do
        local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
        local b = CreateFrame("Button", nil, ov)
        b:SetSize(colW - 8, 18)
        b:SetPoint("TOPLEFT", OPT_RIGHT_X + 2 + col * colW, -436 - rowN * 19)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT")
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.name:SetPoint("LEFT", 22, 0)
        SetColor(b.name, C.text)
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.count:SetPoint("RIGHT", -4, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0.15)
        b.key = p.key
        b:SetScript("OnClick", function(self) LFW:SelectTab(self.key) end)
        ov.catLabels[p.key] = b
    end
    local catHint = AddLabel(ov, "Recipe lists come from anyone who opens a profession window, so they also include recipes nobody knows yet.", nil, C.muted)
    catHint:SetPoint("TOPLEFT", OPT_RIGHT_X + 2, -556)
    catHint:SetWidth(W - 20 - OPT_RIGHT_X - 2)
    if catHint.SetSpacing then catHint:SetSpacing(2) end
end

local function GetCharRow(ov, i)
    if ov.charRows[i] then return ov.charRows[i] end
    local row = CreateFrame("Frame", nil, ov.charChild)
    row:SetSize(OPT_LEFT_R - 20 - 24 - 20, CHAR_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * CHAR_ROW_H)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    ov.charRows[i] = row
    return row
end

local function GetMemberRow(ov, i)
    if ov.memberRows[i] then return ov.memberRows[i] end
    local cw = W - 20 - OPT_RIGHT_X - 24
    local row = CreateFrame("Button", nil, ov.memberChild)
    row:SetSize(cw, MEMBER_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * MEMBER_ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if i % 2 == 0 then bg:SetColorTexture(C.stripe[1], C.stripe[2], C.stripe[3], 0.22) else bg:SetColorTexture(0, 0, 0, 0) end
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(C.goldLight[1], C.goldLight[2], C.goldLight[3], 0.18)
    row.dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.dot:SetPoint("LEFT", 4, 0)
    row.dot:SetText("•")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", 18, 0)
    row.name:SetWidth(132)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.profs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.profs:SetPoint("LEFT", 154, 0)
    row.profs:SetPoint("RIGHT", -70, 0)
    row.profs:SetJustifyH("LEFT")
    if row.profs.SetWordWrap then row.profs:SetWordWrap(false) end
    SetColor(row.profs, C.text)
    row.ago = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.ago:SetPoint("RIGHT", -4, 0)
    row.ago:SetJustifyH("RIGHT")
    SetColor(row.ago, C.muted)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        local rec = self.rec
        if not rec or LFW:IsMe(rec) then return end
        local m = LFW:MemberInfo(rec)
        Whisper((m and m.raw) or rec.name)
    end)
    row:SetScript("OnEnter", function(self)
        if not self.rec then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        LFW:AddMemberTooltip(self.rec)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ov.memberRows[i] = row
    return row
end

function LFW:UpdateOptionsButtons()
    local f = self.frame
    if not f then return end
    local ov = f.optionsView
    local wait = self:QueryCooldown()
    if not IsInGuild() then
        ov.update:Disable()
        ov.update:SetText("Update")
    elseif wait > 0 then
        ov.update:Disable()
        ov.update:SetText(("Update (%d)"):format(wait))
    else
        ov.update:Enable()
        ov.update:SetText("Update")
    end
    -- status line under the button
    local replies, asked = self:QueryReplies()
    if not IsInGuild() then
        ov.updateStatus:SetText(GREY .. "You are not in a guild.|r")
    elseif asked and time() - asked < 600 then
        ov.updateStatus:SetText(("Asked %s.  Received data for %s%d|r %s."):format(ns.FormatAgo(asked), GREEN, replies,
            replies == 1 and "character" or "characters"))
    elseif (self.db.sync.lastQuery or 0) > 0 then
        ov.updateStatus:SetText(GREY .. "Last asked " .. ns.FormatAgo(self.db.sync.lastQuery) .. ".|r")
    elseif ov.updateStatus:GetText() == nil or ov.updateStatus:GetText() == "" then
        ov.updateStatus:SetText(GREY .. "Not asked yet.|r")
    end
end

function LFW:RefreshOptions()
    local f = self.frame
    if not f then return end
    local ov = f.optionsView
    ov.ignoreCheck:SetChecked(self.db.settings.ignoreQueries and true or false)
    self:UpdateOptionsButtons()
    self:UpdateGuildLine()

    -- Your characters: one line per character, then one per profession
    local mine = {}
    for _, rec in pairs(self.db.players) do if rec.mine then mine[#mine + 1] = rec end end
    table.sort(mine, function(a, b)
        if self:IsMe(a) ~= self:IsMe(b) then return self:IsMe(a) end
        return (a.name or "") < (b.name or "")
    end)
    local lines = {}
    for _, rec in ipairs(mine) do
        local guild = GuildDisplayName(rec.guild)
        lines[#lines + 1] = ns.ColorName(rec.name, rec.class)
            .. (self:IsMe(rec) and (GREY .. "  (current)|r") or "")
            .. (guild and (GREY .. "  <" .. guild .. ">|r") or (GREY .. "  no guild|r"))
        local any = false
        for _, p in ipairs(ns.PROFESSIONS) do
            local prof = rec.profs[p.key]
            if prof then
                any = true
                local skill = SkillText(rec, p.key)
                local state
                if prof.known then
                    state = Hex(C.muted) .. "—  " .. ns.CountKeys(prof.known) .. " recipes saved|r"
                else
                    state = "|cffff9040—  not saved yet: open " .. ns.ProfName(p) .. "|r"
                end
                lines[#lines + 1] = "      " .. Hex(C.text) .. ns.ProfName(p) .. "|r " .. Hex(C.legend) .. skill .. "|r  " .. state
            end
        end
        if not any then lines[#lines + 1] = "      " .. GREY .. "no professions|r" end
    end
    for i, text in ipairs(lines) do
        local row = GetCharRow(ov, i)
        row.text:SetText(text)
        row:Show()
    end
    for i = #lines + 1, #ov.charRows do ov.charRows[i]:Hide() end
    ov.charChild:SetHeight(math.max(10, #lines * CHAR_ROW_H))

    -- Guild members sharing data
    local members = SortRecords(self:GuildRecords())
    local online = 0
    for i, rec in ipairs(members) do
        local row = GetMemberRow(ov, i)
        row.rec = rec
        local dot = MemberStatus(rec)
        if dot == C.online then online = online + 1 end
        SetColor(row.dot, dot)
        row.name:SetText(ns.ColorName(rec.name, rec.class))
        local parts = {}
        for _, p in ipairs(ns.PROFESSIONS) do
            if rec.profs[p.key] then
                local lvl = rec.profs[p.key].lvl
                parts[#parts + 1] = p.short .. ((lvl and lvl > 0) and (" " .. lvl) or "")
            end
        end
        row.profs:SetText(#parts > 0 and table.concat(parts, Hex(C.muted) .. "  •  |r") or (GREY .. "no professions|r"))
        row.ago:SetText(self:IsMe(rec) and "you" or ns.FormatAgo(rec.updated))
        row:Show()
    end
    for i = #members + 1, #ov.memberRows do
        ov.memberRows[i]:Hide()
        ov.memberRows[i].rec = nil
    end
    ov.memberChild:SetHeight(math.max(10, #members * MEMBER_ROW_H))
    ov.memberHeader:SetText(("Guild Members Sharing Data  " .. Hex(C.muted) .. "(%d, %d online)|r"):format(#members, online))
    if #members <= 1 then
        ov.memberEmpty:SetText(IsInGuild() and "\n\n\nNo other guild members have shared data yet. Press Update to ask the ones using Looking For Work." or "\n\n\nJoin a guild to share professions.")
        ov.memberEmpty:Show()
    else
        ov.memberEmpty:Hide()
    end

    -- Recipe list sizes
    for key, b in pairs(ov.catLabels) do
        b.icon:SetTexture(ns.ProfIcon(key))
        b.name:SetText(ns.ProfName(key))
        local n = self:CatalogCount(key)
        b.count:SetText(n > 0 and (n .. " recipes") or (GREY .. "none yet|r"))
        SetColor(b.count, C.legend)
    end
end

StaticPopupDialogs["LOOKINGFORWORK_FORGET"] = {
    text = "Forget everything saved about other guild members?\n\nYour own characters and the recipe lists are kept.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        LFW:ForgetGuildData()
        print(LFW.PREFIX .. "Guild member data forgotten. Press Update to fetch it again.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Game Options -> AddOns entry, addon compartment, slash commands
-------------------------------------------------------------------------------
function LFW:RegisterBlizzardOptions()
    local panel = CreateFrame("Frame")
    panel.name = "Looking For Work"
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("Looking For Work")
    local d = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
    d:SetWidth(520)
    d:SetJustifyH("LEFT")
    d:SetText("Find who in your guild can craft a recipe. Recipes, Update, Ignore Queries and your saved characters are in the Looking For Work window. You can also open it with /lfw.")
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(220, 24)
    b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -14)
    b:SetText("Open Looking For Work")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        LFW:Open("options")
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function LookingForWork_OnAddonCompartmentClick()
    LFW:Toggle()
end

function LookingForWork_OnAddonCompartmentEnter(_, button)
    local owner = button or (GetMouseFoci and GetMouseFoci()[1]) or UIParent
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Looking For Work", 1, 0.82, 0)
    GameTooltip:AddLine("Find guild members who can craft a recipe", 1, 1, 1)
    GameTooltip:Show()
end

function LookingForWork_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local function FindProfession(text)
    text = ns.Trim(text):lower()
    if text == "" then return nil end
    for _, p in ipairs(ns.PROFESSIONS) do
        local n = ns.ProfName(p):lower()
        if n == text or p.key == text or n:find(text, 1, true) == 1 then return p end
    end
    return nil
end

-- /lfw find <text>: open the profession with the most matching recipes
function LFW:Find(text)
    text = ns.Trim(text)
    if text == "" then return end
    local best, bestN = nil, 0
    for _, p in ipairs(ns.PROFESSIONS) do
        local entries = self:BuildEntries(p.key, text)
        local n = 0
        for _, e in ipairs(entries) do if not e.header then n = n + 1 end end
        if n > bestN then best, bestN = p.key, n end
    end
    if not best then
        print(self.PREFIX .. "No saved recipe matches \"" .. text .. "\".")
        return
    end
    self:Open(best)
    self.frame.search:SetText(text)
end

function LFW:PrintHelp()
    print(self.PREFIX .. "commands:")
    print("  |cffffd100/lfw|r  open / close the window")
    print("  |cffffd100/lfw <profession>|r  open a profession tab (e.g. /lfw tailoring)")
    print("  |cffffd100/lfw find <text>|r  search every profession by name, tooltip text (e.g. defense), reagent or player")
    print("  |cffffd100/lfw update|r  ask your guild for their professions")
    print("  |cffffd100/lfw ignore|r  turn Ignore Queries on/off")
    print("  |cffffd100/lfw options|r  open the Options tab")
end

SLASH_LOOKINGFORWORK1 = "/lfw"
SLASH_LOOKINGFORWORK2 = "/lookingforwork"
SlashCmdList["LOOKINGFORWORK"] = function(msg)
    if not LFW.db then return end
    msg = ns.Trim(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""
    if cmd == "" then
        LFW:Toggle()
    elseif cmd == "help" or cmd == "?" then
        LFW:PrintHelp()
    elseif cmd == "update" then
        local ok, err = LFW:RequestUpdate()
        print(LFW.PREFIX .. (ok and "Asked your guild for their professions." or err))
    elseif cmd == "ignore" then
        LFW.db.settings.ignoreQueries = not LFW.db.settings.ignoreQueries
        print(LFW.PREFIX .. "Ignore Queries is now " .. (LFW.db.settings.ignoreQueries and "|cffff6040on|r." or "|cff40ff40off|r."))
        LFW:RequestUIRefresh()
    elseif cmd == "options" or cmd == "config" then
        LFW:Open("options")
    elseif cmd == "find" or cmd == "search" then
        LFW:Find(rest)
    elseif cmd == "debug" then
        LFW.db.settings.debug = not LFW.db.settings.debug
        local players, mine = 0, 0
        for _, rec in pairs(LFW.db.players) do players = players + 1; if rec.mine then mine = mine + 1 end end
        print(LFW.PREFIX .. ("v%s  debug %s  —  %d characters saved (%d yours), guild: %s, roster: %d"):format(
            LFW.VERSION, LFW.db.settings.debug and "on" or "off", players, mine, tostring(LFW.guildName), ns.roster.total))
        for _, p in ipairs(ns.PROFESSIONS) do
            local n = LFW:CatalogCount(p.key)
            if n > 0 then print(("  %s: %d recipes"):format(ns.ProfName(p), n)) end
        end
    else
        local p = FindProfession(msg)
        if p then LFW:Open(p.key) else LFW:Find(msg) end
    end
end

function LFW:InitUI()
    self:RegisterBlizzardOptions()
end
