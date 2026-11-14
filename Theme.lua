-- Gatherline: the look. Dark, flat and quiet: near-black panels with hairline
-- edges, white text, one jade accent for what's on or chosen, small uppercase
-- section titles, and a sidebar with a thin accent bar on the open page.
-- Every widget the window uses is built here.

local ADDON, ns = ...
local L = ns.L
local T = {}
ns.Theme = T

T.NAME = "Gatherline"
T.SHORT = "Gatherline"
T.LOGO = "Interface\\AddOns\\" .. tostring(ADDON) .. "\\media\\Logo"
T.FONT = "Fonts\\ARIALN.TTF"   -- in every client, every language's letters
T.ACCENT_HEX = "3fd0a0"
-- Chat lines start with the logo and the name in jade
T.CHAT_PREFIX = "|T" .. T.LOGO .. ":0|t |cff" .. T.ACCENT_HEX .. T.NAME .. "|r"

local C = {
    win      = { 0.051, 0.056, 0.067, 0.97 },
    side     = { 0.035, 0.039, 0.047, 1 },
    head     = { 0.043, 0.047, 0.055, 1 },
    card     = { 0.078, 0.084, 0.098, 1 },
    cardHi   = { 0.098, 0.106, 0.122, 1 },
    field    = { 0.043, 0.047, 0.055, 1 },
    line     = { 0.14, 0.15, 0.17, 1 },
    edge     = { 0.19, 0.20, 0.23, 1 },
    fieldEdge = { 0.21, 0.22, 0.26, 1 },
    btn      = { 0.12, 0.13, 0.15, 1 },
    btnHi    = { 0.17, 0.18, 0.21, 1 },
    btnEdge  = { 0.24, 0.25, 0.29, 1 },
    accent   = { 0.247, 0.816, 0.627, 1 },
    accentHi = { 0.36, 0.89, 0.71, 1 },
    accentDim = { 0.12, 0.33, 0.27, 1 },
    danger   = { 0.86, 0.33, 0.33, 1 },
    offTrack = { 0.19, 0.20, 0.23, 1 },
    knobOff  = { 0.55, 0.57, 0.62, 1 },
    text     = { 0.93, 0.94, 0.96 },
    muted    = { 0.58, 0.61, 0.67 },
    faint    = { 0.42, 0.45, 0.50 },
    dark     = { 0.04, 0.05, 0.05 },
}
-- names the pages still use
C.gold, C.orange, C.title, C.grey = C.accent, C.accent, C.text, C.muted
T.C = C

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------
-- Upper case that knows the umlauts (string.upper only does A-Z)
local function Upper(s)
    return (s:upper():gsub("ä", "Ä"):gsub("ö", "Ö"):gsub("ü", "Ü"))
end
T.Upper = Upper

local function Fill(frame, color, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -8)
    t:SetAllPoints()
    t:SetColorTexture(unpack(color))
    return t
end

-- Hairline edges (1 pixel each side)
local function Border(frame, color)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(color))
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
        edges[#edges + 1] = t
    end
    function frame:SetEdgeColor(c) for _, e in ipairs(edges) do e:SetColorTexture(unpack(c)) end end
    return edges
end

-- Sizes and colors for the font templates the pages ask for
local STYLE = {
    GameFontHighlight = { 13, C.text },
    GameFontHighlightSmall = { 12, C.text },
    GameFontNormal = { 13, C.text },
    GameFontNormalSmall = { 11, C.muted },
    GameFontNormalLarge = { 17, C.text },
    GameFontDisableSmall = { 12, C.muted },
    GameFontDisable = { 13, C.faint },
}

local function Font(fs, size)
    if fs.SetFont then pcall(fs.SetFont, fs, T.FONT, size, "") end
end

-- Text in our font; text is translated (L) here
local function Text(parent, text, template, color, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    local style = STYLE[template or "GameFontHighlight"] or STYLE.GameFontHighlight
    Font(fs, size or style[1])
    local c = color or style[2]
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    fs:SetText(text and L[text] or "")
    return fs
end

-- Flat button: dark with a hairline edge, lighter on hover. b:SetPrimary(true)
-- makes it jade (the one thing a page is for).
local function FlatButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 100, height or 24)
    b.bg = Fill(b, C.btn)
    Border(b, C.btnEdge)
    local fs = Text(b, "", "GameFontHighlight", nil, 12)
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    b:SetFontString(fs)
    b:SetText(text and L[text] or "")
    function b:Restyle()
        local hi = self.hover and not self.disabled
        if self.primary then
            self.bg:SetColorTexture(unpack(hi and C.accentHi or C.accent))
            self:SetEdgeColor(hi and C.accentHi or C.accent)
            fs:SetTextColor(C.dark[1], C.dark[2], C.dark[3])
        else
            self.bg:SetColorTexture(unpack(hi and C.btnHi or C.btn))
            self:SetEdgeColor(hi and C.accentDim or C.btnEdge)
            fs:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
    end
    function b:SetPrimary(on) self.primary = on and true or false; self:Restyle() end
    function b:SetHover(on) self.hover = on; self:Restyle() end
    b:SetScript("OnEnter", function(self) self:SetHover(true) end)
    b:SetScript("OnLeave", function(self) self:SetHover(false) end)
    b:Restyle()
    return b
end

-- A small square button with a game icon in it (Edit, Rebuild, Delete...)
function T.IconButton(parent, texture, size)
    local b = FlatButton(parent, "", size or 24, size or 24)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetSize((size or 24) - 10, (size or 24) - 10)
    icon:SetPoint("CENTER")
    icon:SetTexture(texture)
    b.icon = icon
    return b
end

-- Hover tooltip: a title line and/or a wrapped white one (both translated).
-- Keeps a button's own hover look working.
function T.Tooltip(widget, title, body)
    widget:SetScript("OnEnter", function(self)
        if self.SetHover then self:SetHover(true) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(L[title], C.accent[1], C.accent[2], C.accent[3]) end
        if body then GameTooltip:AddLine(L[body], 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function(self)
        if self.SetHover then self:SetHover(false) end
        GameTooltip:Hide()
    end)
end

-- On/off switch: b:SetOn(bool) paints it; b:IsOn() reads it. A pill-like
-- track, the knob at the right and jade when on.
function T.SwitchWidget(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 16)
    b.isSwitch = true
    local track = b:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    local knob = b:CreateTexture(nil, "ARTWORK")
    knob:SetSize(12, 12)
    function b:SetOn(on)
        self.on = on and true or false
        track:SetColorTexture(unpack(self.on and C.accentDim or C.offTrack))
        knob:SetColorTexture(unpack(self.on and C.accent or C.knobOff))
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", self, "LEFT", self.on and 18 or 2, 0)
    end
    function b:IsOn() return self.on end
    b:SetOn(false)
    return b
end

T.Fill, T.Border, T.Text, T.FlatButton = Fill, Border, Text, FlatButton

-- An on-screen panel: dark, see-through, hairline edge
function T.Panel(frame, alpha)
    frame.bg = Fill(frame, { C.win[1], C.win[2], C.win[3], alpha or 0.9 })
    Border(frame, C.edge)
    return frame
end

---------------------------------------------------------------------------
-- Widgets for a settings page
---------------------------------------------------------------------------
-- The small arrow at the right of anything that opens a menu
function T.MenuArrow(button, inset)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -inset, 0)
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
    return arrow
end

-- Card: a panel with a small spaced-out uppercase title and a short jade mark
-- before it. Content starts at y = -28.
function T.Card(parent, title, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", x, y)
    f:SetSize(w, h)
    Fill(f, C.card)
    Border(f, C.line)
    local mark = f:CreateTexture(nil, "ARTWORK")
    mark:SetSize(2, 10)
    mark:SetPoint("TOPLEFT", 12, -11)
    mark:SetColorTexture(unpack(C.accent))
    local t = title and Upper(L[title]) or ""
    f.title = Text(f, "", "GameFontNormalSmall", C.muted, 11)
    f.title:SetText(t)
    f.title:SetPoint("TOPLEFT", 20, -10)
    return f
end

function T.Note(parent, text, x, y, width)
    local n = Text(parent, text, "GameFontDisableSmall")
    n:SetPoint("TOPLEFT", x, y)
    if width then n:SetWidth(width); n:SetWordWrap(true) end
    return n
end

function T.RowLabel(parent, text, x, y)
    local fs = Text(parent, text, "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y - 4)
    return fs
end

-- Greys a control out (and back): b:SetDisabled(true). Widgets that take clicks
-- check b.disabled; the tooltip still shows, to say why.
local DISABLED_ALPHA = 0.35
local function Disabler(widget, parts)
    function widget:SetDisabled(off)
        self.disabled = off and true or false
        local a = self.disabled and DISABLED_ALPHA or 1
        for _, part in ipairs(parts) do part:SetAlpha(a) end
        if self.Restyle then self:Restyle() end
    end
end
T.Disabler = Disabler

-- Makes the text beside a control part of it
function T.ClickableLabel(widget, label, gap)
    local w = label.GetStringWidth and label:GetStringWidth()
    w = type(w) == "number" and w or 0
    widget:SetHitRectInsets(0, -((gap or 8) + math.ceil(w)), -4, -4)
end

-- A switch with its label to the right
function T.LabeledSwitch(parent, text, x, y, labelWidth)
    local b = T.SwitchWidget(parent)
    b:SetPoint("TOPLEFT", x, y)
    local label = Text(parent, text, "GameFontHighlight")
    label:SetPoint("LEFT", b, "RIGHT", 10, 0)
    if labelWidth then label:SetWidth(labelWidth); label:SetWordWrap(true) end
    b.label = label
    T.ClickableLabel(b, label, 10)
    Disabler(b, { b, label })
    return b, label
end

-- Dropdown: shows the current choice; click for a menu of the choices (or step
-- to the next one where the game has no menus). labels[key] is the text shown.
function T.Dropdown(parent, width, keys, labels, getter, setter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    b.bg = Fill(b, C.field)
    Border(b, C.fieldEdge)
    local fs = Text(b, "", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 9, 0)
    fs:SetPoint("RIGHT", -22, 0)
    b:SetFontString(fs)
    T.MenuArrow(b, 8)
    b.keys, b.labels, b.getter, b.setter = keys, labels, getter, setter
    b:SetScript("OnEnter", function(self) if not self.disabled then self:SetEdgeColor(C.accentDim) end end)
    b:SetScript("OnLeave", function(self) self:SetEdgeColor(C.fieldEdge) end)

    local function label(k)
        local v
        if type(b.labels) == "function" then v = b.labels(k) else v = b.labels[k] or tostring(k) end
        return type(v) == "string" and L[v] or v
    end
    local function refresh() b:SetText(label(b.getter())) end
    local function choose(k) b.setter(k); refresh() end
    Disabler(b, { b })
    b:SetScript("OnClick", function(self)
        if self.disabled then return end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                if self.menuTitle then root:CreateTitle(self.menuTitle) end
                if self.menuScroll and root.SetScrollMode then root:SetScrollMode(self.menuScroll) end
                for _, k in ipairs(self.keys) do
                    root:CreateRadio(self.menuLabels and self.menuLabels[k] or label(k),
                        function() return self.getter() == k end, function() choose(k) end)
                end
            end)
        else
            local cur, nextIdx = self.getter(), 1
            for i, k in ipairs(self.keys) do
                if k == cur then nextIdx = (i % #self.keys) + 1 break end
            end
            if self.keys[nextIdx] ~= nil then choose(self.keys[nextIdx]) end
        end
    end)
    b.Refresh = refresh
    b.Choose = choose
    return b
end

-- Slider: label left, value right in jade, a thin track filled in jade up to
-- a small square knob. get() reads the setting, set(v) saves it; s.Refresh()
-- repaints it. zeroText: what the value reads at 0, when 0 means "off".
function T.Slider(parent, text, x, y, width, get, set, min, max, suffix, step, fmt, zeroText)
    suffix, step, fmt = suffix or "", step or 1, fmt or "%d"
    local function show(v)
        if zeroText and v == 0 then return L[zeroText] end
        if type(fmt) == "function" then return fmt(v) .. L[suffix] end
        return fmt:format(v) .. L[suffix]
    end
    local title = Text(parent, text, "GameFontHighlight")
    title:SetPoint("TOPLEFT", x, y)
    local value = Text(parent, "", "GameFontHighlight", C.accent)
    value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 14)
    s:SetPoint("TOPLEFT", x, y - 18)
    s:SetHitRectInsets(0, 0, -6, -6)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(2)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    track:SetColorTexture(unpack(C.offTrack))
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 10)
    thumb:SetColorTexture(unpack(C.text))
    s:SetThumbTexture(thumb)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(2)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetColorTexture(unpack(C.accent))
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepsOnDrag then s:SetObeyStepsOnDrag(true) end

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        if step >= 1 then v = math.floor(v + 0.5) end
        value:SetText(show(v))
        if get() ~= v then set(v) end
    end)
    function s.Refresh()
        s:SetValue(get())
        value:SetText(show(get()))
    end
    s.title, s.valueText = title, value
    Disabler(s, { s, title, value })
    local setDisabled = s.SetDisabled
    function s:SetDisabled(off)
        setDisabled(self, off)
        self:EnableMouse(not off)
    end
    return s
end

-- Text box: dark field, the edge turns jade while you type in it
function T.EditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, 24)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    Font(eb, 13)
    eb:SetTextInsets(8, 8, 0, 0)
    Fill(eb, C.field)
    Border(eb, C.fieldEdge)
    eb:SetScript("OnEditFocusGained", function(self) self:SetEdgeColor(C.accent) end)
    eb:SetScript("OnEditFocusLost", function(self) self:SetEdgeColor(C.fieldEdge) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

-- A page that can outgrow the window: scrolls with the mouse wheel or the thin
-- bar at its right. Put the content in scroll.child, then call
-- scroll:SetContent(width, height) whenever it changes.
function T.ScrollArea(parent, viewHeight)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(10, 10)
    scroll:SetScrollChild(child)
    scroll.child = child

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(4)
    bar:SetPoint("TOPRIGHT")
    bar:SetPoint("BOTTOMRIGHT")
    Fill(bar, C.offTrack)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(4, 40)
    thumb:SetColorTexture(unpack(C.accentDim))
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
    scroll.bar = bar

    local range = 0
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(math.max(0, math.min(range, (bar:GetValue() or 0) - delta * 40)))
    end)
    function scroll:SetContent(width, height, keepPlace)
        child:SetSize(width, height)
        range = math.max(0, height - viewHeight)
        local at = keepPlace and math.min(bar:GetValue() or 0, range) or 0
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        bar:SetValue(at)
        self:SetVerticalScroll(at)
    end
    return scroll
end

---------------------------------------------------------------------------
-- The window: a slim header (logo, name, version, X) you drag it by, the
-- menu down the left in groups, one page per entry, and a footer line.
--   opts.name     global frame name (Escape closes it)
--   opts.tabs     { { key =, label =, icon =, group =, build = function(body, page) }, ... }
--                 group: a small heading above the first entry of a group
--   opts.hint     footer text
--   opts.version  function returning the version shown beside the name
--   opts.onShow / onHide / onTab(key)   optional
--   opts.height   optional height
-- Returns the window, with .pages[key], .tabButtons[key], :ShowTab(key) and .currentTab
---------------------------------------------------------------------------
T.WINDOW = { W = 760, H = 556, HEADER = 48, FOOTER = 34, SIDE = 190, PAGE_W = 530 }
function T.BodyHeight(h) return (h or T.WINDOW.H) - T.WINDOW.HEADER - T.WINDOW.FOOTER - 60 end
T.WINDOW.BODY_H = T.BodyHeight()

function T.Window(opts)
    local W, H, HEADER, FOOTER, SIDE = T.WINDOW.W, opts.height or T.WINDOW.H, T.WINDOW.HEADER, T.WINDOW.FOOTER, T.WINDOW.SIDE
    local win = CreateFrame("Frame", opts.name, UIParent)
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    table.insert(UISpecialFrames, opts.name)
    Fill(win, C.win)
    Border(win, C.edge)
    win.pages, win.tabButtons = {}, {}

    -- Header: drag to move
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    Fill(header, C.head)
    local hline = header:CreateTexture(nil, "BORDER")
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    hline:SetColorTexture(unpack(C.line))
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(28, 28)
    logo:SetPoint("LEFT", 14, 0)
    logo:SetTexture(T.LOGO)
    local title = Text(header, "", "GameFontNormalLarge", C.text, 17)
    title:SetText(T.NAME)
    title:SetPoint("LEFT", logo, "RIGHT", 10, 1)
    local ver = Text(header, "", "GameFontNormalSmall", C.faint, 11)
    ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
    local x = T.IconButton(header, "Interface\\Buttons\\UI-StopButton", 24)
    x:SetPoint("RIGHT", -12, 0)
    x:SetScript("OnClick", function() win:Hide() end)
    T.Tooltip(x, "Close")
    win.header, win.logo, win.title, win.version = header, logo, title, ver

    win:SetScript("OnShow", function()
        local v = opts.version and opts.version()
        ver:SetText(v and ("v" .. v) or "")
        if opts.onShow then opts.onShow() end
    end)
    win:SetScript("OnHide", function() if opts.onHide then opts.onHide() end end)

    function win:ShowTab(key)
        self.currentTab = key
        for k, page in pairs(self.pages) do page:SetShown(k == key) end
        for k, b in pairs(self.tabButtons) do
            local sel = (k == key)
            b.selBg:SetShown(sel)
            b.accent:SetShown(sel)
            b.icon:SetDesaturated(not sel)
            b.icon:SetAlpha(sel and 1 or 0.55)
            local c = sel and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
        end
        if opts.onTab then opts.onTab(key) end
    end

    -- Menu down the left, in groups
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", 1, -(HEADER + 1))
    side:SetPoint("BOTTOMLEFT", 1, FOOTER + 1)
    side:SetWidth(SIDE)
    Fill(side, C.side)
    local sline = side:CreateTexture(nil, "BORDER")
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)
    sline:SetColorTexture(unpack(C.line))
    local y = -12
    for _, t in ipairs(opts.tabs) do
        if t.group then
            local g = Text(side, "", "GameFontNormalSmall", C.faint, 10)
            g:SetText(Upper(L[t.group]))
            g:SetPoint("TOPLEFT", 16, y - 6)
            y = y - 24
        end
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE - 1, 32)
        b:SetPoint("TOPLEFT", 0, y)
        y = y - 32
        b.selBg = b:CreateTexture(nil, "BACKGROUND")
        b.selBg:SetAllPoints()
        b.selBg:SetColorTexture(unpack(C.cardHi))
        b.accent = b:CreateTexture(nil, "ARTWORK")
        b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(2)
        b.accent:SetColorTexture(unpack(C.accent))
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.03)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 16, 0)
        b.icon:SetTexture(t.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local fs = Text(b, "", "GameFontHighlight")
        fs:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
        b:SetFontString(fs)
        b.label = fs
        b:SetText(L[t.label])
        b:SetScript("OnClick", function() win:ShowTab(t.key) end)
        win.tabButtons[t.key] = b
    end

    -- Pages: a big title, and the page's own short line under it
    for _, t in ipairs(opts.tabs) do
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", SIDE + 20, -(HEADER + 16))
        page:SetPoint("BOTTOMRIGHT", -20, FOOTER + 10)
        page.title = Text(page, t.label, "GameFontNormalLarge", C.text, 18)
        page.title:SetPoint("TOPLEFT", 0, 0)
        page.sub = Text(page, t.sub, "GameFontDisableSmall", C.muted, 12)
        page.sub:SetPoint("TOPLEFT", 0, -22)
        local body = CreateFrame("Frame", nil, page)
        body:SetPoint("TOPLEFT", 0, -44)
        body:SetPoint("BOTTOMRIGHT")
        page.body = body
        win.pages[t.key] = page
        t.build(body, page)
    end

    -- Footer: a quiet hint line
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(FOOTER)
    Fill(foot, C.head)
    local fline = foot:CreateTexture(nil, "BORDER")
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1)
    fline:SetColorTexture(unpack(C.line))
    local hint = Text(foot, opts.hint, "GameFontDisableSmall", C.faint, 11)
    hint:SetPoint("LEFT", 14, 0)
    win.footer, win.hint = foot, hint

    win:ShowTab(opts.tabs[1].key)
    return win
end
