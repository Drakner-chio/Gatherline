-- Gatherline: the gathering HUD, shown while you ride a route. Three parts,
-- each switched on or off on its own (db.hud), moved where you like and
-- sized and faded together:
--
--  * Compass band (top): the way you face, with the next stops on it: the one
--    you're heading for as a diamond, the next ones numbered, empty ones
--    hollow. Under it the stop's name, how far, which way, and the lap so far.
--  * Ground lens: a tilted disc round you, turning with you: the route's line
--    along the ground for the next HUD lens yards and the stops on it.
--  * Lap card: the stop you head for (how far, how many seconds), a dot for
--    every stop of the lap (done, skipped, empty), the lap time against your
--    best, and nodes and gold an hour.
--
-- "Preview" shows it with made-up stops round you, to place it before a ride.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local T = ns.Theme
local C = T.C
local Text = T.Text
local floor, abs, sqrt, atan2, pi, min, max = math.floor, math.abs, math.sqrt, math.atan2 or math.atan, math.pi, math.min, math.max
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

GP.HUD_DEFAULTS = {
    compass = true, lens = false, card = true,
    scale = 100, alpha = 90, lensRange = 100, locked = true, combat = true,
    pos = {},
}
GP.HUD_RANGES = { scale = { 60, 160 }, alpha = { 30, 100 }, lensRange = { 50, 200 } }
GP.HUD_PLACES = {
    compass = { "TOP", 0, -28 },
    lens = { "BOTTOM", 0, 150 },
    card = { "BOTTOM", 0, 92 },
}
GP.HUD_TICK = 0.04

-- Colours of what's at a stop
local KIND_COLOR = {
    ["Herb Gathering"] = { 0.50, 0.84, 0.48 },
    ["Mining"] = { 0.89, 0.60, 0.38 },
    ["Fishing"] = { 0.45, 0.70, 0.95 },
    ["Treasure"] = { 0.95, 0.82, 0.40 },
}
local EMPTY = { 0.42, 0.45, 0.50 }
local function KindColor(kind) return KIND_COLOR[kind] or C.accent end

function GP:HudSettings()
    local db = self.db
    if type(db.hud) ~= "table" then db.hud = {} end
    local h = db.hud
    for k, v in pairs(self.HUD_DEFAULTS) do
        if type(h[k]) ~= type(v) then h[k] = type(v) == "table" and {} or v end
    end
    for k, r in pairs(self.HUD_RANGES) do h[k] = max(r[1], min(r[2], floor(h[k]))) end
    return h
end

---------------------------------------------------------------------------
-- Where you are, which way you face
---------------------------------------------------------------------------
local function Facing()
    if not GetPlayerFacing then return nil end
    local ok, f = pcall(GetPlayerFacing)
    if ok and type(f) == "number" then return f end
end

-- From you to (x, y) on map m: yards to the right, yards ahead, angle (right +)
local function Relative(m, px, py, x, y, facing)
    local w, h = GP:MapYards(m)
    w, h = w or 1500, h or 1000
    local east, south = (x - px) * w, (y - py) * h
    -- facing: radians anticlockwise from north; the way ahead is (-sin f, -cos f) in (east, north)
    local s, c = math.sin(facing), math.cos(facing)
    local north = -south
    local ahead = -s * east + c * north
    local right = c * east + s * north
    return right, ahead, atan2(right, ahead)
end
GP.HudRelative = Relative

local function Distance(m, px, py, x, y)
    local w, h = GP:MapYards(m)
    w, h = w or 1500, h or 1000
    local dx, dy = (x - px) * w, (y - py) * h
    return sqrt(dx * dx + dy * dy)
end

local function FormatDist(d)
    return L["%d yd"]:format(floor(d + 0.5))
end
local function Which(angle)
    local a = angle * 180 / pi
    if abs(a) <= 12 then return L["straight on"] end
    if abs(a) >= 135 then return L["behind you"] end
    if a < 0 then return abs(a) < 45 and L["a little left"] or L["left"] end
    return a < 45 and L["a little right"] or L["right"]
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function Panel(f)
    T.Fill(f, { C.win[1], C.win[2], C.win[3], 0.80 })
    T.Border(f, C.line)
end
local function Label(parent, size, color)
    local fs = Text(parent, "", "GameFontHighlight", color or C.text, size)
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.9) end
    return fs
end
local function Tex(parent, layer, file)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(file or WHITE)
    return t
end
-- A round dot (filled, or a ring: a smaller dark dot on top)
local function Dot(parent, layer)
    local d = Tex(parent, layer or "ARTWORK", DOT)
    d.hole = Tex(parent, "OVERLAY", DOT)
    d.hole:SetPoint("CENTER", d, "CENTER")
    d.hole:SetVertexColor(C.win[1], C.win[2], C.win[3], 1)
    function d:Set(size, color, hollow, alpha)
        self:SetSize(size, size)
        self:SetVertexColor(color[1], color[2], color[3], alpha or 1)
        self.hole:SetSize(size - 4, size - 4)
        self.hole:SetShown(hollow and true or false)
        self:Show()
    end
    local hide = d.Hide
    function d:Hide() hide(self); self.hole:Hide() end
    return d
end

-- A HUD part: a frame placed by its saved point, dragged while unlocked
local parts = {}
local function Part(key, w, h)
    local f = CreateFrame("Frame", "GatherlineHud_" .. key, UIParent)
    f:SetSize(w, h)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not GP:HudSettings().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        GP:HudSettings().pos[key] = { point or "CENTER", floor((x or 0) + 0.5), floor((y or 0) + 0.5), rel }
    end)
    -- shown while unlocked: where it is and that it can be moved
    f.handle = Tex(f, "BACKGROUND")
    f.handle:SetAllPoints()
    f.handle:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
    f.key = key
    f:Hide()
    parts[key] = f
    return f
end

local function Place(f)
    local h = GP:HudSettings()
    local p = h.pos[f.key]
    local d = GP.HUD_PLACES[f.key]
    f:ClearAllPoints()
    if type(p) == "table" and type(p[1]) == "string" then
        f:SetPoint(p[1], UIParent, p[4] or p[1], tonumber(p[2]) or 0, tonumber(p[3]) or 0)
    else
        f:SetPoint(d[1], UIParent, d[1], d[2], d[3])
    end
    f:SetScale(h.scale / 100)
    f:SetAlpha(h.alpha / 100)
    f:EnableMouse(not h.locked)
    f.handle:SetShown(not h.locked)
end

---------------------------------------------------------------------------
-- A: the compass band
---------------------------------------------------------------------------
local BAND_W, BAND_H = 520, 40
local FOV = pi / 3   -- each side
local DIRS = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }

local function BuildCompass()
    local f = Part("compass", BAND_W, BAND_H + 62)
    local band = CreateFrame("Frame", nil, f)
    band:SetPoint("TOP", 0, 0)
    band:SetSize(BAND_W, BAND_H)
    Panel(band)
    f.band = band
    f.ticks, f.letters = {}, {}
    for i = 1, 24 do f.ticks[i] = Tex(band, "ARTWORK") end
    for i = 1, 8 do f.letters[i] = Label(band, 13, C.muted) end
    local mid = Tex(band, "OVERLAY")
    mid:SetSize(2, 9)
    mid:SetPoint("BOTTOM", band, "TOP", 0, -4)
    mid:SetColorTexture(C.text[1], C.text[2], C.text[3], 1)
    f.marks = {}
    for i = 1, 6 do
        local m = Dot(band, "OVERLAY")
        m.num = Label(band, 11)
        f.marks[i] = m
    end
    local diamond = Tex(band, "OVERLAY")
    diamond:SetSize(14, 14)
    if diamond.SetRotation then pcall(diamond.SetRotation, diamond, pi / 4) end
    f.diamond = diamond
    -- under the band: what's next, and the lap
    f.what = Label(f, 16)
    f.what:SetPoint("TOP", band, "BOTTOM", 0, -8)
    f.what:SetJustifyH("CENTER")
    f.bar = Tex(f, "ARTWORK")
    f.bar:SetSize(300, 3)
    f.bar:SetPoint("TOP", f.what, "BOTTOM", 0, -9)
    f.bar:SetColorTexture(1, 1, 1, 0.14)
    f.fill = Tex(f, "OVERLAY")
    f.fill:SetHeight(3)
    f.fill:SetPoint("LEFT", f.bar, "LEFT")
    f.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    f.lap = Label(f, 12, C.muted)
    f.lap:SetPoint("TOP", f.bar, "BOTTOM", 0, -5)
    f.lap:SetJustifyH("CENTER")
    return f
end

local function X(angle) return BAND_W / 2 + angle / FOV * (BAND_W / 2) end
local function Wrap(a)
    while a > pi do a = a - 2 * pi end
    while a < -pi do a = a + 2 * pi end
    return a
end

local function UpdateCompass(f, s, px, py, facing)
    -- heading clockwise from north
    local heading = (-facing) % (2 * pi)
    local ti, li = 0, 0
    for deg = 0, 345, 15 do
        local a = Wrap(math.rad(deg) - heading)
        if abs(a) < FOV then
            ti = ti + 1
            local t = f.ticks[ti]
            local big = deg % 45 == 0
            t:SetSize(2, big and 12 or 6)
            t:SetColorTexture(C.text[1], C.text[2], C.text[3], big and 0.7 or 0.3)
            t:ClearAllPoints()
            t:SetPoint("TOP", f.band, "TOPLEFT", X(a), -4)
            t:Show()
            if big then
                li = li + 1
                local fs = f.letters[li]
                fs:SetText(L[DIRS[deg]])
                fs:ClearAllPoints()
                fs:SetPoint("TOP", f.band, "TOPLEFT", X(a), -18)
                fs:Show()
            end
        end
    end
    for i = ti + 1, #f.ticks do f.ticks[i]:Hide() end
    for i = li + 1, #f.letters do f.letters[i]:Hide() end

    f.diamond:Hide()
    local mi = 0
    local cur
    for _, st in ipairs(s.ahead) do
        local _, _, a = Relative(s.mapID, px, py, st.x, st.y, facing)
        local x = X(max(-FOV, min(FOV, a)))   -- off the band: held at its edge
        if st.current then
            cur = { st = st, angle = a }
            local c = KindColor(st.kind)
            f.diamond:SetVertexColor(c[1], c[2], c[3], 1)
            f.diamond:ClearAllPoints()
            f.diamond:SetPoint("CENTER", f.band, "TOPLEFT", x, -BAND_H / 2 + 6)
            f.diamond:Show()
        elseif mi < #f.marks and abs(a) < FOV then
            mi = mi + 1
            local m = f.marks[mi]
            local c = st.empty and EMPTY or KindColor(st.kind)
            m:Set(st.empty and 10 or 11, c, true, st.empty and 0.7 or 1)
            m:ClearAllPoints()
            m:SetPoint("CENTER", f.band, "TOPLEFT", x, -BAND_H / 2 + 6)
            m.num:SetText(st.empty and L["empty"] or tostring(st.num))
            m.num:SetTextColor(c[1], c[2], c[3])
            m.num:ClearAllPoints()
            m.num:SetPoint("BOTTOM", m, "TOP", 0, 6)
            m.num:Show()
        end
    end
    for i = mi + 1, #f.marks do f.marks[i]:Hide(); f.marks[i].num:Hide() end

    if cur then
        local d = Distance(s.mapID, px, py, cur.st.x, cur.st.y)
        f.what:SetText(("%s  |cff%s%s|r  |cffa9b0bd%s|r"):format(cur.st.what or L["Stop %d/%d"]:format(cur.st.num, s.n),
            T.ACCENT_HEX, FormatDist(d), Which(cur.angle)))
    else
        f.what:SetText("")
    end
    local done = (s.k - 1) / max(1, s.n)
    f.fill:SetWidth(max(1, 300 * done))
    local lap = L["Lap %d · %d/%d"]:format(s.lap, s.k, s.n)
    local best = s.route and s.route.stats and s.route.stats.best
    if s.elapsed then lap = lap .. "  ·  " .. GP.FormatClock(s.elapsed) end
    if best then lap = lap .. "  ·  " .. L["best %s"]:format(GP.FormatClock(best)) end
    f.lap:SetText(lap)
end

---------------------------------------------------------------------------
-- B: the ground lens
---------------------------------------------------------------------------
local LENS_RX, LENS_RY = 170, 72
local LINES = 140

local function BuildLens()
    local f = Part("lens", LENS_RX * 2 + 40, LENS_RY * 2 + 50)
    local disc = Tex(f, "BACKGROUND", DOT)
    disc:SetSize(LENS_RX * 2, LENS_RY * 2)
    disc:SetPoint("CENTER", 0, 0)
    disc:SetVertexColor(C.win[1], C.win[2], C.win[3], 0.55)
    f.rings = {}
    for i, k in ipairs({ 1, 0.66, 0.33 }) do
        local r = Tex(f, "BORDER", DOT)
        r:SetSize(LENS_RX * 2 * k, LENS_RY * 2 * k)
        r:SetPoint("CENTER", 0, 0)
        r:SetVertexColor(C.text[1], C.text[2], C.text[3], 0.06)
        f.rings[i] = r
    end
    f.lines = {}
    f.dots, f.names = {}, {}
    for i = 1, 6 do
        f.dots[i] = Dot(f, "OVERLAY")
        f.names[i] = Label(f, 12)
    end
    local me = Tex(f, "OVERLAY", "Interface\\Minimap\\MinimapArrow")
    me:SetSize(22, 22)
    me:SetPoint("CENTER", 0, 0)
    f.me = me
    f.range = Label(f, 11, C.muted)
    f.range:SetPoint("TOP", f, "CENTER", 0, -LENS_RY - 6)
    f.range:SetJustifyH("CENTER")
    return f
end

-- The lens point for (right, ahead) yards: nil outside it
local function LensXY(right, ahead, R)
    local u, v = right / R, ahead / R
    if u * u + v * v > 1 then return nil end
    local k = 1 - 0.22 * v   -- farther away, narrower
    return u * LENS_RX * k, v * LENS_RY
end

local function Line(f, i)
    local l = f.lines[i]
    if not l then
        if not f.CreateLine then return nil end
        l = f:CreateLine(nil, "ARTWORK")
        l:SetTexture(WHITE)
        l:SetThickness(4)
        f.lines[i] = l
    end
    return l
end

local function UpdateLens(f, s, px, py, facing)
    local R = GP:HudSettings().lensRange
    local m = s.mapID
    local pts, count
    if s.line then pts, count = s.line, floor(#s.line / 2) else pts, count = GP:DrawPoints(s.route) end
    local li = 0
    local w, h = GP:MapYards(m)
    w, h = w or 1500, h or 1000
    local reach2 = (R * 1.5) ^ 2
    local function Rel(i)
        local x, y = pts[2 * i - 1], pts[2 * i]
        local dx, dy = (x - px) * w, (y - py) * h
        if dx * dx + dy * dy > reach2 then return nil end
        local r, a = Relative(m, px, py, x, y, facing)
        return r, a
    end
    local accent = C.accent
    for i = 1, count do
        local j = i % count + 1
        local r1, a1 = Rel(i)
        local r2, a2
        if r1 then r2, a2 = Rel(j) end
        if r1 and r2 then
            -- clip to the disc: walk in from the far end
            local x1, y1 = LensXY(r1, a1, R)
            local x2, y2 = LensXY(r2, a2, R)
            if not x1 or not x2 then
                for t = 0.9, 0.1, -0.2 do
                    if not x1 then x1, y1 = LensXY(r2 + (r1 - r2) * t, a2 + (a1 - a2) * t, R) end
                    if not x2 then x2, y2 = LensXY(r1 + (r2 - r1) * t, a1 + (a2 - a1) * t, R) end
                end
            end
            if x1 and x2 and li < LINES then
                local l = Line(f, li + 1)
                if l then
                    li = li + 1
                    l:SetStartPoint("CENTER", f, x1, y1)
                    l:SetEndPoint("CENTER", f, x2, y2)
                    l:SetVertexColor(accent[1], accent[2], accent[3], 0.9)
                    l:Show()
                end
            end
        end
    end
    for i = li + 1, #f.lines do f.lines[i]:Hide() end
    local di = 0
    for _, st in ipairs(s.ahead) do
        local r, a = Relative(m, px, py, st.x, st.y, facing)
        local x, y = LensXY(r, a, R)
        if x and di < #f.dots then
            di = di + 1
            local c = st.empty and EMPTY or KindColor(st.kind)
            f.dots[di]:Set(st.current and 14 or 10, c, st.empty, st.empty and 0.8 or 1)
            f.dots[di]:ClearAllPoints()
            f.dots[di]:SetPoint("CENTER", f, "CENTER", x, y)
            local nm = f.names[di]
            if st.current or st.empty then
                nm:SetText(st.empty and L["empty"] or ((st.what or L["Stop %d/%d"]:format(st.num, s.n)) .. "  " .. FormatDist(sqrt(r * r + a * a))))
                nm:SetTextColor(c[1], c[2], c[3])
                nm:ClearAllPoints()
                nm:SetPoint("LEFT", f.dots[di], "RIGHT", 6, 0)
                nm:Show()
            else
                nm:Hide()
            end
        end
    end
    for i = di + 1, #f.dots do f.dots[i]:Hide(); f.names[i]:Hide() end
    f.range:SetText(L["%d yards round you"]:format(R))
end

---------------------------------------------------------------------------
-- D: the lap card
---------------------------------------------------------------------------
local CARD_W, CARD_H = 440, 104
local DOTS = 40

local function BuildCard()
    local f = Part("card", CARD_W, CARD_H)
    Panel(f)
    f.top = Label(f, 11, C.muted)
    f.top:SetPoint("TOPLEFT", 14, -10)
    f.name = Label(f, 17)
    f.name:SetPoint("TOPLEFT", 14, -26)
    f.name:SetWidth(270)
    f.name:SetWordWrap(false)
    f.time = Label(f, 24)
    f.time:SetPoint("TOPRIGHT", -14, -10)
    f.time:SetJustifyH("RIGHT")
    f.delta = Label(f, 12)
    f.delta:SetPoint("TOPRIGHT", f.time, "BOTTOMRIGHT", 0, -2)
    f.delta:SetJustifyH("RIGHT")
    f.dots = {}
    for i = 1, DOTS do f.dots[i] = Dot(f, "ARTWORK") end
    f.bar = Tex(f, "ARTWORK")
    f.bar:SetHeight(4)
    f.barFill = Tex(f, "OVERLAY")
    f.barFill:SetHeight(4)
    f.foot = Label(f, 12, C.muted)
    f.foot:SetPoint("BOTTOMLEFT", 14, 10)
    return f
end

local STATE_LOOK = {
    done = function() return 8, C.accent, false, 1 end,
    skipped = function() return 8, EMPTY, true, 0.9 end,
    current = function() return 12, C.accent, true, 1 end,
    empty = function() return 8, EMPTY, true, 0.6 end,
    todo = function() return 8, C.text, false, 0.16 end,
}

local function Speed()
    if GetUnitSpeed then
        local ok, now = pcall(GetUnitSpeed, "player")
        if ok and type(now) == "number" and not (issecretvalue and issecretvalue(now)) and now > 0.5 then return now end
    end
    return GP:Speed()
end

local function UpdateCard(f, s, px, py)
    local cur
    for _, st in ipairs(s.ahead) do if st.current then cur = st break end end
    f.top:SetText(L["STOP %d/%d"]:format(s.k, s.n))
    if cur then
        local d = Distance(s.mapID, px, py, cur.x, cur.y)
        local c = KindColor(cur.kind)
        local hex = ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
        f.name:SetText(("|cff%s%s|r  |cff%s%s · %d s|r"):format(hex, cur.what or L["Stop %d/%d"]:format(cur.num, s.n),
            T.ACCENT_HEX, FormatDist(d), floor(d / Speed() + 0.5)))
    else
        f.name:SetText("")
    end
    -- the lap time, and against your best (worked out from how far round you are)
    local best = s.route and s.route.stats and s.route.stats.best
    f.time:SetText(s.elapsed and GP.FormatClock(s.elapsed) or "–")
    local done = (s.k - 1) / max(1, s.n)
    if s.elapsed and best and done >= 0.15 then
        local diff = s.elapsed / done - best
        local sign = diff < 0 and "−" or "+"
        f.delta:SetText(L["%s to your best"]:format(sign .. GP.FormatClock(abs(diff))))
        if diff < 0 then f.delta:SetTextColor(0.44, 0.83, 0.54) else f.delta:SetTextColor(0.90, 0.55, 0.45) end
    elseif best then
        f.delta:SetText(L["best %s"]:format(GP.FormatClock(best)))
        f.delta:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    else
        f.delta:SetText(L["first lap"])
        f.delta:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end
    -- a dot per stop, or a bar for long laps
    local n = #s.states
    if n <= DOTS then
        f.bar:Hide(); f.barFill:Hide()
        local step = min(10, (CARD_W - 28) / max(1, n))
        for i = 1, DOTS do
            local d = f.dots[i]
            if i <= n then
                d:Set(STATE_LOOK[s.states[i]]())
                d:ClearAllPoints()
                d:SetPoint("CENTER", f, "TOPLEFT", 14 + (i - 0.5) * step, -62)
            else
                d:Hide()
            end
        end
    else
        for i = 1, DOTS do f.dots[i]:Hide() end
        f.bar:ClearAllPoints()
        f.bar:SetPoint("TOPLEFT", 14, -60)
        f.bar:SetWidth(CARD_W - 28)
        f.bar:SetColorTexture(1, 1, 1, 0.14)
        f.barFill:ClearAllPoints()
        f.barFill:SetPoint("LEFT", f.bar, "LEFT")
        f.barFill:SetWidth(max(1, (CARD_W - 28) * done))
        f.barFill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        f.bar:Show(); f.barFill:Show()
    end
    local foot = { s.laps == 1 and L["Lap %d"]:format(s.lap) or (s.laps and s.laps > 0 and L["Lap %d of %d"]:format(s.lap, s.laps)) or L["Lap %d"]:format(s.lap) }
    local st = s.route and s.route.stats
    if st and (st.rideTime or 0) >= 60 then
        local hours = st.rideTime / 3600
        foot[#foot + 1] = L["%d nodes/h"]:format(floor((st.gathered or 0) / hours + 0.5))
        if (st.value or 0) > 0 then foot[#foot + 1] = L["%s/h"]:format(GP.FormatMoney(st.value / hours)) end
    end
    if s.skipped > 0 then foot[#foot + 1] = L["%d skipped (empty)"]:format(s.skipped) end
    f.foot:SetText(table.concat(foot, "   "))
end

---------------------------------------------------------------------------
-- Preview: made-up stops round you
---------------------------------------------------------------------------
local function PreviewState(m, px, py)
    local w, h = GP:MapYards(m)
    w, h = w or 1500, h or 1000
    local off = { { 30, -60 }, { 75, -20 }, { 50, 45 }, { -10, 90 }, { -70, 40 }, { -60, -40 } }
    local kinds = { "Mining", "Herb Gathering", "Mining", "Herb Gathering", "Herb Gathering", "Mining" }
    local names = { L["Tin Vein"], L["Silverleaf"], L["Copper Vein ×2"], L["Peacebloom"], L["Earthroot"], L["Copper Vein"] }
    local s = { mapID = m, n = 23, lap = 2, laps = 0, k = 14, elapsed = 192, ahead = {}, states = {}, skipped = 2, line = {} }
    for i, o in ipairs(off) do
        local x, y = px + o[1] / w, py + o[2] / h
        s.line[#s.line + 1] = x
        s.line[#s.line + 1] = y
        s.ahead[i] = { x = x, y = y, what = names[i], kind = kinds[i], num = 13 + i, current = i == 1, empty = i == 4 }
    end
    for i = 1, 23 do
        s.states[i] = i < 14 and ((i == 5 or i == 10) and "skipped" or "done") or (i == 14 and "current") or (i == 18 and "empty") or "todo"
    end
    s.route = { stats = { best = 358, laps = 3, rideTime = 1100, gathered = 75, value = 56000 } }
    s.fake = true
    return s
end

---------------------------------------------------------------------------
-- Drive
---------------------------------------------------------------------------
local built = false
local function Build()
    if built then return end
    built = true
    BuildCompass()
    BuildLens()
    BuildCard()
    for _, f in pairs(parts) do Place(f) end
end

GP.hudPreview = false

function GP:SetHudPreview(on)
    self.hudPreview = on and true or false
    self:UpdateHud(true)
end

-- Hides or shows the parts and places them; called when settings change
function GP:UpdateHud(force)
    Build()
    for _, f in pairs(parts) do Place(f) end
    if force then self.hudLast = nil end
end

local function Tick()
    local h = GP:HudSettings()
    local s = GP:HudState()
    local m, px, py
    if s then
        m = s.mapID
        px, py = GP.PlayerPos(m)
    elseif GP.hudPreview then
        m = GP:PlayerMap()
        if m then px, py = GP.PlayerPos(m) end
        if px then s = PreviewState(m, px, py) end
    end
    local facing = Facing()
    local hideCombat = not h.combat and InCombatLockdown and InCombatLockdown()
    local on = s and px and facing and not hideCombat
    for key, f in pairs(parts) do
        local want = on and h[key]
        if want then
            if not f:IsShown() then f:Show() end
            if key == "compass" then UpdateCompass(f, s, px, py, facing)
            elseif key == "lens" then UpdateLens(f, s, px, py, facing)
            else UpdateCard(f, s, px, py) end
        elseif f:IsShown() then
            f:Hide()
        end
    end
end
GP.HudTick = Tick

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < GP.HUD_TICK then return end
    acc = 0
    if not GP.db then return end
    Build()
    Tick()
end)
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function() GP:UpdateHud(true) end)
GP.hudParts = parts
