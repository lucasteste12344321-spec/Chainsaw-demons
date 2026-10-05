-- Missões diárias (DailyData). O progresso vem do QuestModule.Listen (inimigo, peixe, poder) e fica no perfil
-- (profile.Daily, salvo pelo PlayerData). O cliente (Device.client: tablet do Caçador / Kog do Infernal) pede o
-- estado e resgata por Remotes.DailyAction; o servidor confere tudo. Atributo DailyClaimable no player = tem algo
-- para resgatar (bolinha vermelha no botão da HUD).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local DailyData = require(ReplicatedStorage:WaitForChild("DailyData"))
local BossData = require(ReplicatedStorage:WaitForChild("BossData"))
local StatConfig = require(ReplicatedStorage:WaitForChild("StatConfig"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))

local lastAction = {}

local function hasPath(player)
	local path = player:GetAttribute("Path")
	return type(path) == "string" and path ~= "None" and path ~= ""
end

-- Missões de hoje (sorteia no primeiro acesso do dia; a sequência zera se pulou um dia sem completar)
local function today(player)
	local profile = PlayerData.GetProfile(player)
	if not profile then return nil end
	local daily = profile.Daily
	if type(daily) ~= "table" then
		daily = DailyData.Reconcile(nil)
		profile.Daily = daily
	end
	local day = DailyData.Day(os.time())
	if daily.Day ~= day then
		daily.Day = day
		daily.Missions = DailyData.Roll(player.UserId, day, PlayerData.GetLevel(player), hasPath(player))
		daily.BonusClaimed = false
		if daily.LastFullDay < day - 1 then
			daily.Streak = 0
		end
	end
	return daily
end

local function claimable(daily)
	if not daily then return false end
	local allDone = #daily.Missions > 0
	for _, mission in daily.Missions do
		if mission.Progress >= mission.Goal and not mission.Claimed then return true end
		if not mission.Claimed then allDone = false end
	end
	return allDone and not daily.BonusClaimed
end

local function sendState(player)
	local daily = today(player)
	if not daily or not player.Parent then return end
	local missions = {}
	for index, mission in daily.Missions do
		local entry = DailyData.Get(mission.Id)
		table.insert(missions, {
			Index = index,
			Text = DailyData.TextFor(entry, mission.Goal),
			Goal = mission.Goal,
			Progress = math.min(mission.Progress, mission.Goal),
			Claimed = mission.Claimed,
		})
	end
	local level = PlayerData.GetLevel(player)
	local reward = DailyData.Reward(level)
	player:SetAttribute("DailyClaimable", claimable(daily))
	Remotes.DailyState:FireClient(player, {
		Missions = missions,
		Gold = reward.Gold,
		XP = math.floor(StatConfig.XPNeeded(level) * reward.XPFraction),
		BonusClaimed = daily.BonusClaimed,
		BonusSpins = DailyData.Bonus.Spins,
		Streak = daily.Streak,
		StreakGold = math.min(daily.Streak, DailyData.Bonus.StreakMax - 1) * DailyData.Bonus.StreakGold,
		NextDayAt = DailyData.NextDayAt(os.time()),
	})
end

-- Progresso: soma 1 em cada missão do tipo que ainda não chegou na meta
local function progress(player, kind, target)
	local daily = today(player)
	if not daily then return end
	local changed = false
	for _, mission in daily.Missions do
		local entry = DailyData.Get(mission.Id)
		if not mission.Claimed and mission.Progress < mission.Goal then
			local counts = false
			if entry.Kind == "Boss" then
				counts = kind == "Kill" and BossData.Get(target) ~= nil
			elseif entry.Kind == kind then
				counts = entry.Target == nil or entry.Target == target
			end
			if counts then
				mission.Progress += 1
				changed = true
				if mission.Progress >= mission.Goal then
					PlayerData.Notify(player, "Missão diária completa!", DailyData.TextFor(entry, mission.Goal)
						.. ". Aperte T para resgatar.", 5)
				end
			end
		end
	end
	if changed then
		sendState(player)
	end
end

local function claim(player, index)
	local daily = today(player)
	local mission = daily and type(index) == "number" and daily.Missions[index]
	if not mission or mission.Claimed or mission.Progress < mission.Goal then return end
	mission.Claimed = true
	local level = PlayerData.GetLevel(player)
	local reward = DailyData.Reward(level)
	local streakBonus = 1 + math.min(daily.Streak, DailyData.Bonus.StreakMax - 1) * DailyData.Bonus.StreakGold
	local gold = PlayerData.AddGold(player, math.floor(reward.Gold * streakBonus)) or 0
	local xp = PlayerData.AddXP(player, math.floor(StatConfig.XPNeeded(level) * reward.XPFraction)) or 0
	PlayerData.Notify(player, "Missão diária", `+{gold} Gold e +{xp} XP.`, 4)
end

local function claimBonus(player)
	local daily = today(player)
	if not daily or daily.BonusClaimed or #daily.Missions == 0 then return end
	for _, mission in daily.Missions do
		if not mission.Claimed then return end
	end
	local profile = PlayerData.GetProfile(player)
	if not profile then return end
	daily.BonusClaimed = true
	daily.Streak = if daily.LastFullDay == daily.Day - 1 then daily.Streak + 1 else 1
	daily.LastFullDay = daily.Day
	profile.Spins = math.clamp((profile.Spins or 0) + DailyData.Bonus.Spins, 0, 9999)
	player:SetAttribute("ClanSpins", profile.Spins)
	PlayerData.Notify(player, "Todas as diárias!", `+{DailyData.Bonus.Spins} giro de clã. Sequência: {daily.Streak} dia(s).`, 6)
end

Remotes.DailyAction.OnServerEvent:Connect(function(player, action, index)
	if type(action) ~= "string" then return end
	local clock = os.clock()
	if clock < (lastAction[player] or 0) then return end
	lastAction[player] = clock + 0.25
	if action == "Claim" then
		claim(player, index)
	elseif action == "Bonus" then
		claimBonus(player)
	end
	sendState(player)
end)

QuestModule.Listen(progress)
PlayerData.ProfileLoaded:Connect(sendState)
Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
end)

-- Virada do dia com o jogador no jogo
task.spawn(function()
	local lastDay = DailyData.Day(os.time())
	while true do
		task.wait(30)
		local day = DailyData.Day(os.time())
		if day ~= lastDay then
			lastDay = day
			for _, player in Players:GetPlayers() do
				sendState(player)
			end
		end
	end
end)
