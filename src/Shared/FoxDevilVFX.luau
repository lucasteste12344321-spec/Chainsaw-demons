-- Mordida da Raposa (Kon). A cabeça sai de um portal escuro de bordas luminosas atrás do alvo, abre a boca bem aberta,
-- dá o bote para a frente, fecha com tudo no ponto mirado e sacode a presa antes de voltar para o portal.
-- No impacto: tremida de câmera e flash para quem está perto, clarão, estouro vermelho, anéis de pressão e a cratera
-- (rachaduras, pedaços do chão, estilhaços, poeira e onda de choque) do tamanho da área de dano (data.Radius).
-- Finalização (VFX.Devour, quando o servidor manda CombatFX "FoxDevour"): a animação base para, o corpo da presa (uma
-- cópia local; o de verdade fica escondido) é puxado para a boca no meio de um jato de sangue (BloodFX), o Kon mastiga
-- Config.DevourChews vezes, engole e só então volta para o portal.
-- Bote (VFX.Lunge, CombatFX "FoxLunge"): a cabeça sai de um portal atrás de quem invocou e corre em linha reta até
-- o fim do caminho, onde fecha a mordida (o servidor arrasta quem ela pega; FoxLungeCatch = sangue em cada um).
-- A mordida usa os ossos (Head, Jaw) e pesos preparados no Blender. Efeito somente no cliente.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage:WaitForChild("FoxDevilConfig"))
local BloodFX = require(ReplicatedStorage:WaitForChild("BloodFX"))
local VFX = {}
local active = {}
local random = Random.new()
local SHAKE_TIME = 0.5 -- tremida da câmera no impacto
local SHAKE_RANGE = 120 -- até essa distância da mordida a câmera treme (mais fraco longe)
local PREY_SHAKE = 0.45 -- segundos sacudindo a presa depois de fechar a boca
local CHEW_SHARE = 0.78 -- finalização: parte do DevourTime mastigando (o resto é a engolida)
-- Pontos da boca no espaço da cabeça (osso Head, modelo em escala 1), medidos em captura na pose da mordida: centro
-- (onde fica a presa, ~2 studs acima do ponto mirado), canto direito (o esquerdo é o espelho) e dentes da frente
local MOUTH_CENTER = Vector3.new(0, 3, -2.45)
local MOUTH_CORNER = Vector3.new(1.07, 3.16, -1.38)
local MOUTH_LIP = Vector3.new(0, 2.6, -3.4)
local function smooth(value)
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end
local function effectPart(name, parent, class)
	local part = Instance.new(class or "Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end
local function ringTemplate()
	local assets = ReplicatedStorage:FindFirstChild("VFX")
	local goblin = assets and assets:FindFirstChild("GoblinKing")
	return goblin and goblin:FindFirstChild("ImpactRing")
end
local function ringCopy(name, parent)
	local template = ringTemplate()
	if not template or not template:IsA("BasePart") then return nil end
	local ring = template:Clone()
	for _, child in ring:GetChildren() do child:Destroy() end
	ring.Name = name
	ring.Anchored = true
	ring.CanCollide, ring.CanTouch, ring.CanQuery, ring.CastShadow = false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Parent = parent
	return ring
end
-- seeThrough: o portal fica entre a câmera e quem invocou (Kon! da fusão, na tela dele): o fundo escuro fica quase
-- transparente para ele continuar vendo o alvo
local function portal(base, scale, parent, fast, seeThrough)
	local center = base * CFrame.new(0, 3.9 * scale, 2.75 * scale)
	local width, height = 6.6 * scale, 8.4 * scale
	local disk = effectPart("KonPortalVoid", parent)
	disk.Shape = Enum.PartType.Cylinder
	disk.Material = Enum.Material.SmoothPlastic
	disk.Color = Color3.fromRGB(9, 1, 6)
	disk.CFrame = center * CFrame.Angles(0, math.pi / 2, 0)
	disk.Size = Vector3.new(0.08, 0.05, 0.05)
	disk.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 94, 30)
	light.Range = 28
	light.Brightness = 0
	light.Shadows = false
	light.Parent = disk
	local rings = {}
	for i = 1, (if fast then 2 else 3) do
		local ring = ringCopy("KonPortalRim", parent)
		if not ring then break end
		ring.Color = if i == 1 then Color3.fromRGB(255, 203, 126) elseif i == 2 then Color3.fromRGB(255, 71, 24) else Color3.fromRGB(155, 12, 37)
		ring.Transparency = 1
		table.insert(rings, ring)
	end
	-- Fumaca e fagulhas nas bordas, sem emissores permanentes.
	for i = 1, (if fast then 4 else 10) do
		local angle = i * math.pi * 2 / (if fast then 4 else 10)
		local attachment = Instance.new("Attachment")
		attachment.Position = disk.CFrame:PointToObjectSpace(center:PointToWorldSpace(Vector3.new(math.cos(angle) * width * 0.46, math.sin(angle) * height * 0.46, -0.12)))
		attachment.Parent = disk
		local mist = Instance.new("ParticleEmitter")
		mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mist.Color = ColorSequence.new(Color3.fromRGB(99, 23, 30), Color3.fromRGB(23, 12, 24))
		mist.LightEmission = 0.3
		mist.Lifetime = NumberRange.new(0.5, 1.1)
		mist.Speed = NumberRange.new(1, 5)
		mist.SpreadAngle = Vector2.new(180, 180)
		mist.Rotation = NumberRange.new(0, 360)
		mist.RotSpeed = NumberRange.new(-90, 90)
		mist.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.1 * scale), NumberSequenceKeypoint.new(1, 2.9 * scale)})
		mist.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.15, 0.3), NumberSequenceKeypoint.new(1, 1)})
		mist.Rate = 0
		mist.Parent = attachment
		mist:Emit(if fast then 2 else 4)
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 214, 126), Color3.fromRGB(255, 55, 15))
		sparks.LightEmission = 1
		sparks.Lifetime = NumberRange.new(0.3, 0.8)
		sparks.Speed = NumberRange.new(4, 12)
		sparks.Acceleration = Vector3.new(0, 3, 0)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0)})
		sparks.Rate = 0
		sparks.Parent = attachment
		sparks:Emit(if fast then 2 else 6)
	end
	return function(t)
		local opening = smooth(t / 0.18)
		local closing = smooth((t - 1.15) / 0.5)
		local extent = math.max(0.005, opening * (1 - closing))
		disk.Size = Vector3.new(0.08, height * extent, width * extent)
		disk.Transparency = math.max(1 - opening, closing, if seeThrough then 0.82 else 0)
		light.Brightness = 4.5 * opening * (1 - closing)
		for i, ring in rings do
			local pulse = 1 + (i - 1) * 0.055 + math.sin(t * 14 + i) * 0.016
			ring.Size = Vector3.new(width * extent * pulse, height * extent * pulse, 0.05)
			ring.CFrame = center * CFrame.new(0, 0, -0.07 - i * 0.035) * CFrame.Angles(0, 0, math.sin(t * 5 + i) * 0.04)
			ring.Transparency = math.clamp(math.max(1 - opening, closing) + (i - 1) * 0.13 + (if seeThrough then 0.35 else 0), 0, 1)
		end
	end
end
-- Cratera do tamanho da área: rachaduras, pedaços do chão subindo, estilhaços em arco, poeira e onda de choque
local function destruction(position, radius, character, parent, fast, effects)
	local exclusions = {effects}
	local powerEffects = workspace:FindFirstChild("PowerEffects")
	if powerEffects then table.insert(exclusions, powerEffects) end
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then table.insert(exclusions, enemies) end
	if character then table.insert(exclusions, character) end
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(exclusions, player.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -18, 0), params)
	if not hit or hit.Normal.Y < 0.45 then return nil end
	local folder = Instance.new("Folder")
	folder.Name = "KonGroundFracture"
	folder.Parent = parent
	Debris:AddItem(folder, 4.5)
	local normal = hit.Normal
	local tangent = normal:Cross(Vector3.zAxis).Unit
	local across = tangent:Cross(normal).Unit
	local color = if hit.Instance:IsA("Terrain") then workspace.Terrain:GetMaterialColor(hit.Material) else hit.Instance.Color
	local material = hit.Material
	local size = math.clamp(radius / 9, 0.6, 1.6) -- pedaços acompanham o tamanho da área
	local density = math.clamp(radius / 9, 1, 2) -- área maior: mais pedaços, estilhaços e poeira
	-- Buraco escuro no centro
	local hole = effectPart("KonCrater", folder, "Part")
	hole.Shape = Enum.PartType.Cylinder
	hole.Material = Enum.Material.SmoothPlastic
	hole.Color = color:Lerp(Color3.new(0, 0, 0), 0.75)
	hole.Size = Vector3.new(0.05, radius * 0.9, radius * 0.9)
	hole.CFrame = CFrame.new(hit.Position + normal * 0.03) * CFrame.fromMatrix(Vector3.zero, normal, across)
	task.delay(2.4, function()
		if hole.Parent then TweenService:Create(hole, TweenInfo.new(0.9), {Transparency = 1}):Play() end
	end)
	-- Anel de pedaços do chão levantados, inclinados para fora
	local count = math.floor((if fast then 12 else 24) * density)
	for i = 1, count do
		local angle = i / count * math.pi * 2 + random:NextNumber(-0.12, 0.12)
		local radial = tangent * math.cos(angle) + across * math.sin(angle)
		local distance = random:NextNumber(radius * 0.45, radius * 1.05)
		local sample = workspace:Raycast(hit.Position + radial * distance + normal * 4, -normal * 9, params)
		if sample and sample.Normal:Dot(normal) > 0.6 then
			local chunk = effectPart("KonGroundChunk", folder, "WedgePart")
			chunk.Material, chunk.Color = material, color
			chunk.Size = Vector3.new(random:NextNumber(1.4, 3), random:NextNumber(1, 2), random:NextNumber(1.6, 3.4)) * size
			local tilt = random:NextNumber(0.35, 0.8)
			local cf = CFrame.lookAt(sample.Position, sample.Position + radial, sample.Normal) * CFrame.Angles(tilt, random:NextNumber(-0.6, 0.6), random:NextNumber(-0.3, 0.3))
			chunk.CFrame = cf - sample.Normal * 1.8 * size
			TweenService:Create(chunk, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {CFrame = cf + sample.Normal * 0.3 * size}):Play()
			task.delay(1.9 + random:NextNumber(0, 0.6), function()
				if chunk.Parent then TweenService:Create(chunk, TweenInfo.new(0.8), {CFrame = cf - sample.Normal * 2 * size, Transparency = 1}):Play() end
			end)
			local crack = effectPart("KonCrack", folder)
			crack.Material = Enum.Material.SmoothPlastic
			crack.Color = color:Lerp(Color3.new(0, 0, 0), 0.8)
			crack.Size = Vector3.new(random:NextNumber(0.12, 0.26), 0.03, random:NextNumber(2.6, 5.2) * size)
			crack.CFrame = CFrame.lookAt(sample.Position + sample.Normal * 0.03, sample.Position + sample.Normal * 0.03 + radial, sample.Normal)
			task.delay(2.3, function()
				if crack.Parent then TweenService:Create(crack, TweenInfo.new(0.7), {Transparency = 1}):Play() end
			end)
		end
	end
	-- Estilhacos ancorados animados em arco: nao entram na simulacao fisica.
	for i = 1, math.floor((if fast then 7 else 16) * density) do
		local angle = random:NextNumber(0, math.pi * 2)
		local radial = tangent * math.cos(angle) + across * math.sin(angle)
		local shard = effectPart("KonFlyingDebris", folder, "WedgePart")
		shard.Material, shard.Color = material, color
		local shardSize = random:NextNumber(0.35, 1.1) * size
		shard.Size = Vector3.new(shardSize, shardSize * 0.6, shardSize * 1.3)
		shard.CFrame = CFrame.new(hit.Position + radial * 2)
		local summit = hit.Position + radial * random:NextNumber(radius * 0.4, radius * 0.9) + normal * random:NextNumber(4, 9)
		TweenService:Create(shard, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = CFrame.new(summit) * CFrame.Angles(i, i * 2, i)}):Play()
		task.delay(0.28, function()
			if shard.Parent then
				TweenService:Create(shard, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = CFrame.new(summit + radial * 4 - normal * 9) * CFrame.Angles(i * 3, i, 0), Transparency = 1}):Play()
			end
		end)
	end
	-- Onda de choque rente ao chão
	local wave = ringCopy("KonGroundWave", folder)
	if wave then
		wave.Color = Color3.fromRGB(255, 196, 150)
		wave.Transparency = 0.15
		local flat = CFrame.new(hit.Position + normal * 0.25) * CFrame.fromMatrix(Vector3.zero, tangent, across)
		wave.CFrame = flat
		wave.Size = Vector3.new(2, 2, 0.06)
		TweenService:Create(wave, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = Vector3.new(radius * 2.6, radius * 2.6, 0.04), Transparency = 1}):Play()
	end
	local anchor = effectPart("KonDustOrigin", folder)
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = hit.Position + normal * 0.2
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color)
	dust.Lifetime = NumberRange.new(0.8, 1.7)
	dust.Speed = NumberRange.new(10 * size, 24 * size)
	dust.Drag = 5
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2.4 * size), NumberSequenceKeypoint.new(0.4, 6 * size), NumberSequenceKeypoint.new(1, 9 * size)})
	dust.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.4, 0.5), NumberSequenceKeypoint.new(1, 1)})
	dust.Rate = 0
	dust.Parent = anchor
	dust:Emit(math.floor((if fast then 16 else 45) * density))
	return folder
end
-- Pose da cabeça e da mandíbula (graus): abre bem, recua, fecha com tudo no impacto (0,45 s), segura e solta
local keys = {
	{0, 4, 0}, {0.14, -8, -6}, {0.34, -14, -10}, {0.45, 38, 9},
	{0.52, 33, 5}, {0.92, 30, 0}, {1.18, 14, -2}, {1.65, 0, 0},
}
local function pose(time, noShake)
	local jaw, head = 0, 0
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if time <= b[1] then
			local t = math.clamp((time - a[1]) / (b[1] - a[1]), 0, 1)
			t = t * t * (3 - 2 * t)
			jaw, head = a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
			break
		end
	end
	-- Sacode a presa logo depois de fechar (na finalização, a mastigada faz isso)
	local since = time - Config.ImpactDelay
	if not noShake and since > 0 and since < PREY_SHAKE then
		local decay = 1 - since / PREY_SHAKE
		jaw += math.sin(since * 55) * 2.5 * decay
		head += math.sin(since * 47) * 6 * decay
	end
	return math.rad(jaw), math.rad(head)
end
-- Mastigada da finalização: abre devagar e fecha com força (Config.DevourChews vezes); no fim a cabeça sobe para
-- engolir. Devolve abertura (0 a 1), engolida (0 a 1), balanço de lado (-1 a 1) e quantas mordidas já fechou.
local function chewPose(since)
	local u = math.clamp(since / Config.DevourTime, 0, 1)
	if u < CHEW_SHARE then
		local cycle = u / CHEW_SHARE * Config.DevourChews
		local phase = cycle % 1
		local open = if phase < 0.7 then smooth(phase / 0.7) else 1 - smooth((phase - 0.7) / 0.3)
		return open, 0, math.sin(cycle * math.pi * 2), cycle
	end
	return 0, math.sin((u - CHEW_SHARE) / (1 - CHEW_SHARE) * math.pi), 0, Config.DevourChews
end
local function playSound(id, parent, volume, speed)
	if not id or not parent then return nil end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Volume = volume
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = 180
	sound.Parent = parent
	sound:Play()
	return sound
end
-- Esconde o corpo de verdade só neste cliente (o servidor apaga o corpo logo depois)
local function hideBody(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = 1
		elseif item:IsA("BillboardGui") or item:IsA("SurfaceGui") then
			item.Enabled = false
		end
	end
end
-- Cópia local do corpo na pose atual: sem juntas nem scripts, peças ancoradas, para ser puxada até a boca
local function puppetOf(model, parent)
	local archivable = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(function() return model:Clone() end)
	model.Archivable = archivable
	if not ok or not copy then return nil end
	local parts = {}
	for _, item in copy:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide, item.CanQuery, item.CanTouch = false, false, false
			table.insert(parts, item)
		elseif item:IsA("Humanoid") then
			-- Fica só para as roupas aparecerem
			item.EvaluateStateMachine = false
			item.BreakJointsOnDeath = false
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			item.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") or item:IsA("LuaSourceContainer")
			or item:IsA("BillboardGui") or item:IsA("SurfaceGui") or item:IsA("Sound") or item:IsA("ProximityPrompt") then
			item:Destroy()
		end
	end
	if #parts == 0 then
		copy:Destroy()
		return nil
	end
	copy.Parent = parent
	return copy, parts
end
local function smoke(part, scale, fast)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 3.6, 2.6) * scale
	attachment.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(224, 217, 205), Color3.fromRGB(111, 107, 109))
	emitter.LightEmission = 0.15
	emitter.Lifetime = NumberRange.new(0.35, 0.8)
	emitter.Speed = NumberRange.new(2, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-50, 50)
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6.5)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)})
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(if fast then 10 else 26)
	return emitter
end
-- Impacto da mordida: clarão, estouro vermelho e anéis de pressão na direção do bote
local function impact(position, look, radius, parent, fast)
	local flash = effectPart("KonBiteFlash", parent)
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 232, 214)
	flash.Transparency = 0.05
	flash.Size = Vector3.one * 2
	flash.Position = position
	TweenService:Create(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.one * radius * 1.3, Transparency = 1}):Play()
	Debris:AddItem(flash, 0.3)
	local anchor = effectPart("KonBloodOrigin", parent)
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	local blood = Instance.new("ParticleEmitter")
	blood.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	blood.Color = ColorSequence.new(Color3.fromRGB(190, 12, 22), Color3.fromRGB(70, 0, 6))
	blood.LightEmission = 0.2
	blood.Lifetime = NumberRange.new(0.35, 0.8)
	blood.Speed = NumberRange.new(18, 38)
	blood.Acceleration = Vector3.new(0, -40, 0)
	blood.SpreadAngle = Vector2.new(70, 70)
	blood.EmissionDirection = Enum.NormalId.Top
	blood.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0.1)})
	blood.Rate = 0
	blood.Parent = anchor
	blood:Emit(math.floor((if fast then 18 else 42) * math.clamp(radius / 9, 1, 2)))
	Debris:AddItem(anchor, 1.2)
	for i = 1, (if fast then 2 else 3) do
		local ring = ringCopy("KonPressureRing", parent)
		if not ring then break end
		ring.Color = if i == 1 then Color3.fromRGB(255, 238, 198) elseif i == 2 then Color3.fromRGB(255, 126, 35) else Color3.fromRGB(200, 20, 30)
		ring.Transparency = 0.1
		ring.Size = Vector3.new(2, 2, 0.06)
		ring.CFrame = CFrame.lookAt(position, position + look) * CFrame.new(0, 0, -0.2 * i)
		local final = radius * 2 + i * 4
		TweenService:Create(ring, TweenInfo.new(0.3 + i * 0.06, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = Vector3.new(final, final, 0.04), Transparency = 1}):Play()
		Debris:AddItem(ring, 0.6)
	end
end
-- Tremida de câmera e flash de contraste para quem está perto (mais fraco com a distância)
-- quiet: só a tremida, sem o flash (mordidas da mastigada)
local function cameraKick(position, strength, quiet)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local distance = (camera.CFrame.Position - position).Magnitude
	local falloff = 1 - math.clamp((distance - 15) / SHAKE_RANGE, 0, 1)
	if falloff <= 0 then return end
	if not quiet then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "KonImpactFlash"
		grade.TintColor = Color3.fromRGB(255, 205, 195)
		grade.Brightness = 0.15 * falloff
		grade.Contrast = 0.45 * falloff
		grade.Saturation = -0.35 * falloff
		grade.Parent = camera
		TweenService:Create(grade, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0, Saturation = 0}):Play()
		Debris:AddItem(grade, 0.4)
	end
	local power = strength * falloff
	local bindName = "KonShake" .. tostring(random:NextInteger(1, 1e9))
	local started = os.clock()
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local elapsed = os.clock() - started
		if elapsed > SHAKE_TIME then
			RunService:UnbindFromRenderStep(bindName)
			return
		end
		local amount = power * (1 - elapsed / SHAKE_TIME) ^ 2
		camera.CFrame *= CFrame.new(random:NextNumber(-1, 1) * amount * 0.4, random:NextNumber(-1, 1) * amount * 0.4, 0)
			* CFrame.Angles(0, 0, random:NextNumber(-1, 1) * amount * 0.025)
	end)
end
function VFX.Play(data, fast)
	if typeof(data.Position) ~= "Vector3" or typeof(data.Look) ~= "Vector3" then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - data.Position).Magnitude > (if fast then 150 else 260) then return end
	if #active >= 5 then active[1].Cancel() end
	local assets = ReplicatedStorage:FindFirstChild("VFX")
	local template = assets and assets:FindFirstChild("FoxDevil")
	if not template then return end
	local look = Vector3.new(data.Look.X, 0, data.Look.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	-- data.Scale / data.Small: versão menor (Kon! da fusão com os Punhos), sem cratera e com tremida leve
	local scale = if type(data.Scale) == "number" and data.Scale > 0 then data.Scale else Config.Scale
	local radius = if type(data.Radius) == "number" and data.Radius > 0 then data.Radius else Config.ImpactRadius
	local base = CFrame.lookAt(data.Position, data.Position + look) * CFrame.new(0, -2.6 * scale, 2.6 * scale)
	local parent = workspace:FindFirstChild("PowerEffects") or workspace
	local lifetime = Config.Duration + Config.DevourTime -- a finalização estica o efeito
	local folder = Instance.new("Folder")
	folder.Name = "KonSummon"
	folder.Parent = parent
	Debris:AddItem(folder, lifetime + 1)
	local model = template:Clone()
	model.Name = "KonBite"
	model:ScaleTo(scale)
	model:PivotTo(base)
	local parts, heads, jaws = {}, {}, {}
	for _, object in model:GetDescendants() do
		if object:IsA("MeshPart") then
			object.Transparency = 1
			table.insert(parts, object)
		elseif object:IsA("Bone") then
			if object.Name == "Head" then table.insert(heads, object)
			elseif object.Name == "Jaw" then table.insert(jaws, object) end
		end
	end
	model.Parent = folder
	local localCharacter = Players.LocalPlayer and Players.LocalPlayer.Character
	local updatePortal = portal(base, scale, folder, fast, data.Small == true and data.Character == localCharacter)
	local emitter = smoke(model.PrimaryPart, scale, fast)
	local started = data.StartTime or workspace:GetServerTimeNow()
	local state = {Model = model, Character = data.Character, StartTime = started}
	local connection, ended, struck, fracture, devour
	function state.Cancel(completed)
		if ended then return end
		ended = true
		if connection then connection:Disconnect() end
		local index = table.find(active, state)
		if index then table.remove(active, index) end
		folder:Destroy()
		if fracture and not completed then fracture:Destroy() end
	end
	table.insert(active, state)
	-- Frame da cabeça (osso Head, já com a inclinação do momento): os pontos da boca são medidos nele
	local function headFrame()
		local bone = heads[1]
		return if bone then bone.TransformedWorldCFrame else model:GetPivot()
	end
	-- Finalização confirmada pelo servidor: a animação base para em devour.At e as presas vão para a boca
	function state.Devour(targets, fastDevour)
		if devour or ended then return end
		local now = workspace:GetServerTimeNow() - started
		local at = math.clamp(now, Config.ImpactDelay + 0.02, 1.05)
		local jaw, head = pose(at, true)
		local mouth = Instance.new("Attachment")
		mouth.Name = "KonMouth"
		mouth.Position = MOUTH_CENTER * scale
		mouth.Parent = model.PrimaryPart
		devour = {At = at, Jaw = jaw, Head = head, Fast = fastDevour, Mouth = mouth, Puppets = {}, Chomps = 0}
		local mouthPosition = headFrame() * (MOUTH_CENTER * scale)
		for _, entry in targets do
			if type(entry) ~= "table" then continue end
			local victim = entry.Model
			local position = entry.Position
			if typeof(victim) == "Instance" and victim:IsA("Model") and victim.Parent then
				local root = victim:FindFirstChild("HumanoidRootPart") or victim.PrimaryPart
				if root and root:IsA("BasePart") then position = root.Position end
				local copy, copyParts = puppetOf(victim, folder)
				hideBody(victim)
				if copy and typeof(position) == "Vector3" then
					local center = CFrame.new(position)
					local relative = {}
					for i, part in copyParts do relative[i] = center:ToObjectSpace(part.CFrame) end
					local distance = (mouthPosition - position).Magnitude
					table.insert(devour.Puppets, {
						Model = copy, Parts = copyParts, Relative = relative, From = position,
						Axis = random:NextUnitVector(), Start = now,
						Duration = math.clamp(distance / 45, 0.14, 0.3), Arc = math.clamp(distance * 0.3, 1, 4),
					})
				end
			end
			if typeof(position) == "Vector3" then
				-- O corpo estoura em sangue ao ser arrancado do chão
				BloodFX.Burst(position + Vector3.new(0, 1, 0), Vector3.yAxis, {Amount = 22, Speed = {18, 38}, Spread = 65, Fast = fastDevour})
			end
		end
		playSound(Config.DevourSounds.Grab, mouth, 1.3, random:NextNumber(0.9, 1))
	end
	local function devourStep(t, since)
		local fastDevour = devour.Fast
		local frame = headFrame()
		local mouth = frame * (MOUTH_CENTER * scale)
		-- Presas voando em arco até a boca, girando; ao chegar somem num estouro de sangue
		for i = #devour.Puppets, 1, -1 do
			local puppet = devour.Puppets[i]
			local u = math.clamp((t - puppet.Start) / puppet.Duration, 0, 1)
			local eased = u * u
			local position = puppet.From:Lerp(mouth, eased) + Vector3.new(0, math.sin(u * math.pi) * puppet.Arc, 0)
			local center = CFrame.new(position) * CFrame.fromAxisAngle(puppet.Axis, eased * math.pi * 1.4)
			local frames = table.create(#puppet.Parts)
			for k, relative in puppet.Relative do frames[k] = center * relative end
			workspace:BulkMoveTo(puppet.Parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			if u >= 1 then
				puppet.Model:Destroy()
				table.remove(devour.Puppets, i)
				BloodFX.Burst(mouth, Vector3.yAxis + frame.LookVector * 0.4, {Amount = 26, Speed = {16, 34}, Spread = 75, Fast = fastDevour})
				if not devour.Splatted then
					devour.Splatted = true
					playSound(Config.DevourSounds.Splat, devour.Mouth, 1.1, random:NextNumber(0.95, 1.05))
				end
			end
		end
		if since <= 0 then return end
		-- Cada mordida da mastigada: sangue pelos cantos da boca, baba pelo lábio e um tranco na câmera
		local _, _, _, cycle = chewPose(since)
		while devour.Chomps < math.floor(cycle) do
			devour.Chomps += 1
			for _, side in {1, -1} do
				local corner = frame * (Vector3.new(MOUTH_CORNER.X * side, MOUTH_CORNER.Y, MOUTH_CORNER.Z) * scale)
				local outward = frame.RightVector * side * 0.8 + frame.LookVector * 0.35 - Vector3.yAxis * 0.25
				BloodFX.Burst(corner, outward, {Amount = 7, Speed = {8, 20}, Spread = 30, Size = {0.16, 0.36}, Mist = 2, Fast = fastDevour})
			end
			BloodFX.Drip(frame * (MOUTH_LIP * scale), 3, fastDevour)
			cameraKick(mouth, 0.45, true)
			if devour.Chomps == 1 then
				devour.Chew = playSound(Config.DevourSounds.Chew, devour.Mouth, 1.5, random:NextNumber(0.95, 1.05))
			end
		end
		-- Engolindo: a mastigada para de soar e a baba cai uma última vez
		if not devour.Swallowed and since >= Config.DevourTime * CHEW_SHARE then
			devour.Swallowed = true
			BloodFX.Drip(frame * (MOUTH_LIP * scale), 4, fastDevour)
			if devour.Chew then
				TweenService:Create(devour.Chew, TweenInfo.new(0.3), {Volume = 0}):Play()
			end
		end
	end
	connection = RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow() - started
		-- Na finalização a animação base fica parada em devour.At enquanto o Kon mastiga, e depois segue
		local te, since = t, 0
		if devour then
			since = t - devour.At
			if since > 0 then te = devour.At + math.max(0, since - Config.DevourTime) end
		end
		if te >= Config.Duration then state.Cancel(true); return end
		if not model.Parent then state.Cancel(); return end
		-- Quem invocou sumiu, ou foi atordoado antes da mordida: a raposa some junto
		if data.Character and (not data.Character.Parent or (not struck and data.Character:GetAttribute("Stunned") == true)) then state.Cancel(); return end
		local jaw, head = pose(math.max(0, te), devour ~= nil)
		local lift, yaw = 0, 0
		if devour and since > 0 then
			if since < Config.DevourTime then
				local open, gulp, grind = chewPose(since)
				jaw = devour.Jaw - math.rad(22) * open
				head = devour.Head - math.rad(9) * open - math.rad(16) * gulp
				lift = scale * (0.12 * open + 0.2 * gulp)
				yaw = math.rad(4) * grind
			else
				jaw = math.max(jaw, devour.Jaw) -- engoliu: a boca fica fechada até sumir no portal
			end
		elseif not devour then
			local shake = te - Config.ImpactDelay
			if shake > 0 and shake < PREY_SHAKE then
				yaw = math.sin(shake * 40) * math.rad(5) * (1 - shake / PREY_SHAKE)
			end
		end
		updatePortal(te)
		local emerge = smooth(te / Config.PortalEmergence)
		local retreat = smooth((te - 1.2) / 0.5)
		-- Bote: recua um pouco antes e avança com tudo no impacto
		local windup = smooth((te - 0.14) / 0.2) * (1 - smooth((te - 0.34) / 0.08))
		local lunge = smooth((te - 0.34) / 0.11) * (1 - smooth((te - 0.6) / 0.45))
		local offset = 2.7 * (1 - emerge) + 1.5 * retreat + 0.5 * windup - 1.3 * lunge
		model:PivotTo(base * CFrame.new(0, lift, scale * offset) * CFrame.Angles(0, yaw, 0))
		for _, bone in heads do bone.Transform = CFrame.Angles(head, 0, 0) end
		for _, bone in jaws do bone.Transform = CFrame.Angles(jaw, 0, 0) end
		local alpha = math.max(1 - smooth((te - 0.06) / 0.15), retreat)
		for _, part in parts do part.Transparency = alpha end
		if not struck and t >= Config.ImpactDelay then
			struck = true
			impact(data.Position, look, radius, folder, fast)
			if not data.Small then
				fracture = destruction(data.Position, radius, data.Character, parent, fast, folder)
			end
			emitter:Emit(if fast then 6 else 18)
			cameraKick(data.Position, if data.Small then 0.5 elseif fast then 1.1 else 1.6, data.Small == true)
		end
		if devour then devourStep(t, since) end
	end)
	Debris:AddItem(model, lifetime + 0.5)
	return state
end
-- O servidor confirmou a finalização (CombatFX "FoxDevour"): a raposa da mesma invocação engole as presas.
-- Sem a raposa neste cliente (estava longe quando ela saiu), o corpo só some num estouro de sangue.
function VFX.Devour(data, fast)
	if type(data.Targets) ~= "table" then return end
	for _, state in active do
		if state.StartTime == data.StartTime and state.Character == data.Character then
			state.Devour(data.Targets, fast)
			return
		end
	end
	local camera = workspace.CurrentCamera
	for _, entry in data.Targets do
		if type(entry) ~= "table" then continue end
		if typeof(entry.Model) == "Instance" and entry.Model:IsA("Model") then hideBody(entry.Model) end
		local position = entry.Position
		if typeof(position) == "Vector3" and camera and (camera.CFrame.Position - position).Magnitude < 200 then
			BloodFX.Burst(position + Vector3.new(0, 1, 0), Vector3.yAxis, {Amount = 22, Speed = {18, 38}, Spread = 65, Fast = fast})
		end
	end
end
-- Bote da Raposa (CombatFX "FoxLunge"): o portal abre atrás de quem invocou, a cabeça sai de boca aberta, corre em
-- linha reta até data.Finish rasgando o chão, fecha a mordida com tudo e some em fumaça.
function VFX.Lunge(data, fast)
	if typeof(data.Start) ~= "Vector3" or typeof(data.Finish) ~= "Vector3" then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - data.Start).Magnitude > (if fast then 150 else 260) then return end
	if #active >= 5 then active[1].Cancel() end
	local assets = ReplicatedStorage:FindFirstChild("VFX")
	local template = assets and assets:FindFirstChild("FoxDevil")
	if not template then return end
	local offset = data.Finish - data.Start
	local look = Vector3.new(offset.X, 0, offset.Z)
	if look.Magnitude < 0.5 then return end
	local distance = look.Magnitude
	look = look.Unit
	local scale = Config.LungeScale
	local behind = Config.LungeBehind
	local origin = data.Start - look * behind
	local function pivotAt(point)
		return CFrame.lookAt(point, point + look) * CFrame.new(0, -2.6 * scale, 2.6 * scale)
	end
	local parent = workspace:FindFirstChild("PowerEffects") or workspace
	local lifetime = Config.LungeDelay + Config.LungeTime + Config.LungeFade + 0.6
	local folder = Instance.new("Folder")
	folder.Name = "KonLunge"
	folder.Parent = parent
	Debris:AddItem(folder, lifetime + 1)
	local model = template:Clone()
	model.Name = "KonLungeHead"
	model:ScaleTo(scale)
	model:PivotTo(pivotAt(origin) * CFrame.new(0, 0, 2.7 * scale))
	local parts, heads, jaws = {}, {}, {}
	for _, object in model:GetDescendants() do
		if object:IsA("MeshPart") then
			object.Transparency = 1
			table.insert(parts, object)
		elseif object:IsA("Bone") then
			if object.Name == "Head" then table.insert(heads, object)
			elseif object.Name == "Jaw" then table.insert(jaws, object) end
		end
	end
	model.Parent = folder
	local updatePortal = portal(pivotAt(origin), scale, folder, fast)
	local emitter = smoke(model.PrimaryPart, scale, fast)
	-- Poeira rente ao chão acompanhando a cabeça
	local dustAnchor = effectPart("KonLungeDust", folder)
	dustAnchor.Transparency = 1
	dustAnchor.Size = Vector3.one
	dustAnchor.Position = origin
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(196, 186, 170), Color3.fromRGB(120, 112, 104))
	dust.Lifetime = NumberRange.new(0.5, 1.1)
	dust.Speed = NumberRange.new(4, 10)
	dust.Drag = 4
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Rotation = NumberRange.new(0, 360)
	dust.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 5)})
	dust.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)})
	dust.Rate = 0
	dust.Parent = dustAnchor
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { folder }
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(exclude, other.Character) end
	end
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then table.insert(exclude, enemies) end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local ground = workspace:Raycast(data.Start + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	local groundY = if ground then ground.Position.Y + 0.2 else data.Start.Y - 3

	local started = data.StartTime or workspace:GetServerTimeNow()
	local travelEnd = Config.LungeDelay + Config.LungeTime
	local state = {Model = model, Character = data.Character, StartTime = started}
	local connection, ended, bitten, lastDust
	function state.Cancel()
		if ended then return end
		ended = true
		if connection then connection:Disconnect() end
		local index = table.find(active, state)
		if index then table.remove(active, index) end
		folder:Destroy()
	end
	table.insert(active, state)
	connection = RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow() - started
		if t >= lifetime then state.Cancel(); return end
		if not model.Parent then state.Cancel(); return end
		updatePortal(t)
		local jaw, head, pivot
		if t < Config.LungeDelay then
			-- Saindo do portal e abrindo a boca
			local emerge = smooth(t / Config.LungeDelay)
			pivot = pivotAt(origin) * CFrame.new(0, 0, 2.7 * scale * (1 - emerge))
			jaw, head = math.rad(-18 * emerge), math.rad(-6 * emerge)
		elseif t < travelEnd then
			-- Correndo pelo caminho de boca bem aberta, com um leve balanço
			local u = (t - Config.LungeDelay) / Config.LungeTime
			local point = origin + look * (distance + behind) * u
			pivot = pivotAt(point) * CFrame.Angles(0, 0, math.sin(t * 30) * math.rad(3))
			jaw, head = math.rad(-20), math.rad(-8)
			dustAnchor.Position = Vector3.new(point.X, groundY, point.Z)
			if not lastDust or t - lastDust > 0.04 then
				lastDust = t
				dust:Emit(if fast then 1 else 3)
			end
		else
			-- Mordida no fim, sacudindo a presa, e some
			local since = t - travelEnd
			local point = origin + look * (distance + behind)
			local shake = if since < 0.35 then math.sin(since * 50) * math.rad(5) * (1 - since / 0.35) else 0
			pivot = pivotAt(point) * CFrame.Angles(0, shake, 0)
			jaw = math.rad(-20 + 58 * smooth(since / 0.08))
			head = math.rad(6 * smooth(since / 0.08))
			if not bitten then
				bitten = true
				local mouth = (pivotAt(point) * CFrame.new(0, 3 * scale, -2.45 * scale)).Position
				impact(mouth, look, 6, folder, fast)
				BloodFX.Burst(mouth, Vector3.yAxis + look * 0.5, {Amount = 18, Speed = {14, 30}, Spread = 70, Fast = fast})
				emitter:Emit(if fast then 4 else 12)
				cameraKick(mouth, if fast then 0.6 else 0.9, true)
				playSound(Config.DevourSounds.Splat, model.PrimaryPart, 0.9, random:NextNumber(1, 1.1))
			end
		end
		model:PivotTo(pivot)
		for _, bone in heads do bone.Transform = CFrame.Angles(head, 0, 0) end
		for _, bone in jaws do bone.Transform = CFrame.Angles(jaw, 0, 0) end
		local appear = 1 - smooth(t / 0.15)
		local fade = smooth((t - travelEnd - 0.2) / Config.LungeFade)
		for _, part in parts do part.Transparency = math.max(appear, fade) end
	end)
	Debris:AddItem(model, lifetime + 0.5)
	return state
end

-- Alguém foi pego pelo bote (CombatFX "FoxLungeCatch"): sangue e o barulho da pegada
function VFX.LungeCatch(data, fast)
	if typeof(data.Position) ~= "Vector3" then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - data.Position).Magnitude > 200 then return end
	local look = if typeof(data.Look) == "Vector3" then data.Look else Vector3.zero
	BloodFX.Burst(data.Position, Vector3.yAxis + look, {Amount = 12, Speed = {12, 26}, Spread = 60, Fast = fast})
	local anchor = effectPart("KonLungeCatch", workspace:FindFirstChild("PowerEffects") or workspace)
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = data.Position
	playSound(Config.DevourSounds.Grab, anchor, 0.8, random:NextNumber(1.05, 1.15))
	Debris:AddItem(anchor, 3)
end
return VFX
