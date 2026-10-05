-- Sangue no cliente: gotas que voam e viram poças onde batem (chão e parede).
-- As gotas não usam física: um loop só move todas (raio do ponto anterior ao novo, workspace:BulkMoveTo) e as peças
-- são reaproveitadas. Há limite de gotas e de poças; passou do limite, a poça mais velha some antes da hora.
-- Mesma ideia do BloodEngine (rotntake, MIT), sem os sons por gota e sem o .rbxm de malhas dele.
-- Uso (opções: Amount, Speed = {mín, máx}, Spread em graus, Size = {mín, máx}, Mist, Fast = Fast Mode ligado):
--   BloodFX.Burst(origem, direção?, opções?)  jato de gotas (sem direção: para todo lado, puxado para cima)
--   BloodFX.Drip(origem, quantidade?, fast?)   gotas soltas caindo (baba)
--   BloodFX.Splat(posição, diâmetro?, fast?)   poça direto no chão abaixo da posição
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BloodFX = {}

local MAX_DROPS, FAST_MAX_DROPS = 160, 60
local MAX_POOLS, FAST_MAX_POOLS = 70, 24
local GRAVITY = 150 -- studs/s² (menos que o do mundo: o arco fica mais bonito)
local AIR_DRAG = 0.6 -- fração da velocidade perdida por segundo no ar
local DROP_LIFETIME = 2.5
local POOL_LIFETIME = NumberRange.new(6, 9)
local POOL_FADE = 1.6
local POOL_GROW = 0.22 -- tempo da poça se espalhando ao nascer
local POOL_MAX = 6.5 -- diâmetro máximo de uma poça que cresce com gotas caindo em cima
local POOL_THICKNESS = 0.06
local SPLASH_SPEED = 28 -- gota mais rápida que isso respinga gotinhas (sem poça) ao bater
local DROP_COLORS = { Color3.fromRGB(150, 6, 12), Color3.fromRGB(124, 2, 8), Color3.fromRGB(172, 14, 20) }
local POOL_COLORS = { Color3.fromRGB(96, 0, 6), Color3.fromRGB(110, 3, 9), Color3.fromRGB(82, 0, 4) }

local random = Random.new()
local folder
local drops, spareDrops = {}, {}
local pools, sparePools = {}, {}
local mistAttachment, mistEmitter
local loop
local nextFilterAt = 0

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true
params.IgnoreWater = true

-- Pasta dos efeitos locais (workspace.CombatFX): o Fast Mode não mexe nela e as hitboxes a ignoram
local function getFolder()
	if folder and folder.Parent then return folder end
	local parent = workspace:FindFirstChild("CombatFX")
	if not parent then
		parent = Instance.new("Folder")
		parent.Name = "CombatFX"
		parent.Parent = workspace
	end
	folder = Instance.new("Folder")
	folder.Name = "Blood"
	folder.Parent = parent
	return folder
end

-- O sangue atravessa personagens, inimigos e efeitos: só o mapa recebe poça
local function refreshFilter()
	local list = { getFolder() }
	for _, name in { "Enemies", "PowerEffects" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(list, child)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	params.FilterDescendantsInstances = list
	nextFilterAt = os.clock() + 1
end

-- Esfera achatada/esticada pela SpecialMesh: a peça fica com tamanho 1 e só a escala da malha muda
local function newBlob(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.one
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part, mesh
end

local function randomColor(list)
	return list[random:NextInteger(1, #list)]
end

-- Direção aleatória num cone de meia abertura angle (radianos) em volta de axis
local function coneDirection(axis, angle)
	local cosAngle = random:NextNumber(math.cos(angle), 1)
	local sinAngle = math.sqrt(math.max(0, 1 - cosAngle * cosAngle))
	local turn = random:NextNumber(0, math.pi * 2)
	local reference = if math.abs(axis.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local side = axis:Cross(reference).Unit
	local up = side:Cross(axis)
	return axis * cosAngle + (side * math.cos(turn) + up * math.sin(turn)) * sinAngle
end

----------------------------------------------------------------------------------------------------
-- Poças
----------------------------------------------------------------------------------------------------

local function poolScale(pool, diameter)
	return Vector3.new(diameter, POOL_THICKNESS, diameter * pool.Stretch)
end

local function resizePool(pool, diameter, time)
	pool.Diameter = diameter
	if pool.Tween then
		pool.Tween:Cancel()
	end
	pool.Tween = TweenService:Create(pool.Mesh, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = poolScale(pool, diameter) })
	pool.Tween:Play()
end

local function recyclePool(index)
	local pool = pools[index]
	table.remove(pools, index)
	for _, key in { "Tween", "FadeTween" } do
		if pool[key] then
			pool[key]:Cancel()
			pool[key] = nil
		end
	end
	pool.Part.Parent = nil
	table.insert(sparePools, pool)
end

local function fadePool(pool, time)
	pool.Fading = true
	pool.DieAt = os.clock() + time
	pool.FadeTween = TweenService:Create(pool.Part, TweenInfo.new(time), { Transparency = 1 })
	pool.FadeTween:Play()
end

-- Abre espaço para mais uma poça: a mais velha some depressa (ou na hora, se todas já estão sumindo)
local function makeRoom(fast)
	local limit = if fast then FAST_MAX_POOLS else MAX_POOLS
	if #pools < limit then return end
	for _, pool in pools do
		if not pool.Fading then
			fadePool(pool, 0.35)
			return
		end
	end
	recyclePool(1)
end

-- Eixo Y da peça na normal da superfície. Em parede, o Z da peça fica na vertical (escorrido para baixo).
local function poolFrame(position, normal, wall)
	local reference = if math.abs(normal.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local right = reference:Cross(normal).Unit
	local frame = CFrame.fromMatrix(position, right, normal)
	if not wall then
		frame *= CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	end
	return frame
end

local function spawnPool(position, normal, diameter, fast)
	makeRoom(fast)
	local pool = table.remove(sparePools)
	if not pool then
		local part, mesh = newBlob("BloodPool")
		part.Reflectance = 0.12
		pool = { Part = part, Mesh = mesh }
	end
	local wall = math.abs(normal.Y) < 0.6
	diameter = math.min(diameter, POOL_MAX)
	pool.Stretch = if wall then random:NextNumber(1.6, 2.4) else random:NextNumber(0.8, 1.25)
	pool.Position, pool.Normal, pool.Fading = position, normal, false
	pool.DieAt = os.clock() + random:NextNumber(POOL_LIFETIME.Min, POOL_LIFETIME.Max)
	local frame = poolFrame(position + normal * random:NextNumber(0.006, 0.02), normal, wall)
	if wall then
		frame *= CFrame.new(0, 0, diameter * (pool.Stretch - 1) * 0.3) -- desce um pouco: escorrido
	end
	pool.Part.CFrame = frame
	pool.Part.Color = randomColor(POOL_COLORS)
	pool.Part.Transparency = 0.04
	pool.Mesh.Scale = poolScale(pool, diameter * 0.35)
	pool.Part.Parent = getFolder()
	table.insert(pools, pool)
	resizePool(pool, diameter, POOL_GROW)
end

----------------------------------------------------------------------------------------------------
-- Gotas
----------------------------------------------------------------------------------------------------

local spawnDrop -- (definida abaixo; o respingo cria gotas ao pousar)

-- Parede invisível (colisão do mapa) não recebe poça: o sangue ficaria boiando no ar. Chão invisível recebe,
-- porque fica na altura do chão de verdade.
local function solidSurface(hit)
	if hit.Normal.Y > 0.6 then return true end
	local instance = hit.Instance
	return instance:IsA("Terrain") or (instance:IsA("BasePart") and instance.Transparency < 0.9)
end

local function land(drop, hit, velocity, fast)
	if drop.NoPool then return end
	local normal, position = hit.Normal, hit.Position
	local speed = velocity.Magnitude
	local size = drop.Size * random:NextNumber(2, 3) * (1 + math.min(speed, 60) / 120)

	-- Caiu em cima de uma poça no mesmo plano: ela cresce (soma a área) em vez de nascer outra
	local merged = false
	for _, pool in pools do
		if not pool.Fading and pool.Normal:Dot(normal) > 0.9 and (pool.Position - position).Magnitude < pool.Diameter * 0.55 then
			local diameter = math.min(POOL_MAX, math.sqrt(pool.Diameter * pool.Diameter + size * size * 0.6))
			if diameter > pool.Diameter + 0.02 then
				resizePool(pool, diameter, 0.15)
			end
			merged = true
			break
		end
	end
	if not merged then
		spawnPool(position, normal, size, fast)
	end

	-- Respingo: gotinhas que pulam do ponto de impacto e não fazem poça
	if speed > SPLASH_SPEED and random:NextNumber() < 0.45 then
		local bounce = velocity - normal * (2 * velocity:Dot(normal))
		for _ = 1, random:NextInteger(1, 2) do
			local splash = bounce * random:NextNumber(0.1, 0.2) + normal * random:NextNumber(4, 9) + random:NextUnitVector() * 3
			spawnDrop(position + normal * 0.15, splash, drop.Size * 0.45, true, fast)
		end
	end
end

local function recycleDrop(index)
	local drop = drops[index]
	drops[index] = drops[#drops]
	drops[#drops] = nil
	drop.Part.Parent = nil
	table.insert(spareDrops, drop)
end

local function step(dt)
	dt = math.min(dt, 1 / 15)
	local now = os.clock()
	if now >= nextFilterAt then
		refreshFilter()
	end

	local parts, frames = {}, {}
	local index = 1
	while index <= #drops do
		local drop = drops[index]
		local velocity = drop.Velocity * math.max(0, 1 - AIR_DRAG * dt) - Vector3.new(0, GRAVITY * dt, 0)
		local travel = velocity * dt
		local hit = workspace:Raycast(drop.Position, travel, params)
		if hit and solidSurface(hit) then
			land(drop, hit, velocity, drop.Fast)
			recycleDrop(index)
		elseif now - drop.Born > DROP_LIFETIME then
			recycleDrop(index)
		else
			drop.Position += travel
			drop.Velocity = velocity
			table.insert(parts, drop.Part)
			table.insert(frames, CFrame.lookAt(drop.Position, drop.Position + velocity))
			index += 1
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	for i = #pools, 1, -1 do
		local pool = pools[i]
		if now >= pool.DieAt then
			if pool.Fading then
				recyclePool(i)
			else
				fadePool(pool, POOL_FADE)
			end
		end
	end

	if #drops == 0 and #pools == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function ensureLoop()
	if not loop then
		loop = RunService.Heartbeat:Connect(step)
	end
end

-- noPool: respingo (some ao bater, sem poça)
function spawnDrop(position, velocity, size, noPool, fast)
	if #drops >= (if fast then FAST_MAX_DROPS else MAX_DROPS) then return end
	local drop = table.remove(spareDrops)
	if not drop then
		local part, mesh = newBlob("BloodDrop")
		drop = { Part = part, Mesh = mesh }
	end
	drop.Position, drop.Velocity, drop.Size = position, velocity, size
	drop.NoPool, drop.Fast, drop.Born = noPool, fast, os.clock()
	-- Esticada na direção do voo: quanto mais rápida, mais comprida
	drop.Mesh.Scale = Vector3.new(size, size, size * math.min(3.5, 1.4 + velocity.Magnitude / 40))
	drop.Part.Color = randomColor(DROP_COLORS)
	drop.Part.CFrame = CFrame.lookAt(position, position + velocity)
	drop.Part.Parent = getFolder()
	table.insert(drops, drop)
	ensureLoop()
end

----------------------------------------------------------------------------------------------------
-- Névoa (um emissor só, levado até o ponto antes de cada estouro)
----------------------------------------------------------------------------------------------------

local function mist(position, amount)
	if amount <= 0 then return end
	if not mistEmitter or not mistEmitter:IsDescendantOf(workspace) then
		local holder = Instance.new("Part")
		holder.Name = "BloodMist"
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.Parent = getFolder()
		mistAttachment = Instance.new("Attachment")
		mistAttachment.Parent = holder
		mistEmitter = Instance.new("ParticleEmitter")
		mistEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mistEmitter.Color = ColorSequence.new(Color3.fromRGB(140, 8, 14), Color3.fromRGB(60, 0, 4))
		mistEmitter.LightEmission = 0
		mistEmitter.LightInfluence = 1
		mistEmitter.Lifetime = NumberRange.new(0.35, 0.75)
		mistEmitter.Speed = NumberRange.new(3, 11)
		mistEmitter.Drag = 6
		mistEmitter.Acceleration = Vector3.new(0, -6, 0)
		mistEmitter.SpreadAngle = Vector2.new(180, 180)
		mistEmitter.Rotation = NumberRange.new(0, 360)
		mistEmitter.RotSpeed = NumberRange.new(-80, 80)
		mistEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 3.2) })
		mistEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.6, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		mistEmitter.Rate = 0
		mistEmitter.Parent = mistAttachment
	end
	mistAttachment.WorldPosition = position
	mistEmitter:Emit(amount)
end

----------------------------------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------------------------------

-- Jato de gotas a partir de origin. direction (opcional): centro do jato; sem ela, para todo lado e puxado para cima.
function BloodFX.Burst(origin, direction, options)
	if typeof(origin) ~= "Vector3" then return end
	options = options or {}
	local fast = options.Fast == true
	local amount = math.floor((options.Amount or 20) * (if fast then 0.45 else 1) + 0.5)
	local speed = options.Speed or { 14, 32 }
	local size = options.Size or { 0.18, 0.42 }
	local spread = math.rad(options.Spread or 55)
	local axis = if typeof(direction) == "Vector3" and direction.Magnitude > 1e-3 then direction.Unit else nil
	refreshFilter()
	for _ = 1, amount do
		local heading = if axis then coneDirection(axis, spread) else (random:NextUnitVector() + Vector3.new(0, 0.9, 0)).Unit
		local offset = random:NextUnitVector() * random:NextNumber(0, 0.4)
		spawnDrop(origin + offset, heading * random:NextNumber(speed[1], speed[2]), random:NextNumber(size[1], size[2]), false, fast)
	end
	local mistAmount = options.Mist or math.ceil(amount * 0.3)
	mist(origin, math.floor(mistAmount * (if fast then 0.5 else 1)))
end

-- Gotas soltas caindo de um ponto (baba de sangue), quase sem velocidade
function BloodFX.Drip(origin, amount, fast)
	BloodFX.Burst(origin, Vector3.new(0, -1, 0), {
		Amount = amount or 3,
		Speed = { 0.5, 4 },
		Spread = 30,
		Size = { 0.2, 0.34 },
		Mist = 0,
		Fast = fast,
	})
end

-- Poça direto no chão logo abaixo de position
function BloodFX.Splat(position, diameter, fast)
	if typeof(position) ~= "Vector3" then return end
	refreshFilter()
	local hit = workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -20, 0), params)
	if hit and solidSurface(hit) then
		spawnPool(hit.Position, hit.Normal, diameter or 3, fast)
		ensureLoop()
	end
end

return BloodFX
