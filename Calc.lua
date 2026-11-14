-- Imbue Advisor: the maths.
-- Each imbue's numbers are read from its own spell tooltip, so they follow
-- whatever values WoW Forever uses. If a tooltip can't be parsed, level-scaled
-- fallback numbers are used and /imbue report says so.
local _, ns = ...
local Calc = {}
ns.Calc = Calc

local max, min, floor = math.max, math.min, math.floor
local WORDS = { a = 1, an = 1, one = 1, two = 2, three = 3, four = 4 }

----------------------------------------------------------------------
-- Tooltip parsing
----------------------------------------------------------------------
function Calc.Clean(desc)
    if not desc or desc == "" then return nil end
    local d = desc:lower()
    d = d:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    d = d:gsub("(%d),(%d%d%d)", "%1%2")
    return d
end

local function firstNum(d, ...)
    for i = 1, select("#", ...) do
        local v = d:match((select(i, ...)))
        if v then return tonumber(v) end
    end
end

-- "X to Y <school> damage" or "X <school> damage"
local function rangeNum(d, school)
    local lo, hi = d:match("(%d+%.?%d*)%s+to%s+(%d+%.?%d*)[^%.]-" .. school .. " damage")
    if lo then return tonumber(lo), tonumber(hi) end
    local v = firstNum(d, "(%d+%.?%d*)%s+additional " .. school .. " damage", "(%d+%.?%d*)%s+" .. school .. " damage")
    if v then return v, v end
end

Calc.parsers = {}

function Calc.parsers.windfury(d, lvl)
    local p = { chance = 0.20, attacks = 1, extraAP = floor(lvl * 5.5), icd = 0, parsed = false }
    if not d then return p end
    local c = firstNum(d, "(%d+%.?%d*)%%%s*chance")
    if c then p.chance = c / 100; p.parsed = true end
    local ap = firstNum(d, "(%d+)%s+extra attack power", "(%d+)%s+additional attack power",
        "attack power by (%d+)", "(%d+)%s+attack power")
    if ap then p.extraAP = ap; p.parsed = true end
    local d2 = d:gsub("attack power", "#ap#")   -- so "333 extra attack power" isn't read as 333 attacks
    local n = firstNum(d2, "(%d+)%s+extra attacks?", "(%d+)%s+additional attacks?")
    if n then
        p.attacks = n
    else
        local w = d2:match("(%a+)%s+extra attacks?") or d2:match("(%a+)%s+additional attacks?")
        if w and WORDS[w] then p.attacks = WORDS[w] end
    end
    local cd = firstNum(d, "once every (%d+%.?%d*) sec", "(%d+%.?%d*) sec cooldown")
    if cd then p.icd = cd end
    return p
end

function Calc.parsers.flametongue(d, lvl)
    local p = { lo = lvl * 0.5, hi = lvl * 1.6, speedScaled = true, spellPower = 0, parsed = false }
    if not d then return p end
    local lo, hi = rangeNum(d, "fire")
    if lo then
        p.lo, p.hi, p.parsed = lo, hi, true
        p.speedScaled = lo ~= hi and d:find("speed", 1, true) ~= nil
    end
    p.spellPower = firstNum(d, "spell power by (%d+)", "spell damage by (%d+)",
        "spell damage and healing by (%d+)", "(%d+)%s+spell power") or 0
    return p
end

function Calc.parsers.frostbrand(d, lvl)
    local p = { lo = lvl * 1.8, hi = lvl * 1.8, chance = nil, ppm = 9, parsed = false }
    if not d then return p end
    local lo, hi = rangeNum(d, "frost")
    if lo then p.lo, p.hi, p.parsed = lo, hi, true end
    local c = firstNum(d, "(%d+%.?%d*)%%%s*chance")
    if c then p.chance = c / 100 end
    local ppm = firstNum(d, "(%d+%.?%d*)%s+times? per minute", "(%d+%.?%d*)%s+procs? per minute")
    if ppm then p.ppm = ppm end
    return p
end

function Calc.parsers.rockbiter(d, lvl)
    local p = { ap = 0, dps = 0, threat = 0, parsed = false }
    if d then
        p.ap = firstNum(d, "attack power by (%d+)", "(%d+)%s+attack power") or 0
        p.dps = firstNum(d, "by (%d+%.?%d*) damage per second", "(%d+%.?%d*)%s+damage per second",
            "damage by (%d+%.?%d*) per second", "damage per second by (%d+%.?%d*)") or 0
        p.threat = firstNum(d, "(%d+)%%%s+additional threat", "threat by (%d+)%%", "(%d+)%%%s+more threat") or 0
        p.parsed = p.ap > 0 or p.dps > 0
    end
    if not p.parsed then p.ap = floor(lvl * 1.0) end
    return p
end

function Calc.parsers.earthliving(d)
    local p = { chance = 0.20, parsed = false }
    if not d then return p end
    local c = firstNum(d, "(%d+%.?%d*)%%%s*chance")
    if c then p.chance = c / 100; p.parsed = true end
    return p
end

----------------------------------------------------------------------
-- Player state
----------------------------------------------------------------------
local SPEC_IDS = { [262] = "elemental", [263] = "enhancement", [264] = "restoration" }
local TREES = { "elemental", "enhancement", "restoration" }

function Calc.TalentTree()
    if GetSpecialization and GetSpecializationInfo then
        local ok, spec = pcall(GetSpecialization)
        if ok and type(spec) == "number" and spec > 0 then
            local id, _, _, _, role = GetSpecializationInfo(spec)
            return SPEC_IDS[id] or TREES[spec], role
        end
    end
    if GetNumTalentTabs and GetTalentTabInfo then
        local best, bestPts = nil, 0
        for i = 1, min(3, GetNumTalentTabs() or 0) do
            local r = { GetTalentTabInfo(i) }
            local pts = (type(r[1]) == "number") and r[5] or r[3]
            if type(pts) == "number" and pts > bestPts then best, bestPts = i, pts end
        end
        if best then return TREES[best] end
    end
end

function Calc.GatherStats(db)
    local st = { level = UnitLevel("player") or 1 }

    local mhID = GetInventoryItemID("player", 16)
    local ohID = GetInventoryItemID("player", 17)
    local _, _, _, mhLoc, _, mhClass = ns.ItemInfoInstant(mhID)
    local _, _, _, ohLoc, _, ohClass = ns.ItemInfoInstant(ohID)
    st.mhWeapon = mhID ~= nil and mhClass == 2
    st.ohWeapon = ohID ~= nil and ohClass == 2
    st.twoHand = mhLoc == "INVTYPE_2HWEAPON"
    st.shield = ohLoc == "INVTYPE_SHIELD"

    local mhSpeed, ohSpeed = UnitAttackSpeed("player")
    local haste = GetMeleeHaste and (GetMeleeHaste() or 0) or 0
    local minD, maxD, minO, maxO = UnitDamage("player")
    local base, pos, neg = UnitAttackPower("player")
    st.ap = (base or 0) + (pos or 0) + (neg or 0)
    st.crit = min(1, (GetCritChance and GetCritChance() or 5) / 100)
    st.spellCrit = min(1, (GetSpellCritChance and GetSpellCritChance(3) or 5) / 100)
    st.fireSP = GetSpellBonusDamage and GetSpellBonusDamage(3) or 0
    st.frostSP = GetSpellBonusDamage and GetSpellBonusDamage(5) or 0

    st.dualWield = st.mhWeapon and st.ohWeapon and ohSpeed ~= nil and ohSpeed > 0

    -- Hit table (approximate; attacking from behind, so no parry)
    local diff = db.targetLevelDiff or 0
    local up = max(0, diff)
    local miss = (diff >= 3) and 0.08 or (0.05 + 0.005 * up)
    local dodge = 0.05 + 0.005 * up
    if st.dualWield then miss = miss + 0.19 end
    local hitBonus = GetHitModifier and (GetHitModifier() or 0) or 0
    if GetCombatRatingBonus and CR_HIT_MELEE then hitBonus = hitBonus + (GetCombatRatingBonus(CR_HIT_MELEE) or 0) end
    st.landed = max(0.3, 1 - max(0, miss - hitBonus / 100) - dodge)
    st.spellHit = 1 - ((diff >= 3) and 0.17 or (0.04 + 0.01 * up))

    st.hands = {}
    if st.mhWeapon and mhSpeed and mhSpeed > 0 then
        st.hands[16] = {
            speed = mhSpeed, baseSpeed = mhSpeed * (1 + haste / 100),
            avg = ((minD or 0) + (maxD or 0)) / 2, landed = st.landed, hps = st.landed / mhSpeed,
        }
    end
    if st.dualWield then
        st.hands[17] = {
            speed = ohSpeed, baseSpeed = ohSpeed * (1 + haste / 100),
            avg = ((minO or 0) + (maxO or 0)) / 2, landed = st.landed, hps = st.landed / ohSpeed,
        }
    end
    return st
end

function Calc.ResolveMode(db, st)
    if db.mode ~= "auto" then return db.mode, "set with /imbue mode" end
    local tree, role = Calc.TalentTree()
    if UnitGroupRolesAssigned then
        local r = UnitGroupRolesAssigned("player")
        if r and r ~= "NONE" then role = r end
    end
    if role == "TANK" then return "tank", "tank role" end
    if role == "HEALER" or tree == "restoration" then return "heal", "Restoration / healer role" end
    if tree == "elemental" then return "caster", "Elemental" end
    local _, instType = IsInInstance()
    if instType == "pvp" or instType == "arena" then return "pvp", "battleground or arena" end
    if tree == "enhancement" then return "melee", "Enhancement" end
    return "melee", "no spec yet (leveling)"
end

----------------------------------------------------------------------
-- Damage models (per weapon hand)
----------------------------------------------------------------------
local Melee = {}

local function wfRate(hps, chance, icd)
    local raw = hps * chance
    if raw <= 0 then return 0 end
    if icd and icd > 0 then return 1 / (icd + 1 / raw) end
    return raw
end

function Melee.windfury(p, slot, st, db, other)
    if slot == 17 and not db.windfuryOffhandProcs then return 0 end
    local h = st.hands[slot]
    local apScale = (slot == 17) and 0.5 or 1
    local perAttack = (h.avg + p.extraAP / 14 * h.baseSpeed * apScale) * (1 + st.crit) * h.landed
    local rate = wfRate(h.hps, p.chance, p.icd)
    local o = st.hands[slot == 17 and 16 or 17]
    if other == "windfury" and o and db.windfurySharedCooldown and p.icd > 0 then
        -- both hands share one cooldown: only the extra procs count
        rate = wfRate(h.hps + o.hps, p.chance, p.icd) - wfRate(o.hps, p.chance, p.icd)
    end
    return rate * p.attacks * perAttack
end

function Melee.flametongue(p, slot, st)
    local h = st.hands[slot]
    local perHit
    if p.speedScaled and p.lo ~= p.hi then
        local t = max(0, min(1, (h.baseSpeed - 1.0) / 3.0))   -- range read as 1.0s .. 4.0s weapons
        perHit = p.lo + (p.hi - p.lo) * t
    else
        perHit = (p.lo + p.hi) / 2
    end
    perHit = perHit + 0.1 * (h.baseSpeed / 2.6) * st.fireSP
    return h.hps * st.spellHit * perHit * (1 + 0.5 * st.spellCrit)
end

function Melee.frostbrand(p, slot, st)
    local h = st.hands[slot]
    local rate = p.chance and (h.hps * p.chance) or (p.ppm / 60 * h.landed)
    local dmg = (p.lo + p.hi) / 2 + 0.1 * st.frostSP
    return rate * st.spellHit * dmg * (1 + 0.5 * st.spellCrit)
end

function Melee.rockbiter(p, slot, st)
    local h = st.hands[slot]
    local v = 0
    if p.ap > 0 then
        -- attack power applies to every melee swing, both hands
        local w = st.hands[16] and st.hands[16].landed * (1 + st.crit) or 0
        if st.hands[17] then w = w + st.hands[17].landed * (1 + st.crit) * 0.5 end
        v = v + p.ap / 14 * w
    end
    if p.dps > 0 then
        v = v + p.dps * h.landed * (1 + st.crit) * ((slot == 17) and 0.5 or 1)
    end
    return v
end

function Melee.earthliving() return 0 end

-- Priority scores for modes where melee damage isn't the point
local CASTER_PRIORITY = { flametongue = 10, earthliving = 5, rockbiter = 2, frostbrand = 1, windfury = 0 }
local HEAL_PRIORITY   = { earthliving = 20, flametongue = 10, rockbiter = 2, frostbrand = 1, windfury = 0 }

function Calc.ScoreSlot(slot, st, imbues, mode, db, other)
    local sr = { scores = {}, unit = "dps" }
    if not st.hands[slot] and not (slot == 16 and st.mhWeapon) then return sr end

    if mode == "caster" or mode == "heal" then
        sr.unit = "priority"
        local prio = (mode == "heal") and HEAL_PRIORITY or CASTER_PRIORITY
        for key, info in pairs(imbues) do
            local v = prio[key] or 0
            if key == "flametongue" then v = v + (info.params.spellPower or 0) / 100 end
            sr.scores[key] = v
        end
    elseif st.hands[slot] then
        for key, info in pairs(imbues) do
            local v = Melee[key](info.params, slot, st, db, other)
            if mode == "tank" and key == "rockbiter" then
                v = v * db.tankRockbiterThreat * (1 + info.params.threat / 100)
            end
            sr.scores[key] = v
        end
        if mode == "pvp" and sr.scores.frostbrand and other ~= "frostbrand" then
            local bestOther = 0
            for key, v in pairs(sr.scores) do
                if key ~= "frostbrand" then bestOther = max(bestOther, v) end
            end
            sr.slowBonus = bestOther * db.pvpSlowBonus
            sr.scores.frostbrand = sr.scores.frostbrand + sr.slowBonus
        end
    end

    local bestV
    for _, key in ipairs(ns.IMBUE_ORDER) do
        local v = sr.scores[key]
        if v and (not bestV or v > bestV + 1e-6) then sr.best, bestV = key, v end
    end
    return sr
end

function Calc.Evaluate(db)
    local st = Calc.GatherStats(db)
    local imbues = {}
    for _, key in ipairs(ns.IMBUE_ORDER) do
        local info = ns.ResolveImbue(key)
        if info then
            local desc = ns.SpellDescription(info.spellID)
            if not desc then ns.RequestSpellData(info.spellID) end
            info.desc = desc
            info.params = Calc.parsers[key](Calc.Clean(desc), st.level)
            imbues[key] = info
        end
    end

    local mode, reason = Calc.ResolveMode(db, st)
    local res = { stats = st, imbues = imbues, mode = mode, modeReason = reason, slots = {} }
    if st.mhWeapon then
        res.slots[16] = Calc.ScoreSlot(16, st, imbues, mode, db, nil)
    end
    if st.dualWield then
        res.slots[17] = Calc.ScoreSlot(17, st, imbues, mode, db, res.slots[16] and res.slots[16].best)
    end
    return res
end

function Calc.SortedScores(res, sr)
    local rows = {}
    if not sr then return rows end
    for key, v in pairs(sr.scores) do
        rows[#rows + 1] = { key = key, value = v, name = res.imbues[key].name }
    end
    table.sort(rows, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.key < b.key
    end)
    return rows
end
