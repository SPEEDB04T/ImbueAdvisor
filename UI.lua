-- Imbue Advisor: the on-screen frame (one click-to-cast button per weapon hand)
local _, ns = ...
local UI = {}
ns.UI = UI

local max = math.max
local SLOTS = { 16, 17 }
local SLOT_NAME = { [16] = "Main hand", [17] = "Off hand" }
local SLOT_SHORT = { [16] = "MH", [17] = "OH" }
local MODE_LABEL = { melee = "Melee", tank = "Tank", caster = "Caster", heal = "Healer", pvp = "PvP" }

local COLOR_OK = { 0.2, 0.9, 0.2 }       -- recommended imbue is on
local COLOR_WRONG = { 1.0, 0.8, 0.1 }    -- a different imbue is on
local COLOR_MISSING = { 1.0, 0.15, 0.15 } -- nothing on the weapon

local BTN, GAP, PAD = 36, 8, 8

local function UseKeyDown()
    local ok, v
    if C_CVar and C_CVar.GetCVarBool then
        ok, v = pcall(C_CVar.GetCVarBool, "ActionButtonUseKeyDown")
    elseif GetCVarBool then
        ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
    end
    return ok and v
end

local function FormatTime(sec)
    if sec >= 60 then return ("%dm"):format(math.ceil(sec / 60)) end
    return ("%ds"):format(math.floor(sec))
end

local function ImbueName(key)
    if not key then return nil end
    local res = UI.result
    if res and res.imbues[key] then return res.imbues[key].name end
    return ns.IMBUES[key] and ns.IMBUES[key].english
end

----------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------
local function OnEnter(self)
    local res = UI.result
    if not res then return end
    local slot = self.slot
    local sr = res.slots[slot]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Imbue Advisor: " .. SLOT_NAME[slot])
    if self.rec then GameTooltip:AddDoubleLine("Use", self.rec.name, 1, 1, 1, 0.3, 1, 0.3) end
    local e = ns.WeaponEnchants()[slot]
    local cur = ImbueName(ns.current[slot]) or (e.has and "something else" or "none")
    GameTooltip:AddDoubleLine("On weapon now", cur, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
    for _, row in ipairs(ns.Calc.SortedScores(res, sr)) do
        local txt = sr.unit == "dps" and ("%.1f dps"):format(row.value) or ("priority %.0f"):format(row.value)
        if sr.slowBonus and row.key == "frostbrand" then txt = txt .. " (incl. slow)" end
        local r, g, b = 0.8, 0.8, 0.8
        if row.key == sr.best then r, g, b = 0.3, 1, 0.3 end
        GameTooltip:AddDoubleLine(row.name, txt, r, g, b, r, g, b)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Mode: %s (%s)"):format(MODE_LABEL[res.mode] or res.mode, res.modeReason), 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Left-click: apply   Right-click: report in chat", 0.5, 0.8, 1)
    GameTooltip:Show()
end

local function OnLeave() GameTooltip:Hide() end

----------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------
function UI.SavePosition()
    local point, _, relPoint, x, y = UI.frame:GetPoint()
    ns.db.point = { point, relPoint, x, y }
end

function UI.RestorePosition()
    local f, p = UI.frame, ns.db.point
    f:ClearAllPoints()
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -180) end
end

local function StartMove(self)
    local f = UI.frame
    if not ns.db.locked and not InCombatLockdown() then f:StartMoving(); f.moving = true end
end

local function StopMove()
    local f = UI.frame
    if f.moving then f:StopMovingOrSizing(); f.moving = nil; UI.SavePosition() end
end

function UI.Create()
    if UI.frame then return end
    local f = CreateFrame("Frame", "ImbueAdvisorFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    UI.frame = f
    f:SetSize(PAD * 2 + BTN * 2 + GAP, BTN + 26)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", StartMove)
    f:SetScript("OnDragStop", StopMove)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0, 0, 0, 0.6)
        f:SetBackdropBorderColor(0.25, 0.45, 0.9, 0.9)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOP", f, "TOP", 0, -6)

    f.buttons = {}
    for _, slot in ipairs(SLOTS) do
        local b = CreateFrame("Button", "ImbueAdvisorButton" .. slot, f, "SecureActionButtonTemplate")
        b.slot = slot
        b:SetSize(BTN, BTN)
        if UseKeyDown() then b:RegisterForClicks("AnyDown", "AnyUp") else b:RegisterForClicks("AnyUp") end
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", StartMove)
        b:SetScript("OnDragStop", StopMove)

        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetPoint("TOPLEFT", -2, 2)
        b.border:SetPoint("BOTTOMRIGHT", 2, -2)
        b.border:SetColorTexture(unpack(COLOR_MISSING))

        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.15)

        b.label = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.label:SetPoint("TOPLEFT", 2, -2)
        b.label:SetText(SLOT_SHORT[slot])

        b.timer = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.timer:SetPoint("BOTTOM", 0, 2)

        b:SetScript("OnEnter", OnEnter)
        b:SetScript("OnLeave", OnLeave)
        b:SetScript("PostClick", function(_, button, down)
            if button == "RightButton" and not down then UI.PrintReport() end
        end)
        b:Hide()
        f.buttons[slot] = b
    end

    f:SetScale(ns.db.scale or 1)
    UI.RestorePosition()
    f:Hide()
end

-- Recommendation changed: update icons now, secure attributes when allowed.
function UI.Update(res)
    UI.result = res
    local f = UI.frame
    if not f then return end
    f.title:SetText(MODE_LABEL[res.mode] or res.mode)
    for _, slot in ipairs(SLOTS) do
        local b = f.buttons[slot]
        local sr = res.slots[slot]
        b.rec = sr and sr.best and res.imbues[sr.best] or nil
        b.icon:SetTexture(b.rec and b.rec.icon or nil)
    end
    UI.ApplySecure()
    UI.UpdateStatus()
end

-- Layout and click actions. Blocked in combat, so it waits for combat to end.
function UI.ApplySecure()
    local f = UI.frame
    if not f then return end
    if InCombatLockdown() then UI.pending = true; return end
    UI.pending = false

    local shownSlots = {}
    for _, slot in ipairs(SLOTS) do
        local b = f.buttons[slot]
        if b.rec then
            b:SetAttribute("type1", "macro")
            -- /use <slot> points a weapon-targeted imbue at the right hand
            b:SetAttribute("macrotext1", "/cast " .. b.rec.name .. "\n/use " .. slot)
            shownSlots[#shownSlots + 1] = slot
        else
            b:SetAttribute("type1", nil)
            b:SetAttribute("macrotext1", nil)
            b:Hide()
        end
    end
    local n = #shownSlots
    local width = max(76, PAD * 2 + n * BTN + max(0, n - 1) * GAP)
    f:SetWidth(width)
    local x0 = (width - (n * BTN + max(0, n - 1) * GAP)) / 2
    for i, slot in ipairs(shownSlots) do
        local b = f.buttons[slot]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + (i - 1) * (BTN + GAP), -20)
        b:Show()
    end
    if ns.db.shown and n > 0 then f:Show() else f:Hide() end
end

-- Border colours and timers (runs every second, safe in combat)
function UI.UpdateStatus()
    local f = UI.frame
    if not f or not f:IsShown() then return end
    local ench = ns.WeaponEnchants()
    for _, slot in ipairs(SLOTS) do
        local b = f.buttons[slot]
        if b:IsShown() and b.rec then
            local e = ench[slot]
            local col
            if not e.has then
                col = COLOR_MISSING
            elseif ns.current[slot] == b.rec.key then
                col = COLOR_OK
            else
                col = COLOR_WRONG
            end
            b.border:SetColorTexture(col[1], col[2], col[3], 1)
            if e.has and e.exp then
                b.timer:SetText(FormatTime(e.exp))
            else
                b.timer:SetText(e.has and "" or "|cffff4040none|r")
            end
        end
    end
end

----------------------------------------------------------------------
-- Chat output
----------------------------------------------------------------------
function UI.PrintReport()
    local res = ns.result
    if not res then ns.Print("nothing calculated yet.") return end
    local st = res.stats
    ns.Print(("mode %s (%s), target level %+d, hit %.0f%%, crit %.1f%%"):format(
        MODE_LABEL[res.mode] or res.mode, res.modeReason, ns.db.targetLevelDiff, st.landed * 100, st.crit * 100))
    for _, slot in ipairs(SLOTS) do
        local sr = res.slots[slot]
        if sr and sr.best then
            local h = st.hands[slot]
            local parts = {}
            for _, row in ipairs(ns.Calc.SortedScores(res, sr)) do
                parts[#parts + 1] = ("%s %s"):format(ns.IMBUES[row.key].short,
                    sr.unit == "dps" and ("%.1f"):format(row.value) or ("p%.0f"):format(row.value))
            end
            local weapon = h and ("%.2fs%s"):format(h.baseSpeed, (slot == 16 and st.twoHand) and " 2H" or "") or "-"
            ns.Print(("%s (%s): |cff40ff40%s|r   [%s%s]"):format(SLOT_SHORT[slot], weapon,
                res.imbues[sr.best].name, table.concat(parts, ", "), sr.unit == "dps" and " dps" or ""))
        end
    end
    local fallback = {}
    for key, info in pairs(res.imbues) do
        if not info.params.parsed then fallback[#fallback + 1] = info.name end
    end
    if #fallback > 0 then
        ns.Print("|cffffaa00couldn't read the tooltip of " .. table.concat(fallback, ", ") ..
            "; using estimated numbers. /imbue debug shows the text.|r")
    end
    if not st.mhWeapon then ns.Print("no main-hand weapon equipped.") end
end

function UI.PrintDebug()
    local res = ns.result
    if not res then ns.Print("nothing calculated yet.") return end
    for _, key in ipairs(ns.IMBUE_ORDER) do
        local info = res.imbues[key]
        if info then
            local kv = {}
            for k, v in pairs(info.params) do kv[#kv + 1] = k .. "=" .. tostring(v) end
            table.sort(kv)
            ns.Print(("%s (id %d): %s"):format(info.name, info.spellID, table.concat(kv, " ")))
            ns.Print("   tooltip: " .. tostring(info.desc))
        else
            ns.Print(ns.IMBUES[key].english .. ": not known")
        end
    end
    ns.Print(("current: MH=%s OH=%s"):format(tostring(ns.current[16]), tostring(ns.current[17])))
end
