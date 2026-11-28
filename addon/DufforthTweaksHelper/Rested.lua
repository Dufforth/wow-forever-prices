-- Rested XP in full (user, 2026-11-27): the game's XP bar stops showing rested at the end of the level, so this says
-- how far the whole amount reaches (levels + percent), how many kills it covers, and when it is full, for this
-- character and your alts. Rules are Classic's (user's pick): rested doubles kill XP, fills 5% of a level per 8 hours
-- in an inn or city (a quarter of that outside), caps at 1.5 levels. Shown in the guide's progress bar (GuideUI).
local L = DufforthTweaksHelperL or setmetatable({}, { __index = function(_, k) return k end })
local R = {}
DufforthTweaksHelperRested = R

-- XP to go from level i to i + 1 (Classic; the same table as catalog/route_score.py).
R.XP_TABLE = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
    17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54100,
    57700, 61000, 64900, 68200, 71900, 75300, 79100, 82800, 86800, 90600, 94500, 98600, 102700, 106800, 111000,
    115200, 119500, 123800, 128200, 132600, 137000, 141600, 146200, 150800, 155500, 160300, 165200 }
R.MAX_LEVEL = 60
R.CAP = 1.5                 -- levels of the current level's XP
R.PER_8_HOURS = 0.05        -- share of a level gained per 8 hours while resting
R.OUTSIDE = 0.25            -- outside an inn or city

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- How far `rested` XP reaches from `cur` of `max` at `level`: {level, pct (0-1 into that level), share, capped}.
function R.Reach(level, cur, max, rested)
    local out = { share = max > 0 and rested / max or 0, capped = false }
    local left, lv, have, need = rested, level, cur, max
    while lv < R.MAX_LEVEL and left >= need - have do
        left = left - (need - have)
        lv, have = lv + 1, 0
        need = R.XP_TABLE[lv] or need
    end
    if lv >= R.MAX_LEVEL then
        out.level, out.pct, out.capped = R.MAX_LEVEL, 0, true
    else
        out.level, out.pct = lv, (have + left) / need
    end
    return out
end

-- A kill of your level (Classic, solo, before Forever's cut for lower monsters).
function R.KillXP(level) return level * 5 + 45 end

-- Rested doubles kill XP: each kill uses up as much rested as it gives.
function R.Kills(rested, killXP)
    if not rested or rested <= 0 or killXP <= 0 then return 0 end
    return math.ceil(rested / killXP)
end

function R.Cap(max) return math.floor(max * R.CAP) end

function R.PerHour(max, resting)
    return max * R.PER_8_HOURS / 8 * (resting and 1 or R.OUTSIDE)
end

function R.SecondsToCap(rested, max, resting)
    local room = R.Cap(max) - rested
    if room <= 0 or max <= 0 then return 0 end
    return math.floor(room / R.PerHour(max, resting) * 3600 + 0.5)
end

-- An alt's rested now, from what was saved when it logged out.
function R.Estimate(snap, now)
    local hours = math.max(0, (now - (snap.at or now)) / 3600)
    return math.min(R.Cap(snap.max or 0), (snap.rested or 0) + R.PerHour(snap.max or 0, snap.resting) * hours)
end

function R.Duration(s)
    s = math.floor(s)
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-- This character now, or nil at level 60 or when the game hides the numbers.
function R.Current()
    local level = UnitLevel and Plain(UnitLevel("player"))
    local cur = UnitXP and Plain(UnitXP("player"))
    local max = UnitXPMax and Plain(UnitXPMax("player"))
    if not level or not cur or not max or max <= 0 or level >= R.MAX_LEVEL then return nil end
    local rested = (GetXPExhaustion and Plain(GetXPExhaustion())) or 0
    local resting = IsResting and Plain(IsResting()) and true or false
    return { level = level, cur = cur, max = max, rested = rested, resting = resting }
end

-- Forever's UnitName gives first and last name and GetRealmName is "", so "Name-Realm" made two characters with the
-- same first name share one entry. The key is the character's unique id; the old first-name key is dropped on save.
local function FullName()
    local first, last
    if UnitName then first, last = UnitName("player") end
    first = first or "?"
    if type(last) == "string" and last ~= "" then return first .. " " .. last, first end
    return first, first
end

function R.Key()
    local name, first = FullName()
    local realm = GetRealmName and GetRealmName() or ""
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then return guid, name, first .. "-" .. realm end
    return name .. "-" .. realm, name, first .. "-" .. realm
end
local Key = R.Key

local function Store()
    DufforthTweaksHelperDB = DufforthTweaksHelperDB or {}
    DufforthTweaksHelperDB.rested = DufforthTweaksHelperDB.rested or {}
    local s = DufforthTweaksHelperDB.rested
    s.chars = s.chars or {}
    return s
end

function R.Save()
    local c = R.Current()
    local key, name, legacy = Key()
    local chars = Store().chars
    if legacy ~= key then chars[legacy] = nil end
    if not c then
        if UnitLevel and Plain(UnitLevel("player")) == R.MAX_LEVEL then chars[key] = nil end
        return
    end
    local class -- "x and f()" would keep only f's first value
    if UnitClass then class = select(2, UnitClass("player")) end
    chars[key] = { name = name, level = c.level, cur = c.cur, max = c.max, rested = c.rested, resting = c.resting,
        at = time and time() or 0, class = class }
end

-- Alts with rested to gain: full ones first, then the soonest to fill. {name, level, pct, left (seconds)}.
function R.Alts(store, me, now)
    local list = {}
    for key, snap in pairs(store.chars or {}) do
        if key ~= me and (snap.level or 0) < R.MAX_LEVEL and (snap.max or 0) > 0 then
            local rested = R.Estimate(snap, now)
            list[#list + 1] = { name = snap.name or key, level = snap.level, pct = rested / snap.max,
                left = R.SecondsToCap(rested, snap.max, snap.resting), rested = rested, max = snap.max,
                cur = snap.cur, resting = snap.resting and true or false, at = snap.at }
        end
    end
    table.sort(list, function(a, b)
        if a.left ~= b.left then return a.left < b.left end
        return a.name < b.name
    end)
    return list
end

-- Rows for the main window's Rested XP view: you first (when below 60), then the alts like R.Alts.
function R.Rows(store, me, now)
    local rows = {}
    local c = R.Current()
    if c then
        rows[1] = { name = FullName(), level = c.level, pct = c.rested / c.max, rested = c.rested, max = c.max,
            cur = c.cur, left = R.SecondsToCap(c.rested, c.max, c.resting), me = true, resting = c.resting }
    end
    for _, a in ipairs(R.Alts(store, me, now)) do rows[#rows + 1] = a end
    return rows
end

function R.RowText(row)
    if row.left <= 0 then
        return string.format(L["%s (%d): %d%% rested, full"], row.name, row.level, math.floor(row.pct * 100))
    end
    return string.format(L["%s (%d): %d%% rested, full in %s"], row.name, row.level, math.floor(row.pct * 100),
        R.Duration(row.left))
end

function R.Store() return Store() end

-- One short piece for the progress bar: "Rested to 23 + 83%", or "" with nothing to say.
function R.ShortText()
    local c = R.Current()
    if not c or c.rested <= 0 then return "" end
    local r = R.Reach(c.level, c.cur, c.max, c.rested)
    if r.capped then return L["Rested to level 60"] end
    return string.format(L["Rested to %d + %d%%"], r.level, math.floor(r.pct * 100))
end

function R.HoverText()
    local lines = {}
    local c = R.Current()
    if c then
        if c.rested > 0 then
            local r = R.Reach(c.level, c.cur, c.max, c.rested)
            lines[#lines + 1] = string.format(L["Rested XP: %d (%d%% of this level)"], math.floor(c.rested),
                math.floor(r.share * 100 + 0.5))
            if r.capped then
                lines[#lines + 1] = L["Reaches level 60"]
            else
                lines[#lines + 1] = string.format(L["Reaches level %d + %d%%"], r.level, math.floor(r.pct * 100))
            end
            lines[#lines + 1] = string.format(L["About %d kills of your level (rested doubles kill XP)"],
                R.Kills(c.rested, R.KillXP(c.level)))
        else
            lines[#lines + 1] = L["No rested XP"]
        end
        local left = R.SecondsToCap(c.rested, c.max, c.resting)
        if left <= 0 then
            lines[#lines + 1] = L["Rested XP is full: rest no longer adds more"]
        elseif c.resting then
            lines[#lines + 1] = string.format(L["Full in %s while you rest here"], R.Duration(left))
        else
            lines[#lines + 1] = string.format(L["Full in %s out here (4x slower than in an inn or city)"], R.Duration(left))
        end
    end
    local store = Store()
    local alts = R.Alts(store, Key(), time and time() or 0)
    if #alts > 0 then
        lines[#lines + 1] = L["Alts"]
        for k = 1, math.min(8, #alts) do
            local a = alts[k]
            if a.left <= 0 then
                lines[#lines + 1] = string.format(L["%s (%d): full"], a.name, a.level)
            else
                lines[#lines + 1] = string.format(L["%s (%d): %d%% rested, full in %s"], a.name, a.level,
                    math.floor(a.pct * 100), R.Duration(a.left))
            end
        end
    end
    if #lines == 0 then return "" end
    lines[#lines + 1] = L["Estimates with Classic rules: 5% of a level per 8 hours rested, 1.5 levels at most."]
    return table.concat(lines, "\n")
end

-- ---- Alts tab (user: "i want to see all my alts reste experience amount in a tab") ----
-- One row per character: name, level, rested XP now, the level it reaches, resting or not, time to full.
-- Alts full now (rest wasted) or full within a day are marked (user: "mark the ones that are about to reach
-- the rested limit so i can notice and login and consume it").
R.SOON_SECONDS = 24 * 3600

function R.Alert(left)
    if left <= 0 then return "full" end
    if left <= R.SOON_SECONDS then return "soon" end
    return nil
end

function R.Thousands(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- R.Rows plus how far each one's rested reaches (nil when the XP into the level wasn't saved yet).
function R.TableRows(store, me, now)
    local rows = R.Rows(store, me, now)
    for _, row in ipairs(rows) do
        if row.cur and row.max and row.max > 0 then
            row.reach = R.Reach(row.level, row.cur, row.max, row.rested or 0)
        end
    end
    return rows
end

function R.MarkedCount(store, me, now)
    local n = 0
    for _, a in ipairs(R.Alts(store, me, now)) do if R.Alert(a.left) then n = n + 1 end end
    return n
end

local function ReachText(reach)
    if not reach then return "?" end
    if reach.capped then return "60" end
    return string.format("%d + %d%%", reach.level, math.floor(reach.pct * 100))
end

function R.Cells(row)
    local share = math.floor((row.pct or 0) * 100 + 0.5)
    return {
        name = row.name, level = tostring(row.level),
        rested = string.format("%s (%d%%)", R.Thousands(row.rested or 0), share),
        reach = ReachText(row.reach),
        where = row.resting and L["Inn or city"] or L["Outside"],
        full = row.left <= 0 and L["Full"] or R.Duration(row.left),
        alert = R.Alert(row.left),
    }
end

function R.RowTip(row)
    local lines = { string.format(L["%s, level %d"], row.name, row.level) }
    lines[#lines + 1] = string.format(L["Rested XP: %s (%d%% of a level)"], R.Thousands(row.rested or 0),
        math.floor((row.pct or 0) * 100 + 0.5))
    if not row.reach then
        lines[#lines + 1] = L["Reach unknown: log in once with this version to save where you are in the level."]
    elseif row.reach.capped then
        lines[#lines + 1] = L["Reaches level 60"]
    else
        lines[#lines + 1] = string.format(L["Reaches level %d + %d%%"], row.reach.level, math.floor(row.reach.pct * 100))
    end
    lines[#lines + 1] = row.resting and L["Resting in an inn or city."]
        or L["Outside an inn or city: rest fills 4x slower."]
    local alert = R.Alert(row.left)
    if alert == "full" then
        lines[#lines + 1] = L["|cffff6060Full: rest is being wasted. Log in and use it.|r"]
    elseif alert == "soon" then
        lines[#lines + 1] = string.format(L["|cffffd100Full in %s: log in soon and use it.|r"], R.Duration(row.left))
    else
        lines[#lines + 1] = string.format(L["Full in %s"], R.Duration(row.left))
    end
    if not row.me and row.at and time then
        lines[#lines + 1] = string.format(L["Saved %s ago, when it logged out."], R.Duration(math.max(0, time() - row.at)))
    end
    lines[#lines + 1] = L["Estimates with Classic rules: 5% of a level per 8 hours rested, 1.5 levels at most."]
    return table.concat(lines, "\n")
end

-- Builds the tab on `page`; returns the function that redraws it (the window calls it on every refresh).
R.MAX_ROWS = 20
local ROW_H, TOP = 20, -66
local ALERT_BAND = { full = { 0.55, 0.12, 0.12, 0.45 }, soon = { 0.45, 0.36, 0.05, 0.40 } }
local ALERT_TEXT = { full = "|cffff6060", soon = "|cffffd100" }

local function Line(parent, font, x, y, w, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint("TOPLEFT", x, y); t:SetWidth(w); t:SetJustifyH(justify or "LEFT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    return t
end

local function Tip(owner, text)
    if not text or not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

function R.BuildPanel(page, width)
    local inner = width - 24
    -- Fixed column widths; the name takes what is left and is cut (full name in the hover).
    local cols = { { key = "level", w = 30, j = "CENTER", title = L["Lvl"] },
        { key = "rested", w = 90, j = "RIGHT", title = L["Rested XP"] },
        { key = "reach", w = 60, j = "CENTER", title = L["Reaches"] },
        { key = "where", w = 66, j = "LEFT", title = L["Resting"] },
        { key = "full", w = 56, j = "RIGHT", title = L["Full in"] } }
    local fixed = 0
    for _, c in ipairs(cols) do fixed = fixed + c.w + 6 end
    table.insert(cols, 1, { key = "name", w = math.max(48, inner - fixed), j = "LEFT", title = L["Character"] })
    local x = 12
    for _, c in ipairs(cols) do c.x = x; x = x + c.w + 6 end

    local title = Line(page, "GameFontNormal", 8, -4, inner)
    title:SetText(L["Rested XP of your characters"])
    -- One fixed line each: the legend and the summary, cut, with the full text on hover.
    local legendBox = CreateFrame("Frame", nil, page)
    legendBox:SetPoint("TOPLEFT", 8, -24); legendBox:SetSize(inner + 4, 16); legendBox:EnableMouse(true)
    local legend = Line(legendBox, "GameFontHighlightSmall", 4, -1, inner)
    local LEGEND = L["Red = full, rest is wasted. Gold = full within a day. Log in and use it. Hover a row for details."]
    legend:SetText(LEGEND)
    legendBox:SetScript("OnEnter", function(self) Tip(self, LEGEND .. "\n" .. L["An alt shows here after it logs in once with this version. Estimates with Classic rules: 5% of a level per 8 hours rested, 1.5 levels at most."]) end)
    legendBox:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local summary = Line(page, "GameFontHighlightSmall", 12, -42, inner)

    for _, c in ipairs(cols) do
        local h = Line(page, "GameFontDisableSmall", c.x, TOP + 16, c.w, c.j)
        h:SetText(c.title)
    end

    local rows = {}
    for k = 1, R.MAX_ROWS do
        local r = CreateFrame("Button", nil, page)
        r:SetPoint("TOPLEFT", 8, TOP - (k - 1) * ROW_H); r:SetSize(inner + 4, ROW_H - 2)
        r.band = r:CreateTexture(nil, "BACKGROUND"); r.band:SetAllPoints()
        r.accent = r:CreateTexture(nil, "BORDER"); r.accent:SetPoint("TOPLEFT"); r.accent:SetPoint("BOTTOMLEFT"); r.accent:SetWidth(3)
        r.cells = {}
        for _, c in ipairs(cols) do r.cells[c.key] = Line(r, "GameFontHighlight", c.x - 8, -3, c.w, c.j) end
        r:SetScript("OnEnter", function(self) Tip(self, rawget(self, "tip")) end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        r:Hide()
        rows[k] = r
    end
    local empty = Line(page, "GameFontHighlight", 12, TOP - 4, inner)

    return function()
        local key = R.Key()
        local now = time and time() or 0
        local list = R.TableRows(Store(), key, now)
        local room = math.floor(((page.GetHeight and tonumber((page:GetHeight()))) or 420) + TOP - 4) / ROW_H
        local shown = math.max(1, math.min(R.MAX_ROWS, math.floor(room)))
        local marked = {}
        for k = 1, R.MAX_ROWS do
            local r, row = rows[k], list[k]
            if row and k <= shown then
                local cells = R.Cells(row)
                local color = ALERT_TEXT[cells.alert]
                for _, c in ipairs(cols) do
                    local text = cells[c.key]
                    if c.key == "name" and row.me then text = "|cffffd100" .. text .. "|r " .. L["(you)"] end
                    if color and (c.key == "full" or c.key == "rested") then text = color .. text .. "|r" end
                    r.cells[c.key]:SetText(text)
                end
                local band = ALERT_BAND[cells.alert]
                if band then
                    r.band:SetColorTexture(unpack(band)); r.accent:SetColorTexture(band[1] * 1.8, band[2] * 1.8, band[3] * 1.8, 1)
                    r.accent:Show()
                    if not row.me then marked[#marked + 1] = row.name end
                else
                    r.band:SetColorTexture(1, 1, 1, k % 2 == 0 and 0.03 or 0); r.accent:Hide()
                end
                r.tip = R.RowTip(row)
                r:Show()
            else
                r:Hide()
            end
        end
        if #list == 0 then
            empty:SetText(L["No character below 60 saved yet. Each alt shows here after it logs in once with this version."])
        elseif #list == 1 and list[1].me then
            empty:SetPoint("TOPLEFT", 12, TOP - ROW_H - 6)
            empty:SetText(L["Your alts show here after each one logs in once with this version."])
        else
            empty:SetText("")
        end
        if #marked > 0 then
            summary:SetText(string.format(L["|cffffd100Log in to use their rest: %s|r"], table.concat(marked, ", ")))
        elseif #list > shown then
            summary:SetText(string.format(L["%d characters; make the window taller to see all."], #list))
        else
            summary:SetText(L["No alt is near full rested XP."])
        end
    end
end

function R.OnEvent(_, event)
    pcall(R.Save)
end

if CreateFrame then
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_UPDATE_RESTING", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", R.OnEvent)
end
