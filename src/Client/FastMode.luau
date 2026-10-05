-- Fast Mode: troca os gráficos pesados por versões leves SÓ neste cliente (ninguém mais vê diferença).
-- Tudo que muda é guardado e volta exatamente como era ao desligar.
--
-- O que ele faz:
--   Lighting: sem sombras globais, sem reflexo do ambiente (EnvironmentDiffuse/SpecularScale), pós-efeitos
--             desligados (Bloom, Blur, ColorCorrection, DepthOfField, SunRays), nuvens desligadas
--   Terreno:  água sem ondas e sem reflexo
--   Mapa:     materiais caros viram SmoothPlastic (Neon e ForceField ficam), sem Reflectance, sem CastShadow,
--             SurfaceAppearance (PBR) removida, Textures (repetidas) escondidas
--   Efeitos:  ParticleEmitter, Trail, Beam, Smoke, Fire e Sparkles desligados (mesmo se o servidor religar),
--             luzes sem sombra, explosões sem o visual
-- Personagens e NPCs (Models com Humanoid) não são mexidos, nem os efeitos de combate locais (workspace.CombatFX).
-- O que não dá para mudar por script: grama do terreno (Decoration), qualidade gráfica do Roblox, Technology.
--
-- Mapas grandes: liga e desliga em lotes (BATCH por frame), sem travar a tela.
-- A escolha é salva no perfil (Remotes.SaveSetting) e volta sozinha na próxima entrada (atributo SettingFastMode).
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local FastMode = {}

local BATCH = 1200 -- instâncias por frame

local enabled = false
local userChanged = false -- depois que o jogador mexe, o valor salvo não manda mais

local changedEvent = Instance.new("BindableEvent")
FastMode.Changed = changedEvent.Event -- (enabled)

-- saved[instância] = { [propriedade] = valor original }. Tabela normal (não fraca): o objeto Lua de uma Instance
-- pode ser recolhido mesmo com ela ainda no mapa, e aí o valor original se perderia antes de desligar.
-- As entradas saem no restore; as de instâncias destruídas saem no disable.
local saved = {}
-- SurfaceAppearance tirada do lugar: referência forte (sem Parent ela sumiria da memória) -> Parent original
local detached = {}
-- Efeitos vigiados enquanto ligado (o servidor pode religar): [instância] = { conexões }
local watchers = {}
local liveConnections = {}
local writing = false -- true enquanto o próprio Fast Mode escreve (os vigias ignoram)

local KEEP_MATERIALS = {
	[Enum.Material.Plastic] = true,
	[Enum.Material.SmoothPlastic] = true,
	[Enum.Material.Neon] = true, -- efeitos brilhantes
	[Enum.Material.ForceField] = true,
}

local EFFECT_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Smoke", "Fire", "Sparkles" }

-- ================= Guardar e aplicar =================

local function set(instance, property, value)
	local entry = saved[instance]
	if not entry then
		entry = {}
		saved[instance] = entry
	end
	local isNew = entry[property] == nil
	if isNew then
		entry[property] = instance[property]
	end
	writing = true
	local ok = pcall(function()
		instance[property] = value
	end)
	writing = false
	if not ok and isNew then
		entry[property] = nil
	end
end

-- Personagem ou NPC (qualquer Model com Humanoid acima): fica como está
local function inCharacter(instance)
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local localEffects -- workspace.CombatFX (efeitos do próprio cliente, já leves)
local function isLocalEffect(instance)
	localEffects = localEffects or workspace:FindFirstChild("CombatFX")
	return localEffects ~= nil and instance:IsDescendantOf(localEffects)
end

local function isEffect(instance)
	for _, className in EFFECT_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

-- O servidor religou um efeito com o Fast Mode ligado: guarda o novo valor original e desliga de novo
local function watch(instance, property)
	if watchers[instance] then return end
	watchers[instance] = {
		instance:GetPropertyChangedSignal(property):Connect(function()
			if writing or not enabled then return end
			local entry = saved[instance]
			if entry then
				entry[property] = instance[property]
			end
			if instance[property] then
				writing = true
				instance[property] = false
				writing = false
			end
		end),
		instance.Destroying:Connect(function()
			local list = watchers[instance]
			watchers[instance] = nil
			if list then
				for _, connection in list do
					connection:Disconnect()
				end
			end
		end),
	}
end

local function simplify(instance)
	if not instance.Parent or instance:IsA("Terrain") then return end

	if instance:IsA("BasePart") then
		if isLocalEffect(instance) or inCharacter(instance) then return end
		if not KEEP_MATERIALS[instance.Material] then
			set(instance, "Material", Enum.Material.SmoothPlastic)
		end
		if instance.Reflectance > 0 then
			set(instance, "Reflectance", 0)
		end
		if instance.CastShadow then
			set(instance, "CastShadow", false)
		end
	elseif instance:IsA("SurfaceAppearance") then
		if detached[instance] or inCharacter(instance) then return end
		detached[instance] = instance.Parent
		instance.Parent = nil
	elseif instance:IsA("Texture") then
		-- Textures repetidas saem; Decals (placas, rostos) ficam, porque costumam ter informação
		if inCharacter(instance) then return end
		set(instance, "Transparency", 1)
	elseif isEffect(instance) then
		if isLocalEffect(instance) or inCharacter(instance) then return end
		if instance.Enabled then
			set(instance, "Enabled", false)
		end
		watch(instance, "Enabled")
	elseif instance:IsA("Light") then
		if instance.Shadows then
			set(instance, "Shadows", false)
		end
	elseif instance:IsA("PostEffect") then
		if instance.Enabled then
			set(instance, "Enabled", false)
		end
		watch(instance, "Enabled")
	elseif instance:IsA("Clouds") then
		if instance.Enabled then
			set(instance, "Enabled", false)
		end
	elseif instance:IsA("Explosion") then
		instance.Visible = false -- dura um instante: não precisa voltar
	end
end

local function restore(instance, entry)
	if not instance.Parent then return end
	writing = true
	for property, value in entry do
		pcall(function()
			instance[property] = value
		end)
	end
	writing = false
end

-- ================= Lotes =================

local queue = {}
local queueIndex = 1
local queueMode -- "apply" ou "restore"

local function startQueue(mode, list)
	queue = list
	queueIndex = 1
	queueMode = mode
end

RunService.Heartbeat:Connect(function()
	if queueIndex > #queue then return end
	local stop = math.min(#queue, queueIndex + BATCH - 1)
	for index = queueIndex, stop do
		local item = queue[index]
		if queueMode == "apply" then
			-- Uma instância estranha (ex.: travada por outro sistema) não pode parar o lote inteiro
			local ok, err = pcall(simplify, item)
			if not ok then
				writing = false
				warn("[FastMode] " .. tostring(err))
			end
		else
			local entry = saved[item]
			if entry then
				saved[item] = nil
				restore(item, entry)
			end
		end
	end
	queueIndex = stop + 1
	if queueIndex > #queue then
		table.clear(queue)
		queueIndex = 1
	end
end)

-- ================= Ligar / desligar =================

local function enable()
	-- Globais primeiro (efeito imediato e barato)
	set(Lighting, "GlobalShadows", false)
	set(Lighting, "EnvironmentDiffuseScale", 0)
	set(Lighting, "EnvironmentSpecularScale", 0)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		set(terrain, "WaterWaveSize", 0)
		set(terrain, "WaterWaveSpeed", 0)
		set(terrain, "WaterReflectance", 0)
	end

	local list = Lighting:GetDescendants()
	for _, instance in workspace:GetDescendants() do
		table.insert(list, instance)
	end
	startQueue("apply", list)

	-- O que aparecer depois (inimigos, efeitos, partes carregadas pelo streaming) entra na fila também
	for _, container in { workspace, Lighting } do
		table.insert(liveConnections, container.DescendantAdded:Connect(function(instance)
			table.insert(queue, instance)
		end))
	end
end

local function disable()
	for _, connection in liveConnections do
		connection:Disconnect()
	end
	table.clear(liveConnections)
	for instance, list in watchers do
		watchers[instance] = nil
		for _, connection in list do
			connection:Disconnect()
		end
	end

	-- SurfaceAppearance de volta (se a parte ainda existe)
	for appearance, parent in detached do
		detached[appearance] = nil
		if parent.Parent then
			appearance.Parent = parent
		else
			appearance:Destroy()
		end
	end

	local list = {}
	for instance in saved do
		if instance.Parent then
			table.insert(list, instance)
		else
			saved[instance] = nil -- destruída enquanto o Fast Mode estava ligado
		end
	end
	startQueue("restore", list)
end

function FastMode.IsEnabled()
	return enabled
end

-- fromSave = true quando vem do valor salvo (não salva de novo)
function FastMode.Set(value, fromSave)
	value = value == true
	if not fromSave then
		userChanged = true
		Remotes.SaveSetting:FireServer("FastMode", value)
	end
	if value == enabled then return end
	enabled = value

	if enabled then
		enable()
	else
		disable()
	end

	changedEvent:Fire(enabled)
end

function FastMode.Toggle()
	FastMode.Set(not enabled)
end

-- Valor salvo no perfil: aplica quando chegar (se o jogador ainda não mexeu nesta sessão)
local function applySaved()
	if userChanged then return end
	local value = player:GetAttribute("SettingFastMode")
	if type(value) == "boolean" then
		FastMode.Set(value, true)
	end
end
player:GetAttributeChangedSignal("SettingFastMode"):Connect(applySaved)
task.defer(applySaved)

return FastMode
