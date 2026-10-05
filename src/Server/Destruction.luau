-- Destruição do mapa (servidor): os golpes fortes quebram o que estiver perto, menos o chão. Tudo volta sozinho em
-- RESET_TIME segundos.
--   * Part de bloco visível: vira voxels pelo VoxBreaker (Bartokens, MIT; cópia em VoxBreaker.luau). Os pedaços de
--     dentro da explosão voam (os mais perto) ou somem (o resto), abrindo o buraco.
--   * Malha, união, cunha e Part pequena: o VoxBreaker só divide Part de bloco, então a peça some e voam pedaços da cor
--     e do material dela (ou a própria peça inteira, se for pequena: um poste, uma caixa). A colisão invisível que
--     estiver dentro dela (a cidade é malha por cima de peças invisíveis) sai junto.
-- Nunca quebram: chão (peça baixa e larga, ou com nome de chão), peça invisível sozinha (colisão do mapa), peça enorme
-- (prédio inteiro), personagens, inimigos, NPCs de missão, spawns, assentos, peças com ProximityPrompt e tudo que tiver
-- o atributo NoDestroy = true (nela ou numa pasta/modelo acima). workspace:SetAttribute("DestructionDisabled", true)
-- desliga tudo.
-- Quem usa: PathSkills (Mordida, Bote, Area, Projectile), CombatService (Soco carregado, Saque, Kon!, golpes que
-- arremessam) e, para o Infernal do Sangue, ctx.Destruction no PathSkills.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local VoxBreaker = require(script.Parent:WaitForChild("VoxBreaker"))

local Destruction = {}

local RESET_TIME = 30 -- segundos até a peça voltar
local RESET_RETRY = 2 -- com alguém dentro da peça na hora de voltar, tenta de novo depois disso
local RESET_MAX_WAIT = 30 -- e volta assim mesmo depois disso
local MAX_EXTENT = 120 -- Part maior que isso (em qualquer eixo) não quebra
local MAX_SHATTER = 45 -- malha/união maior que isso (um prédio inteiro) não quebra
local WHOLE_SIZE = 8 -- peça com todos os lados até isso voa inteira
local FLOOR_HEIGHT = 6 -- chão: altura até isso...
local FLOOR_RATIO = 3 -- ...e o lado menor na horizontal pelo menos 3x a altura...
local FLOOR_MIN_WIDTH = 8 -- ...e o lado maior pelo menos isso
local FLOOR_NAMES = { "floor", "ground", "chao", "piso", "road", "rua", "calcada", "baseplate", "asfalto", "terrain" }
local MAX_FLUNG = 24 -- pedaços que voam por explosão (o resto some)
local MAX_SHATTERED = 12 -- malhas quebradas por explosão
local MAX_LIVE_DEBRIS = 260 -- pedaços voando no jogo todo; acima disso some em vez de voar
local DEBRIS_LIFETIME = 5
local BLASTS_PER_SECOND = 16 -- limite do jogo todo (o Bote sozinho faz uns 7)

-- Pastas: workspace.Destruction (voxels do VoxBreaker) e workspace.Destruction.Debris (o que está voando)
local folder = workspace:FindFirstChild("Destruction")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Destruction"
	folder.Parent = workspace
end
local debrisFolder = folder:FindFirstChild("Debris")
if not debrisFolder then
	debrisFolder = Instance.new("Folder")
	debrisFolder.Name = "Debris"
	debrisFolder.Parent = folder
end

-- Pedaços voando batem no mapa, mas não em personagens (não empurram ninguém)
for _, group in { "Debris", "Players", "NPCs" } do
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
end
PhysicsService:CollisionGroupSetCollidable("Debris", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Debris", "NPCs", false)
PhysicsService:CollisionGroupSetCollidable("Debris", "Debris", false)

local rng = Random.new()
local kinds = setmetatable({}, { __mode = "k" }) -- [peça do mapa] = "Voxel" | "Shatter" | false
local broken = setmetatable({}, { __mode = "k" }) -- [peça quebrada pelo Shatter] = true
local liveDebris = 0
local budget, budgetAt = BLASTS_PER_SECOND, os.clock()

----------------------------------------------------------------------------------------------------
-- O que pode quebrar
----------------------------------------------------------------------------------------------------

-- Tamanho da caixa da peça nos eixos do mundo
local function extents(part)
	local cf, size = part.CFrame, part.Size
	local r, u, b = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(b.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(b.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(b.Z) * size.Z
	)
end

local function normalized(name)
	return (string.lower(name):gsub("ã", "a"):gsub("á", "a"):gsub("ç", "c"))
end

local function isFloor(part, ext)
	local name = normalized(part.Name)
	for _, word in FLOOR_NAMES do
		if string.find(name, word, 1, true) then return true end
	end
	local wide = math.max(ext.X, ext.Z)
	local narrow = math.min(ext.X, ext.Z)
	if ext.Y <= FLOOR_HEIGHT and narrow >= ext.Y * FLOOR_RATIO and wide >= FLOOR_MIN_WIDTH then
		return true
	end
	-- Rampa (cunha deitada): também é chão
	if (part:IsA("WedgePart") or part:IsA("CornerWedgePart")) and wide >= ext.Y * 2 then
		return true
	end
	return false
end

local function blockedByAncestor(part)
	local enemies = workspace:FindFirstChild("Enemies")
	local spawns = workspace:FindFirstChild("EnemySpawns")
	local fx = workspace:FindFirstChild("CombatFX")
	local node = part
	while node and node ~= workspace do
		if node:GetAttribute("NoDestroy") == true then return true end
		if node == enemies or node == spawns or node == fx or node == workspace.CurrentCamera then return true end
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then return true end
		if node:IsA("Tool") or node:IsA("Accessory") then return true end
		if CollectionService:HasTag(node, "QuestGiver") then return true end
		node = node.Parent
	end
	return node ~= workspace
end

-- "Voxel" (VoxBreaker), "Shatter" (some e solta pedaços) ou false
local function classify(part)
	if part:IsDescendantOf(folder) then
		-- Voxels de uma explosão anterior continuam quebráveis; o que está voando não
		return if part:IsA("Part") and part:GetAttribute("Destroyable") == true then "Voxel" else false
	end
	local cached = kinds[part]
	if cached ~= nil then return cached end

	local kind = false
	if part:IsA("BasePart") and not part:IsA("Terrain") and part.Anchored and part.Transparency < 0.95
		and not part:IsA("SpawnLocation") and not part:IsA("Seat") and not part:IsA("VehicleSeat")
		and part:GetAttribute("Destroyable") ~= false
		and not part:FindFirstChildWhichIsA("ProximityPrompt", true) and not part:FindFirstChildWhichIsA("ClickDetector")
		and not blockedByAncestor(part) then
		local ext = extents(part)
		local largest = math.max(ext.X, ext.Y, ext.Z)
		if not isFloor(part, ext) then
			local isBlock = part.ClassName == "Part" and part.Shape == Enum.PartType.Block
			if isBlock and largest > WHOLE_SIZE and largest <= MAX_EXTENT then
				kind = "Voxel"
			elseif largest <= MAX_SHATTER then
				kind = "Shatter"
			end
		end
	end
	kinds[part] = kind
	return kind
end

local function characterFilter()
	local list = { debrisFolder }
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then table.insert(list, enemies) end
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(list, player.Character) end
	end
	return list
end

local function takeBudget()
	local t = os.clock()
	budget = math.min(BLASTS_PER_SECOND, budget + (t - budgetAt) * BLASTS_PER_SECOND)
	budgetAt = t
	if budget < 1 then return false end
	budget -= 1
	return true
end

----------------------------------------------------------------------------------------------------
-- Pedaços voando
----------------------------------------------------------------------------------------------------

local function fling(piece, center, power)
	if liveDebris >= MAX_LIVE_DEBRIS then
		piece:Destroy()
		return
	end
	piece:SetAttribute("Destroyable", false)
	piece.Anchored = false
	piece.CanCollide = true
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CollisionGroup = "Debris"
	piece.Parent = debrisFolder
	liveDebris += 1
	piece.AncestryChanged:Once(function()
		liveDebris -= 1
	end)
	local away = piece.Position - center
	local direction = if away.Magnitude > 0.05 then away.Unit else Vector3.yAxis
	local speed = power * rng:NextNumber(0.55, 1.1)
	piece.AssemblyLinearVelocity = direction * speed + Vector3.new(0, power * rng:NextNumber(0.25, 0.6), 0)
	piece.AssemblyAngularVelocity = rng:NextUnitVector() * rng:NextNumber(4, 14)
	Debris:AddItem(piece, DEBRIS_LIFETIME + rng:NextNumber(0, 1.5))
end

-- Alguém (jogador ou inimigo) dentro da caixa: a peça não volta em cima dele
local function occupied(cframe, size)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = characterFilter()
	return #workspace:GetPartBoundsInBox(cframe, size + Vector3.one, params) > 0
end

-- Colisão invisível dentro da malha (o visual da cidade é malha; quem segura o jogador é a peça invisível embaixo)
local function hiddenColliders(part, ext)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter()
	local center = part.Position
	local half = ext / 2 + Vector3.one * 1.5
	local found = {}
	for _, other in workspace:GetPartBoundsInBox(part.CFrame, part.Size + Vector3.one * 2, params) do
		if other ~= part and other.Anchored and other.CanCollide and other.Transparency >= 0.95
			and not other:IsDescendantOf(folder) then
			local otherExt = extents(other)
			local offset = other.Position - center
			local inside = math.abs(offset.X) + otherExt.X / 2 <= half.X
				and math.abs(offset.Y) + otherExt.Y / 2 <= half.Y
				and math.abs(offset.Z) + otherExt.Z / 2 <= half.Z
			if inside and not isFloor(other, otherExt) then
				table.insert(found, other)
			end
		end
	end
	return found
end

-- Some com a peça (malha, união, cunha, Part pequena) e solta pedaços; volta em RESET_TIME
local function shatter(part, center, power, flungLeft)
	broken[part] = true
	local ext = extents(part)
	local saved = { Transparency = part.Transparency, CanCollide = part.CanCollide, CanQuery = part.CanQuery }
	local colliders = {}
	for _, collider in hiddenColliders(part, ext) do
		table.insert(colliders, { Part = collider, CanCollide = collider.CanCollide, CanQuery = collider.CanQuery })
		collider.CanCollide = false
		collider.CanQuery = false
	end
	local decals = {}
	for _, child in part:GetChildren() do
		if child:IsA("Decal") or child:IsA("Texture") then
			decals[child] = child.Transparency
			child.Transparency = 1
		end
	end

	local largest = math.max(ext.X, ext.Y, ext.Z)
	local used = 0
	if flungLeft > 0 then
		if largest <= WHOLE_SIZE then
			-- Pequena: a própria peça voa (só o visual: sem scripts nem prompts)
			local copy = part:Clone()
			for _, descendant in copy:GetDescendants() do
				if descendant:IsA("LuaSourceContainer") or descendant:IsA("ProximityPrompt") or descendant:IsA("Light")
					or descendant:IsA("Sound") then
					descendant:Destroy()
				end
			end
			copy.Transparency = saved.Transparency
			fling(copy, center, power)
			used = 1
		else
			local count = math.min(flungLeft, math.clamp(math.floor(largest / 3), 3, 8))
			local smallest = math.min(ext.X, ext.Y, ext.Z)
			for _ = 1, count do
				local chunk = Instance.new("Part")
				chunk.Name = "Chunk"
				local side = math.clamp(smallest * rng:NextNumber(0.3, 0.55), 0.6, 3.5)
				chunk.Size = Vector3.new(side, side * rng:NextNumber(0.6, 1.2), side * rng:NextNumber(0.6, 1.2))
				chunk.Color = part.Color
				chunk.Material = part.Material
				chunk.TopSurface = Enum.SurfaceType.Smooth
				chunk.BottomSurface = Enum.SurfaceType.Smooth
				chunk.CFrame = CFrame.new(part.Position + Vector3.new(
					rng:NextNumber(-0.4, 0.4) * ext.X, rng:NextNumber(-0.4, 0.4) * ext.Y, rng:NextNumber(-0.4, 0.4) * ext.Z
				)) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
				fling(chunk, center, power)
			end
			used = count
		end
	end

	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false

	task.delay(RESET_TIME, function()
		local waited = 0
		while part.Parent and waited < RESET_MAX_WAIT and occupied(part.CFrame, part.Size) do
			task.wait(RESET_RETRY)
			waited += RESET_RETRY
		end
		if part.Parent then
			part.Transparency = saved.Transparency
			part.CanCollide = saved.CanCollide
			part.CanQuery = saved.CanQuery
		end
		for decal, transparency in decals do
			if decal.Parent then decal.Transparency = transparency end
		end
		for _, entry in colliders do
			if entry.Part.Parent then
				entry.Part.CanCollide = entry.CanCollide
				entry.Part.CanQuery = entry.CanQuery
			end
		end
		broken[part] = nil
	end)
	return used
end

----------------------------------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------------------------------

-- Explosão: quebra o que estiver a até radius studs de position. opts.Power = velocidade dos pedaços (padrão 50);
-- opts.VoxelSize = tamanho dos voxels (padrão: proporcional ao raio). Devolve quantas peças quebraram.
function Destruction.Blast(position, radius, opts)
	if workspace:GetAttribute("DestructionDisabled") == true then return 0 end
	if typeof(position) ~= "Vector3" or type(radius) ~= "number" or radius <= 0 then return 0 end
	if not takeBudget() then return 0 end
	opts = opts or {}
	local power = opts.Power or 50
	radius = math.min(radius, 24)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter()
	params.MaxParts = 300

	local voxelParts, shatterParts = {}, {}
	for _, part in workspace:GetPartBoundsInRadius(position, radius, params) do
		local kind = classify(part)
		if kind == "Voxel" then
			if part:GetAttribute("Destroyable") == nil then
				part:SetAttribute("Destroyable", true) -- o VoxBreaker só divide peça com o atributo
			end
			table.insert(voxelParts, part)
		elseif kind == "Shatter" and not broken[part] then
			table.insert(shatterParts, part)
		end
	end

	local count = 0
	local flungLeft = MAX_FLUNG
	if #voxelParts > 0 then
		local include = OverlapParams.new()
		include.FilterType = Enum.RaycastFilterType.Include
		-- As peças achadas e a pasta dos voxels (o VoxBreaker procura de novo nos pedaços que acabou de criar)
		table.insert(voxelParts, folder)
		include.FilterDescendantsInstances = voxelParts
		local voxelSize = opts.VoxelSize or math.clamp(radius / 3.5, 1.5, 5)
		local ok, voxels = pcall(VoxBreaker.CreateHitbox, VoxBreaker, Vector3.one * radius * 2, CFrame.new(position),
			Enum.PartType.Ball, voxelSize, RESET_TIME, include)
		if ok and type(voxels) == "table" then
			table.sort(voxels, function(a, b)
				return (a.Position - position).Magnitude < (b.Position - position).Magnitude
			end)
			for _, voxel in voxels do
				if voxel.Parent then
					if flungLeft > 0 then
						flungLeft -= 1
						fling(voxel, position, power)
					else
						voxel:Destroy()
					end
					count += 1
				end
			end
		elseif not ok then
			warn("[Destruction] VoxBreaker: " .. tostring(voxels))
		end
	end

	table.sort(shatterParts, function(a, b)
		return (a.Position - position).Magnitude < (b.Position - position).Magnitude
	end)
	for index, part in shatterParts do
		if index > MAX_SHATTERED then break end
		flungLeft -= shatter(part, position, power, flungLeft)
		count += 1
	end
	return count
end

-- Diagnóstico (/destruir no ItemCommands): por que cada peça perto do ponto quebra ou não. Devolve { [motivo] = n }
local function whyNot(part)
	if not part:IsA("BasePart") or part:IsA("Terrain") then return "terreno" end
	if not part.Anchored then return "solta (sem Anchored)" end
	if part.Transparency >= 0.95 then return "invisível (colisão do mapa)" end
	if part:IsA("SpawnLocation") or part:IsA("Seat") or part:IsA("VehicleSeat") then return "spawn/assento" end
	if part:GetAttribute("Destroyable") == false then return "Destroyable = false" end
	if part:FindFirstChildWhichIsA("ProximityPrompt", true) or part:FindFirstChildWhichIsA("ClickDetector") then return "tem prompt" end
	if blockedByAncestor(part) then return "protegida (NoDestroy, NPC, inimigo, spawn de inimigo)" end
	local ext = extents(part)
	if isFloor(part, ext) then return "chão" end
	return "grande demais"
end

function Destruction.Explain(position, radius)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characterFilter()
	params.MaxParts = 300
	local counts = {}
	for _, part in workspace:GetPartBoundsInRadius(position, radius, params) do
		local kind = classify(part)
		local reason = if kind == "Voxel" then "quebra em cubos"
			elseif kind == "Shatter" then (if broken[part] then "já quebrada" else "quebra em pedaços")
			else whyNot(part)
		counts[reason] = (counts[reason] or 0) + 1
	end
	return counts
end

-- Quem foi arremessado quebra o que bater pelo caminho (parede, poste, caixa). duration = tempo do arremesso.
function Destruction.Launch(model, duration, opts)
	if workspace:GetAttribute("DestructionDisabled") == true then return end
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	opts = opts or {}
	local minSpeed = opts.MinSpeed or 24
	local maxImpacts = opts.MaxImpacts or 2
	task.spawn(function()
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = characterFilter()
		local endAt = os.clock() + (duration or 0.3) + 0.6 -- o corpo continua voando um pouco depois do empurrão
		local impacts, lastImpact = 0, 0
		while os.clock() < endAt and root.Parent and impacts < maxImpacts do
			task.wait(0.05)
			local velocity = root.AssemblyLinearVelocity
			local speed = velocity.Magnitude
			if speed >= minSpeed and os.clock() - lastImpact > 0.2 then
				local ahead = root.Position + velocity.Unit * 2
				for _, part in workspace:GetPartBoundsInRadius(ahead, 2.5, params) do
					local kind = classify(part)
					if kind and not broken[part] then
						impacts += 1
						lastImpact = os.clock()
						Destruction.Blast(ahead, math.clamp(speed / 12, 3, 6), { Power = math.min(speed * 0.6, 70) })
						break
					end
				end
			end
		end
	end)
end

return Destruction
