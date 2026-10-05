-- Efeitos visuais do combate para todos os personagens (o servidor avisa pelo Remotes.CombatFX).
-- O corpo só se mexe pelas animações (CombatStyles.Animations): as poses antigas feitas por código, no C0 dos ombros,
-- saíram em 2026-09-30.
-- Efeitos: só Parts locais (Neon, Ball, Cylinder), Tweens, Highlight e BillboardGui, sem asset ids.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
-- Com o Fast Mode ligado: sem faíscas, anéis nem brilho no personagem (o impacto e os textos continuam)
local FastMode = require(script.Parent:WaitForChild("FastMode"))
local BloodFX = require(ReplicatedStorage:WaitForChild("BloodFX"))

local player = Players.LocalPlayer
local rng = Random.new()

local WHITE = Color3.fromRGB(255, 255, 255)
local BLOCK_COLOR = Color3.fromRGB(140, 200, 255)
local PARRY_COLOR = Color3.fromRGB(255, 220, 90)
local BREAK_COLOR = Color3.fromRGB(255, 80, 40)

-- Pasta dos efeitos locais (outros scripts de efeito, como o BloodFiendVFX, usam a mesma)
local fxFolder = workspace:FindFirstChild("CombatFX")
if not fxFolder then
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "CombatFX"
	fxFolder.Parent = workspace
end

local function tween(instance, time, props, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Estilo do evento. Quem tem a fusão do contrato com esse estilo (CombatStyles.Resolve) recebe o estilo fundido, com o
-- Theme do contrato: vale para o efeito previsto aqui e para o que chega do servidor (a fusão sai do atacante).
local function styleOf(data)
	if not data or type(data.Style) ~= "string" then return nil end
	local base = CombatStyles.Styles[data.Style]
	if not base then return nil end
	local fighter = if typeof(data.Attacker) == "Instance" then data.Attacker elseif typeof(data.Character) == "Instance" then data.Character else nil
	return (fighter and CombatStyles.Resolve(fighter, data.Style)) or base
end

-- Para sons e hitstop: o estilo do evento ou, sem ele (guarda, parry), os Punhos
local function styleOrDefault(data)
	return styleOf(data) or CombatStyles.Styles.Punhos
end

-- ================= Som =================

-- Um Sound modelo por ID, pré-carregado assim que o script começa. Cada golpe toca uma cópia de um som já
-- carregado, que sai na hora (criar um Sound novo por golpe fazia o áudio carregar na hora: atraso e travadas).
local soundTemplates = {}
local function soundTemplate(soundId)
	local template = soundTemplates[soundId]
	if not template then
		template = Instance.new("Sound")
		template.SoundId = soundId
		template.Volume = 0.8
		template.RollOffMaxDistance = 90
		soundTemplates[soundId] = template
	end
	return template
end

task.spawn(function()
	local list = {}
	for _, style in CombatStyles.Styles do
		for name in style.Sounds or {} do
			for index = 1, CombatStyles.SoundCount(style, name) do
				local soundId = CombatStyles.Sound(style, name, index)
				if soundId then
					table.insert(list, soundTemplate(soundId))
				end
			end
		end
	end
	if #list > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end
end)

-- Som com variações: cada toque usa a próxima da lista
local soundTurns = {}
local function playSound(data, name, at)
	local style = styleOrDefault(data)
	local key = tostring(data and data.Style) .. name
	soundTurns[key] = (soundTurns[key] or 0) + 1
	local soundId = CombatStyles.Sound(style, name, soundTurns[key])
	if not soundId or typeof(at) ~= "Instance" or not at:IsA("BasePart") then return end
	local sound = soundTemplate(soundId):Clone()
	sound.PlaybackSpeed = 0.96 + math.random() * 0.08
	sound.Parent = at
	sound:Play()
	Debris:AddItem(sound, math.max(3, sound.TimeLength + 0.5))
end

-- ================= Hitstop =================
-- Congela por um instante as animações de ação de quem bateu e de quem apanhou (só neste cliente)

local HITSTOP_PRIORITIES = {
	[Enum.AnimationPriority.Action] = true,
	[Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true,
	[Enum.AnimationPriority.Action4] = true,
}
local frozen = setmetatable({}, { __mode = "k" }) -- [track] = velocidade antes de congelar

-- Animação já parada (pose do soco carregado segurando o R) fica de fora: guardar a velocidade 0 dela e devolver
-- depois congelava o soco se o R fosse solto durante a pausa. Pelo mesmo motivo, só devolve a velocidade se
-- ninguém mexeu nela enquanto estava congelada.
local function hitstop(characters, duration)
	if duration <= 0 then return end
	local paused = {}
	for _, character in characters do
		local humanoid = typeof(character) == "Instance" and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				if HITSTOP_PRIORITIES[track.Priority] and frozen[track] == nil and track.Speed ~= 0 then
					frozen[track] = track.Speed
					track:AdjustSpeed(0)
					table.insert(paused, track)
				end
			end
		end
	end
	if #paused == 0 then return end
	task.delay(duration, function()
		for _, track in paused do
			local speed = frozen[track]
			frozen[track] = nil
			if speed and track.IsPlaying and track.Speed == 0 then
				track:AdjustSpeed(speed)
			end
		end
	end)
end

local function styleColor(data)
	local style = styleOf(data)
	return if style and style.Color then style.Color else Color3.fromRGB(255, 170, 60)
end

local function rootOf(character)
	return typeof(character) == "Instance" and character.Parent and character:FindFirstChild("HumanoidRootPart") or nil
end

local function flatLook(root)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.001 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Ação em andamento de cada personagem (guarda, carga, rajada): a rajada usa para saber quando parar o efeito
local heldPose = setmetatable({}, { __mode = "k" })

-- ================= Peças de efeito =================

local function newPart(shape, color, cframe, size)
	local part = Instance.new("Part")
	part.Shape = shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Parent = fxFolder
	return part
end

local function burst(position, color, size, time)
	local ball = newPart(Enum.PartType.Ball, color, CFrame.new(position), Vector3.one * size * 0.3)
	ball.Transparency = 0.1
	tween(ball, time, { Size = Vector3.one * size, Transparency = 1 })
	Debris:AddItem(ball, time + 0.05)
end

-- Anel achatado virado para "direction"
local function ring(position, direction, color, size, time)
	if FastMode.IsEnabled() then return end
	local cframe = CFrame.lookAt(position, position + direction) * CFrame.Angles(0, math.rad(90), 0)
	local disc = newPart(Enum.PartType.Cylinder, color, cframe, Vector3.new(0.12, size * 0.3, size * 0.3))
	disc.Transparency = 0.25
	tween(disc, time, { Size = Vector3.new(0.05, size, size), Transparency = 1 })
	Debris:AddItem(disc, time + 0.05)
end

local function sparks(position, color, count, speed)
	if FastMode.IsEnabled() then return end
	for _ = 1, count do
		local direction = rng:NextUnitVector()
		local spark = newPart(Enum.PartType.Block, color, CFrame.lookAt(position, position + direction), Vector3.new(0.12, 0.12, 0.7))
		local time = rng:NextNumber(0.15, 0.3)
		tween(spark, time, {
			CFrame = CFrame.lookAt(position + direction * speed * time, position + direction * (speed * time + 1)),
			Size = Vector3.new(0.04, 0.04, 0.2),
			Transparency = 1,
		})
		Debris:AddItem(spark, time + 0.05)
	end
end

local function flash(character, color, time)
	if FastMode.IsEnabled() then return end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = fxFolder
	tween(highlight, time, { FillTransparency = 1 })
	Debris:AddItem(highlight, time + 0.05)
end

local function floatText(character, text, color)
	local head = character:FindFirstChild("Head") or rootOf(character)
	if not head then return end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	-- Sem AlwaysOnTop: no Studio o texto com AlwaysOnTop não aparecia (as barras dos inimigos, sem ele, aparecem)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = UITheme.Fonts.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = fxFolder
	tween(gui, 0.8, { StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0) })
	task.delay(0.35, function()
		tween(label, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(gui, 0.85)
end

-- Tremida rápida da câmera de quem participou do golpe forte
local function shake(strength)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	task.spawn(function()
		for i = 1, 6 do
			local fade = 1 - (i - 1) / 6
			humanoid.CameraOffset = rng:NextUnitVector() * strength * fade
			task.wait(0.025)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

-- Ponto de impacto: na frente da vítima, virado para quem atacou
local function impactPoint(victim, attacker)
	local victimRoot = rootOf(victim)
	if not victimRoot then return nil end
	local attackerRoot = rootOf(attacker)
	local toward = if attackerRoot then attackerRoot.Position - victimRoot.Position else victimRoot.CFrame.LookVector
	toward = Vector3.new(toward.X, 0, toward.Z)
	toward = if toward.Magnitude > 0.01 then toward.Unit else Vector3.new(0, 0, -1)
	return victimRoot.Position + toward * 1.2 + Vector3.new(0, 0.6, 0), toward
end

-- ================= Guarda e carga (efeitos presos ao personagem) =================

local attached = setmetatable({}, { __mode = "k" }) -- [character] = { [nome] = { Parts, Connection } }

local function clearAttached(character, name)
	local list = attached[character]
	local entry = list and list[name]
	if not entry then return end
	list[name] = nil
	if entry.Connection then
		entry.Connection:Disconnect()
	end
	for _, part in entry.Parts do
		tween(part, 0.15, { Transparency = 1 })
		Debris:AddItem(part, 0.2)
	end
end

local function attach(character, name, parts, update)
	clearAttached(character, name)
	attached[character] = attached[character] or {}
	local entry = { Parts = parts }
	entry.Connection = RunService.RenderStepped:Connect(function(dt)
		if not character.Parent or not rootOf(character) then
			clearAttached(character, name)
			return
		end
		update(dt)
	end)
	attached[character][name] = entry
end

local function handPosition(character)
	local hand = character:FindFirstChild("RightHand")
	if hand then return hand.Position end
	local arm = character:FindFirstChild("Right Arm")
	if arm then return (arm.CFrame * CFrame.new(0, -1, 0)).Position end
	local root = rootOf(character)
	return root and root.Position or Vector3.zero
end

local function startBlock(character)
	heldPose[character] = "Block"

	local shield = newPart(
		Enum.PartType.Cylinder,
		BLOCK_COLOR,
		CFrame.new(),
		Vector3.new(0.08, 4.2, 4.2)
	)

	shield.Transparency = 0.8

	attach(character, "Block", { shield }, function()
		local root = rootOf(character)
		if not root then return end

		local look = flatLook(root)
		local position = root.Position + look * 1.6 + Vector3.new(0, 0.6, 0)

		shield.CFrame =
			CFrame.lookAt(position, position + look)
			* CFrame.Angles(0, math.rad(90), 0)
	end)
end

local function endBlock(character)
	if heldPose[character] == "Block" then
		heldPose[character] = nil
	end
	clearAttached(character, "Block")
end

-- ================= VFX modelados (ReplicatedStorage.VFX.Punchs) =================
-- ChargedPunch: malhas estáticas (Charge_Orbit, Release_Pressure, Impact_Circle, Impact_ShockRing, Ground_*),
-- movidas aqui por código. BarragePunch: emissores de partícula no padrão dos pacotes de VFX (atributos
-- EmitDelay, EmitCount, EmitDuration). Sem a pasta, os efeitos simples antigos continuam funcionando.

-- Onde fica a raiz do atacante dentro do modelo ChargedPunch (o modelo aponta para +Z). Se o efeito sair
-- deslocado do punho, ajuste aqui.
local CHARGED_ORIGIN = Vector3.new(-1.03, 0.54, 0)
local CHARGED_GROUND_DROP = 3 -- chão do modelo fica 3 studs abaixo da raiz (altura do HumanoidRootPart do R6)
local CHARGED_SCALE = 2.2 -- tamanho do efeito do soco carregado (1 = tamanho do modelo)
local CHARGED_ORBIT_SCALE = 1.5 -- órbitas na mão durante a carga
local NEON_WHITE = Color3.fromRGB(255, 250, 240)
local INK = Color3.fromRGB(14, 12, 14)
local CRACK_COLOR = Color3.fromRGB(22, 18, 18)

local function vfxTemplate(name)
	local folder = ReplicatedStorage:FindFirstChild("VFX")
	folder = folder and folder:FindFirstChild("Punchs")
	return folder and folder:FindFirstChild(name)
end

-- Peças do ChargedPunch por grupo ("Charge_Orbit", "Ground_Crack"...), já em relação à raiz do atacante
-- (frente = -Z, como no Roblox)
local chargedPieces
local function getChargedPieces()
	if chargedPieces then return chargedPieces end
	local model = vfxTemplate("ChargedPunch")
	if not model or not model:IsA("Model") then return nil end
	local pivot = model:GetPivot()
	local toAttacker = CFrame.Angles(0, math.pi, 0) * CFrame.new(-CHARGED_ORIGIN)
	local groups = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local group = part.Name:match("^VFX_(%a+_%a+)") or "Other"
			groups[group] = groups[group] or {}
			table.insert(groups[group], {
				Template = part,
				Name = part.Name,
				Rel = toAttacker * pivot:ToObjectSpace(part.CFrame),
				Size = part.Size,
			})
		end
	end

	-- Tamanho do efeito: CHARGED_SCALE vezes maior, crescendo a partir do punho (onde ficam as órbitas da carga),
	-- para o disparo continuar saindo da mão e o impacto ficar logo à frente. O chão cresce em volta da cratera,
	-- que fica embaixo dos círculos do impacto e no nível do chão. As órbitas crescem menos.
	local fist, orbitCount = Vector3.zero, 0
	for _, piece in groups.Charge_Orbit or {} do
		fist += piece.Rel.Position
		orbitCount += 1
	end
	fist = if orbitCount > 0 then fist / orbitCount else Vector3.new(0, 0.2, -2.2)

	for group, pieces in groups do
		for _, piece in pieces do
			if group == "Charge_Orbit" then
				piece.Size *= CHARGED_ORBIT_SCALE
			elseif string.sub(group, 1, 7) ~= "Ground_" then
				piece.Rel = CFrame.new(fist + (piece.Rel.Position - fist) * CHARGED_SCALE) * piece.Rel.Rotation
				piece.Size *= CHARGED_SCALE
			end
		end
	end

	local crater = groups.Ground_CraterInterior and groups.Ground_CraterInterior[1]
	local center = if crater then crater.Rel.Position else Vector3.new(0, -CHARGED_GROUND_DROP, -5.6)
	local impactZ, circleCount = 0, 0
	for _, piece in groups.Impact_Circle or {} do
		impactZ += piece.Rel.Position.Z
		circleCount += 1
	end
	local newCenter = Vector3.new(center.X, center.Y, if circleCount > 0 then impactZ / circleCount else center.Z)
	for group, pieces in groups do
		if string.sub(group, 1, 7) == "Ground_" then
			for _, piece in pieces do
				local offset = piece.Rel.Position - center
				local position = newCenter + Vector3.new(offset.X * CHARGED_SCALE, offset.Y, offset.Z * CHARGED_SCALE)
				piece.Rel = CFrame.new(position) * piece.Rel.Rotation
				piece.Size *= CHARGED_SCALE
			end
		end
	end

	chargedPieces = groups
	return groups
end

local function spawnPiece(piece, cframe, size, color, material, transparency)
	local part = piece.Template:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = cframe
	part.Size = size
	if color then
		part.Color = color
	end
	if material then
		part.Material = material
	end
	part.Transparency = transparency or 0
	part.Parent = fxFolder
	return part
end

-- Referência do golpe: na raiz, olhando para a frente (sem inclinar)
local function attackFrame(root)
	return CFrame.lookAt(root.Position, root.Position + flatLook(root))
end

-- Altura do chão embaixo de um ponto (nil se não tiver chão perto)
local function groundBelow(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	return hit and hit.Position.Y or nil
end

-- Espera um marcador da animação que o personagem está tocando (funciona também com a animação de outro
-- jogador, que chega replicada). Volta no marcador ou no tempo limite.
local function waitAnimationMarker(character, animationId, markerName, timeout)
	local deadline = os.clock() + timeout
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator or not animationId or not markerName then
		task.wait(timeout)
		return
	end
	local wanted = tostring(animationId)
	local track
	repeat
		for _, playing in animator:GetPlayingAnimationTracks() do
			local animation = playing.Animation
			if animation and string.find(animation.AnimationId, wanted, 1, true) then
				track = playing
				break
			end
		end
		if not track then
			task.wait()
		end
	until track or os.clock() > deadline
	if not track then return end
	local reached = false
	local connections = CombatStyles.OnMarker(track, markerName, function()
		reached = true
	end)
	while not reached and os.clock() < deadline and track.IsPlaying do
		task.wait()
	end
	for _, connection in connections do
		connection:Disconnect()
	end
end

-- Órbitas da carga: giram na mão, cada uma numa velocidade, e crescem com a carga
local function startChargeOrbits(character, maxCharge)
	local groups = getChargedPieces()
	local orbits = groups and groups.Charge_Orbit
	if not orbits or #orbits == 0 then return false end
	local parts, speeds = {}, {}
	for index, piece in orbits do
		local part = spawnPiece(piece, CFrame.new(handPosition(character)), piece.Size * 0.4, NEON_WHITE, Enum.Material.Neon, 0.35)
		table.insert(parts, part)
		speeds[part] = (if index % 2 == 0 then -1 else 1) * (5 + index * 2.5)
	end
	local elapsed = 0
	local full = false
	attach(character, "Charge", parts, function(dt)
		elapsed += dt
		local power = math.clamp(elapsed / maxCharge, 0, 1)
		local root = rootOf(character)
		local look = flatLook(root)
		local hand = handPosition(character) + look * 0.4
		local pulse = 1 + math.sin(elapsed * 14) * 0.06
		for index, part in parts do
			local piece = orbits[index]
			part.Size = piece.Size * (0.4 + 0.7 * power) * pulse
			part.CFrame = CFrame.lookAt(hand, hand + look) * CFrame.Angles(0, 0, elapsed * speeds[part])
			part.Transparency = 0.5 - 0.35 * power
		end
		if power >= 1 and not full then
			full = true
			for _, part in parts do
				part.Color = PARRY_COLOR
			end
			burst(hand, WHITE, 4, 0.2)
		end
	end)
	return true
end

-- Soco carregado solto: pressão avançando, impacto (círculos e anéis) no marcador de impacto e o chão quebrando
local function playChargedPunchVFX(character, data, power)
	local groups = getChargedPieces()
	local root = rootOf(character)
	if not groups or not root then return false end
	local frame = attackFrame(root)
	local look = frame.LookVector
	local scale = 1 + power * 0.6
	local fast = FastMode.IsEnabled()

	-- Aparece forte, segura um instante e só depois some (sumir enquanto cresce deixava tudo quase invisível)
	local function fadeLater(part, hold, fadeTime, props)
		task.delay(hold, function()
			if part.Parent then
				local goals = props or {}
				goals.Transparency = 1
				tween(part, fadeTime, goals)
			end
		end)
		Debris:AddItem(part, hold + fadeTime + 0.05)
	end

	-- 1. Disparo: faixas de pressão saem do punho e esticam para a frente
	for _, piece in groups.Release_Pressure or {} do
		local target = frame * piece.Rel
		local part = spawnPiece(piece, target - look * 0.5, piece.Size * Vector3.new(0.7, 0.7, 0.4), NEON_WHITE, Enum.Material.Neon, 0)
		tween(part, 0.12, { CFrame = target + look * 0.8 * scale, Size = piece.Size * Vector3.new(scale, scale, scale * 1.2) })
		fadeLater(part, 0.14, 0.2)
	end

	task.spawn(function()
		-- 2. Impacto: no marcador de impacto da animação (ou num tempo curto sem animação)
		local style = styleOf(data)
		local _, cfg = CombatStyles.SkillOfKind(style, "Charge")
		local animationId = CombatStyles.Animation(style, "ChargedPunch")
		waitAnimationMarker(character, animationId, cfg and cfg.HitMarker, if animationId and cfg then 0.9 else 0.12)
		if not character.Parent then return end
		local currentRoot = rootOf(character)
		if currentRoot then
			frame = attackFrame(currentRoot)
			look = frame.LookVector
		end

		for _, piece in groups.Impact_Circle or {} do
			local ink = string.find(piece.Name, "Ink", 1, true) ~= nil
			local echo = string.find(piece.Name, "Echo", 1, true) ~= nil
			local target = frame * piece.Rel
			local part = spawnPiece(piece, target, piece.Size * 0.4,
				if ink then INK else NEON_WHITE,
				if ink then Enum.Material.SmoothPlastic else Enum.Material.Neon,
				if echo then 0.45 else 0)
			local grow = (if echo then 1.4 else 1) + power * 0.4
			tween(part, 0.12, { Size = piece.Size * grow }, Enum.EasingStyle.Back)
			fadeLater(part, 0.2, 0.3, { Size = piece.Size * grow * 1.25, CFrame = target + look * 0.8 })
		end
		for index, piece in groups.Impact_ShockRing or {} do
			if fast and index > 1 then break end
			task.delay((index - 1) * 0.05, function()
				local target = frame * piece.Rel
				local part = spawnPiece(piece, target, piece.Size * 0.6, NEON_WHITE, Enum.Material.Neon, 0.05)
				tween(part, 0.4, { Size = piece.Size * (1.6 + power), CFrame = target + look * (1 + index * 1.5) })
				fadeLater(part, 0.18, 0.25)
			end)
		end
		if character == player.Character then
			shake(0.25 + 0.4 * power)
		end

		-- 3. Chão: só se tiver chão embaixo do impacto
		local craterPiece = groups.Ground_CraterInterior and groups.Ground_CraterInterior[1]
		local craterCenter = if craterPiece then (frame * craterPiece.Rel).Position else frame.Position + look * 5.6
		local groundY = groundBelow(Vector3.new(craterCenter.X, frame.Position.Y, craterCenter.Z), { character, fxFolder })
		if not groundY then return end
		task.wait(0.08)
		local shift = Vector3.new(0, groundY - (frame.Position.Y - CHARGED_GROUND_DROP), 0)
		local groundScale = 0.85 + power * 0.45
		local function place(piece)
			local cf = frame * piece.Rel + shift
			local offset = cf.Position - (craterCenter + shift)
			return cf + Vector3.new(offset.X, 0, offset.Z) * (groundScale - 1)
		end
		local hold = 0.9

		for _, group in { "Ground_Crack", "Ground_CraterInterior" } do
			for _, piece in groups[group] or {} do
				local target = place(piece)
				local part = spawnPiece(piece, target, piece.Size * 0.2, CRACK_COLOR, Enum.Material.SmoothPlastic, 0.15)
				tween(part, 0.1, { Size = piece.Size * groundScale })
				task.delay(hold, function()
					tween(part, 0.4, { Transparency = 1 })
				end)
				Debris:AddItem(part, hold + 0.45)
			end
		end
		if fast then return end
		for _, piece in groups.Ground_RimSlab or {} do
			local target = place(piece)
			local tilt = CFrame.Angles(math.rad(rng:NextNumber(-18, 18)), 0, math.rad(rng:NextNumber(-18, 18)))
			local part = spawnPiece(piece, target - Vector3.new(0, 0.5, 0), piece.Size * groundScale)
			tween(part, 0.14, { CFrame = target * tilt }, Enum.EasingStyle.Back)
			task.delay(hold, function()
				tween(part, 0.4, { CFrame = target - Vector3.new(0, 0.4, 0), Transparency = 1 })
			end)
			Debris:AddItem(part, hold + 0.45)
		end
		for _, piece in groups.Ground_FlyingShard or {} do
			local target = place(piece)
			local start = CFrame.new(craterCenter + shift + Vector3.new(0, 0.2, 0))
			local up = rng:NextNumber(1.5, 3.2) * groundScale * CHARGED_SCALE * 0.7
			local spin = CFrame.Angles(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3))
			local part = spawnPiece(piece, start, piece.Size * groundScale)
			local peak = CFrame.new(target.Position + Vector3.new(0, up, 0)) * spin
			tween(part, 0.22, { CFrame = peak })
			task.delay(0.22, function()
				tween(part, 0.38, { CFrame = CFrame.new(target.Position.X, groundY + piece.Size.Y / 2, target.Position.Z) * spin * spin }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
			task.delay(hold, function()
				tween(part, 0.3, { Transparency = 1 })
			end)
			Debris:AddItem(part, hold + 0.35)
		end
	end)
	return true
end

-- Cópia do modelo de partículas pronta para o mapa: partes ancoradas e sem colisão, emissores desligados
local function prepareEmitterModel(template)
	local model = template:Clone()
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
		elseif item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then
			item.Enabled = false
		end
	end
	return model
end

-- Rajada: a peça base fica na frente do punho, acompanha o atacante e o efeito flui sem parar enquanto isActive()
local function playBarrageVFX(character, duration, isActive, skill)
	local template = vfxTemplate("BarragePunch")
	local root = rootOf(character)
	if not template or not root then return false end
	local model = prepareEmitterModel(template)
	-- A peça base (crash4) é onde o soco "bate no ar": fica na frente do punho, deitada, com a face de cima (+Y)
	-- apontando para onde o personagem soca. O resto do efeito (VFX, crash3) sai dela para a frente, ao longo do +Y.
	-- Mesmo giro do modelo original: o X da peça aponta para baixo.
	local base = if model:IsA("Model") then (model.PrimaryPart or model:FindFirstChild("crash4")) else model
	local pivotOffset = if model:IsA("Model") and base then base.CFrame:ToObjectSpace(model:GetPivot()) else CFrame.new()
	local function place()
		local currentRoot = rootOf(character)
		if not currentRoot then return end
		local baseCFrame = CombatStyles.BarrageBaseCFrame(currentRoot.CFrame, skill)
		if model:IsA("Model") then
			model:PivotTo(baseCFrame * pivotOffset)
		elseif model:IsA("BasePart") then
			model.CFrame = baseCFrame
		end
	end
	place()
	model.Parent = fxFolder

	-- Todos os emissores ficam ligados (na taxa Rate de cada um) a rajada inteira, sem piscar;
	-- no começo sai também a rajada dos EmitCount. No Fast Mode, metade das partículas.
	local fast = FastMode.IsEnabled()
	local emitters = {}
	for _, emitter in model:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			if fast then
				emitter.Rate *= 0.5
			end
			emitter.Enabled = true
			table.insert(emitters, emitter)
		end
	end
	for _, emitter in emitters do
		local count = emitter:GetAttribute("EmitCount")
		if type(count) == "number" and count > 0 then
			emitter:Emit(math.max(1, math.floor(count * (if fast then 0.5 else 1) + 0.5)))
		end
	end
	local follow = RunService.RenderStepped:Connect(place)
	task.spawn(function()
		local finish = os.clock() + duration
		while os.clock() < finish and character.Parent and isActive() do
			task.wait(0.05)
		end
		follow:Disconnect()
		for _, emitter in emitters do
			emitter.Enabled = false
		end
		Debris:AddItem(model, 1.6) -- deixa as últimas partículas terminarem
	end)
	return true
end

local function startCharge(character, data)
	heldPose[character] = "Charge"

	local maxCharge = if type(data.MaxCharge) == "number" and data.MaxCharge > 0 then data.MaxCharge else 1.5
	if startChargeOrbits(character, maxCharge) then return end

	-- Sem os VFX modelados: aura simples na mão
	local color = styleColor(data)
	local aura = newPart(Enum.PartType.Ball, color, CFrame.new(handPosition(character)), Vector3.one * 0.6)
	aura.Transparency = 0.3
	local elapsed = 0
	local full = false
	attach(character, "Charge", { aura }, function(dt)
		elapsed += dt
		local power = math.clamp(elapsed / maxCharge, 0, 1)
		local pulse = (math.sin(elapsed * 18) + 1) / 2
		aura.Size = Vector3.one * (0.6 + 1.8 * power + pulse * 0.25)
		aura.CFrame = CFrame.new(handPosition(character))
		if power >= 1 and not full then
			full = true
			aura.Color = WHITE:Lerp(PARRY_COLOR, 0.5)
			burst(aura.Position, WHITE, 5, 0.25)
		end
	end)
end

local function endCharge(character)
	if heldPose[character] == "Charge" then
		heldPose[character] = nil
	end
	clearAttached(character, "Charge")
end

-- ================= Katana =================
-- Skills: KatanaVFX (Codex; malhas em ReplicatedStorage.VFX.Katana), nas fases dos marcadores das animações. Cortes do
-- M1, dos acertos, o risco do Avanço e os fantasmas no caminho: feitos aqui (Beam e peças, sem asset). Sem as malhas
-- do Codex no Studio, os arcos daqui também desenham o corte das skills.

local KatanaVFX = require(ReplicatedStorage:WaitForChild("KatanaVFX"))
local katanaVFX = KatanaVFX.new(function()
	return FastMode.IsEnabled()
end)
local BLADE_GLOW = Color3.fromRGB(240, 31, 52)

-- Malhas do KatanaVFX carregadas antes do primeiro golpe
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("Katana", 30)
	if folder then
		pcall(function()
			ContentProvider:PreloadAsync(folder:GetChildren())
		end)
	end
end)

local function katanaMeshes()
	local folder = ReplicatedStorage:FindFirstChild("VFX")
	return folder ~= nil and folder:FindFirstChild("Katana") ~= nil
end

-- Arco de corte: faixa curva (Beam) no plano XZ de frame (0° = frente, -Z; positivo gira para +X), com raio radius.
-- A ponta corre de fromAngle até toAngle em 35% do tempo e depois o rastro encolhe atrás dela e some.
-- Curva do Beam = Bézier cúbica: controle 1 no Attachment0 + Axis * CurveSize0, controle 2 no Attachment1 - Axis *
-- CurveSize1; com os Axis na direção do movimento e CurveSize = 4/3 tan(ângulo/4) raio, vira um arco de círculo.
local function slashArc(frame, radius, fromAngle, toAngle, color, width, life, core)
	local fast = FastMode.IsEnabled()
	local host = newPart(Enum.PartType.Block, WHITE, frame, Vector3.one * 0.05)
	host.Transparency = 1
	local tail = Instance.new("Attachment")
	tail.Parent = host
	local head = Instance.new("Attachment")
	head.Parent = host
	local beams = {}
	local function addBeam(beamWidth, beamColor, alpha)
		local beam = Instance.new("Beam")
		beam.Attachment0 = tail
		beam.Attachment1 = head
		beam.FaceCamera = true
		beam.Segments = 18
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(beamColor)
		beam.Parent = host
		table.insert(beams, { Beam = beam, Width = beamWidth, Alpha = alpha })
	end
	if not fast then
		addBeam(width * 1.9, color, 0.5) -- brilho
	end
	addBeam(width * 0.55, core or WHITE, 0) -- núcleo

	local a0, a1 = math.rad(fromAngle), math.rad(toAngle)
	local sign = if a1 >= a0 then 1 else -1
	local function place(attachment, angle)
		local position = Vector3.new(math.sin(angle) * radius, 0, -math.cos(angle) * radius)
		local tangent = Vector3.new(math.cos(angle), 0, math.sin(angle)) * sign
		attachment.CFrame = CFrame.fromMatrix(position, tangent, Vector3.yAxis)
	end
	local sweep = life * 0.35
	local started = os.clock()
	local connection
	local function update()
		local t = os.clock() - started
		if t >= life or not host.Parent then
			connection:Disconnect()
			host:Destroy()
			return
		end
		local grow = 1 - (1 - math.min(1, t / sweep)) ^ 3
		local fade = math.clamp((t - sweep) / (life - sweep), 0, 1)
		local headAngle = a0 + (a1 - a0) * grow
		local tailAngle = a0 + (headAngle - a0) * (fade ^ 0.7)
		place(tail, tailAngle)
		place(head, headAngle)
		local curve = 4 / 3 * math.tan(math.abs(headAngle - tailAngle) / 4) * radius
		for _, entry in beams do
			local beam = entry.Beam
			beam.CurveSize0 = curve
			beam.CurveSize1 = curve
			beam.Width0 = entry.Width * 0.15
			beam.Width1 = entry.Width * (1 - fade * 0.6)
			local alpha = entry.Alpha + (1 - entry.Alpha) * fade
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, math.min(1, alpha + 0.25)),
				NumberSequenceKeypoint.new(1, alpha),
			})
		end
	end
	connection = RunService.RenderStepped:Connect(update)
	update()
end

-- Corte atravessando a vítima, virado para quem atacou. cut: nil/"Single" = um corte, "Cross" = X, "Wide" = um
-- longo deitado (Saque), "Flurry" = chuva de cortes em ângulos soltos terminando num X grande (Avanço cortante).
-- Cada corte pega a posição da vítima na hora em que sai (ela pode estar sendo empurrada).
local function cutAcross(victim, attacker, cut, strong)
	local function slash(tilt, radius, span, width, delay, withSparks)
		task.delay(delay, function()
			local position, toward = impactPoint(victim, attacker)
			if not position then return end
			local chest = position - toward * 1.2
			local angle = math.rad(tilt)
			local axis = toward:Cross(Vector3.yAxis) * math.cos(angle) + Vector3.yAxis * math.sin(angle)
			local back = axis:Cross(toward)
			-- O meio do arco passa pelo peito: o centro fica radius studs para trás no plano do corte
			slashArc(CFrame.fromMatrix(chest + back * radius, axis, toward), radius, -span, span, BLADE_GLOW, width, 0.3)
			if withSparks then
				sparks(chest + rng:NextUnitVector() * 0.5, BLADE_GLOW, 4, 22)
				burst(chest, WHITE, 1.2, 0.08)
			end
		end)
	end
	if cut == "Flurry" then
		local count = if FastMode.IsEnabled() then 3 else 7
		local gap = 0.045
		for index = 1, count do
			slash(rng:NextNumber(-85, 85), rng:NextNumber(4, 6), rng:NextNumber(20, 30), 0.55, (index - 1) * gap, true)
		end
		local finale = count * gap + 0.05
		slash(35, 6.5, 30, 1.15, finale, true)
		slash(-35, 6.5, 30, 1.15, finale + 0.04, false)
		return
	end
	local tilts = if cut == "Cross" then { 35, -35 } elseif cut == "Wide" then { rng:NextNumber(-8, 8) } else { rng:NextNumber(-55, 55) }
	local radius = if cut == "Wide" then 9 else 5.5
	local span = if cut == "Wide" then 32 elseif strong then 26 else 20
	for index, tilt in tilts do
		slash(tilt, radius, span, if strong then 0.9 else 0.6, (index - 1) * 0.06, false)
	end
end

-- Garras da Raposa (estilo fundido com o contrato, Theme "Raposa"): três riscos carmesins lado a lado (arcos com o mesmo
-- centro e raios vizinhos, como unhas), num plano de frente para quem bate.
local CLAW_COLOR = Color3.fromRGB(212, 18, 46) -- carmesim
local CLAW_CORE = Color3.fromRGB(255, 135, 150)
local CLAW_ROLLS = { 10, -10, 18, -18 } -- diagonal das garras em cada golpe do combo (o 5º cruza dois conjuntos)
local CLAW_PITCH = 10
local lastClaws = setmetatable({}, { __mode = "k" }) -- [personagem] = os.clock() do último M1 com garras

-- Garra em forma de lua crescente (estilo anime): grossa no meio e fina nas duas pontas, com contorno escuro por fora,
-- o carmesim no meio e um brilho claro na borda de dentro. Cada camada é um arco de raio próprio (o contorno um pouco
-- para fora, o brilho um pouco para dentro) feito de dois Beams (ponta -> meio -> ponta), para afinar nas duas pontas.
-- Mesmo plano e animação do slashArc: cresce varrendo de fromAngle a toAngle e some encolhendo atrás da ponta.
-- No Fast Mode sai sem o contorno escuro.
local CLAW_LAYERS = {
	{ Color = Color3.fromRGB(14, 0, 4), Emission = 0, Width = 1, Offset = 0.22, Alpha = 0.05, ZOffset = -0.2 },
	{ Color = CLAW_COLOR, Emission = 1, Width = 0.68, Offset = 0, Alpha = 0, ZOffset = 0 },
	{ Color = CLAW_CORE, Emission = 1, Width = 0.26, Offset = -0.16, Alpha = 0, ZOffset = 0.2 },
}
local function crescent(frame, radius, fromAngle, toAngle, thickness, life)
	local fast = FastMode.IsEnabled()
	local host = newPart(Enum.PartType.Block, WHITE, frame, Vector3.one * 0.05)
	host.Transparency = 1
	local layers = {}
	for index, layer in CLAW_LAYERS do
		if fast and index == 1 then continue end
		-- Pontos: ponta de trás, meio (duas vezes, um pouco sobrepostos: sem emenda visível no meio) e ponta da frente
		local points = {}
		for i = 1, 4 do
			local attachment = Instance.new("Attachment")
			attachment.Parent = host
			points[i] = attachment
		end
		local beams = {}
		for half = 1, 2 do
			local beam = Instance.new("Beam")
			beam.Attachment0 = points[half * 2 - 1]
			beam.Attachment1 = points[half * 2]
			beam.FaceCamera = true
			beam.Segments = 14
			beam.LightEmission = layer.Emission
			beam.LightInfluence = 0
			beam.ZOffset = layer.ZOffset
			beam.Color = ColorSequence.new(layer.Color)
			beam.Parent = host
			beams[half] = beam
		end
		table.insert(layers, { Points = points, Beams = beams, Layer = layer, Radius = radius + layer.Offset * thickness })
	end

	local a0, a1 = math.rad(fromAngle), math.rad(toAngle)
	local sign = if a1 >= a0 then 1 else -1
	local function place(attachment, angle, r)
		local position = Vector3.new(math.sin(angle) * r, 0, -math.cos(angle) * r)
		local tangent = Vector3.new(math.cos(angle), 0, math.sin(angle)) * sign
		attachment.CFrame = CFrame.fromMatrix(position, tangent, Vector3.yAxis)
	end
	local sweep = life * 0.3
	local started = os.clock()
	local connection
	local function update()
		local t = os.clock() - started
		if t >= life or not host.Parent then
			connection:Disconnect()
			host:Destroy()
			return
		end
		local grow = 1 - (1 - math.min(1, t / sweep)) ^ 3
		local fade = math.clamp((t - sweep) / (life - sweep), 0, 1)
		local headAngle = a0 + (a1 - a0) * grow
		local tailAngle = a0 + (headAngle - a0) * (fade ^ 0.8)
		local midAngle = (headAngle + tailAngle) / 2
		local overlap = (headAngle - tailAngle) * 0.03
		-- A lua engorda enquanto cresce e afina sumindo
		local span = math.abs(headAngle - tailAngle) / math.max(math.abs(a1 - a0), 1e-3)
		local width = thickness * span * (1 - fade * 0.35)
		for _, entry in layers do
			local r = entry.Radius
			place(entry.Points[1], tailAngle, r)
			place(entry.Points[2], midAngle + overlap, r)
			place(entry.Points[3], midAngle - overlap, r)
			place(entry.Points[4], headAngle, r)
			local curve = 4 / 3 * math.tan(math.abs(midAngle + overlap - tailAngle) / 4) * r
			local layerWidth = width * entry.Layer.Width
			local alpha = NumberSequence.new(entry.Layer.Alpha + (1 - entry.Layer.Alpha) * fade ^ 1.5)
			for half, beam in entry.Beams do
				beam.CurveSize0 = curve
				beam.CurveSize1 = curve
				beam.Width0 = if half == 1 then layerWidth * 0.05 else layerWidth
				beam.Width1 = if half == 1 then layerWidth else layerWidth * 0.05
				beam.Transparency = alpha
			end
		end
	end
	connection = RunService.RenderStepped:Connect(update)
	update()
end

-- Três garras deitadas, uma em cima da outra (planos paralelos, como uma parede), cada uma curvando para dentro em
-- volta de quem bate: o meio da lua entra no alvo (na distância do golpe) e as pontas voltam pelos lados.
-- origin: centro da curva (o peito de quem bate); pitch levanta um pouco a frente (o plano fica de frente para a câmera
-- de trás); roll inclina na diagonal; reverse risca da direita para a esquerda.
local CLAW_GAP = 1.3 -- distância entre as três garras
local function wrapClaws(origin, look, pitch, roll, radius, span, thickness, reverse)
	local flat = Vector3.new(look.X, 0, look.Z)
	look = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local base = CFrame.lookAt(origin, origin + look) * CFrame.Angles(math.rad(pitch), 0, 0) * CFrame.Angles(0, 0, math.rad(roll))
	local from, to = -span, span
	if reverse then
		from, to = span, -span
	end
	for index = 1, 3 do
		local frame = base + base.UpVector * ((index - 2) * CLAW_GAP)
		task.delay((index - 1) * 0.03, function()
			crescent(frame, radius, from, to, thickness * (if index == 2 then 1 else 0.85), 0.38)
		end)
	end
end

-- Garras de cada M1, na frente de quem bate, no tempo do impacto (acertando ou não). O último golpe do combo e o
-- uppercut fazem um X duplo maior. Os outros jogadores veem pelo "Swing" do servidor.
local function swingClaws(character, style, move, combo)
	lastClaws[character] = os.clock()
	local value = style.M1 and style.M1.ClawDelay
	local delay = (if type(value) == "table" then value[combo] or value[1] else value) or 0.14
	task.delay(delay, function()
		local root = rootOf(character)
		if not root then return end
		local look = flatLook(root)
		-- Centro da curva no peito, um pouco atrás: o meio das garras passa na distância da hitbox do M1
		local origin = root.Position - look * 0.5 + Vector3.new(0, 0.6, 0)
		if move == "Uppercut" then
			wrapClaws(origin, look, CLAW_PITCH, 55, 5, 60, 2.6, false) -- bem na diagonal, de baixo para cima
		elseif combo >= ((style.M1 and style.M1.Hits) or 5) then
			wrapClaws(origin, look, CLAW_PITCH + 2, 26, 5.2, 64, 2.8, false)
			task.delay(0.07, function()
				wrapClaws(origin, look, CLAW_PITCH + 2, -26, 5.2, 64, 2.8, true)
			end)
		else
			wrapClaws(origin, look, CLAW_PITCH, CLAW_ROLLS[combo] or 10, 4.8, 58, 2.4, combo % 2 == 0)
		end
	end)
end

-- Garras atravessando a vítima (golpes sem M1: Rajada de Garras, Kon!, soco carregado). No máximo um conjunto a cada
-- 0,2 s por atacante (a Rajada acerta a cada 0,12 s: as garras saem em golpes alternados)
local lastAcross = setmetatable({}, { __mode = "k" })
local function clawsAcross(victim, attacker, strong)
	if typeof(attacker) == "Instance" then
		local clock = os.clock()
		if not strong and clock - (lastAcross[attacker] or 0) < 0.2 then return end
		lastAcross[attacker] = clock
	end
	-- A mesma parede do M1, em cima da vítima
	local attackerRoot, victimRoot = rootOf(attacker), rootOf(victim)
	if not attackerRoot or not victimRoot then return end
	local offset = victimRoot.Position - attackerRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local look = if flat.Magnitude > 0.1 then flat.Unit else flatLook(attackerRoot)
	-- Mesma curva do M1, com o raio até a vítima (o meio das garras passa por ela)
	local origin = attackerRoot.Position - look * 0.3 + Vector3.new(0, 0.6, 0)
	local radius = math.clamp(flat.Magnitude + 0.3, 3, 8)
	local roll = rng:NextNumber(-20, 20)
	wrapClaws(origin, look, CLAW_PITCH, roll, radius, if strong then 62 else 56, if strong then 2.8 else 2.2, rng:NextNumber() < 0.5)
	if strong then
		task.delay(0.07, function()
			wrapClaws(origin, look, CLAW_PITCH, if roll >= 0 then -24 else 24, radius, 62, 2.8, rng:NextNumber() < 0.5)
		end)
	end
end

-- Rastro da espada: o Trail "SwingTrail" que o StyleWeapons prende na lâmina (Handle) e na bainha (SheathRoot). Como
-- ele está preso na peça, segue a animação sozinho: aqui só liga e desliga. A troca é só neste cliente (cada cliente
-- liga o rastro dos golpes que vê). Devolve a função que desliga antes do tempo.
local trailTokens = setmetatable({}, { __mode = "k" })
local function swingTrail(character, styleName, arm, duration)
	local weapon = typeof(character) == "Instance" and character:FindFirstChild(tostring(styleName) .. "Weapon")
	local root = weapon and weapon:FindFirstChild(if arm == "Left" then "SheathRoot" else "Handle")
	local trail = root and root:FindFirstChild("SwingTrail")
	if not trail then
		return function() end
	end
	local token = (trailTokens[trail] or 0) + 1
	trailTokens[trail] = token
	trail.Enabled = true
	local function stop()
		if trailTokens[trail] == token then
			trail.Enabled = false
		end
	end
	task.delay(duration, stop)
	return stop
end

-- Fases de cada skill da Katana: fase -> campo de tempo da skill (dispara o marcador ou o tempo, o que vier primeiro).
-- Fase sem o campo na skill não acontece; o marcador pode ter outro nome (skill.Markers[fase]).
-- Grab, Strike e Release do Agarrão vêm do servidor (dependem de quem foi pego).
local KATANA_PHASES = {
	DashSlash = { Dash = "DashAt", Slash = "SlashAt" },
	Grab = { Reach = "ReachAt" },
	DrawSlash = { Charge = "ChargeAt", Slash = "SlashAt", Sheathe = "SheatheAt" },
}

-- Animação tocando no personagem com esse ID (a de outro jogador chega replicada)
local function playingTrack(character, animationId)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator or not animationId then return nil end
	local wanted = tostring(animationId)
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Animation and string.find(track.Animation.AnimationId, wanted, 1, true) then
			return track
		end
	end
	return nil
end

-- As malhas do KatanaVFX são só da Katana: outro estilo com as mesmas mecânicas (Motosserra) desenha os arcos na cor
-- dele (SlashColor do estilo)
local function usesKatanaMeshes(styleName)
	return styleName == "Katana" and katanaMeshes()
end

local function katanaPhase(character, styleName, skill, slot, phase)
	if styleName == "Katana" then
		katanaVFX:Play(slot, phase, { Character = character })
	end
	local root = rootOf(character)
	if not root then return end
	local soundData = { Style = styleName }
	local styleData = CombatStyles.Styles[styleName]
	local glow = styleData and styleData.SlashColor or BLADE_GLOW
	if phase == "Dash" then
		playSound(soundData, "Dash", root)
		swingTrail(character, styleName, "Right", (skill.SlashAt or 0.35) - (skill.DashAt or 0.15) + 0.15)
	elseif phase == "Slash" and skill.Kind == "DrawSlash" then
		playSound(soundData, "Draw", root)
		swingTrail(character, styleName, "Right", 0.28)
		if not usesKatanaMeshes(styleName) then
			local frame = root.CFrame * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(-6))
			local arc = math.min(skill.Arc, 359)
			slashArc(frame, skill.Range * 0.75, -arc / 2, arc / 2, glow, 1.5, 0.4)
		end
		if character == player.Character then
			shake(0.35)
		end
	elseif phase == "Slash" and skill.Kind == "DashSlash" then
		playSound(soundData, "HeavyHit", root)
		if not usesKatanaMeshes(styleName) then
			local frame = root.CFrame * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(-38))
			slashArc(frame, 4, 70, -70, glow, 1.1, 0.3)
		end
	end
end

-- Golpe do combo da Katana: rastro do começo do golpe até um instante depois do marcador de impacto (Hitframe1).
-- M1.SwingArm diz de onde sai o rastro em cada golpe: "Right" = lâmina, "Left" = bainha.
local TRAIL_AFTER_HIT = 0.08
local function katanaSwing(character, styleName, style, move, combo)
	local arm = if move == "Uppercut" then style.M1.Uppercut.SwingArm else style.M1.SwingArm and style.M1.SwingArm[combo]
	local stop = swingTrail(character, styleName, arm or "Right", 0.45)
	local track = playingTrack(character, CombatStyles.Animation(style, move, combo))
	if not track then
		task.delay((style.M1.Windup or 0.15) + TRAIL_AFTER_HIT, stop)
		return
	end
	local connections
	connections = CombatStyles.OnMarker(track, style.HitMarker or "Hit", function()
		for _, connection in connections do
			connection:Disconnect()
		end
		task.delay(TRAIL_AFTER_HIT, stop)
	end)
	track.Stopped:Once(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		stop()
	end)
end

-- ================= Eventos do servidor =================

local handlers = {}

function handlers.Swing(data)
	local character = data.Character
	local move = data.Move
	local combo = if type(data.Combo) == "number" then data.Combo else 1
	local style = styleOf(data)
	-- Estilo com SwingOnMiss: o som do golpe no ar sai no "Miss" (frame do corte, sem acertar ninguém)
	if not (style and style.SwingOnMiss) then
		playSound(data, "Swing", rootOf(character))
	end
	if style and style.HitFX == "Slash" then
		katanaSwing(character, data.Style, style, move, combo)
	elseif style and style.Theme == "Raposa" and typeof(character) == "Instance" then
		swingClaws(character, style, move, combo)
	end
end

-- Golpe que pegou no ar (estilo com SwingOnMiss): quem atacou prevê, os outros recebem do servidor
function handlers.Miss(data)
	playSound(data, "Swing", rootOf(data.Character))
end

function handlers.Hit(data)
	local position, toward = impactPoint(data.Character, data.Attacker)
	if not position then return end
	local color = WHITE
	local theme = styleOrDefault(data).Theme
	if theme == "Raposa" then
		-- Punhos da Raposa (fusão): o M1 já desenhou as garras no golpe (swingClaws); os outros golpes (Rajada,
		-- Kon!, soco carregado) desenham em cima da vítima. Faíscas carmesins e um pouco de sangue.
		local attacker = data.Attacker
		local fromSwing = typeof(attacker) == "Instance" and os.clock() - (lastClaws[attacker] or 0) < 0.4
		if not fromSwing then
			clawsAcross(data.Character, attacker, data.Strong)
		end
		burst(position, CLAW_COLOR, if data.Strong then 3.4 else 1.8, 0.14)
		sparks(position, CLAW_CORE, if data.Strong then 9 else 4, 26)
		if data.Strong then
			ring(position, toward, CLAW_COLOR, 8, 0.3)
		end
		BloodFX.Burst(position, toward + Vector3.new(0, 0.6, 0), {
			Amount = if data.Strong then 10 else 4,
			Speed = { 10, 24 },
			Spread = 45,
			Mist = if data.Strong then 3 else 1,
			Fast = FastMode.IsEnabled(),
		})
	elseif styleOrDefault(data).HitFX == "Slash" then
		-- Katana: corte atravessando a vítima no lugar do impacto redondo
		cutAcross(data.Character, data.Attacker, data.Cut, data.Strong)
		burst(position, color, if data.Strong then 2.6 else 1.6, 0.12)
		sparks(position, BLADE_GLOW, if data.Strong then 10 else 5, 24)
	elseif data.Strong then
		burst(position, color, 4.5, 0.25)
		ring(position, toward, color, 7, 0.3)
		sparks(position, PARRY_COLOR, 8, 30)
	else
		burst(position, color, 2.4, 0.16)
		sparks(position, color, 3, 18)
	end
	flash(data.Character, WHITE, 0.12)
	if data.Character == player.Character or data.Attacker == player.Character then
		shake(if data.Strong then 0.6 else 0.18)
	end
	-- Contra-golpe da esquiva (o M1 logo depois de desviar)
	if data.Counter then
		floatText(data.Character, "CONTRA-GOLPE!", PARRY_COLOR)
	end
	local style = styleOrDefault(data)
	playSound(data, if data.Strong then "HeavyHit" else "Hit", rootOf(data.Character))
	hitstop({ data.Attacker, data.Character }, if data.Strong then style.HeavyHitstop or 0.09 else style.Hitstop or 0.05)
end

-- Kon! (estilo fundido com a Raposa): a cabeça da mordida, menor, sai de um portal na frente de quem invocou e
-- abocanha no tempo do SnapAt (o mesmo ImpactDelay do FoxDevilVFX)
local FoxDevilVFX = require(ReplicatedStorage:WaitForChild("FoxDevilVFX"))
function handlers.FoxSnap(data)
	local root = rootOf(data.Character)
	if not root then return end
	-- A garrada e a mordida já têm efeito próprio: os "Hit" delas não desenham garras na vítima
	if typeof(data.Character) == "Instance" then
		lastClaws[data.Character] = os.clock() + 0.3
	end
	local style = styleOrDefault(data)
	local cfg = style.Skills and style.Skills[data.Slot]
	local range = if cfg and cfg.Range then cfg.Range else 10
	local look = if typeof(data.Look) == "Vector3" then data.Look else flatLook(root)
	-- Primeiro a garrada carmesim (X grande na frente), depois a cabeça
	local clawAt = if cfg and cfg.ClawAt then cfg.ClawAt else 0
	if clawAt > 0 then
		task.delay(math.max(0, clawAt - 0.04), function()
			local now = rootOf(data.Character)
			if not now then return end
			local forward = flatLook(now)
			local origin = now.Position - forward * 0.5 + Vector3.new(0, 0.6, 0)
			wrapClaws(origin, forward, CLAW_PITCH + 2, 24, 5.6, 66, 3, false)
			task.delay(0.06, function()
				wrapClaws(origin, forward, CLAW_PITCH + 2, -24, 5.6, 66, 3, true)
			end)
		end)
	end
	FoxDevilVFX.Play({
		Character = data.Character,
		Position = root.Position + look * (range * 0.55),
		Look = look,
		Radius = 5,
		StartTime = data.StartTime,
		Scale = 1.3,
		Small = true,
	}, FastMode.IsEnabled())
end

function handlers.Blocked(data)
	local position, toward = impactPoint(data.Character, data.Attacker)
	if not position then return end
	burst(position, BLOCK_COLOR, 2.2, 0.15)
	ring(position, toward, BLOCK_COLOR, 3.5, 0.18)
	sparks(position, BLOCK_COLOR, 4, 16)
	playSound(data, "Block", rootOf(data.Character))
	hitstop({ data.Attacker, data.Character }, (styleOrDefault(data).Hitstop or 0.05) * 0.6)
end

function handlers.Parry(data)
	local position, toward = impactPoint(data.Character, data.Attacker)
	if not position then return end
	burst(position, PARRY_COLOR, 5, 0.3)
	ring(position, toward, PARRY_COLOR, 9, 0.35)
	sparks(position, WHITE, 10, 35)
	floatText(data.Character, "PARRY!", PARRY_COLOR)
	if typeof(data.Attacker) == "Instance" then
		flash(data.Attacker, PARRY_COLOR, 0.3)
	end
	if data.Character == player.Character or data.Attacker == player.Character then
		shake(0.45)
	end
	playSound(data, "Parry", rootOf(data.Character))
	hitstop({ data.Attacker, data.Character }, styleOrDefault(data).HeavyHitstop or 0.09)
end

function handlers.GuardBreak(data)
	local root = rootOf(data.Character)
	if not root then return end
	local position = root.Position + flatLook(root) * 1.4 + Vector3.new(0, 0.6, 0)
	burst(position, BREAK_COLOR, 5, 0.3)
	sparks(position, BREAK_COLOR, 14, 28)
	flash(data.Character, BREAK_COLOR, 0.4)
	floatText(data.Character, "GUARDA QUEBRADA", BREAK_COLOR)
	playSound(data, "GuardBreak", root)
	endBlock(data.Character)
	if data.Character == player.Character then
		shake(0.5)
	end
end

-- Quebra-combo (CombatStyles.PvP): o atordoado saiu do combo com o dash
function handlers.ComboBreaker(data)
	local root = rootOf(data.Character)
	if not root then return end
	burst(root.Position, PARRY_COLOR, 6, 0.3)
	flash(data.Character, PARRY_COLOR, 0.3)
	floatText(data.Character, "QUEBRA-COMBO!", PARRY_COLOR)
	if data.Character == player.Character then
		shake(0.3)
	end
end

-- ----- Esquiva automática (DodgeData) -----
-- Todos veem o "ESQUIVOU" e o rastro; quem desviou toca a animação do lado (replica sozinha) e dá o passo (o cliente é
-- dono do próprio personagem). Sem Side (invencível no avanço da Katana): só o texto.
local DodgeData = require(ReplicatedStorage:WaitForChild("DodgeData"))
local DODGE_COLOR = Color3.fromRGB(170, 220, 255)

task.spawn(function()
	local list = {}
	for _, id in DodgeData.Animations do
		if type(id) == "number" and id > 0 then
			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. id
			table.insert(list, animation)
		end
	end
	if #list > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end
end)

-- Rastro: o corpo em azul claro, parado onde estava, sumindo
local function dodgeGhost(character)
	if FastMode.IsEnabled() then return end
	for _, name in { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local ghost = newPart(Enum.PartType.Block, DODGE_COLOR, part.CFrame, part.Size)
			ghost.Transparency = 0.45
			tween(ghost, 0.35, { Transparency = 1 })
			Debris:AddItem(ghost, 0.4)
		end
	end
end

local function playDodgeAnimation(character, side)
	local id = DodgeData.Animations[side]
	if type(id) ~= "number" or id <= 0 then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then return end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.05)
	track.Stopped:Once(function()
		track:Destroy()
		animation:Destroy()
	end)
	-- Corta a sobra parada do fim (animação exportada com a linha do tempo inteira)
	task.delay(DodgeData.AnimationMaxTime, function()
		if track.IsPlaying then
			track:Stop(0.15)
		end
	end)
end

-- Passo para o lado (para antes de parede)
local function dodgeStep(character, side)
	local root = rootOf(character)
	if not root then return end
	local cframe = root.CFrame
	local direction = if side == "Left" then -cframe.RightVector elseif side == "Right" then cframe.RightVector else -cframe.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then return end
	direction = direction.Unit
	local ignore = { character }
	for _, name in { "Enemies", "CombatFX", "PowerEffects" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Blockcast(CFrame.lookAt(cframe.Position, cframe.Position + direction), Vector3.new(1.8, 3.5, 0.6),
		direction * DodgeData.Step, params)
	local distance = if hit and hit.Normal.Y < 0.6 then math.max(0, hit.Distance - 0.5) else DodgeData.Step
	if distance < 0.2 then return end
	local began = os.clock()
	local moved = 0
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not root.Parent then
			connection:Disconnect()
			return
		end
		local alpha = math.min(1, (os.clock() - began) / DodgeData.StepTime)
		local target = distance * (1 - (1 - alpha) ^ 2)
		root.CFrame += direction * (target - moved)
		moved = target
		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end

function handlers.Dodge(data)
	if typeof(data.Character) ~= "Instance" then return end
	floatText(data.Character, "ESQUIVOU", DODGE_COLOR)
	local side = data.Side
	if side ~= "Left" and side ~= "Right" and side ~= "Back" then return end
	dodgeGhost(data.Character)
	if data.Character == player.Character then
		playDodgeAnimation(data.Character, side)
		dodgeStep(data.Character, side)
	end
end

function handlers.BlockStart(data)
	if not rootOf(data.Character) then return end
	startBlock(data.Character)
end

function handlers.BlockEnd(data)
	if typeof(data.Character) ~= "Instance" then return end
	endBlock(data.Character)
end

function handlers.Barrage(data)
	local character = data.Character
	local root = rootOf(character)
	if not root then return end
	local duration = if type(data.Duration) == "number" then math.min(data.Duration, 3) else 0.9
	heldPose[character] = "Barrage"
	local function active()
		return heldPose[character] == "Barrage"
	end
	-- VFX modelado (ReplicatedStorage.VFX.Punchs.BarragePunch)
	local style = styleOf(data)
	playBarrageVFX(character, duration, active, (select(2, CombatStyles.SkillOfKind(style, "Barrage"))))
	task.delay(duration, function()
		if active() then
			heldPose[character] = nil
		end
	end)
end

function handlers.BarrageEnd(data)
	local character = data.Character
	if typeof(character) ~= "Instance" then return end
	if heldPose[character] == "Barrage" then
		heldPose[character] = nil
	end
end

function handlers.ChargeStart(data)
	if not rootOf(data.Character) then return end
	startCharge(data.Character, data)
end

function handlers.ChargeCancel(data)
	if typeof(data.Character) ~= "Instance" then return end
	endCharge(data.Character)
end

function handlers.ChargedPunch(data)
	local character = data.Character
	local root = rootOf(character)
	if not root then return end
	endCharge(character)
	local power = if type(data.Power) == "number" then math.clamp(data.Power, 0, 1) else 0
	-- VFX modelado (ReplicatedStorage.VFX.Punchs.ChargedPunch); sem ele, a onda simples abaixo
	if playChargedPunchVFX(character, data, power) then return end
	local color = styleColor(data):Lerp(WHITE, power * 0.5)
	local look = flatLook(root)
	local front = root.Position + look * 2.5 + Vector3.new(0, 0.6, 0)
	task.delay(0.1, function()
		burst(front, color, 3 + 3 * power, 0.25)
		ring(front + look * (1 + 2 * power), look, color, 5 + 7 * power, 0.35)
		-- Rastro do soco
		local length = 4 + 5 * power
		local center = front + look * (length / 2)
		local streak = newPart(Enum.PartType.Cylinder, color, CFrame.lookAt(center, center + look) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(length, 0.9 + power, 0.9 + power))
		streak.Transparency = 0.3
		tween(streak, 0.25, { Size = Vector3.new(length, 0.1, 0.1), Transparency = 1 })
		Debris:AddItem(streak, 0.3)
		if character == player.Character then
			shake(0.2 + 0.4 * power)
		end
	end)
end

-- Skill da Katana começou (o próprio cliente manda com a Track; os outros recebem do servidor)
function handlers.KatanaSkill(data)
	local style = styleOf(data)
	local slot = data.Slot
	local skill = style and style.Skills and type(slot) == "string" and style.Skills[slot]
	local phases = skill and KATANA_PHASES[skill.Kind]
	if not phases then return end
	local character = data.Character
	local track = if typeof(data.Track) == "Instance" and data.Track:IsA("AnimationTrack") then data.Track
		else playingTrack(character, CombatStyles.Animation(style, skill.Animation))
	for phase, timeField in phases do
		if not skill[timeField] then continue end
		local fired = false
		local connection
		local function fire()
			if fired then return end
			fired = true
			if connection then
				connection:Disconnect()
			end
			if character.Parent and character:GetAttribute("Stunned") ~= true then
				katanaPhase(character, data.Style, skill, slot, phase)
			end
		end
		if track then
			connection = track:GetMarkerReachedSignal(skill.Markers and skill.Markers[phase] or phase):Connect(fire)
		end
		-- Sem animação (ou o marcador não chegou): no tempo da skill
		task.delay((skill[timeField] or 0) + (if track then 0.2 else 0), fire)
	end
end

-- Avanço cortante: risco no caminho e fantasmas de quem passou
function handlers.DashSlashPath(data)
	local from, to = data.From, data.To
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then return end
	local offset = to - from
	local length = offset.Magnitude
	if length < 1 then return end
	local middle = (from + to) / 2
	local frame = CFrame.lookAt(middle, to)
	local core = newPart(Enum.PartType.Block, WHITE, frame, Vector3.new(0.2, 0.2, length))
	tween(core, 0.5, { Size = Vector3.new(0.02, 0.02, length), Transparency = 1 })
	Debris:AddItem(core, 0.55)
	if FastMode.IsEnabled() then return end
	local glow = newPart(Enum.PartType.Block, BLADE_GLOW, frame, Vector3.new(0.7, 0.7, length))
	glow.Transparency = 0.45
	tween(glow, 0.45, { Size = Vector3.new(0.05, 0.05, length), Transparency = 1 })
	Debris:AddItem(glow, 0.5)

	local root = rootOf(data.Character)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if not root or flat.Magnitude < 0.5 then return end
	local limbs = {}
	for _, name in { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local part = data.Character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(limbs, { Size = part.Size, Offset = root.CFrame:ToObjectSpace(part.CFrame) })
		end
	end
	local facing = CFrame.lookAt(Vector3.zero, flat).Rotation
	for i = 1, 4 do
		local base = CFrame.new(from:Lerp(to, i / 5)) * facing
		for _, limb in limbs do
			local ghost = newPart(Enum.PartType.Block, if i % 2 == 0 then WHITE else BLADE_GLOW, base * limb.Offset, limb.Size)
			ghost.Transparency = 0.5 + i * 0.08
			tween(ghost, 0.3 + i * 0.04, { Transparency = 1 })
			Debris:AddItem(ghost, 0.5)
		end
	end
end

-- Avanço acertou: quem ficou no caminho pisca e trava; os cortes saem no dano (efeito "Hit" com Cut = "Flurry")
function handlers.DashSlashConnect(data)
	if type(data.Targets) ~= "table" then return end
	for _, target in data.Targets do
		if typeof(target) == "Instance" and target:IsA("Model") and rootOf(target) then
			flash(target, WHITE, 0.25)
			local position = impactPoint(target, data.Character)
			if position then
				burst(position, WHITE, 1.8, 0.12)
			end
		end
	end
	if data.Character == player.Character then
		shake(0.25)
	end
end

-- Agarrão (fases que dependem de quem foi pego, mandadas pelo servidor)
function handlers.KatanaGrab(data)
	if data.Style == "Katana" then
		katanaVFX:Play("X", "Grab", { Character = data.Character, Target = data.Target })
	end
	if typeof(data.Target) == "Instance" then
		flash(data.Target, WHITE, 0.2)
	end
	if data.Character == player.Character or data.Target == player.Character then
		shake(0.3)
	end
end

function handlers.KatanaGrabStrike(data)
	if data.Style == "Katana" then
		katanaVFX:Play("X", "Strike", { Character = data.Character, Target = data.Target })
	end
	swingTrail(data.Character, data.Style, "Right", 0.22)
end

function handlers.KatanaGrabRelease(data)
	if data.Style == "Katana" then
		katanaVFX:Play("X", "Release", { Character = data.Character, Target = data.Target })
	end
	swingTrail(data.Character, data.Style, "Right", 0.25)
end

function handlers.KatanaGrabMiss(data)
	katanaVFX:Cancel(data.Character)
end

-- Luta longe da câmera não desenha nada (o servidor manda os efeitos para todos). Os avisos de fim (BlockEnd...) passam
-- sempre, para nunca deixar um efeito preso.
local FX_RANGE = 260
local ALWAYS = { BlockEnd = true, ChargeCancel = true, BarrageEnd = true, KatanaGrabMiss = true }
local function inRange(character)
	local root = rootOf(character)
	local camera = workspace.CurrentCamera
	if not root or not camera then return true end
	return (root.Position - camera.CFrame.Position).Magnitude <= FX_RANGE
end

local function dispatch(kind, data)
	local handler = handlers[kind]
	if handler and type(data) == "table" and typeof(data.Character) == "Instance" then
		if not ALWAYS[kind] and data.Character ~= player.Character and data.Attacker ~= player.Character
			and not inRange(data.Character) then
			return
		end
		handler(data)
	end
end

-- Do servidor (golpes dos outros, e o que quem atacou não consegue prever: parry, guarda quebrada, esquiva)
Remotes.CombatFX.OnClientEvent:Connect(dispatch)

-- ================= Rede de segurança: animação parada nos outros =================
-- O hitstop daqui pausa por um instante as animações de quem bateu e de quem apanhou, inclusive dos outros jogadores e
-- dos inimigos (animações que chegam replicadas). Se uma delas fica parada neste cliente (o dono parou ou trocou a dele
-- no meio da pausa), ela ficava presa no personagem dele, só para quem viu, até ele morrer. Aqui: animação de ação
-- parada em velocidade 0 por mais de OTHERS_STUCK_LIMIT num personagem vivo por perto é encerrada (só neste cliente).
-- Pausas de propósito dos outros (carga do soco, aviso do Pisão do chefe) são mais curtas; a mira do Kon vai até 8 s.
-- Corpo morto fica de fora (a pose final da morte é parada de propósito). O próprio personagem é do CombatAnimations.
local OTHERS_STUCK_LIMIT = 2.5
local OTHERS_HOLD_LIMIT = 9
local othersStuckSince = {} -- [track] = os.clock() de quando parou (tabela comum: limpa abaixo)
local nextOthersCheck = 0

local function scanStuck(model, clock, seen)
	if model == player.Character or not inRange(model) then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in animator:GetPlayingAnimationTracks() do
		if HITSTOP_PRIORITIES[track.Priority] and track.Speed == 0 then
			seen[track] = true
			local since = othersStuckSince[track]
			local held = track.Animation ~= nil and track.Animation:GetAttribute("AllowAimHold") == true
			if not since then
				othersStuckSince[track] = clock
			elseif clock - since > (if held then OTHERS_HOLD_LIMIT else OTHERS_STUCK_LIMIT) then
				othersStuckSince[track] = nil
				track:Stop(0.15)
			end
		end
	end
end

RunService.Heartbeat:Connect(function()
	local clock = os.clock()
	if clock < nextOthersCheck then return end
	nextOthersCheck = clock + 0.25
	local seen = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			scanStuck(other.Character, clock, seen)
		end
	end
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		for _, npc in enemies:GetChildren() do
			scanStuck(npc, clock, seen)
		end
	end
	for track in othersStuckSince do
		if not seen[track] then
			othersStuckSince[track] = nil
		end
	end
end)

-- Previstos pelo próprio cliente na hora do golpe (CombatInput): mesmo tratamento
local localFX = Instance.new("BindableEvent")
localFX.Name = "CombatLocalFX"
localFX.Parent = script.Parent
localFX.Event:Connect(dispatch)
