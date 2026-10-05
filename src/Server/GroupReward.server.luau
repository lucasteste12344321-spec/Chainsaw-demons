-- Recompensa de quem entra no grupo do jogo (uma vez por conta). O cliente (HUB_GUI, botão 団) abre o convite do Roblox
-- (GroupService:PromptJoinAsync) e pede "Claim"; aqui o servidor confere se a pessoa está mesmo no grupo e entrega.
-- Like/favorito não dá recompensa: as regras do Roblox não deixam premiar quem curte o jogo (e nem dá para saber quem
-- curtiu). O que é permitido é recompensar todo mundo quando o jogo bate uma meta de likes (um código, por exemplo).
-- Marca de "já ganhou": "@GRUPO" em profile.Codes (salvo pelo PlayerData; o "@" não passa no campo de códigos).
-- Atributo no player: GroupRewarded (bool; a HUD esconde o botão depois de ganhar).
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- O grupo dono do jogo (o jogo é do grupo 126221487; se um dia mudar de dono, ele acompanha)
local GROUP_ID = if game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 126221487
local REWARD = { Gold = 300, Spins = 1 } -- o que quem entra no grupo ganha (uma vez)
local MARK = "@GRUPO"
local CLAIM_GAP = 3 -- segundos entre pedidos do mesmo jogador

ReplicatedStorage:SetAttribute("GroupId", GROUP_ID) -- o cliente usa no convite

local lastClaim = {}

-- Está no grupo agora? GetGroupsAsync consulta o site na hora (o IsInGroup guarda a resposta do começo da sessão e
-- não veria quem acabou de entrar pelo convite)
local function isMember(player)
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if ok and type(groups) == "table" then
		for _, group in groups do
			if group.Id == GROUP_ID then
				return true
			end
		end
		return false
	end
	local okMember, member = pcall(player.IsInGroup, player, GROUP_ID)
	return okMember and member == true
end

local function onClaim(player, action)
	if action ~= "Claim" then return end
	local clock = os.clock()
	if clock - (lastClaim[player] or 0) < CLAIM_GAP then return end
	lastClaim[player] = clock
	local profile = PlayerData.GetProfile(player)
	if not profile or type(profile.Codes) ~= "table" or profile.Codes[MARK] then return end
	if not isMember(player) then
		PlayerData.Notify(player, "Grupo", "Entre no grupo do jogo para ganhar a recompensa.", 5)
		return
	end
	profile.Codes[MARK] = true
	local parts = {}
	if REWARD.Gold > 0 then
		PlayerData.AddGold(player, REWARD.Gold, true)
		table.insert(parts, `+{REWARD.Gold} Gold`)
	end
	if REWARD.Spins > 0 and type(profile.Spins) == "number" then
		profile.Spins += REWARD.Spins
		player:SetAttribute("ClanSpins", profile.Spins)
		table.insert(parts, if REWARD.Spins == 1 then "+1 giro de clã" else `+{REWARD.Spins} giros de clã`)
	end
	player:SetAttribute("GroupRewarded", true)
	PlayerData.Notify(player, "Obrigado por entrar no grupo!", table.concat(parts, " e "), 6)
end
Remotes.GroupReward.OnServerEvent:Connect(onClaim)

local function onPlayer(player)
	local profile = PlayerData.WaitForProfile(player)
	if profile and type(profile.Codes) == "table" then
		player:SetAttribute("GroupRewarded", profile.Codes[MARK] == true)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
Players.PlayerRemoving:Connect(function(player)
	lastClaim[player] = nil
end)
