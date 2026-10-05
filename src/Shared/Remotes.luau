-- Ponto único de acesso aos RemoteEvents do jogo.
-- O servidor cria os remotes em ReplicatedStorage.RemoteEvents; o cliente espera por eles.
-- Uso: local Remotes = require(ReplicatedStorage.Remotes); Remotes.Notify:FireClient(...)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"GamepassAction", -- C->S: State, Refresh, Daily, VIPServer, PublicServer
	"GamepassState", -- S->C: verified ownership and daily claim status
	-- Dados do jogador / progressão
	"StatusUpgrade", -- C->S (statName) sistema antigo de pontos de status (não usado; a árvore substituiu)
	"StatusReset", -- C->S () reseta a árvore de habilidades: devolve os pontos gastos, custa Gold
	"SkillTreeUnlock", -- C->S (nodeId) desbloqueia um nó da árvore (SkillTreeData)
	"EquipItem", -- C->S (itemId, equip) veste ou tira um item do inventário (ItemData)
	"EquipStyle", -- C->S (styleName, equip) guarda ou equipa um estilo de combate pelo inventário (PlayerData)
	"SaveAppearance", -- C->S (appearance) salva a aparência do criador de personagem (AppearanceData)
	"ClanSpin", -- C->S () gira o clã (gasta 1 giro); a resposta vem no ClanResult
	"ClanResult", -- S->C (clanId, spinsLeft) resultado do giro, para a animação do menu
	"BuySpin", -- C->S () compra 1 giro de clã com Gold (ClanData.SpinGoldCost)
	"ClanChoose", -- C->S (clanId) escolhe o clã direto (contas sem sorteio pago, ClanData.ChooseGoldCost); resposta no ClanResult
	"GroupReward", -- C->S ("Claim") recompensa de quem entrou no grupo do jogo (GroupReward.server); resposta no Notify
	"RedeemCode", -- C->S (code) resgata um código (Server/Codes); a resposta vem no CodeResult
	"CodeResult", -- S->C (ok, message)
	"SaveSetting", -- C->S (key, value) configuração do jogador salva no perfil (ex.: "FastMode", true)
	"QuestEvent", -- C->S () pede estado atual | S->C (data)
	"QuestDialog", -- S->C (data) abre o diálogo de um NPC de missão
	"QuestAction", -- C->S (action, questId, npcId) ex.: "Accept"
	"TutorialAction", -- C->S (action, value) "Step" (índice) | "Finish" | "Skip" | "Restart" | "Dummy" (true/false)
	"FishingAction", -- C->S (action, sessionOrSpotId, value): server validates phase, distance and input
	"FishingState", -- S->C fishing UI, bag and authoritative minigame snapshots
	"FishingFX", -- S->C nearby rod, bobber and catch presentation
	"WorldActivityState", -- C->S snapshot request | S->C regional event state

	-- Notificações
	"Notify", -- S->C (title, text, duration?) toast pequeno
	"Announcement", -- S->C (title, text, duration?) banner no topo da tela

	-- Times
	"SelectTeam", -- C->S (teamName)

	-- Combate (estilos em CombatStyles; o servidor é o CombatService)
	"CombatM1", -- C->S (seq, aerial) começou um M1; aerial = true pede o uppercut no 4º golpe
	"CombatSkill", -- C->S (slot, holding, seq?) "Z" | "X" | "C"; skill de segurar manda true ao apertar e false (+ seq) ao soltar
	"CombatHit", -- C->S (seq, targets, impactTime, originCFrame): horário sincronizado e origem validados para rewind
	"DashRequest", -- C->S (character, seq, direction, timestamp, originCFrame): servidor autoriza e desconta stamina
	"DashState", -- S->C (snapshot): stamina/recarga e confirmação ou recusa por seq, sempre do mesmo personagem
	"CombatBlock", -- C->S (holding) segurar F
	"CombatFX", -- S->C (kind, data) efeitos visuais (CombatFX.client.luau)
	"CombatImpulse", -- S->C (velocity, duration) empurrão aplicado pelo próprio cliente no personagem dele
	"CombatDamage", -- S->C (victim, amount, result) dano que o jogador causou (número de dano e contador de acertos)

	-- Caminhos (Fase 4, ver docs/fase4-caminhos.md)
	"PathAction", -- C->S (action, id, npcId): "Open" | "ChooseHunter" | "ChooseFiend" | "Reset"
	"PathDialog", -- S->C (data) abre a tela de escolher/renunciar ao caminho
	"UsePower", -- C->S (slot) "Z" ou "X" (teclas V e B)
	"SetAllyProtection", -- C->S (enabled)
	"ContractAction", -- C->S (action, npcId): "Fuse" funde o contrato com o estilo (ContractService, Mestre dos Pactos)
}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("RemoteEvents")
end

local Remotes = {}
for _, name in NAMES do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
