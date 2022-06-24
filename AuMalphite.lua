if Player.CharName ~= "Malphite" then return end

local scriptName = "AuMalphite"
local scriptCreator = "AURUM"
local credits = "Orietto"
local patchNotesPrevUpdate = "12/21/2021"
local patchNotesPreVersion = "1.1.0"
local patchNotesVersion, scriptVersionUpdater = "1.1.2", "1.1.2"
local scriptVersion = scriptVersionUpdater
local scriptLastUpdated = "02/19/2022"
local scriptIsBeta = false

if scriptIsBeta then
    scriptVersion = scriptVersion .. " Beta"
else
    scriptVersion = scriptVersion .. " Release"
end

local scriptColor = 0x3C9BF0FF

module(scriptName, package.seeall, log.setup)
clean.module(scriptName, clean.seeall, log.setup)

local insert, sort = table.insert, table.sort
local huge, pow, min, max, floor = math.huge, math.pow, math.min, math.max, math.floor

local SDK = _G.CoreEx

SDK.AutoUpdate("https://raw.githubusercontent.com/roburAURUM/robur-AuEdition/main/AuMalphite.lua", scriptVersionUpdater)

local ObjManager = SDK.ObjectManager
local EventManager = SDK.EventManager
local Geometry = SDK.Geometry
local Renderer = SDK.Renderer
local Enums = SDK.Enums
local Game = SDK.Game
local Input = SDK.Input

local Vector = Geometry.Vector

local Libs = _G.Libs

local Menu = Libs.NewMenu
local Orbwalker = Libs.Orbwalker
local Collision = Libs.CollisionLib
local Prediction = Libs.Prediction
local Spell = Libs.Spell
local DmgLib = Libs.DamageLib
local TS = Libs.TargetSelector()

local Profiler = Libs.Profiler

local slots = {
    Q = Enums.SpellSlots.Q,
    W = Enums.SpellSlots.W,
    E = Enums.SpellSlots.E,
    R = Enums.SpellSlots.R
}

local dmgTypes = {
    Physical = Enums.DamageTypes.Physical,
    Magical = Enums.DamageTypes.Magical,
    True = Enums.DamageTypes.True
}

local damages = {
    Q = {
        Base = {70, 120, 170, 220, 270},
        TotalAP = 0.6,
        Type = dmgTypes.Magical
    },
    W = {
        Base = {30, 45, 60, 75, 90},
        TotalAP  = 0.2,
        Type = dmgTypes.Magical
    },
    E = {
        Base = {60, 95, 130, 165, 200},
        TotalAP  = 0.6,
        Type = dmgTypes.Magical
    },
    R = {
        Base = {200, 300, 400},
        TotalAP = 0.8,
        Type = dmgTypes.Magical
    }
}

local spells = {
    Q = Spell.Targeted({
        Slot = slots.Q,
        Delay = 0.25,
        Speed = 1200,
        Range = 625,
    }),
    W = Spell.Active({
        Slot = slots.W,
        Delay = 0.0,
        Range = 300,
    }),
    E = Spell.Active({
        Slot = slots.E,
        Delay = 0.25,
        Range = 335,
        Type = "Circular",
    }),
    R = Spell.Skillshot({
        Slot = slots.R,
        Delay = 0.0,
        Speed = 1838,
        Range = 1000,
        Radius = 255,
        Type = "Circular",
    }),
    Flash = {
        Slot = nil,
        LastCastT = 0,
        LastCheckT = 0,
        Range = 400
    }
}

local events = {}

local combatVariants = {}

local OriUtils = {}

local cacheName = Player.CharName

---@param unit AIBaseClient
---@param radius number|nil
---@param fromPos Vector|nil
function OriUtils.IsValidTarget(unit, radius, fromPos)
    fromPos = fromPos or Player.ServerPos
    radius = radius or huge

    return unit and unit.MaxHealth > 6 and fromPos:DistanceSqr(unit.ServerPos) < pow(radius, 2) and TS:IsValidTarget(unit)
end

function OriUtils.CastSpell(slot, pos_unit)
    return Input.Cast(slot, pos_unit)
end

function OriUtils.CastFlash(pos)
    if not spells.Flash.Slot then return false end

    local curTime = Game.GetTime()
    if curTime < spells.Flash.LastCastT + 0.25 then return false end

    return OriUtils.CastSpell(spells.Flash.Slot, pos)
end

function OriUtils.IsSpellReady(slot)
    return Player:GetSpellState(slot) == Enums.SpellStates.Ready
end

function OriUtils.ShouldRunLogic()
    return not (Game.IsChatOpen() or Game.IsMinimized() or Player.IsDead or Player.IsRecalling)
end

function OriUtils.MGet(menuId, nothrow)
    return Menu.Get(cacheName .. "." .. menuId, nothrow)
end

local summSlots = {Enums.SpellSlots.Summoner1, Enums.SpellSlots.Summoner2}
function OriUtils.CheckFlashSlot()
    local curTime = Game.GetTime()

    if curTime < spells.Flash.LastCheckT + 1 then return end

    spells.Flash.LastCheckT = curTime

    local function IsFlash(slot)
        return Player:GetSpell(slot).Name == "SummonerFlash"
    end

    for _, slot in ipairs(summSlots) do
        if IsFlash(slot) then
            if spells.Flash.Slot ~= slot then
                INFO("Flash was found on %d", slot)
                
                spells.Flash.Slot = slot
            end

            return
        end
    end

    if spells.Flash.Slot ~= nil then
        INFO("Flash was lost")

        spells.Flash.Slot = nil
    end
end

function OriUtils.CanCastSpell(slot, menuId)
    return OriUtils.IsSpellReady(slot) and OriUtils.MGet(menuId)
end

---@return AIMinionClient[]
function OriUtils.GetEnemyAndJungleMinions(radius, fromPos)
    fromPos = fromPos or Player.ServerPos

    local result = {}

    ---@param group GameObject[]
    local function AddIfValid(group)
        for _, unit in ipairs(group) do
            local minion = unit.AsMinion

            if OriUtils.IsValidTarget(minion, radius, fromPos) then
                result[#result+1] = minion
            end
        end
    end

    local enemyMinions = ObjManager.GetNearby("enemy", "minions")
    local jungleMinions = ObjManager.GetNearby("neutral", "minions")

    AddIfValid(enemyMinions)
    AddIfValid(jungleMinions)

    return result
end

function OriUtils.AddDrawMenu(data)
    for _, element in ipairs(data) do
        local id = element.id
        local displayText = element.displayText

        Menu.Checkbox(cacheName .. ".draw." .. id, "Draw " .. displayText .. " range", true)
        Menu.Indent(function()
            Menu.ColorPicker(cacheName .. ".draw." .. id .. ".color", "Color", scriptColor)
        end)
    end

    Menu.Separator()

    Menu.Checkbox(cacheName .. ".draw." .. "comboDamage", "Draw combo damage on healthbar", true)
    Menu.Checkbox(cacheName .. ".draw." .. "AlwaysDraw", "Always show Drawings", false)
end

---@param forcedTarget AIHeroClient
---@param ranges number[]
---@return AIHeroClient|nil
function OriUtils.ChooseTarget(forcedTarget, ranges)
    if forcedTarget and OriUtils.IsValidTarget(forcedTarget) then
        return forcedTarget
    elseif not forcedTarget then
        for _, range in ipairs(ranges) do
            local target = TS:GetTarget(range)

            if target then
                return target
            end
        end
    end

    return nil
end

local drawData = {
    {slot = slots.Q, id = "Q", displayText = "[Q] Seismic Shard", range = spells.Q.Range},
    {slot = slots.W, id = "W", displayText = "[W] Thunderclap", range = spells.W.Range},
    {slot = slots.E, id = "E", displayText = "[E] Ground Slam", range = spells.E.Range},
    {slot = slots.R, id = "R", displayText = "[R] Unstoppable Force", range = spells.R.Range}
}

--ASCIIArt
local ASCIIArt = "                 __  __       _       _     _ _        "
local ASCIIArt2 = "      /\\        |  \\/  |     | |     | |   (_) |       "
local ASCIIArt3 = "     /  \\  _   _| \\  / | __ _| |_ __ | |__  _| |_ ___  "
local ASCIIArt4 = "    / /\\ \\| | | | |\\/| |/ _` | | '_ \\| '_ \\| | __/ _ \\ "
local ASCIIArt5 = "   / ____ \\ |_| | |  | | (_| | | |_) | | | | | ||  __/ "
local ASCIIArt6 = "  /_/    \\_\\__,_|_|  |_|\\__,_|_| .__/|_| |_|_|\\__\\___| "
local ASCIIArt7 = "                               | |                    "
local ASCIIArt8 = "                               |_|                    "

local Malphite = {}

function Malphite.EFarm()
    if spells.E:IsReady() and OriUtils.MGet("clear.useE") then
        local count = 0

        local enemyMinions = ObjManager.GetNearby("enemy", "minions")
        for iE, objE in ipairs(enemyMinions) do
            local minion = objE.AsMinion

            if OriUtils.IsValidTarget(minion, spells.E.Range) then
                count = count + 1
            end        
        end

        return count
    end
end

function Malphite.KS()
    if OriUtils.MGet("ks.useQ") or OriUtils.MGet("ks.useW") or OriUtils.MGet("ks.useE") or  OriUtils.MGet("ks.useR") then
        local allyHeroes = ObjManager.GetNearby("ally", "heroes")
        for iKSA, objKSA in ipairs(allyHeroes) do
            local ally = objKSA.AsHero
            if not ally.IsMe and not ally.IsDead then
            local nearbyEnemiesKS = ObjManager.GetNearby("enemy", "heroes")
                for iKS, objKS in ipairs(nearbyEnemiesKS) do
                    local enemyHero = objKS.AsHero
                    local qDamage = Malphite.GetDamage(enemyHero, slots.Q)
                    local healthPredQ = spells.Q:GetHealthPred(objKS)
                    local wDamage = Malphite.GetDamage(enemyHero, slots.W)
                    local healthPredW = spells.W:GetHealthPred(objKS)
                    local eDamage = Malphite.GetDamage(enemyHero, slots.E)
                    local healthPredE = spells.E:GetHealthPred(objKS)
                    local rDamage = Malphite.GetDamage(enemyHero, slots.R)
                    local healthPredR = spells.R:GetHealthPred(objKS)
                    if not enemyHero.IsDead and enemyHero.IsVisible and enemyHero.IsTargetable then
                        if OriUtils.CanCastSpell(slots.Q, "ks.useQ") and spells.Q:IsInRange(objKS) then
                            if OriUtils.MGet("ks.qWL." .. enemyHero.CharName, true) then
                                if healthPredQ > 0 and healthPredQ < floor(qDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.Q:Cast(enemyHero) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "ks.useW") and spells.W:IsInRange(objKS) then
                            if OriUtils.MGet("ks.wWL." .. enemyHero.CharName, true) then
                                if healthPredE > 0 and healthPredE < floor(eDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.W:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "ks.useE") and spells.E:IsInRange(objKS) then
                            if OriUtils.MGet("ks.eWL." .. enemyHero.CharName, true) then
                                if healthPredE > 0 and healthPredE < floor(eDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.E:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "ks.useR") and spells.R:IsInRange(objKS) then
                            if OriUtils.MGet("ks.rWL." .. enemyHero.CharName, true) then
                                if healthPredR > 0 and healthPredR < floor(rDamage - 50) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.R:Cast(enemyHero) then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end 

function Malphite.DrakeSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") or OriUtils.MGet("steal.useE") or OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal, objSteal in ipairs(enemiesAround) do
            local enemy = objSteal.AsHero
            if OriUtils.IsValidTarget(objSteal) then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Malphite.GetDamage(minion, slots.Q)
                    local healthPredDrakeQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Malphite.GetDamage(minion, slots.W)
                    local healthPredDrakeW = spells.W:GetHealthPred(minion)
                    local eDamage = Malphite.GetDamage(minion, slots.E)
                    local healthPredDrakeE = spells.E:GetHealthPred(minion)
                    local rDamage = Malphite.GetDamage(minion, slots.R)
                    local healthPredDrakeR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsDragon and minion:Distance(enemy) < 1800 or enemy.IsInDragonPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") and spells.Q:IsInRange(minion) then
                            if healthPredDrakeQ > 0 and healthPredDrakeQ < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "steal.useW") and spells.W:IsInRange(minion)then
                            if healthPredDrakeW > 0 and healthPredDrakeW < floor(wDamage) then
                                if spells.W:Cast() then
                                    return
                                end
                            end
                        end                        
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") and spells.E:IsInRange(minion)then
                            if healthPredDrakeE > 0 and healthPredDrakeE < floor(eDamage) then
                                if spells.E:Cast() then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and spells.R:IsInRange(minion)then
                            if healthPredDrakeR > 0 and healthPredDrakeR < floor(rDamage) then
                                if spells.R:Cast(minion) then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Malphite.BaronSteal()
    if OriUtils.MGet("steal.useQ") or OriUtils.MGet("steal.useW") or OriUtils.MGet("steal.useE") or  OriUtils.MGet("steal.useR") then 
        local enemiesAround = ObjManager.GetNearby("enemy", "heroes")
        for iSteal2, objSteal2 in ipairs(enemiesAround) do
            local enemy = objSteal2.AsHero
            if OriUtils.IsValidTarget(objSteal2) then
                local nearbyMinions = ObjManager.GetNearby("neutral", "minions")
                for iM2, minion in ipairs(nearbyMinions) do
                    local minion = minion.AsMinion
                    local qDamage = Malphite.GetDamage(minion, slots.Q)
                    local healthPredBaronQ = spells.Q:GetHealthPred(minion)
                    local wDamage = Malphite.GetDamage(minion, slots.W)
                    local healthPredBaronW = spells.W:GetHealthPred(minion)
                    local eDamage = Malphite.GetDamage(minion, slots.E)
                    local healthPredBaronE = spells.E:GetHealthPred(minion)
                    local rDamage = Malphite.GetDamage(minion, slots.R)
                    local healthPredBaronR = spells.R:GetHealthPred(minion)
                    if not minion.IsDead and minion.IsBaron and minion:Distance(enemy) < 1800 or enemy.IsInBaronPit then
                        if OriUtils.CanCastSpell(slots.Q, "steal.useQ") and spells.Q:IsInRange(minion) then
                            if healthPredBaronQ > 0 and healthPredBaronQ < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.W, "steal.useW") and spells.W:IsInRange(minion)then
                            if healthPredBaronW > 0 and healthPredBaronW < floor(wDamage) then
                                if spells.W:Cast() then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.E, "steal.useE") and spells.E:IsInRange(minion)then
                            if healthPredBaronE > 0 and healthPredBaronE < floor(eDamage) then
                                if spells.E:Cast() then
                                    return
                                end
                            end
                        end
                        if OriUtils.CanCastSpell(slots.R, "steal.useR") and spells.R:IsInRange(minion)then
                            if healthPredBaronR > 0 and healthPredBaronR < floor(rDamage) then
                                if spells.R:Cast(minion) then
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local slotToDamageTable = {
    [slots.Q] = damages.Q,
    [slots.W] = damages.W,
    [slots.E] = damages.E,
    [slots.R] = damages.R
}

function Malphite.flashR()
    if OriUtils.MGet("misc.flashR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)

        if spells.R:IsReady() then
            local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
            if not flashReady then
                return
            end

            local rFlashRange = (spells.R.Range - 10) + spells.Flash.Range
            local rFlashTarget = TS:GetTarget(rFlashRange, false)
            if rFlashTarget and not spells.R:IsInRange(rFlashTarget) then
                local flashPos = Player.ServerPos:Extended(rFlashTarget, spells.Flash.Range) 

                local spellInput = {
                    Slot = slots.R,
                    Delay = 0,
                    Speed = 1838,
                    Range = 1000,
                    Radius = 270,
                    Type = "Circular",
                }
                local pred = Prediction.GetPredictedPosition(rFlashTarget, spellInput, flashPos)
                if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                    if Input.Cast(spells.Flash.Slot, flashPos) then
                        delay(85, function()spells.R:Cast(rFlashTarget) end)
                        return
                    end
                end
            end
        end
    end
end

function Malphite.forceR()
    if OriUtils.MGet("misc.forceR") then
        Orbwalker.Orbwalk(Renderer.GetMousePos(), nil)
        local enemyPositions = {}
        
        for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
            local pred = spells.R:GetPrediction(obj)
            if pred and pred.HitChance >= (OriUtils.MGet("hcNew.R") / 100) then
                table.insert(enemyPositions, pred.TargetPosition)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(enemyPositions, spells.R.Radius)
        if numberOfHits >= 1 then
            if spells.R:Cast(bestPos) then
                return
            end
        end
    end
end

function Malphite.AutoR()
    if OriUtils.CanCastSpell(slots.R,"misc.AutoR") then
        local enemyPositions = {}
        
        for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
            local pred = spells.R:GetPrediction(obj)
            if pred and pred.HitChance >= (OriUtils.MGet("hcNew.R") / 100) then
                table.insert(enemyPositions, pred.TargetPosition)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(enemyPositions, spells.R.Radius)
        if numberOfHits >= OriUtils.MGet("misc.AutoRSlider") then
            if spells.R:Cast(bestPos) then
                return
            end
        end
    end
end

---@param target AIBaseClient
---@param slot slut
function Malphite.GetDamage(target, slot)
    local me = Player
    local rawDamage = 0
    local damageType = nil

    local spellLevel = me:GetSpell(slot).Level

    if spellLevel >= 1 then
        local data = slotToDamageTable[slot]

        if data then
            damageType = data.Type

            rawDamage = rawDamage + data.Base[spellLevel]

            if data.TotalAP then
                rawDamage = rawDamage + (data.TotalAP * me.TotalAP)
            end

            if data.BonusAD then
                rawDamage = rawDamage + (data.BonusAD * me.BonusAD)
            end

            if damageType == dmgTypes.Physical then
                return DmgLib.CalculatePhysicalDamage(me, target, rawDamage)
            elseif damageType == dmgTypes.Magical then
                return DmgLib.CalculateMagicalDamage(me, target, rawDamage)
            else
                return rawDamage
            end
        end
    end

    return 0
end

function combatVariants.Combo()
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        local enemyPositions = {}
        
        for i, obj in ipairs(TS:GetTargets(spells.R.Range)) do
            local pred = spells.R:GetPrediction(obj)
            if pred and pred.HitChance >= (OriUtils.MGet("hcNew.R") / 100) then
                table.insert(enemyPositions, pred.TargetPosition)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(enemyPositions, spells.R.Radius)
        if numberOfHits >= OriUtils.MGet("combo.useR.minEnemies") then
            if spells.R:Cast(bestPos) then
                return
            end
        end
    end

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:Cast() then
                return
            end
        end
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        local wTarget = spells.W:GetTarget()
        if wTarget then
            if spells.W:Cast() then
                return
            end
        end
    end
end

function combatVariants.Harass()
    if spells.Q:IsReady() and OriUtils.MGet("harass.useQ") then
        local qTarget = spells.Q:GetTarget()
        if qTarget then
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end

    if spells.E:IsReady() and OriUtils.MGet("harass.useE") then
        local eTarget = spells.E:GetTarget()
        if eTarget then
            if spells.E:Cast() then
                return
            end
        end
    end
end

function combatVariants.Waveclear()
    if OriUtils.CanCastSpell(slots.Q, "jglclear.useQ") then
        local jglminionsQ = ObjManager.GetNearby("neutral", "minions")
        for iJGLQ, objJGLQ in ipairs(jglminionsQ) do
            if OriUtils.IsValidTarget(objJGLQ, spells.Q.Range) then
                if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.QManaSlider") then
                    if not Orbwalker.IsWindingUp() then
                        if spells.Q:Cast(objJGLQ) then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.W, "jglclear.useW") then
        local jglminionsW = ObjManager.GetNearby("neutral", "minions")
        for iJGLW, objJGLW in ipairs(jglminionsW) do
            if OriUtils.IsValidTarget(objJGLW, spells.W.Range) then
                if Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.WManaSlider") then
                    if not Orbwalker.IsWindingUp() then
                        if spells.W:Cast() then
                            return
                        end
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "jglclear.useE") then
        local jglminionsE = ObjManager.GetNearby("neutral", "minions")
        local minionsPositions = {}

        for iJGLE, objJGLE in ipairs(jglminionsE) do
            local minion = objJGLE.AsMinion
            if OriUtils.IsValidTarget(objJGLE, spells.E.Range) then
                insert(minionsPositions, minion.Position)
            end
        end
        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.E.Range) 
        if numberOfHits >= 1 and Player.ManaPercent * 100 >= OriUtils.MGet("jglclear.EManaSlider") then
            if not Orbwalker.IsWindingUp() then
                if spells.E:Cast() then
                    return
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.pokeQ") then
        if Orbwalker.IsWindingUp() then
            return
        else
            local qTarget = spells.Q:GetTarget()
            if qTarget and not Orbwalker.IsWindingUp() then
                if spells.Q:Cast(qTarget) then
                    return
                end
            end
        end
    end

    if OriUtils.MGet("clear.enemiesAround") and TS:GetTarget(1800) then
        return
    end

    if OriUtils.CanCastSpell(slots.Q, "clear.useQ") then
        local qMinions = ObjManager.GetNearby("enemy", "minions")
        for iQ, minionQ in ipairs(qMinions) do 
            local healthPred = spells.Q:GetHealthPred(minionQ)
            local minion = minionQ.AsMinion
            local qDamage = Malphite.GetDamage(minion, slots.Q)
            local AARange = Orbwalker.GetTrueAutoAttackRange(Player)
            if Player.ManaPercent * 100 >= OriUtils.MGet("clear.QManaSlider") then
                if OriUtils.MGet("clear.useQ.options") == 0 then
                    if not minion.IsDead and minion.IsSiegeMinion then
                        if spells.Q:IsInRange(minion) and Player:Distance(minion) > AARange + 100 then
                            if healthPred > 0 and healthPred < floor(qDamage) then
                                if spells.Q:Cast(minion) then
                                    return
                                end
                            end
                        end
                    end
                else
                    if not minion.IsDead and spells.Q:IsInRange(minion) and Player:Distance(minion) > AARange + 100 then
                            if healthPred > 0 and healthPred < floor(qDamage) then
                                if not Orbwalker.IsWindingUp() then
                                    if spells.Q:Cast(minion) then
                                        return
                                    end
                                end
                            end
                        
                    end
                end
            end
        end
    end

    if OriUtils.CanCastSpell(slots.E, "clear.useE") then
        local minionsInERange = ObjManager.GetNearby("enemy", "minions")
        local minionsPositions = {}

        for _, minion in ipairs(minionsInERange) do
            if spells.E:IsInRange(minion) then
                insert(minionsPositions, minion.Position)
            end
        end

        local bestPos, numberOfHits = Geometry.BestCoveringCircle(minionsPositions, spells.E.Radius) 
        if numberOfHits >= OriUtils.MGet("clear.eMinions") then
            if Player.ManaPercent * 100 >= OriUtils.MGet("clear.EManaSlider") then
                if not Orbwalker.IsWindingUp() then
                    if spells.E:Cast() then
                        return
                    end
                end
            end
        end
    end
end

function combatVariants.Lasthit()
    if OriUtils.CanCastSpell(slots.W, "lasthit.useW") then
        local wLMinions = ObjManager.GetNearby("enemy", "minions")
        for iWL, minionWL in ipairs(wLMinions) do 
            local healthPred = spells.W:GetHealthPred(minionWL)
            local minion = minionWL.AsMinion
            local wDamage = Malphite.GetDamage(minion, slots.W)
            local AARange = Orbwalker.GetTrueAutoAttackRange(Player)
            if OriUtils.MGet("lasthit.useW.options") == 0 then
                if Player.ManaPercent * 100 >= OriUtils.MGet("lasthit.useW.0.ManaSlider") then
                    if not minion.IsDead and minion.IsSiegeMinion then
                        if spells.W:IsInRange(minion) then
                            if healthPred > 0 and healthPred < floor(wDamage + Player.BaseAttackDamage) then
                                if not Orbwalker.IsWindingUp() then
                                    if spells.W:Cast() then
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            else
                if not minion.IsDead and spells.W:IsInRange(minion) then
                    if Player.ManaPercent * 100 >= OriUtils.MGet("lasthit.useW.1.ManaSlider") then
                        if healthPred > 0 and healthPred < floor(wDamage + Player.BaseAttackDamage) then
                            if not Orbwalker.IsWindingUp() then
                                if spells.W:Cast() then
                                    return
                                end
                            end
                        end
                    else
                        if OriUtils.MGet("lasthit.useW.alwaysCanon") then
                            if minion.IsSiegeMinion then
                                if healthPred > 0 and healthPred < floor(wDamage + Player.BaseAttackDamage) then
                                    if not Orbwalker.IsWindingUp() then
                                        if spells.W:Cast() then
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end                            
                end
            end
        end
    end
end

function combatVariants.Flee()
end

function events.OnTick()
    OriUtils.CheckFlashSlot()
    if not OriUtils.ShouldRunLogic() then
        return
    end
    -- Get State of Orbwaler by Orbwalker.GetMode()
    local OrbwalkerState = Orbwalker.GetMode()
    -- Check OrbwalkerState (Combo,Harass,Flee,Waveclear,Lasthit) and apply combatVariants Logic
    if OrbwalkerState == "Combo" then
        combatVariants.Combo()
    elseif OrbwalkerState == "Harass" then
        combatVariants.Harass()
    elseif OrbwalkerState == "Waveclear" then
        combatVariants.Waveclear()
    elseif OrbwalkerState == "Lasthit" then
        combatVariants.Lasthit()
    elseif OrbwalkerState == "Flee" then
        combatVariants.Flee()
    end

    Malphite.AutoR()
    Malphite.forceR()
    Malphite.flashR()
    Malphite.BaronSteal()
    Malphite.DrakeSteal()
    Malphite.KS()
end

---@param source GameObject
function events.OnInterruptibleSpell(source, spellCast, danger, endTime, canMoveDuringChannel)
    if source.IsHero and source.IsEnemy then
        if spells.R:IsReady() and OriUtils.MGet("interrupt.R") then
            if OriUtils.MGet("interrupt.rWL." .. source.CharName, true) then
                if danger >= 5 and spells.R:IsInRange(source) then
                    local pred = spells.R:GetPrediction(source)
                    if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                        if spells.R:Cast(pred.CastPosition) then
                            return
                        end
                    end
                end
            end
        end
    end
end

function events.OnDraw()
    if Player.IsDead then
        return
    end

    local myPos = Player.Position

    for _, drawInfo in ipairs(drawData) do
        local slot = drawInfo.slot
        local id = drawInfo.id
        local range = drawInfo.range

        if type(range) == "function" then
            range = range()
        end
        
        if not OriUtils.MGet("draw.AlwaysDraw") then
            if OriUtils.CanCastSpell(slot, "draw." .. id) then
                Renderer.DrawCircle3D(myPos, range, 30, 2, OriUtils.MGet("draw." .. id .. ".color"))
            end
        else
            if Player:GetSpell(slot).IsLearned then
                Renderer.DrawCircle3D(myPos, range, 30, 2, OriUtils.MGet("draw." .. id .. ".color"))
            end
        end
    end

    if OriUtils.MGet("misc.flashR") then
        local flashReady = spells.Flash.Slot and OriUtils.IsSpellReady(spells.Flash.Slot)
        if spells.R:IsReady() then
            if not flashReady then
                return Renderer.DrawTextOnPlayer("Flash not Ready", 0xFF0000FF)
            else
                local rRange = spells.Flash.Range + spells.R.Range
                INFO("Test")
                return Renderer.DrawCircle3D(myPos, rRange, 30, 5, 0xFF0000FF)
            end
        else
            if flashReady then
                return Renderer.DrawTextOnPlayer("R not Ready", scriptColor)
            else
                return Renderer.DrawTextOnPlayer("R and Flash not Ready", 0xFFFF00FF)
            end
        end
    end
end

function events.OnDrawDamage(target, dmgList)
    if not OriUtils.MGet("draw.comboDamage") then
        return
    end

    local damageToDeal = 0

    if spells.Q:IsReady() and OriUtils.MGet("combo.useQ") then
        damageToDeal = damageToDeal + Malphite.GetDamage(target, slots.Q)
    end

    if spells.W:IsReady() and OriUtils.MGet("combo.useW") then
        damageToDeal = damageToDeal + Malphite.GetDamage(target, slots.E)
    end

    if spells.E:IsReady() and OriUtils.MGet("combo.useE") then
        damageToDeal = damageToDeal + Malphite.GetDamage(target, slots.E)
    end
    if spells.R:IsReady() and OriUtils.MGet("combo.useR") then
        damageToDeal = damageToDeal + Malphite.GetDamage(target, slots.R)
    end

    insert(dmgList, damageToDeal)
end

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffGain(obj, buffInst)
    if obj and buffInst then
        if obj.IsEnemy and obj.IsHero then
            --INFO("An enemy hero gained the buff: " .. buffInst.Name)
        end
    end
end

---@param obj GameObject
---@param buffInst BuffInst
function events.OnBuffLost(obj, buffInst)
    if obj and buffInst then
        if obj.IsEnemy and obj.IsHero then
            --INFO("An enemy hero lost the buff: " .. buffInst.Name)
        end
    end
end

function Malphite.RegisterEvents()
    for eventName, eventId in pairs(Enums.Events) do
        if events[eventName] then
            EventManager.RegisterCallback(eventId, events[eventName])
        end
    end
end

function Malphite.InitMenu()
    local function QHeader()
        Menu.ColoredText(drawData[1].displayText, scriptColor, true)
    end
    local function QHeaderHit()
        Menu.ColoredText(drawData[1].displayText .. " Hitchance", scriptColor, true)
    end

    local function WHeader()
        Menu.ColoredText(drawData[2].displayText, scriptColor, true)
    end
    local function WHeaderHit()
        Menu.ColoredText(drawData[2].displayText .. " Hitchance", scriptColor, true)
    end

    local function EHeader()
        Menu.ColoredText(drawData[3].displayText, scriptColor, true)
    end
    local function EHeaderHit()
        Menu.ColoredText(drawData[3].displayText .. " Hitchance", scriptColor, true)
    end

    local function RHeader()
        Menu.ColoredText(drawData[4].displayText, scriptColor, true)
    end
    local function RHeaderHit()
        Menu.ColoredText(drawData[4].displayText .. " Hitchance", scriptColor, true)
    end

    local function MalphiteMenu()
        Menu.Text("" .. ASCIIArt, true)
        Menu.Text("" .. ASCIIArt2, true)
        Menu.Text("" .. ASCIIArt3, true)
        Menu.Text("" .. ASCIIArt4, true)
        Menu.Text("" .. ASCIIArt5, true)
        Menu.Text("" .. ASCIIArt6, true)
        Menu.Text("" .. ASCIIArt7, true)
        Menu.Text("" .. ASCIIArt8, true)
        Menu.Separator()

        Menu.Text("", true)
        Menu.Text("Version:", true) Menu.SameLine()
        Menu.ColoredText(scriptVersion, scriptColor, false)
        Menu.Text("Last Updated:", true) Menu.SameLine()
        Menu.ColoredText(scriptLastUpdated, scriptColor, false)
        Menu.Text("Creator:", true) Menu.SameLine()
        Menu.ColoredText(scriptCreator, 0x6EFF26FF, false)
        Menu.Text("Credits to:", true) Menu.SameLine()
        Menu.ColoredText(credits, 0x6EFF26FF, false)

        if scriptIsBeta then
            Menu.ColoredText("This script is in an early stage , which means you'll have to redownload the final version once it's done!", 0xFFFF00FF, true)
            Menu.ColoredText("Please keep in mind, that you might encounter bugs/issues.", 0xFFFF00FF, true)
            Menu.ColoredText("If you find any, please contact " .. scriptCreator .. " via robur.lol", 0xFF0000FF, true)
        end
        
        if Menu.Checkbox("Malphite.Updates110", "Don't show updates") == false then
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. scriptLastUpdated .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesVersion, 0XFFFF00FF, true)
            Menu.Text("- Adjusted Hitchance for new Prediction", true)
            Menu.Separator()
            Menu.ColoredText("*** UPDATE " .. patchNotesPrevUpdate .. " ***", scriptColor, true)
            Menu.Separator()
            Menu.ColoredText(patchNotesPreVersion, 0XFFFF00FF, true)
            Menu.Text("- Initial Release of AuMalphite 1.0.0", true)
        end

        Menu.Separator()

        Menu.NewTree("Malphite.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Malphite.comboMenu.QE", "Malphite.comboMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Malphite.combo.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Malphite.combo.useE", "Enable E", true)
            end)

            Menu.ColumnLayout("Malphite.comboMenu.WR", "Malphite.comboMenu.WR", 2, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Malphite.combo.useW", "Enable W", true)
                Menu.NextColumn()
                RHeader()
                Menu.Checkbox("Malphite.combo.useR", "Enable R", true)
                Menu.Slider("Malphite.combo.useR.minEnemies", "Use if X enemy(s)", 3, 1, 5)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Malphite.harassMenu", "Harass Settings", function()
            Menu.ColumnLayout("Malphite.harassMenu.QE", "Malphite.harassMenu.QE", 2, true, function()
                Menu.Text("")
                QHeader()
                Menu.Checkbox("Malphite.harass.useQ", "Enable Q", true)
                Menu.NextColumn()
                Menu.Text("")
                EHeader()
                Menu.Checkbox("Malphite.harass.useE", "Enable E", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Malphite.clearMenu", "Clear Settings", function()
            Menu.NewTree("Malphite.waveMenu", "Waveclear", function()
                Menu.Checkbox("Malphite.clear.enemiesAround", "Don't clear while enemies around", true)
                Menu.Separator()
                Menu.Checkbox("Malphite.clear.pokeQ", "Enable Q Poke on Enemy", true)
                Menu.Checkbox("Malphite.clear.useQ", "Use Q", true)
                Menu.Dropdown("Malphite.clear.useQ.options", "Use Q for", 0, {"Canon", "All"})
                Menu.Slider("Malphite.clear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Malphite.clear.useE", "Enable E", false)
                Menu.Slider("Malphite.clear.eMinions", "if X Minions", 5, 1, 6, 1)
                Menu.Slider("Malphite.clear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
            Menu.NewTree("Malphite.jglMenu", "Jungleclear", function()
                Menu.Checkbox("Malphite.jglclear.useQ", "Use Q", true)
                Menu.Slider("Malphite.jglclear.QManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Malphite.jglclear.useW", "Use W", true)
                Menu.Slider("Malphite.jglclear.WManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
                Menu.Checkbox("Malphite.jglclear.useE", "Use E", true)
                Menu.Slider("Malphite.jglclear.EManaSlider", "Don't use if Mana < %", 35, 1, 100, 1)
            end)
        end)

        Menu.Separator()

        Menu.NewTree("Malphite.lasthitMenu", "Lasthit Settings", function()
            Menu.ColumnLayout("Malphite.lasthitMenu.W", "Malphite.lasthitMenu.W", 1, true, function()
                Menu.Text("")
                WHeader()
                Menu.Checkbox("Malphite.lasthit.useW", "Enable W", true)
                Menu.Dropdown("Malphite.lasthit.useW.options", "Use W on", 0, {"Canon", "All"})
                local ddResultW = OriUtils.MGet("lasthit.useW.options") == 0
                if ddResultW then
                    Menu.Slider("Malphite.lasthit.useW.0.ManaSlider", "Only use if Mana above X", 40, 1, 100, 1)
                end
                local ddResultW1 = OriUtils.MGet("lasthit.useW.options") == 1
                if ddResultW1 then
                    Menu.Slider("Malphite.lasthit.useW.1.ManaSlider", "Only use if Mana above X", 40, 1, 100, 1)
                    Menu.Checkbox("Malphite.lasthit.useW.alwaysCanon", "Always use for Canon")
                end
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Malphite.stealMenu", "Steal Settings", function()
            Menu.NewTree("Malphite.ksMenu", "Killsteal", function()
                Menu.Checkbox("Malphite.ks.useQ", "Killsteal with Q", true)
                local cbResult = OriUtils.MGet("ks.useQ")
                if cbResult then
                    Menu.Indent(function()
                        Menu.NewTree("Malphite.ksMenu.qWhitelist", "KS Q Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Malphite.ks.qWL." .. heroName, "Q KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Malphite.ks.useW", "Killsteal with W", true)
                local cbResultW = OriUtils.MGet("ks.useW")
                if cbResultW then
                    Menu.Indent(function()
                        Menu.NewTree("Malphite.ksMenu.wWhitelist", "KS W Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Malphite.ks.wWL." .. heroName, "W KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Malphite.ks.useE", "Killsteal with E", true)
                local cbResult2 = OriUtils.MGet("ks.useE")
                if cbResult2 then
                    Menu.Indent(function()
                        Menu.NewTree("Malphite.ksMenu.eWhitelist", "KS E Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Malphite.ks.eWL." .. heroName, "E KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.Checkbox("Malphite.ks.useR", "Killsteal with R", false)
                local cbResult3 = OriUtils.MGet("ks.useR")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Malphite.ksMenu.rWhitelist", "KS R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Malphite.ks.rWL." .. heroName, "R KS on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
            end)
            Menu.NewTree("Malphite.jglstealMenu", "Junglesteal (Drake/Baron) | BETA", function()
                Menu.Checkbox("Malphite.steal.useQ", "Junglesteal with Q", true)
                Menu.Checkbox("Malphite.steal.useW", "Junglesteal with W", true)
                Menu.Checkbox("Malphite.steal.useE", "Junglesteal with E", true)
                Menu.Checkbox("Malphite.steal.useR", "Junglesteal with R", false)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Malphite.miscMenu", "Misc Settings", function()
            Menu.ColumnLayout("Malphite.miscMenu.R", "Malphite.miscMenu.R", 2, true, function()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Malphite.misc.forceR", "Force R", string.byte("T"), false, false,  true)
                Menu.Checkbox("Malphite.interrupt.R", "Interrupt with R", true)
                local cbResult3 = OriUtils.MGet("interrupt.R")
                if cbResult3 then
                    Menu.Indent(function()
                        Menu.NewTree("Malphite.miscMenu.interruptR", "interrupt R Whitelist", function()
                            local enemyHeroes = ObjManager.Get("enemy", "heroes")
        
                            local addedWL = {}
        
                            for _, obj in pairs(enemyHeroes) do
                                local hero = obj.AsHero
                                local heroName = hero.CharName
        
                                if hero and not addedWL[heroName] then
                                    Menu.Checkbox("Malphite.interrupt.rWL." .. heroName, "Use R interrupt on " .. heroName, true)
        
                                    addedWL[heroName] = true
                                end
                            end
                        end)
                    end)
                end
                Menu.NextColumn()
                Menu.Text("")
                RHeader()
                Menu.Keybind("Malphite.misc.flashR", "Flash R", string.byte("G"), false, false, true)
                Menu.Checkbox("Malphite.misc.AutoR", "Enable Auto R", true)
                Menu.Slider("Malphite.misc.AutoRSlider", "If can hit X Enemies", 4, 1, 5, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Malphite.hcMenu", "Hitchance Settings", function()
            Menu.ColumnLayout("Malphite.hcMenu.R", "Malphite.hcMenu.R", 1, true, function()
                Menu.Text("")
                RHeaderHit()
                Menu.Text("")
                Menu.Slider("Malphite.hcNew.R", "%", 45, 1, 100, 1)
            end)
        end)
        Menu.Separator()

        Menu.NewTree("Malphite.drawMenu", "Draw Settings", function()
            OriUtils.AddDrawMenu(drawData)
        end)
    end

    Menu.RegisterMenu(scriptName, scriptName, MalphiteMenu)
end

function OnLoad()
    Malphite.InitMenu()
    
    Malphite.RegisterEvents()
    return true
end
