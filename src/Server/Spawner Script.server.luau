-- Mantém os inimigos de cada zona e renasce os que morrem.
-- Zonas: Parts dentro de workspace.EnemySpawns (ou de subpastas dela). O tipo é o nome da Part (a chave do
-- EnemyData ou o DisplayName, sem diferenciar maiúsculas/acentos e ignorando número no fim) ou o atributo EnemyType.
-- Atributos opcionais: MaxEnemies (padrão 3), RespawnTime (padrão 8), Level (padrão: o do tipo).
-- No jogo a Part fica invisível e sem colisão.
-- O modelo usado é EnemyData[EnemyType].Template (ou o próprio EnemyType) em ServerStorage.EnemyTemplates.
-- Sem workspace.EnemySpawns, nascem 5 Goblins em volta da origem. Zonas sugeridas em docs/mapa-fase4.md.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local BossData = require(ReplicatedStorage:WaitForChild("BossData"))
local EnemyData = require(ServerScriptService:WaitForChild("EnemyData"))
local EnemyModule = require(ServerScriptService:WaitForChild("EnemyModule"))

local DEFAULT_TYPE = "Goblin"
local DEFAULT_MAX = 3
local DEFAULT_RESPAWN = 8
local MAP_WAIT = 5 -- segundos esperando workspace.EnemySpawns antes de usar o spawn padrão

-- Templates: ficam em ServerStorage.EnemyTemplates. Se estiverem no workspace, vão para lá
-- (no workspace sofrem física, podem cair no void e perder partes).
local templates = ServerStorage:FindFirstChild("EnemyTemplates")
local templatesInWorkspace = workspace:FindFirstChild("EnemyTemplates")
if templatesInWorkspace then
	if templates then
		for _, child in templatesInWorkspace:GetChildren() do
			child.Parent = templates
		end
		templatesInWorkspace:Destroy()
	else
		templatesInWorkspace.Parent = ServerStorage
		templates = templatesInWorkspace
	end
end
if not templates then
	templates = workspace:WaitForChild("EnemyTemplates", 10)
	if templates then
		templates.Parent = ServerStorage
	else
		warn("[Spawner] Nenhuma pasta EnemyTemplates (em ServerStorage ou workspace). Nenhum inimigo vai nascer.")
		return
	end
end

local warnedTypes = {}
local function getTemplate(enemyType)
	if not EnemyData[enemyType] and not warnedTypes[enemyType] then
		warn(`[Spawner] "{enemyType}" ainda não tem entrada no EnemyData: usa os números de um inimigo comum `
			.. `do level da zona (atributo Level; sem ele, level 1). Para números próprios, crie a entrada no EnemyData.`)
	end

	local templateName = EnemyModule.GetTemplateName(enemyType)
	local template = templates:FindFirstChild(templateName)
	if not template and not warnedTypes[enemyType] then
		warn(`[Spawner] Não existe ServerStorage.EnemyTemplates.{templateName} (usado pelo tipo {enemyType})`)
	end
	warnedTypes[enemyType] = true
	return template
end

local function numberAttr(instance, name, default)
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- zone = { EnemyType, MaxEnemies, RespawnTime, Level, GetSpawnCFrame(), IsActive() }
local function runZone(zone)
	local template = getTemplate(zone.EnemyType)
	if not template then return end

	local function spawnOne()
		if not zone.IsActive() then return end
		local cframe = zone.GetSpawnCFrame()
		EnemyModule.SpawnEnemy(template, cframe, {
			EnemyType = zone.EnemyType, -- o tipo da zona, não o nome do template (recompensas e missões usam ele)
			Level = zone.Level,
			Home = cframe.Position,
			OnDied = function()
				task.wait(zone.RespawnTime)
				spawnOne()
			end,
		})
	end

	-- Cada spawn na sua thread: um erro num inimigo não para as outras zonas
	for _ = 1, zone.MaxEnemies do
		task.spawn(spawnOne)
	end
end

-- Nome comparável: minúsculo, sem acento, sem espaço/símbolo e sem número no fim ("Goblin Ladrão (2)" -> "goblinladrao")
local ACCENTS = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
	["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
	["ç"] = "c", ["ñ"] = "n",
	-- string.lower não mexe em letras acentuadas (UTF-8): as maiúsculas vão direto
	["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["Ä"] = "a",
	["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
	["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ö"] = "o",
	["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
	["Ç"] = "c", ["Ñ"] = "n",
}
local function normalize(text)
	text = string.lower(text)
	for accented, plain in ACCENTS do
		text = string.gsub(text, accented, plain)
	end
	text = string.gsub(text, "[^%w]", "")
	return (string.gsub(text, "%d+$", ""))
end

-- [nome normalizado] = EnemyType, pela chave do EnemyData e pelo DisplayName
local typesByName = {}
for enemyType, data in EnemyData do
	typesByName[normalize(enemyType)] = enemyType
	if type(data.LegacyName) == "string" then
		typesByName[normalize(data.LegacyName)] = enemyType
	end
	if type(data.DisplayName) == "string" then
		typesByName[normalize(data.DisplayName)] = enemyType
	end
end

-- Tipo da zona: atributo EnemyType ou, sem ele, o nome da Part ("GoblinLadrao", "Goblin Ladrão", "Goblin Ladrão 2")
local warnedParts = {}
local function zoneType(part)
	local attribute = part:GetAttribute("EnemyType")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	local wanted = normalize(part.Name)
	local byName = typesByName[wanted]
	if byName then
		return byName
	end
	-- Inimigo novo que ainda não está no EnemyData: o nome de um modelo em EnemyTemplates
	for _, template in templates:GetChildren() do
		if normalize(template.Name) == wanted then
			return template.Name
		end
	end
	if not warnedParts[part.Name] then
		warnedParts[part.Name] = true
		local names = {}
		for enemyType in EnemyData do
			table.insert(names, enemyType)
		end
		table.sort(names)
		warn(`[Spawner] A zona "{part:GetFullName()}" não tem o nome de um inimigo (EnemyData ou modelo em EnemyTemplates) `
			.. `nem o atributo EnemyType: nasce "{DEFAULT_TYPE}". Nomes do EnemyData: {table.concat(names, ", ")}`)
	end
	return DEFAULT_TYPE
end

local function zoneFromPart(part)
	return {
		EnemyType = zoneType(part),
		MaxEnemies = numberAttr(part, "MaxEnemies", DEFAULT_MAX),
		RespawnTime = numberAttr(part, "RespawnTime", DEFAULT_RESPAWN),
		Level = part:GetAttribute("Level"),
		IsActive = function()
			return part.Parent ~= nil
		end,
		-- Ponto aleatório em cima da Part
		GetSpawnCFrame = function()
			local size = part.Size
			local offset = Vector3.new((math.random() - 0.5) * size.X, size.Y / 2 + 3, (math.random() - 0.5) * size.Z)
			return CFrame.new(part.CFrame:PointToWorldSpace(offset))
		end,
	}
end

local startedParts = {}
local spawnsFolder
local function startPart(part)
	if not part:IsA("BasePart") or startedParts[part] then return end
	-- Peça de um Model dentro da pasta (ex.: o trono do boss) é decoração, não zona
	local model = part:FindFirstAncestorWhichIsA("Model")
	if model and spawnsFolder and model:IsDescendantOf(spawnsFolder) then return end
	startedParts[part] = true
	-- No Studio a zona pode ficar visível para editar; no jogo ela some e não atrapalha ninguém
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	local zone = zoneFromPart(part)
	-- O tipo resolvido fica na Part para o cliente (o minimapa marca as zonas do alvo das missões)
	part:SetAttribute("ZoneType", zone.EnemyType)
	-- Chefe nasce pelo BossService, no lugar onde o modelo dele foi colocado (não por zona)
	if BossData.Get(zone.EnemyType) then
		warn(`[Spawner] A zona "{part:GetFullName()}" é de um chefe ({zone.EnemyType}): chefes nascem sozinhos onde o `
			.. `modelo deles está (BossService). A zona foi ignorada.`)
		return
	end
	runZone(zone)
end

-- Zonas: Parts em workspace.EnemySpawns, inclusive dentro de subpastas (ex.: uma pasta por bairro)
spawnsFolder = workspace:FindFirstChild("EnemySpawns") or workspace:WaitForChild("EnemySpawns", MAP_WAIT)
if spawnsFolder then
	for _, part in spawnsFolder:GetDescendants() do
		startPart(part)
	end
	spawnsFolder.DescendantAdded:Connect(startPart)
else
	runZone({
		EnemyType = DEFAULT_TYPE,
		MaxEnemies = 5,
		RespawnTime = 5,
		Level = nil,
		IsActive = function()
			return true
		end,
		GetSpawnCFrame = function()
			return CFrame.new(math.random(-20, 20), 5, math.random(-20, 20))
		end,
	})
end
