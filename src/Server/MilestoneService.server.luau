-- Marcos (MilestoneData): conta inimigos e chefes derrotados (QuestModule.Listen), lê peixes, missões concluídas e
-- level direto do perfil, e paga cada nível resgatado (Remotes.MilestoneAction "Claim", em ordem). Salvo em
-- profile.Milestones (PlayerData). Atributo MilestoneClaimable no player: tem nível para resgatar (bolinha na HUD).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local MilestoneData = require(ReplicatedStorage:WaitForChild("MilestoneData"))
local BossData = require(ReplicatedStorage:WaitForChild("BossData"))
local PassConfig = require(ReplicatedStorage:WaitForChild("GamepassConfig"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))

local lastAction = {}
local pendingSend = {}

local function milestones(player)
	local profile = PlayerData.GetProfile(player)
	if not profile then return nil, nil end
	if type(profile.Milestones) ~= "table" then
		profile.Milestones = MilestoneData.Reconcile(nil)
	end
	return profile.Milestones, profile
end

-- Progresso atual de uma trilha
local function progressOf(player, profile, track)
	local data = profile.Milestones
	if track.Source == "Kills" or track.Source == "Bosses" then
		return data.Counts[track.Source] or 0
	elseif track.Source == "Fish" then
		return if type(profile.Fishing) == "table" and type(profile.Fishing.Catches) == "number" then profile.Fishing.Catches else 0
	elseif track.Source == "Quests" then
		local total = 0
		local completed = type(profile.Quests) == "table" and profile.Quests.Completed
		if type(completed) == "table" then
			for _, times in completed do
				if type(times) == "number" then total += times end
			end
		end
		return total
	elseif track.Source == "Level" then
		return PlayerData.GetLevel(player)
	end
	return 0
end

local function sendState(player)
	pendingSend[player] = nil
	local data, profile = milestones(player)
	if not data or not player.Parent then return end
	local tracks = {}
	local claimable = false
	for _, track in MilestoneData.Tracks do
		local progress = progressOf(player, profile, track)
		local claimed = data.Claimed[track.Id] or 0
		local nextTier = track.Tiers[claimed + 1]
		if nextTier and progress >= nextTier.Goal then claimable = true end
		table.insert(tracks, { Id = track.Id, Progress = progress, Claimed = claimed })
	end
	player:SetAttribute("MilestoneClaimable", claimable)
	Remotes.MilestoneState:FireClient(player, { Tracks = tracks })
end

-- Vários abates seguidos mandam um estado só
local function queueSend(player)
	if pendingSend[player] then return end
	pendingSend[player] = true
	task.delay(0.5, function()
		if pendingSend[player] then sendState(player) end
	end)
end

local function claim(player, trackId)
	local track = MilestoneData.Get(trackId)
	local data, profile = milestones(player)
	if not track or not data then return end
	local claimed = data.Claimed[track.Id] or 0
	local tier = track.Tiers[claimed + 1]
	if not tier or progressOf(player, profile, track) < tier.Goal then return end
	data.Claimed[track.Id] = claimed + 1
	PlayerData.AddGold(player, tier.Gold, true)
	if tier.Spins and tier.Spins > 0 then
		profile.Spins = math.clamp((profile.Spins or 0) + tier.Spins, 0, PassConfig.MaxSpins)
		player:SetAttribute("ClanSpins", profile.Spins)
	end
	PlayerData.Notify(player, `Milestone: {track.Name}`, `{MilestoneData.TierText(track, tier)}: +{MilestoneData.RewardText(tier)}`, 5)
end

QuestModule.Listen(function(player, kind, target)
	local data = milestones(player)
	if not data then return end
	if kind == "Kill" then
		data.Counts.Kills += 1
		if type(target) == "string" and BossData.Get(target) then
			data.Counts.Bosses += 1
		end
		queueSend(player)
	elseif kind == "Fish" or kind == "Quest" then
		queueSend(player)
	end
end)

Remotes.MilestoneAction.OnServerEvent:Connect(function(player, action, trackId)
	if type(action) ~= "string" then return end
	local clock = os.clock()
	if clock < (lastAction[player] or 0) then return end
	lastAction[player] = clock + 0.25
	if action == "Claim" and type(trackId) == "string" then
		claim(player, trackId)
	end
	sendState(player)
end)

PlayerData.ProfileLoaded:Connect(function(player)
	sendState(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local level = leaderstats and leaderstats:FindFirstChild("Level")
	if level then
		level.Changed:Connect(function()
			queueSend(player)
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
	pendingSend[player] = nil
end)
