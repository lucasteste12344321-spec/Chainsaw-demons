-- Entrega os estilos de combate sempre que o jogador renasce e já equipa o primeiro.
-- Cada estilo é um Tool sem Handle com o nome do estilo (CombatStyles); os golpes ficam no CombatService.
-- Quais estilos: os do atributo EquippedStyles (JSON) do player, que o PlayerData publica: os aprendidos menos os
-- guardados no inventário e, com a fusão do contrato (forma V2), só o estilo da fusão. Estilo que entra na lista chega
-- na hora (sem equipar); o que sai da lista some da mochila e da mão.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local HttpService = game:GetService("HttpService")

local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))

local OLD_TOOLS = { "Katana" } -- armas antigas que não existem mais (a Katana nova é um estilo, entregue daqui)

-- Cópias antigas no StarterPack dariam ferramentas duplicadas ou que não funcionam
for _, name in OLD_TOOLS do
	local old = StarterPack:FindFirstChild(name)
	if old then
		warn(`[GiveTools] Removendo StarterPack.{name}: essa arma saiu do StarterPack`)
		old:Destroy()
	end
end

local templates = {}
for name, style in CombatStyles.Styles do
	local old = StarterPack:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.RequiresHandle = false
	tool.CanBeDropped = false -- Backspace não joga fora
	tool.ToolTip = style.DisplayName
	templates[name] = tool
end

-- Estilos com ferramenta: o atributo EquippedStyles ou, antes de o perfil carregar, só os iniciais
local function ownedStyles(player)
	local raw = player:GetAttribute("EquippedStyles")
	if type(raw) == "string" then
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(list) == "table" then
			return list
		end
	end
	return CombatStyles.StartingStyles
end

-- Tira da mochila e da mão os estilos que saíram da lista (guardados no inventário ou travados pela fusão)
local function pruneTools(player)
	local keep = ownedStyles(player)
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and CombatStyles.Styles[child.Name] and not table.find(keep, child.Name) then
					child:Destroy()
				end
			end
		end
	end
end

local function hasTool(player, name)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	return (backpack and backpack:FindFirstChild(name)) or (character and character:FindFirstChild(name))
end

-- Coloca na mochila os estilos que faltam. Devolve o primeiro Tool novo.
local function fillBackpack(player, backpack)
	local first
	for _, name in ownedStyles(player) do
		local template = templates[name]
		if template and not hasTool(player, name) then
			local tool = template:Clone()
			tool.Parent = backpack
			first = first or tool
		end
	end
	return first
end

local function giveTools(player, character)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack or player.Character ~= character then return end

	pruneTools(player)
	local first = fillBackpack(player, backpack)

	-- Já nasce com os punhos na mão (1 guarda e equipa de novo)
	local humanoid = character:WaitForChild("Humanoid", 10)
	for _ = 1, 50 do
		if character.Parent or player.Character ~= character then break end
		task.wait(0.1)
	end
	if first and humanoid and humanoid.Health > 0 and first.Parent == backpack and player.Character == character
		and not character:FindFirstChildOfClass("Tool") then
		humanoid:EquipTool(first)
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		giveTools(player, character)
	end)
	-- Aprendeu, guardou ou equipou um estilo (ou fez a fusão do contrato): a mochila acompanha
	player:GetAttributeChangedSignal("EquippedStyles"):Connect(function()
		pruneTools(player)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and player.Character then
			fillBackpack(player, backpack)
		end
	end)
	if player.Character then
		task.spawn(giveTools, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
