local bot = GetBot()
local botName = bot:GetUnitName()

if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local J = require( GetScriptDirectory()..'/FunLib/jmz_func')

local cAbility = nil
local TinkerShouldWaitInBaseToHeal = false

local ShouldWaitInBaseToHeal = false
local TPScroll = nil

local ShouldMoveCloseTowerForEdict = false
local EdictTowerTarget = nil

local ShouldMoveOutsideFountain = false
local ShouldMoveOutsideFountainCheckTime = 0
local MoveOutsideFountainDistance = 1500
local BearAttackLimitDistance = 1100
local TetherBreakDistance = 1000
local ConsiderHeroSpecificRoaming = {}

local laneToGank = nil
local lastGankDecisionTime = DotaTime()
local gankDecisionHoldTime = 1.25 * 60 -- cant change dicision within this time
local TwinGates = { }
local targetGate
local gateWarp = bot:GetAbilityByName("twin_gate_portal_warp")
local enableGateUsage = false -- to be fixed
local arriveRoamLocTime = 0
local roamTimeAfterArrival = 0.55 * 60 -- stay to roam after arriving the location
local gankGapTime = 2 * 60 -- don't roam again within this duration after roaming once.
local lastStaticLinkDebuffStack = 0
local nInRangeEnemy, nInRangeAlly, allyTowers, enemyTowers, trySeduce, shouldTempRetreat, botTarget, shouldGoBackToFountain

local laneAndT1s = {
	{LANE_TOP, TOWER_TOP_1},
	{LANE_MID, TOWER_MID_1},
	{LANE_BOT, TOWER_BOT_1}
}

function GetDesire()
	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return BOT_MODE_DESIRE_NONE end

	trySeduce = false
	shouldTempRetreat = false
	TPScroll = J.GetItem2(bot, 'item_tpscroll')
	botTarget = J.GetProperTarget(bot)
	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	nInRangeAlly = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
	allyTowers = bot:GetNearbyTowers(1600, false)
	enemyTowers = bot:GetNearbyTowers(1600, true)

	-- if ConsiderWaitInBaseToHeal()
	-- and GetUnitToLocationDistance(bot, J.GetTeamFountain()) > 5500
	-- then
	-- 	return BOT_ACTION_DESIRE_ABSOLUTE
	-- end

	TinkerShouldWaitInBaseToHeal = TinkerWaitInBaseAndHeal()
	if TinkerShouldWaitInBaseToHeal
	then
		return BOT_ACTION_DESIRE_ABSOLUTE
	end

	if DotaTime() > 0 and DotaTime() - ShouldMoveOutsideFountainCheckTime < 2 then
		return Clamp(bot:GetActiveModeDesire() + 0.2, 0, 1.1)
	else
		ShouldMoveOutsideFountain = false
	end

	if ConsiderHeroMoveOutsideFountain() then
		ShouldMoveOutsideFountain = true
		ShouldMoveOutsideFountainCheckTime = DotaTime()
		return Clamp(bot:GetActiveModeDesire() + 0.2, 0, 1.1)
	end

	-- unit special abilities
	local specialRoaming = ConsiderHeroSpecificRoaming[botName]
	if specialRoaming then
		-- return specialRoaming
		local specialDesire = specialRoaming()
		if specialDesire and specialDesire > 0 then return Clamp(specialDesire, 0, 0.99) end
	end

	-- general items or conditions.
	local generalRoaming = ConsiderGeneralRoamingInConditions()
	if generalRoaming then
		if generalRoaming > 0 and generalRoaming <= 1 then
			return Clamp(generalRoaming, 0, 0.99)
		else
			return generalRoaming
		end
	end

	if J.IsValidHero(botTarget)
	and ((J.GetModifierTime(bot, 'modifier_dazzle_shallow_grave') > 0.5 and J.GetHP(botTarget) < 0.15 and botName ~= "npc_dota_hero_axe")
	or J.GetModifierTime(bot, 'modifier_oracle_false_promise_timer') > 0.5)
	then
		local nAttackTarget = J.GetAttackableWeakestUnit( bot, bot:GetAttackRange() + 400, true, true )
		bot:SetTarget( nAttackTarget )
	end

	return BOT_MODE_DESIRE_NONE
end

function Think()
    if J.CanNotUseAction(bot) then return end

	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)

	ThinkIndividualRoaming() -- unit special abilities
	ThinkGeneralRoaming() -- general items or conditions.
	ThinkActualRoamingInLanes()
end

function ThinkIndividualRoaming()
	-- Heal in Base
	-- Just for TP. Too much back and forth when "forcing" them try to walk to fountain; <- not reliable and misses farm.
	if ShouldWaitInBaseToHeal
	then
		if GetUnitToLocationDistance(bot, J.GetTeamFountain()) > 150
		then
			nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1600)
			if J.Item.GetItemCharges(bot, 'item_tpscroll') >= 1
			and nInRangeEnemy ~= nil and #nInRangeEnemy == 0
			then
				if bot:GetUnitName() == 'npc_dota_hero_furion'
				then
					local Teleportation = bot:GetAbilityByName('furion_teleportation')
					if Teleportation:IsTrained()
					and Teleportation:IsFullyCastable()
					then
						bot:Action_UseAbilityOnLocation(Teleportation, J.GetTeamFountain())
						return
					end
				end

				if TPScroll ~= nil
				and not TPScroll:IsNull()
				and TPScroll:IsFullyCastable()
				then
					bot:Action_UseAbilityOnLocation(TPScroll, J.GetTeamFountain())
					return
				end
			end
		else
			if J.GetHP(bot) < 0.85 or J.GetMP(bot) < 0.85
			then
				if J.Item.GetItemCharges(bot, 'item_tpscroll') <= 1
				and bot:GetGold() >= GetItemCost('item_tpscroll')
				then
					bot:ActionImmediate_PurchaseItem('item_tpscroll')
					return
				end

				bot:Action_MoveToLocation(bot:GetLocation() + 150)
				return
			else
				ShouldWaitInBaseToHeal = false
			end
		end
	end

	-- Tinker
	if TinkerShouldWaitInBaseToHeal
	then
		if J.GetHP(bot) < 0.8 or J.GetMP(bot) < 0.8
		then
			bot:Action_ClearActions(true)
			return
		end
	end

	-- Spirit Breaker
	if bot:HasModifier('modifier_spirit_breaker_charge_of_darkness')
	then
		bot:Action_ClearActions(false)
		if bot.chargeRetreat
		and nInRangeEnemy ~= nil and #nInRangeEnemy == 0
		then
			bot:Action_MoveToLocation(bot:GetLocation() + RandomVector(150))
			bot.chargeRetreat = false
		end

		return
	end

	-- Batrider
	if bot:HasModifier('modifier_batrider_flaming_lasso_self')
	then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	-- Nyx Assassin
	if bot.canVendettaKill
	then
		if bot.vendettaTarget ~= nil
		then
			if GetUnitToUnitDistance(bot, bot.vendettaTarget) > bot:GetAttackRange() + 200
			then
				bot:Action_MoveToLocation(bot.vendettaTarget:GetLocation())
				return
			else
				bot:Action_AttackUnit(bot.vendettaTarget, true)
				return
			end
		end
	end

	-- Rolling Thunder
	if bot:HasModifier('modifier_pangolier_gyroshell')
	then
		if J.IsInTeamFight(bot, 1600)
		then
			local target = nil
			local hp = 0
			for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
			do
				if J.IsValidHero(enemyHero)
				and J.IsInRange(bot, enemyHero, 2200)
				and J.CanBeAttacked(enemyHero)
				and J.CanCastOnNonMagicImmune(enemyHero)
				and not enemyHero:HasModifier('modifier_faceless_void_chronosphere_freeze')
				and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
				and hp < enemyHero:GetHealth()
				then
					hp = enemyHero:GetHealth()
					target = enemyHero
				end
			end

			if target ~= nil
			then
				bot:Action_MoveToLocation(J.GetCorrectLoc(target, 0.2))
				return
			end
		end

		if J.IsRetreating(bot)
		then
			bot:Action_MoveToLocation(J.GetTeamFountain())
			return
		end

		local tEnemyHeroes = bot:GetNearbyHeroes(880, true, BOT_MODE_NONE)
		if J.IsValidHero(tEnemyHeroes[1])
		and not tEnemyHeroes[1]:HasModifier('modifier_faceless_void_chronosphere_freeze')
		then
			bot:Action_MoveToLocation(J.GetCorrectLoc(tEnemyHeroes[1], 0.2))
			return
		end

		local tCreeps = bot:GetNearbyCreeps(880, true)
		if J.IsValid(tCreeps[1])
		then
			bot:Action_MoveToLocation(J.GetCorrectLoc(tCreeps[1], 0.2))
			return
		end
	end

	-- Primal Beast
	if bot:HasModifier('modifier_primal_beast_trample') then
		local tAllyHeroes = J.GetAlliesNearLoc(bot:GetLocation(), 1200)
		local tEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)

		if #tEnemyHeroes > #tAllyHeroes + 1
		or (not J.WeAreStronger(bot, 800) and J.GetHP(bot) < 0.55)
		or (#tEnemyHeroes > 0 and J.GetHP(bot) < 0.3) then
			TrampleToBase()
			return
		end

		-- bot.trample_status {1 - type, 2 - location, 3 - target, if any}
		if bot.trample_status ~= nil and type(bot.trample_status) == "table" then
			if bot.trample_status[1] == 'engaging' then
				if J.IsValidHero(bot.trample_status[3]) then
					DoTrample(J.GetCorrectLoc( bot.trample_status[3], 0.2 ))
					return
				elseif #tEnemyHeroes > 0 then
					local target = nil
					local hp = 0
					for _, enemyHero in pairs(tEnemyHeroes) do
						if J.IsValidHero(enemyHero)
						and J.IsInRange(bot, enemyHero, 2200)
						and J.CanBeAttacked(enemyHero)
						and J.CanCastOnNonMagicImmune(enemyHero)
						and not enemyHero:HasModifier('modifier_faceless_void_chronosphere_freeze')
						and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
						and hp < enemyHero:GetHealth()
						then
							hp = enemyHero:GetHealth()
							target = enemyHero
						end
					end

					if target ~= nil then
						DoTrample(J.GetCorrectLoc( target, 0.2 ))
						return
					end
				else
					if #tAllyHeroes >= #tEnemyHeroes and J.WeAreStronger(bot, 800) then
						for _, ally in pairs(tAllyHeroes) do
							if J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally) then
								local allyTarget = ally:GetAttackTarget()
								if J.IsValidHero(allyTarget) then
									DoTrample(J.GetCorrectLoc( allyTarget, 0.2 ))
									return
								end
							end
						end
					end
				end
				-- TrampleToBase()
				return
			elseif bot.trample_status[1] == 'retreating' then
				TrampleToBase()
				return
			elseif bot.trample_status[1] == 'farming' or bot.trample_status[1] == 'laning' then
				local tCreeps = bot:GetNearbyCreeps(1200, true)
				if J.IsValid(tCreeps[1]) and J.CanBeAttacked(tCreeps[1])
				then
					local nLocationAoE = bot:FindAoELocation(true, false, tCreeps[1]:GetLocation(), 0, 300, 0, 0)
					if nLocationAoE.count > 0 then
						DoTrample(nLocationAoE.targetloc)
						return
					end
				else
					TrampleToBase()
					return
				end
			elseif bot.trample_status[1] == 'miniboss' then
				if J.IsValid(bot.trample_status[3]) then
					DoTrample(bot.trample_status[2])
					return
				else
					TrampleToBase()
					return
				end
			end
		end
		TrampleToBase()
		return
	end

	-- Phoenix
	if bot:HasModifier('modifier_phoenix_sun_ray') and not bot:HasModifier('modifier_phoenix_supernova_hiding')
	then
		if J.IsValidHero(bot.targetSunRay)
		then
			bot:Action_MoveToLocation(bot.targetSunRay:GetLocation())
			return
		end
	end

	if bot:HasModifier('modifier_hoodwink_sharpshooter_windup') then
		local Sharpshooter = bot:GetAbilityByName('hoodwink_sharpshooter')
		local nCastRange = Sharpshooter:GetCastRange()

		if J.IsValidHero(bot.sharpshooter_target) then
			bot:Action_MoveToLocation(bot.sharpshooter_target:GetLocation())
			return
		else
			local target = nil
			local targetHealth = math.huge
			for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
				if J.IsValidHero(enemy)
				and J.IsInRange(bot, enemy, nCastRange * 0.8)
				and J.CanCastOnNonMagicImmune(enemy)
				and not enemy:HasModifier('modifier_abaddon_borrowed_time')
				and not enemy:HasModifier('modifier_dazzle_shallow_grave')
				and not enemy:HasModifier('modifier_necrolyte_reapers_scythe')
				and not enemy:HasModifier('modifier_item_aeon_disk_buff')
				and not enemy:HasModifier('modifier_item_blade_mail_reflect')
				then
					local enemyHealth = enemy:GetHealth()
					if enemyHealth < targetHealth then
						targetHealth = enemyHealth
						target = enemy
					end
				end
			end

			if target ~= nil then
				bot:Action_MoveToLocation(target:GetLocation())
				return
			end

			--
			for i = 1, #GetTeamPlayers( GetTeam() ) do
				local member = GetTeamMember(i)
				if J.IsValidHero(member)
				and J.IsInRange(bot, member, 1600)
				then
					local memberTarget = member:GetAttackTarget()
					if J.IsValidHero(memberTarget)
					and J.IsInRange(bot, memberTarget, nCastRange)
					and J.CanCastOnNonMagicImmune(memberTarget)
					and not memberTarget:HasModifier('modifier_abaddon_borrowed_time')
					and not memberTarget:HasModifier('modifier_dazzle_shallow_grave')
					and not memberTarget:HasModifier('modifier_necrolyte_reapers_scythe')
					and not memberTarget:HasModifier('modifier_item_aeon_disk_buff')
					and not memberTarget:HasModifier('modifier_item_blade_mail_reflect')
					then
						bot:Action_MoveToLocation(memberTarget:GetLocation())
						return
					end
				end
			end
		end
	end

	-- Snapfire
	if bot:HasModifier('modifier_snapfire_mortimer_kisses')
	then
		local nKissesTarget = GetMortimerKissesTarget()

		if nKissesTarget ~= nil
		then
			local eta = (GetUnitToUnitDistance(bot, nKissesTarget) / 1300) + 0.3
			bot:Action_MoveToLocation(J.GetCorrectLoc(nKissesTarget, eta))
			return
		end
	end

	-- Leshrac
	if ShouldMoveCloseTowerForEdict
	then
		if EdictTowerTarget ~= nil
		then
			if GetUnitToUnitDistance(bot, EdictTowerTarget) > 350
			then
				bot:Action_MoveToLocation(EdictTowerTarget:GetLocation())
				return
			end
		end
	end

	-- Void Spirit
	if bot:HasModifier('modifier_void_spirit_dissimilate_phase')
	then
		local botTarget = J.GetProperTarget(bot)

		if J.IsGoingOnSomeone(bot)
		then
			if J.IsValidTarget(botTarget)
			then
				bot:Action_MoveToLocation(botTarget:GetLocation())
			end
		end

		if J.IsRetreating(bot)
		then
			bot:Action_MoveToLocation(J.GetEscapeLoc())
		end

		return
	end

	-- Marci
	if bot:HasModifier("modifier_marci_unleash") then
		local botTarget = J.GetProperTarget(bot)
		if botTarget and GetUnitToUnitDistance(bot, botTarget) > bot:GetAttackRange() + 200
		then
			bot:Action_MoveToLocation(botTarget:GetLocation())
			return
		else
			bot:Action_AttackUnit(botTarget, false)
			return
		end
	end

	if bot:HasModifier("modifier_muerta_pierce_the_veil_buff")
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget and GetUnitToUnitDistance(bot, botTarget) > bot:GetAttackRange() + 200
		then
			bot:Action_MoveToLocation(botTarget:GetLocation())
			return
		else
			bot:Action_AttackUnit(botTarget, false)
			return
		end
	end

	if bot:HasModifier('modifier_razor_static_link_buff') then
		local botTarget = J.GetProperTarget(bot)
		if botTarget then
			local distanceFromHero = GetUnitToUnitDistance(bot, botTarget)
			if distanceFromHero > bot:GetAttackRange()
			then
				bot:Action_MoveToLocation(botTarget:GetLocation() + RandomVector(200))
				return
			elseif distanceFromHero <= bot:GetAttackRange() / 2 then
				bot:Action_AttackUnit(botTarget, false)
				return
			end
		end
	end

	if bot:HasModifier("modifier_faceless_void_chronosphere")
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget and GetUnitToUnitDistance(bot, botTarget) > bot:GetAttackRange() + 200
		then
			bot:Action_MoveToLocation(botTarget:GetLocation())
			return
		else
			bot:Action_AttackUnit(botTarget, false)
			return
		end
	end

	-- Leshrac
	if bot:HasModifier("modifier_leshrac_pulse_nova")
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget and GetUnitToUnitDistance(bot, botTarget) > 400
		then
			bot:Action_MoveToLocation(botTarget:GetLocation())
			return
		else
			bot:ActionQueue_AttackUnit(botTarget, false)
			return
		end
	end

	if bot:HasModifier("modifier_wisp_tether")
	and J.IsValid(bot.stateTetheredHero) then
		if GetUnitToUnitDistance(bot, bot.stateTetheredHero) > TetherBreakDistance - 400 then
			bot:Action_MoveToLocation(bot.stateTetheredHero:GetLocation())
			return
		else
			local botTarget = J.GetProperTarget(bot)
			if botTarget then
				bot:ActionQueue_AttackUnit(botTarget, false)
			end
			return
		end
	end

	if botName == 'npc_dota_hero_lone_druid_bear' then
		local hero = J.Utils.GetLoneDruid(bot).hero
		local hasUltimateScepter = J.Item.HasItem(bot, 'item_ultimate_scepter') or bot:HasModifier('modifier_item_ultimate_scepter_consumed')
		local distanceFromHero = GetUnitToUnitDistance(J.Utils.GetLoneDruid(bot).hero, bot)
		local target = J.GetProperTarget(bot) or J.GetProperTarget(hero)

		if J.IsValidHero(hero)
		and not hasUltimateScepter
		then
			-- has enemy near by.
			if #nInRangeEnemy >= 1 then
				-- distance to bear beyond attack limit
				if distanceFromHero > BearAttackLimitDistance then
					bot:Action_ClearActions(false)
					bot:Action_MoveToLocation(hero:GetLocation())
					return
				end
				-- distance of target to hero beyond attack limit
				if J.IsValidTarget(target) then
					local heroDistanceFromTarget = GetUnitToUnitDistance(hero, target)
					if heroDistanceFromTarget > BearAttackLimitDistance then
						bot:Action_ClearActions(false)
						bot:Action_AttackMove(hero:GetLocation())
						return
					end
				end
			else
				if distanceFromHero > 500 then
					bot:Action_ClearActions(false)
					bot:Action_AttackMove(hero:GetLocation())
					return
				end
			end
			if J.IsValidTarget(target) then
				bot:Action_AttackUnit(target, false)
				return
			end
		end
		return
	end

	if botName == 'npc_dota_hero_pudge' then
		local Rot = bot:GetAbilityByName('pudge_rot')
		if Rot:GetToggleState()
		then
			local botTarget = J.GetProperTarget(bot)
			if botTarget and GetUnitToUnitDistance(bot, botTarget) > 400
			then
				bot:Action_MoveToLocation(botTarget:GetLocation())
				return
			end
		end
		bot:ActionQueue_AttackUnit(botTarget, false)
	end

	if botName == 'npc_dota_hero_nevermore' then
		if J.Utils.IsTruelyInvisible(bot) then
			local botTarget = J.GetProperTarget(bot)
			if botTarget and GetUnitToUnitDistance(bot, botTarget) > 400
			then
				bot:Action_MoveToLocation(botTarget:GetLocation())
				return
			end
		end
	end
end

local trample_step = 12
local trample = {}
function DoTrample(vLoc)
	trample = J.Utils.GetCirclarPointsAroundCenterPoint(vLoc, 300, 12)
	if trample_step < 12 then
		bot:Action_MoveToLocation(trample[trample_step])
		trample_step = trample_step + 1
	else
		trample_step = 1
	end
end
function TrampleToBase()
	trample_step = 12
	trample = {}
	bot:Action_MoveToLocation(J.GetTeamFountain())
end

function ThinkGeneralRoaming()
	-- Get out of fountain if in item mode
	if ShouldMoveOutsideFountain
	then
		bot:Action_AttackMove(J.Utils.GetOffsetLocationTowardsTargetLocation(J.GetTeamFountain(), J.GetEnemyFountain(), MoveOutsideFountainDistance))
		return
	end

	if bot:HasModifier("modifier_item_mask_of_madness_berserk") then
		local botTarget = J.GetProperTarget(bot)
		if J.IsValid(botTarget) then
			if GetUnitToUnitDistance(bot, botTarget) > bot:GetAttackRange() + 200
			then
				bot:Action_MoveToLocation(botTarget:GetLocation())
				return
			else
				bot:Action_AttackUnit(botTarget, false)
				return
			end
		end
	end

	if bot:HasModifier("modifier_skeleton_king_reincarnation_scepter_active") then
		local botTarget = J.GetProperTarget(bot)
		if J.IsValid(botTarget) then
			if GetUnitToUnitDistance(bot, botTarget) > bot:GetAttackRange() + 200
			then
				bot:Action_MoveToLocation(botTarget:GetLocation())
				return
			else
				bot:Action_AttackUnit(botTarget, false)
				return
			end
		end
	end

	if bot:HasModifier("modifier_nevermore_shadowraze_debuff") then
		MoveAwayFromTarget(GetTargetEnemy("npc_dota_hero_nevermore"), 1350)
		return
	end

	if bot:HasModifier("modifier_razor_static_link_debuff") then
		MoveAwayFromTarget(GetTargetEnemy("npc_dota_hero_razor"), 1200)
		return
	end

	if bot:HasModifier("modifier_ursa_fury_swipes_damage_increase") then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if bot:HasModifier("modifier_monkey_king_quadruple_tap_counter") then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if bot:HasModifier("modifier_slark_essence_shift_debuff_counter") then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if bot:HasModifier("modifier_silencer_glaives_of_wisdom_debuff_counter") then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if bot:HasModifier("modifier_dazzle_poison_touch") then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if bot:HasModifier("modifier_maledict") then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if bot:HasModifier("modifier_viper_poison_attack_slow") then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if J.GetModifierCount(bot, "modifier_huskar_burning_spear_debuff") >= 2 then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if trySeduce then
		allyTowers = bot:GetNearbyTowers(1600, false)
		if allyTowers[1] then
			local distanceFromFountain = GetUnitToLocationDistance(bot, J.GetTeamFountain())
			local towerFromFountain = GetUnitToLocationDistance(allyTowers[1], J.GetTeamFountain())
			local distanceToTower = GetUnitToUnitDistance(bot, allyTowers[1])
			if distanceFromFountain > towerFromFountain and distanceToTower > 300 then
				bot:Action_MoveToLocation(allyTowers[1]:GetLocation() + RandomVector(150))
			else
				bot:Action_MoveToLocation(J.GetTeamFountain())
			end
			return
		end
	end

	if shouldTempRetreat then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end

	if shouldGoBackToFountain then
		bot:Action_MoveToLocation(J.GetTeamFountain())
		return
	end
end

function GeneralReactToStackedDebuff(enemyHeroName)
	local enemy = GetTargetEnemy(enemyHeroName)
	if enemy ~= nil then -- nil check is enough here
		if J.GetHP(bot) > 0.6 and not J.Utils.NumActionTypeInQueue(BOT_ACTION_TYPE_ATTACK) <= 2 then
			bot:ActionImmediate_Ping(enemy:GetLocation().x, enemy:GetLocation().y, true)
			bot:ActionQueue_AttackUnit(enemy, false)
		else
			bot:Action_MoveToLocation(J.GetTeamFountain())
		end
	end
end

function MoveAwayFromTarget(target, keepDistance)
	if J.IsValidHero(target) and GetUnitToUnitDistance(bot, target) < keepDistance then
		if GetUnitToLocationDistance(target, J.GetTeamFountain()) > GetUnitToLocationDistance(bot, J.GetTeamFountain()) then
			bot:Action_MoveToLocation(J.GetTeamFountain())
		else
			bot:Action_MoveToLocation(J.Utils.GetOffsetLocationTowardsTargetLocation(target:GetLocation(), bot:GetLocation(), keepDistance * 2))
		end
	end
end

function ActualGankDesire()
	SetupTwinGates()

	if J.IsInLaningPhase()
	and bot:WasRecentlyDamagedByAnyHero(2)
	and (botTarget == nil or #nInRangeEnemy <= 0 or nInRangeEnemy[1] ~= botTarget) then
		local botLvl = bot:GetLevel()
		if (J.GetPosition(bot) == 2 and botLvl >= 6 and J.GetHP(bot) > 0.7 and J.GetMP(bot) > 0.6) -- mid player roaming
		or (J.GetPosition(bot) > 3 and botLvl >= 3 and J.GetHP(bot) > 0.6 and J.GetMP(bot) > 0.6) -- supports roaming
		then
			return CheckLaneToGank()
		end
	end
	return BOT_MODE_DESIRE_NONE
end

function SetupTwinGates()
	if #TwinGates == 0 then
		for _, unit in pairs(GetUnitList(UNIT_LIST_ALL))
		do
			if unit:GetUnitName() == 'npc_dota_unit_twin_gate'
			then
				table.insert(TwinGates, unit)
			end
			if #TwinGates >= 2 then
				break
			end
		end
	end
end

function ThinkActualRoamingInLanes()
	if laneToGank ~= nil then
		local targetLoc = GetLaneFrontLocation(GetTeam(), laneToGank, -300)
		local distanceToRoamLoc = GetUnitToLocationDistance(bot, targetLoc)
		if distanceToRoamLoc > 5000 then
			if J.GetPosition(bot) > 3
			and targetGate ~= nil
			and enableGateUsage
			then
				local distanceToGate = GetUnitToUnitDistance(bot, targetGate)
				if distanceToGate > 350 then
					bot:Action_MoveToLocation(targetGate:GetLocation())
					return
				elseif gateWarp:IsFullyCastable()
				then
					print('Trying to use gate '..botName)
					bot:Action_UseAbilityOnEntity(gateWarp, targetGate)
					return
				end
			end
		end

		if distanceToRoamLoc > bot:GetAttackRange() + 300 and bot:WasRecentlyDamagedByAnyHero(1.5) then
			bot:Action_MoveToLocation(targetLoc)
		end
		if distanceToRoamLoc < 600 and DotaTime() - arriveRoamLocTime > roamTimeAfterArrival * 1.1 then
			arriveRoamLocTime = DotaTime()
		end
		if DotaTime() - arriveRoamLocTime > roamTimeAfterArrival then
			laneToGank = nil
		end
	end
end

function OnStart()
end

function OnEnd()
	laneToGank = nil
	targetGate = nil
	if shouldGoBackToFountain and IsInHealthyState() then
		shouldGoBackToFountain = false
	end
end

function IsInHealthyState()
	return botName ~= 'npc_dota_hero_huskar' and J.GetHP(bot) > 0.7 and J.GetMP(bot) > 0.6
end

function CheckLaneToGank()

	if DotaTime() - lastGankDecisionTime <= gankDecisionHoldTime and laneToGank ~= nil then
		return BOT_ACTION_DESIRE_VERYHIGH
	end

	if DotaTime() - lastGankDecisionTime < gankGapTime then
		return BOT_MODE_DESIRE_NONE
	end

	if not HasSufficientMana(300) then -- idelaly should have mana at least able to use 2 abilities + tp.
		return BOT_MODE_DESIRE_NONE
	end
	for _, lane in pairs(laneAndT1s)
	do
		local enemyCountInLane = J.GetEnemyCountInLane(lane[1])
		if enemyCountInLane > 0
		then
			local tTower = GetTower(GetTeam(), lane[2])
			if tTower ~= nil then
				local laneFront = GetLaneFrontLocation(GetTeam(), lane[1], 0)
				local laneFrontToT1Dist = GetUnitToLocationDistance(tTower, laneFront)
				local nInRangeAlly = J.GetAlliesNearLoc(laneFront, 1200)

				if enableGateUsage
				and laneFrontToT1Dist < 2000
				then
					targetGate = GetGateNearLane(laneFront)
					if enemyCountInLane >= #nInRangeAlly
					then
						laneToGank = lane[1]
						return RemapValClamped(GetUnitToUnitDistance(bot, targetGate), 5000, 600, BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_ABSOLUTE * 0.96 )
					end
				end

				if #enemyCountInLane >= 1 and GetUnitToUnitDistance(bot, tTower) > 3000 then
					return RemapValClamped(laneFrontToT1Dist, 5000, 600, BOT_ACTION_DESIRE_HIGH, BOT_ACTION_DESIRE_ABSOLUTE * 0.96 )
				end
			end

		end
	end

	return BOT_MODE_DESIRE_NONE
end

function HasSufficientMana(nMana)
	return bot:GetMana() > nMana and not botName == 'npc_dota_hero_huskar'
end

function GetGateNearLane(laneLoc)
	local minDis = 99999
	local tGate
	for _, gate in pairs(TwinGates)
	do
		local distanceToGate = GetUnitToLocationDistance(gate, laneLoc)
		if distanceToGate < minDis then
			tGate = gate
			minDis = distanceToGate
		end
	end
	return tGate
end


function TinkerWaitInBaseAndHeal()
	if bot:GetUnitName() == 'npc_dota_hero_tinker'
	and bot.healInBase
	and GetUnitToLocationDistance(bot, J.GetTeamFountain()) < 500
	then
		return true
	end

	return false
end

function GetMortimerKissesTarget()
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and J.IsInRange(bot, enemyHero, 3000 + (275 / 2))
		and J.CanCastOnNonMagicImmune(enemyHero)
		and not J.IsInRange(bot, enemyHero, 600)
		then
			if J.IsLocationInChrono(enemyHero:GetLocation())
			or J.IsLocationInBlackHole(enemyHero:GetLocation())
			then
				return enemyHero
			end
		end

		if J.IsValidHero(enemyHero)
		and J.IsInRange(bot, enemyHero, 3000 + (275 / 2))
		and J.CanCastOnNonMagicImmune(enemyHero)
		and not J.IsInRange(bot, enemyHero, 600)
		and not enemyHero:HasModifier('modifier_abaddon_borrowed_time')
		and not enemyHero:HasModifier('modifier_dazzle_shallow_grave')
		and not enemyHero:HasModifier('modifier_oracle_false_promise_timer')
		and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
		then
			return enemyHero
		end
	end

	local nCreeps = bot:GetNearbyCreeps(1600, true)
	if J.IsValid(nCreeps[1])
	then
		return nCreeps[1]
	end

	return nil
end


-- Just for TP. Too much back and forth when "forcing" them try to walk to fountain; <- not reliable and misses farm.
function ConsiderWaitInBaseToHeal()
	local ProphetTP = nil
	if bot:GetUnitName() == 'npc_dota_hero_furion'
	then
		ProphetTP = bot:GetAbilityByName('furion_teleportation')
	end

	if not J.IsInLaningPhase()
	and not (J.IsFarming(bot) and J.IsAttacking(bot))
	and nInRangeEnemy ~= nil and #nInRangeEnemy == 0
	and GetUnitToUnitDistance(bot, GetAncient(GetOpposingTeam())) > 2400
	and (  (TPScroll ~= nil and TPScroll:IsFullyCastable())
		or (ProphetTP ~= nil and ProphetTP:IsTrained() and ProphetTP:IsFullyCastable()))
	then
		if (J.GetHP(bot) < 0.25
			and bot:GetHealthRegen() < 15
			and bot:GetUnitName() ~= 'npc_dota_hero_huskar'
			and bot:GetUnitName() ~= 'npc_dota_hero_slark'
			and bot:GetUnitName() ~= 'npc_dota_hero_necrolyte'
			and not bot:HasModifier('modifier_tango_heal')
			and not bot:HasModifier('modifier_flask_healing')
			and not bot:HasModifier('modifier_alchemist_chemical_rage')
			and not bot:HasModifier('modifier_arc_warden_tempest_double')
			and not bot:HasModifier('modifier_juggernaut_healing_ward_heal')
			and not bot:HasModifier('modifier_oracle_purifying_flames')
			and not bot:HasModifier('modifier_warlock_fatal_bonds')
			and not bot:HasModifier('modifier_item_satanic_unholy')
			and not bot:HasModifier('modifier_item_spirit_vessel_heal')
			and not bot:HasModifier('modifier_item_urn_heal'))
		or (((J.IsCore(bot) and J.GetMP(bot) < 0.25 and (J.GetHP(bot) < 0.75 and bot:GetHealthRegen() < 10))
				or ((not J.IsCore(bot) and J.GetMP(bot) < 0.25 and bot:GetHealthRegen() < 10)))
			and bot:GetUnitName() ~= 'npc_dota_hero_necrolyte'
			and not (J.IsPushing(bot) and #J.GetAlliesNearLoc(bot:GetLocation(), 900) >= 3))
		then
			ShouldWaitInBaseToHeal = true
			return true
		end
	end

	return false
end

function ConsiderHeroMoveOutsideFountain()
	if DotaTime() < 0 then return false end
	if bot:DistanceFromFountain() > MoveOutsideFountainDistance then return false end

	if (bot:HasModifier('modifier_fountain_aura_buff') -- in fountain with high hp
		and J.GetHP(bot) > 0.95)
	and (bot:GetUnitName() == 'npc_dota_hero_huskar' -- is huskar (ignore mana)
		or (bot:GetActiveMode() == BOT_MODE_ITEM -- is stuck in item mode
			and J.GetMP(bot) > 0.95))
	then
		return true
	end

	return false
end

function ConsiderGeneralRoamingInConditions()
	if bot:HasModifier("modifier_item_mask_of_madness_berserk") then
		local botTarget = J.GetProperTarget(bot)
		if J.IsValid(botTarget) and J.GetHP(bot) > 0.3 then
			return BOT_ACTION_DESIRE_ABSOLUTE
		end
	end

	if bot:HasModifier("modifier_skeleton_king_reincarnation_scepter_active") then
		local botTarget = J.GetAttackableWeakestUnit( bot, 1500, true, true )
		if J.IsValidHero(botTarget) then
			bot:SetTarget( botTarget )
			return BOT_ACTION_DESIRE_ABSOLUTE * 2
		end
	end

	if bot:HasModifier("modifier_razor_static_link_debuff") then
		local staticLinkDebuffStack = J.GetModifierCount( bot, "modifier_razor_static_link_debuff" )
		if staticLinkDebuffStack > lastStaticLinkDebuffStack then
			local enemy = GetTargetEnemy("npc_dota_hero_razor")
			if enemy ~= nil and J.GetHP(bot) - 0.2 < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= 850 then
				return BOT_ACTION_DESIRE_ABSOLUTE
			end
		end
	end

	if J.IsInLaningPhase() then

		-- 状态不好 回泉水补给
		if not bot:WasRecentlyDamagedByAnyHero(1.5)
		and (
			(shouldGoBackToFountain and not IsInHealthyState())
			or ((J.GetHP(bot) < 0.22 or (J.GetHP(bot) < 0.3 and J.GetMP(bot) < 0.22))
				and (not J.HasItem(bot, "item_tango") or not bot:HasModifier("modifier_tango_heal"))
				and (not J.HasItem(bot, "item_flask") or not bot:HasModifier("modifier_flask_healing"))
				and (not J.HasItem(bot, "item_bottle") or not bot:HasModifier("modifier_bottle_regeneration")))
		) then
			shouldGoBackToFountain = true
			return BOT_ACTION_DESIRE_ABSOLUTE * 1.5
		end

		if J.GetModifierCount(bot, "modifier_nevermore_shadowraze_debuff") >= 2 then -- 7s
			local enemy = GetTargetEnemy("npc_dota_hero_nevermore")
			if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= 1200 then
				return BOT_ACTION_DESIRE_VERYHIGH * 1.2
			end
		end

		if J.GetModifierCount(bot, "modifier_monkey_king_quadruple_tap_counter") >= 2 then -- 7 - 10s
			local enemy = GetTargetEnemy("npc_dota_hero_monkey_king")
			if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
				return BOT_ACTION_DESIRE_VERYHIGH * 1.2
			end
		end

		if J.GetModifierCount(bot, "modifier_viper_poison_attack_slow") >= 2 then -- 4s
			local enemy = GetTargetEnemy("npc_dota_hero_viper")
			if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
				return BOT_ACTION_DESIRE_VERYHIGH * 1.2
			end
		end

		if J.GetModifierCount(bot, "modifier_huskar_burning_spear_debuff") >= 3 then -- 9s
			local enemy = GetTargetEnemy("npc_dota_hero_huskar")
			if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
				return BOT_ACTION_DESIRE_VERYHIGH * 1.2
			end
		end

		-- long duration debuff
		if not J.WeAreStronger(bot, 1200) then
			if J.GetModifierCount(bot, "modifier_slark_essence_shift_debuff_counter") >= 2 then -- 20 - 80s
				local enemy = GetTargetEnemy("npc_dota_hero_slark")
				if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
					return BOT_ACTION_DESIRE_VERYHIGH * 1.2
				end
			end

			if J.GetModifierCount(bot, "modifier_silencer_glaives_of_wisdom_debuff_counter") >= 2 then -- 20 - 35s
				local enemy = GetTargetEnemy("npc_dota_hero_silencer")
				if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
					return BOT_ACTION_DESIRE_VERYHIGH * 1.2
				end
			end

			if J.GetModifierCount(bot, "modifier_ursa_fury_swipes_damage_increase") >= 2 then -- 8 - 20s
				local enemy = GetTargetEnemy("npc_dota_hero_ursa")
				if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
					return BOT_ACTION_DESIRE_VERYHIGH * 1.2
				end
			end

			if bot:HasModifier("modifier_dazzle_poison_touch") then -- 5s - forever
				local enemy = GetTargetEnemy("npc_dota_hero_dazzle")
				if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
					return BOT_ACTION_DESIRE_VERYHIGH * 1.2
				end
			end

			if bot:HasModifier("modifier_maledict") then -- 5s - forever
				local enemy = GetTargetEnemy("npc_dota_hero_witch_doctor")
				if enemy ~= nil and J.GetHP(bot) < J.GetHP(enemy) and GetUnitToUnitDistance(bot, enemy) <= enemy:GetAttackRange() * 1.5 then
					return BOT_ACTION_DESIRE_VERYHIGH * 1.2
				end
			end
		end

		-- 尝试勾引
		if #nInRangeEnemy >= 1
		and #allyTowers >= 1
		and GetUnitToUnitDistance(allyTowers[1], bot) < 1600
		and #nInRangeAlly <= #nInRangeEnemy then
			for _, enemy in pairs(nInRangeEnemy) do
				if J.Utils.IsValidHero(enemy) then
					if enemy:IsFacingLocation(bot:GetLocation(), 15)
					and J.IsInRange(bot, enemy, enemy:GetAttackRange() * 1.5 + 350)
					and J.GetHP(enemy) > J.GetHP(bot) - 0.15
					and bot:WasRecentlyDamagedByAnyHero(3)
					and J.GetHP(bot) < 0.75 and J.GetHP(bot) > 0.2 -- don't block real retreat action
					then
						trySeduce = true
						return BOT_ACTION_DESIRE_VERYHIGH
					end
				end
			end
		end
	end

	if bot:WasRecentlyDamagedByTower(0.2) then
		local nInRangeAlly = bot:GetNearbyHeroes(1000, false, BOT_MODE_NONE)
		if #nInRangeAlly >= 2 and J.GetHP(nInRangeAlly[2]) > J.GetHP(bot) then
			bot:Action_AttackUnit(nInRangeAlly[2], true)
		else
			local allyCreeps = bot:GetNearbyCreeps(1000, false)
			if #allyCreeps >= 1 and J.IsValid(allyCreeps[1]) then
				bot:Action_AttackUnit(allyCreeps[1], true)
			end
		end
	end

	local actualGankingDesire = ActualGankDesire()
	if actualGankingDesire > 0 then
		lastGankDecisionTime = DotaTime()
		return actualGankingDesire
	end
	return BOT_ACTION_DESIRE_NONE
end

function GetTargetEnemy(unitName)
	for _, enemyHero in pairs(nInRangeEnemy)
	do
		if J.IsValidHero(enemyHero) and enemyHero:GetUnitName() == unitName then
			return enemyHero
		end
	end
	return nil
end

------------------------------
-- Hero Channel/Kill/CC abilities
------------------------------
-- ConsiderHeroSpecificRoaming['npc_dota_hero_rubick'] = function ()
-- 	if bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
-- 	then
-- 		return BOT_MODE_DESIRE_ABSOLUTE
-- 	end
-- 	return BOT_MODE_DESIRE_NONE
-- end

function CheckHighPriorityChannelAbility(abilityName)
	if cAbility == nil then cAbility = bot:GetAbilityByName(abilityName) end;
	if cAbility:IsTrained() and (cAbility:IsInAbilityPhase() or bot:IsChanneling()) then
		return BOT_MODE_DESIRE_ABSOLUTE;
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_pugna'] = function ()
	return CheckHighPriorityChannelAbility("pugna_life_drain")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_drow_ranger'] = function ()
	return CheckHighPriorityChannelAbility("drow_ranger_multishot")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_shadow_shaman'] = function ()
	return CheckHighPriorityChannelAbility("shadow_shaman_shackles")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_clinkz'] = function ()
	return CheckHighPriorityChannelAbility("clinkz_burning_barrage")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_tiny'] = function ()
	return CheckHighPriorityChannelAbility("tiny_tree_channel")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_hoodwink'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("hoodwink_sharpshooter") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_hoodwink_sharpshooter_windup') then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
end

ConsiderHeroSpecificRoaming['npc_dota_hero_void_spirit'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("void_spirit_dissimilate") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier("modifier_void_spirit_dissimilate_phase")
		then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_primal_beast'] = function ()
	cAbility = bot:GetAbilityByName("primal_beast_onslaught")
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_primal_beast_onslaught_windup') or bot:HasModifier('modifier_prevent_taunts') or bot:HasModifier('modifier_primal_beast_onslaught_movement_adjustable') then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end

	cAbility = bot:GetAbilityByName("primal_beast_trample")
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or (bot:HasModifier('modifier_primal_beast_trample') and J.GetHP(bot) > 0.3) then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end

	cAbility = bot:GetAbilityByName("primal_beast_pulverize")
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_primal_beast_pulverize_self') then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_batrider'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("batrider_flaming_lasso") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier("modifier_batrider_flaming_lasso_self")
		then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_enigma'] = function ()
	return CheckHighPriorityChannelAbility("enigma_black_hole")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_keeper_of_the_light'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("keeper_of_the_light_illuminate") end
	if cAbility:IsInAbilityPhase() or bot:IsChanneling() or bot:HasModifier('modifier_keeper_of_the_light_illuminate') then
		return BOT_MODE_DESIRE_ABSOLUTE
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_meepo'] = function ()
	return CheckHighPriorityChannelAbility("meepo_poof")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_monkey_king'] = function ()
	return CheckHighPriorityChannelAbility("monkey_king_primal_spring")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_nyx_assassin'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("nyx_assassin_vendetta") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_nyx_assassin_vendetta')
		then
			if bot.canVendettaKill
			then
				return BOT_MODE_DESIRE_ABSOLUTE
			end
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_pangolier'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("pangolier_gyroshell") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_pangolier_gyroshell')
		then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_phoenix'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("phoenix_supernova") end
	if cAbility:IsTrained()
	then
		if bot:HasModifier('modifier_phoenix_supernova_hiding') then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end

	if cAbility == nil then cAbility = bot:GetAbilityByName("phoenix_sun_ray") end
	if cAbility:IsTrained()
	then
		if bot:HasModifier('modifier_phoenix_sun_ray')
		and not bot:HasModifier('modifier_phoenix_supernova_hiding')
		then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_puck'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("puck_phase_shift") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_puck_phase_shift') then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_ringmaster'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("ringmaster_tame_the_beasts") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier("modifier_ringmaster_tame_the_beasts") then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_snapfire'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("snapfire_mortimer_kisses") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_snapfire_mortimer_kisses') then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_spirit_breaker'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("spirit_breaker_charge_of_darkness") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:HasModifier('modifier_spirit_breaker_charge_of_darkness') then
			return BOT_MODE_DESIRE_ABSOLUTE * 1.2
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_windrunner'] = function ()
	return CheckHighPriorityChannelAbility("windrunner_powershot")
end

ConsiderHeroSpecificRoaming['npc_dota_hero_tinker'] = function ()
	if cAbility == nil then cAbility = bot:GetAbilityByName("tinker_rearm") end
	if cAbility:IsTrained()
	then
		if cAbility:IsInAbilityPhase() or bot:IsChanneling() or bot:HasModifier('modifier_tinker_rearm') then
			return BOT_MODE_DESIRE_ABSOLUTE
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_leshrac'] = function ()
	if bot:HasModifier("modifier_leshrac_diabolic_edict")
	then
		local DiabolicEdict = bot:GetAbilityByName('leshrac_diabolic_edict')
		if DiabolicEdict:IsTrained()
		then
			local nRadius = DiabolicEdict:GetSpecialValueInt('radius')
			if J.IsPushing(bot)
			then
				local nEnemyTowers = bot:GetNearbyTowers(1600, true)
				local nEnemyLaneCreeps = bot:GetNearbyLaneCreeps(nRadius, true)
				if nEnemyTowers ~= nil and #nEnemyTowers >= 1
				and J.IsValidBuilding(nEnemyTowers[1])
				and J.CanBeAttacked(nEnemyTowers[1])
				and not J.IsInRange(bot, nEnemyTowers[1], nRadius - 75)
				and nEnemyLaneCreeps ~= nil and #nEnemyLaneCreeps <= 2
				then
					EdictTowerTarget = nEnemyTowers[1]
					return BOT_MODE_DESIRE_VERYHIGH
				end
			end
		end
	end

	if bot:HasModifier("modifier_leshrac_pulse_nova")
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget ~= nil and J.GetHP(bot) > J.GetHP(botTarget) then
			if GetUnitToUnitDistance(bot, botTarget) > 400
			then
				return BOT_MODE_DESIRE_VERYHIGH
			end
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_lone_druid_bear'] = function ()
	local hero = J.Utils.GetLoneDruid(bot).hero
	local hasUltimateScepter = J.Item.HasItem(bot, 'item_ultimate_scepter') or bot:HasModifier('modifier_item_ultimate_scepter_consumed')
    local distanceFromHero = GetUnitToUnitDistance(J.Utils.GetLoneDruid(bot).hero, bot)

    if J.IsValidHero(hero)
	and J.GetHP(bot) >= J.GetHP(hero) - 0.2 -- hp is higher or within 20% lower than hero.
	and J.GetHP(bot) > 0.3
    and not (bot:IsChanneling() or bot:IsUsingAbility())
	and not hasUltimateScepter
	then
        if distanceFromHero > BearAttackLimitDistance * 0.6 then
			return BOT_MODE_DESIRE_VERYHIGH
        end
    end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_marci'] = function ()
	if bot:HasModifier("modifier_marci_unleash")
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget ~= nil and J.GetHP(bot) > J.GetHP(botTarget) then
			if J.IsInTeamFight(bot, 1500) then
				return BOT_MODE_DESIRE_VERYHIGH
			end
			if J.IsGoingOnSomeone(bot) and #nInRangeEnemy >= 1 then
				return BOT_MODE_DESIRE_ABSOLUTE
			end
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_wisp'] = function ()
	if bot:HasModifier("modifier_wisp_tether") and DotaTime() > 60
	then
		if J.IsValid(bot.stateTetheredHero)
		and J.GetHP(bot) > 0.5
		and GetUnitToUnitDistance(bot, bot.stateTetheredHero) > TetherBreakDistance - 200 then
			return BOT_MODE_DESIRE_ABSOLUTE * 0.85
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_pudge'] = function ()
	local Rot = bot:GetAbilityByName('pudge_rot')
	if Rot ~= nil and Rot:GetToggleState() and J.WeAreStronger(bot, 1200)
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget ~= nil and J.GetHP(bot) > J.GetHP(botTarget) then
			return BOT_MODE_DESIRE_ABSOLUTE * 0.85
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_muerta'] = function ()
	if bot:HasModifier("modifier_muerta_pierce_the_veil_buff")
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget ~= nil and J.GetHP(bot) > 0.2 then
			if J.IsInTeamFight(bot, 1500) then
				return BOT_MODE_DESIRE_VERYHIGH
			end
			if J.IsGoingOnSomeone(bot) and #nInRangeEnemy >= 1 then
				return BOT_MODE_DESIRE_ABSOLUTE
			end
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_razor'] = function ()
	if bot:HasModifier("modifier_razor_static_link_buff")
	then
		local botTarget = J.GetProperTarget(bot)
		if J.IsValidHero(botTarget) and J.GetHP(bot) > 0.3 and J.GetHP(bot) >= J.GetHP(botTarget) then
			if enemyTowers == nil or #enemyTowers == 0 or GetUnitToUnitDistance(bot, enemyTowers[1]) > 850 then
				return BOT_MODE_DESIRE_VERYHIGH
			end
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_faceless_void'] = function ()
	if bot:HasModifier("modifier_faceless_void_chronosphere")
	then
		local botTarget = J.GetProperTarget(bot)
		if botTarget ~= nil and J.GetHP(bot) > 0.25
		and J.IsLocationInChrono(botTarget:GetLocation()) then
			return BOT_MODE_DESIRE_VERYHIGH
		end
	end
	return BOT_MODE_DESIRE_NONE
end

ConsiderHeroSpecificRoaming['npc_dota_hero_nevermore'] = function ()
	bot.invisUltCombo = false
	if J.Utils.IsTruelyInvisible(bot)
	and bot:GetAbilityByName("nevermore_requiem"):IsFullyCastable()
	then
		local botTarget = J.GetProperTarget(bot)
		if J.IsValidHero(botTarget) and J.GetHP(bot) > 0.5 and J.GetHP(botTarget) > 0.5 and botTarget:GetHealth() > 800 then
			if enemyTowers == nil or #enemyTowers == 0 or GetUnitToUnitDistance(bot, enemyTowers[1]) > 850 then
				bot.invisUltCombo = true
				return BOT_MODE_DESIRE_VERYHIGH
			end
		end
	end
	return BOT_MODE_DESIRE_NONE
end
