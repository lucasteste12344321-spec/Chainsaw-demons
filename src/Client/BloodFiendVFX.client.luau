-- Efeitos do Infernal do Sangue: Lança de Sangue e Martelo de Sangue. Quem dá o dano e decide os tempos é o servidor
-- (BloodFiendSkills, chamado pelo PathSkills); aqui só se desenha o que ele manda em Remotes.CombatFX "BloodFiend":
--   Cast     começou (Position, Direction, Ground, Normal): sangue juntando na mão, a arma cresce nela (FormTime) e quem
--            invocou toca a animação (ReplicatedStorage.VFX.BloodFiend.Animations[SkillId])
--   Launch   a lança saiu (Position, Direction, Speed, Range, LaunchTime): ela voa com rastro, pingando sangue
--   Impact   lança: cravou (Position, Normal, Target?) e estoura; martelo: bateu no chão (Position, Normal, Radius)
--   Dissolve a lança chegou no alcance sem acertar: desfaz em sangue
--   Cancel   o golpe foi cortado (stun, morte): a arma estoura e some
-- Modelos (Blender, Codex): VFX.BloodFiend.BloodSpear (ponta no -Z do modelo), BloodHammer (cabeça no +Y, pivô no cabo),
-- BloodPressureRing e BloodCrescent (planos no XZ), BloodShard (espinho no +Y). Malha que não carrega (asset novo ainda
-- em análise na moderação do Roblox, ou recusado) vira uma forma neon parecida. Remontar pelos dados (EditableMesh) não
-- serve: no jogo essa API vem desligada (Game Settings > Security) e a peça aparece como um cubo xadrez.
-- Martelo: quem invoca salta para a frente (BloodFiendConfig.MarteloSangue.Leap*: o próprio cliente move o personagem) e
-- bate no chão ao cair. Para quem invoca, os efeitos saem nos marcadores da animação ("Release" da lança, "Hit" do
-- martelo), sem esperar o servidor; os outros jogadores veem pelos eventos do servidor.
-- Este script também é o sinal para o servidor usar o BloodFiendSkills (o PathSkills procura por ele no StarterPlayerScripts).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Config = require(ReplicatedStorage:WaitForChild("BloodFiendConfig"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local BloodFX = require(ReplicatedStorage:WaitForChild("BloodFX"))
local FastMode = require(script.Parent:WaitForChild("FastMode"))

local player = Players.LocalPlayer
local random = Random.new()

local BLOOD = Color3.fromRGB(150, 6, 18)
local BLOOD_DARK = Color3.fromRGB(70, 0, 8)
local GLOW = Color3.fromRGB(255, 35, 62)
local GROW_TIME = 0.22 -- a arma cresce na mão em tanto tempo depois do FormTime
local SPEAR_TILT = math.rad(8) -- a lança na mão aponta um pouco para cima
local SPEAR_TIP = 5.7 -- da origem do modelo até a ponta (-Z)
-- Martelo na mão: o cabo sai do punho inclinado 45° para a frente do braço. Na pegada de Tool ele ficava em pé e, no
-- golpe da animação, a cabeça passava por cima; assim, no marcador "Hit" a ponta de espinho encosta no chão uns 5 studs
-- à frente (BloodFiendConfig.MarteloSangue.SlamOffset). Conta feita quadro a quadro com o clips.json do Codex.
local HAMMER_TILT = math.rad(45)
local HAMMER_GRIP = CFrame.fromMatrix(
	Vector3.zero,
	Vector3.new(0, math.sin(HAMMER_TILT), -math.cos(HAMMER_TILT)),
	Vector3.new(0, -math.cos(HAMMER_TILT), -math.sin(HAMMER_TILT))
)
local ROOT_HEIGHT = 3 -- R6: a raiz fica 3 studs acima do chão
local SHAKE_RANGE = 70

local assets -- ReplicatedStorage.VFX.BloodFiend
local readyParts = {} -- [nome da peça] = MeshPart pronta para clonar (só as que carregaram)
local partOffsets = {} -- [nome da peça] = CFrame dela em relação ao pivô do modelo dela

-- O Roblox centraliza cada malha na caixa dela, então o pivô do Blender (onde a mão segura) se perde na importação.
-- Centro de cada peça das armas em relação a esse pivô, medido nos vértices de assets/vfx/blood_fiend/meshes.json
-- (se a malha for refeita, medir de novo).
local MESH_CENTERS = {
	BloodSpear_Core = Vector3.new(0, 0, -1.85),
	BloodSpear_Veins = Vector3.new(0, 0, -2.187),
	BloodHammer_Core = Vector3.new(0, 1.325, 0),
	BloodHammer_Veins = Vector3.new(0, 1.603, -0.013),
}

-- Pasta dos efeitos locais (o Fast Mode não mexe nela e as hitboxes a ignoram)
local function effectsFolder()
	local parent = workspace:FindFirstChild("CombatFX")
	if not parent then
		parent = Instance.new("Folder")
		parent.Name = "CombatFX"
		parent.Parent = workspace
	end
	local folder = parent:FindFirstChild("BloodFiend")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BloodFiend"
		folder.Parent = parent
	end
	return folder
end

local function smooth(value)
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end

local function tween(instance, time, goals, style, direction)
	local playing = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	playing:Play()
	return playing
end

local function newPart(name, className)
	local part = Instance.new(className or "Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = GLOW
	return part
end

local function near(position, extra)
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= Config.EffectDistance + (extra or 0)
end

----------------------------------------------------------------------------------------------------
-- Modelos (com reserva quando a malha não carregou)
----------------------------------------------------------------------------------------------------

local WEAPON_PARTS = {
	BloodSpear = { "BloodSpear_Core", "BloodSpear_Veins" },
	BloodHammer = { "BloodHammer_Core", "BloodHammer_Veins" },
}

-- Arma de reserva: mesmas proporções, peças neon simples. O pivô (peça Origin, invisível) fica onde a mão segura.
local function fallbackWeapon(kind)
	local model = Instance.new("Model")
	model.Name = kind .. "Fallback"
	local origin = newPart("Origin")
	origin.Transparency = 1
	origin.Size = Vector3.one * 0.1
	origin.CFrame = CFrame.identity
	origin.Parent = model
	if kind == "BloodSpear" then
		local shaft = newPart("Core")
		shaft.Material = Enum.Material.SmoothPlastic
		shaft.Color = BLOOD
		shaft.Size = Vector3.new(0.22, 0.22, 7.6)
		shaft.CFrame = CFrame.new(0, 0, -1.85)
		shaft.Parent = model
		local blade = newPart("Glow", "WedgePart")
		blade.Size = Vector3.new(0.12, 0.6, 2.6)
		blade.CFrame = CFrame.new(0, 0, -4.4) * CFrame.Angles(0, 0, math.rad(90))
		blade.Parent = model
	else
		local head = newPart("Core")
		head.Material = Enum.Material.SmoothPlastic
		head.Color = BLOOD
		head.Size = Vector3.new(4.4, 1.8, 2.1)
		head.CFrame = CFrame.new(0, 3.45, 0)
		head.Parent = model
		local handle = newPart("Glow")
		handle.Shape = Enum.PartType.Cylinder
		handle.Size = Vector3.new(4.4, 0.35, 0.35)
		handle.CFrame = CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90))
		handle.Parent = model
	end
	model.PrimaryPart = origin
	return model
end

local function newWeapon(kind)
	local names = WEAPON_PARTS[kind]
	local model
	if readyParts[names[1]] then
		-- Malha do Codex: as peças no lugar delas em volta do pivô (no cabo)
		model = Instance.new("Model")
		model.Name = kind
		local origin = newPart("Origin")
		origin.Transparency = 1
		origin.Size = Vector3.one * 0.1
		origin.CFrame = CFrame.identity
		origin.Parent = model
		for _, name in names do
			local template = readyParts[name]
			if template then
				local part = template:Clone()
				part.CFrame = partOffsets[name] or CFrame.identity
				part.Parent = model
			end
		end
		model.PrimaryPart = origin
	else
		model = fallbackWeapon(kind)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	return model
end

-- Anel/onda/espinho: a peça do Codex ou uma forma parecida
local function effectPiece(name)
	local template = readyParts[name]
	if template then
		local piece = template:Clone()
		piece.Anchored = true
		piece.CanCollide, piece.CanQuery, piece.CanTouch, piece.CastShadow = false, false, false, false
		return piece, piece.Size
	end
	local piece
	if name == "BloodShard" then
		piece = newPart(name, "WedgePart")
		piece.Material = Enum.Material.SmoothPlastic
		piece.Color = BLOOD
		piece.Size = Vector3.new(0.37, 1.45, 0.37)
	else
		piece = newPart(name)
		piece.Shape = Enum.PartType.Cylinder
		piece.Size = Vector3.new(0.05, 2, 2)
	end
	return piece, piece.Size
end

----------------------------------------------------------------------------------------------------
-- Pedaços de efeito
----------------------------------------------------------------------------------------------------

-- Tremida de câmera e um flash vermelho para quem está perto
local function cameraKick(position, strength)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local distance = (camera.CFrame.Position - position).Magnitude
	local falloff = 1 - math.clamp((distance - 10) / SHAKE_RANGE, 0, 1)
	if falloff <= 0 then return end
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "BloodImpactFlash"
	grade.TintColor = Color3.fromRGB(255, 190, 190)
	grade.Contrast = 0.3 * falloff
	grade.Saturation = 0.25 * falloff
	grade.Parent = camera
	tween(grade, 0.3, { TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0 })
	Debris:AddItem(grade, 0.35)
	local power = strength * falloff
	local bindName = "BloodShake" .. random:NextInteger(1, 1e9)
	local started = os.clock()
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local elapsed = os.clock() - started
		if elapsed > 0.35 then
			RunService:UnbindFromRenderStep(bindName)
			return
		end
		local amount = power * (1 - elapsed / 0.35) ^ 2
		camera.CFrame *= CFrame.new(random:NextNumber(-1, 1) * amount * 0.35, random:NextNumber(-1, 1) * amount * 0.35, 0)
	end)
end

-- Plano (XZ do modelo) deitado na superfície de normal dada
local function flatOn(position, normal)
	local reference = if math.abs(normal.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local right = reference:Cross(normal).Unit
	return CFrame.fromMatrix(position, right, normal)
end

-- Anel de pressão que abre e some
local function pressureRing(position, normal, finalSize, time, delay)
	task.delay(delay or 0, function()
		local ring, baseSize = effectPiece("BloodPressureRing")
		local flat = baseSize.Y < baseSize.X -- a peça do Codex é deitada no XZ; a reserva é um cilindro (eixo X)
		ring.CFrame = if flat then flatOn(position + normal * 0.08, normal) else flatOn(position + normal * 0.08, normal) * CFrame.Angles(0, 0, math.rad(90))
		ring.Size = if flat then Vector3.new(2, baseSize.Y, 2) else Vector3.new(0.05, 2, 2)
		ring.Transparency = 0.05
		ring.Parent = effectsFolder()
		local goal = if flat then Vector3.new(finalSize, baseSize.Y, finalSize) else Vector3.new(0.05, finalSize, finalSize)
		tween(ring, time, { Size = goal, Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(ring, time + 0.1)
	end)
end

-- Estilhaços de sangue voando em arco a partir de um ponto (ancorados, sem física)
local function flyingShards(position, normal, count, reach)
	for _ = 1, count do
		local shard = effectPiece("BloodShard")
		local direction = (normal * random:NextNumber(0.6, 1.2) + random:NextUnitVector() * 0.9).Unit
		local scale = random:NextNumber(0.6, 1.1)
		shard.Size *= scale
		shard.CFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(-math.pi / 2, 0, 0)
		shard.Parent = effectsFolder()
		local apex = position + direction * reach * random:NextNumber(0.5, 1) + normal * random:NextNumber(1, 3)
		local landing = apex + direction * reach * 0.4 - Vector3.new(0, 5, 0)
		local spin = CFrame.Angles(random:NextNumber(-3, 3), random:NextNumber(-3, 3), random:NextNumber(-3, 3))
		tween(shard, 0.22, { CFrame = CFrame.new(apex) * spin })
		task.delay(0.22, function()
			if shard.Parent then
				tween(shard, 0.45, { CFrame = CFrame.new(landing) * spin * spin, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
		Debris:AddItem(shard, 0.8)
	end
end

-- Espinhos de sangue que saem do chão em volta do impacto e afundam depois
local function groundSpikes(position, normal, radius, count)
	local flat = flatOn(position, normal)
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local distance = radius * random:NextNumber(0.35, 0.9)
		local spot = flat * Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local outward = (spot - position).Unit
		local shard = effectPiece("BloodShard")
		local scale = random:NextNumber(1.6, 2.8)
		shard.Size *= scale
		local tilt = CFrame.fromAxisAngle(normal:Cross(outward).Unit, math.rad(random:NextNumber(18, 38)))
		local up = tilt * flatOn(Vector3.zero, normal)
		local raised = up + spot + up.UpVector * (shard.Size.Y * 0.35)
		local sunk = up + spot - up.UpVector * (shard.Size.Y * 0.6)
		shard.CFrame = sunk
		shard.Parent = effectsFolder()
		task.delay(random:NextNumber(0, 0.08), function()
			if not shard.Parent then return end
			tween(shard, 0.14, { CFrame = raised }, Enum.EasingStyle.Back)
			task.delay(0.7 + random:NextNumber(0, 0.3), function()
				if shard.Parent then
					tween(shard, 0.4, { CFrame = sunk, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end)
		Debris:AddItem(shard, 1.6)
	end
end

-- Ondas de sangue em lua correndo para fora do impacto
local function crescentWaves(position, normal, direction, radius, count)
	local template = readyParts.BloodCrescent
	if not template then return end
	local flat = flatOn(position + normal * 0.12, normal)
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local outward = (flat:VectorToWorldSpace(Vector3.new(math.cos(angle), 0, math.sin(angle)))).Unit
		local wave = template:Clone()
		wave.Anchored = true
		wave.CanCollide, wave.CanQuery, wave.CanTouch, wave.CastShadow = false, false, false, false
		-- A lua (XZ do modelo) deitada no chão com a barriga (+X da malha) para fora
		local start = CFrame.lookAt(position + normal * 0.12 + outward * 1.5, position + normal * 0.12 + outward * 3, normal)
			* CFrame.Angles(0, math.pi / 2, 0)
		wave.CFrame = start
		wave.Size = Vector3.new(wave.Size.X * 1.4, wave.Size.Y, wave.Size.Z * 1.4)
		wave.Parent = effectsFolder()
		tween(wave, 0.45, {
			CFrame = start + outward * radius,
			Size = Vector3.new(wave.Size.X * 2.6, wave.Size.Y, wave.Size.Z * 2.6),
			Transparency = 1,
		}, Enum.EasingStyle.Quart)
		Debris:AddItem(wave, 0.55)
	end
end

----------------------------------------------------------------------------------------------------
-- Andamento de cada uso
----------------------------------------------------------------------------------------------------

local casts = {} -- [CastId] = estado
local order = {} -- CastIds na ordem (para o limite Config.MaxCasts)

local function rightHand(character)
	local arm = character and character:FindFirstChild("Right Arm")
	return arm and arm.CFrame * CFrame.new(0, -1.05, 0)
end

local function flatLook(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local look = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

local function flatDirection(vector, character)
	if typeof(vector) == "Vector3" then
		local flat = Vector3.new(vector.X, 0, vector.Z)
		if flat.Magnitude > 0.01 then
			return flat.Unit
		end
	end
	return flatLook(character)
end

local function endCast(castId)
	local state = casts[castId]
	if not state then return end
	casts[castId] = nil
	local index = table.find(order, castId)
	if index then
		table.remove(order, index)
	end
	if state.Track then
		state.Track:Stop(0.15)
	end
	if state.Weapon then
		state.Weapon:Destroy()
	end
end

-- Some a arma em sangue (fade das peças e umas gotas)
local function dissolveWeapon(state, position, fast)
	local weapon = state.Weapon
	state.Weapon = nil
	if not weapon then return end
	for _, part in weapon:GetDescendants() do
		if part:IsA("BasePart") then
			tween(part, 0.35, { Transparency = 1 })
		end
	end
	BloodFX.Drip(position, if fast then 3 else 6, fast)
	Debris:AddItem(weapon, 0.4)
end

-- Números do poder (PathData: alcance, velocidade, raio)
local function skillData(skillId)
	local fiend = PathData.FiendTypes.Sangue
	for _, skill in (fiend and fiend.Skills) or {} do
		if skill.Id == skillId then
			return skill
		end
	end
	return {}
end

local function moveParams(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { character }
	for _, name in { "Enemies", "CombatFX", "PowerEffects", "KatanaVisuals" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

-- Pulo do martelo (só o próprio personagem): de LeapStart até ImpactTime, até LeapDistance à frente (para antes de
-- parede), num arco de LeapHeight, caindo na altura do chão de lá. Move a raiz direto (CFrame), como o avanço da Katana.
local function leap(state)
	local cfg = state.Cfg
	local character = state.Character
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if casts[state.CastId] ~= state or not root or not humanoid or humanoid.Health <= 0 then return end
	if character:GetAttribute("Stunned") == true then return end
	-- Mesma conta do servidor (BloodFiendSkills.leapLanding): na direção do uso, parando antes de parede (rampa e degrau
	-- baixo não contam, o arco passa por cima)
	local direction = state.CastDirection
	local params = moveParams(character)
	local start = root.Position
	local distance = cfg.LeapDistance
	local hit = workspace:Blockcast(CFrame.lookAt(start, start + direction), Vector3.new(2, 2.5, 1), direction * distance, params)
	if hit and hit.Normal.Y < 0.6 then
		distance = math.max(0, hit.Distance - 1)
	end
	local landing = start + direction * distance
	local floor = workspace:Raycast(landing + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	if floor then
		landing = Vector3.new(landing.X, floor.Position.Y + ROOT_HEIGHT, landing.Z)
	end
	-- Cai na hora em que o servidor bate (StartTime + ImpactTime), que é o marcador "Hit" da animação
	local began = workspace:GetServerTimeNow()
	local duration = math.max(0.1, state.StartTime + cfg.ImpactTime - began)
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if casts[state.CastId] ~= state or not root.Parent or humanoid.Health <= 0 or character:GetAttribute("Stunned") == true then
			connection:Disconnect()
			return
		end
		local u = math.min(1, (workspace:GetServerTimeNow() - began) / duration)
		local position = start:Lerp(landing, u) + Vector3.new(0, cfg.LeapHeight * 4 * u * (1 - u), 0)
		root.CFrame = CFrame.lookAt(position, position + direction)
		root.AssemblyLinearVelocity = Vector3.zero
		if u >= 1 then
			connection:Disconnect()
			root.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
		end
	end)
end

local spearLaunch, hammerImpact -- (definidas abaixo)

-- Quem invoca: o efeito sai no marcador da animação ("Release" da lança, "Hit" do martelo), sem esperar o servidor, e o
-- evento do servidor não repete. As contas são as mesmas do BloodFiendSkills (saída da lança e ponto da batida).
local function predictFromMarkers(state, track)
	local marker = state.Cfg.Marker or (if state.SkillId == "LancaSangue" then "Release" else "Hit")
	track:GetMarkerReachedSignal(marker):Connect(function()
		if casts[state.CastId] ~= state or state.Phase ~= "Form" then return end
		local root = state.Character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local direction = state.CastDirection
		local fast = FastMode.IsEnabled()
		state.Predicted = true
		if state.SkillId == "LancaSangue" then
			local skill = skillData("LancaSangue")
			spearLaunch(state, {
				Position = root.Position + Vector3.new(0, 0.5, 0) + direction * 2,
				Direction = direction,
				Speed = skill.Speed,
				Range = skill.Range,
				LaunchTime = workspace:GetServerTimeNow(),
			}, fast)
		else
			-- SlamOffset à frente de onde caiu do pulo
			local params = moveParams(state.Character)
			local center = root.Position + direction * (state.Cfg.SlamOffset or 3)
			local wall = workspace:Raycast(root.Position, center - root.Position, params)
			if wall then
				center = wall.Position - direction * 0.5
			end
			local floor = workspace:Raycast(center + Vector3.new(0, 3, 0), Vector3.new(0, -18, 0), params)
			hammerImpact(state, {
				CastId = state.CastId,
				Position = if floor then floor.Position else center - Vector3.new(0, ROOT_HEIGHT, 0),
				Normal = if floor then floor.Normal else Vector3.yAxis,
				Radius = skillData("MarteloSangue").Radius,
				Direction = direction,
			}, fast)
		end
	end)
end

local function playAnimation(state, data)
	if data.Character ~= player.Character then return end -- cada um toca a do próprio personagem (replica sozinha)
	local humanoid = data.Character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animation = assets and assets:FindFirstChild("Animations") and assets.Animations:FindFirstChild(data.SkillId)
	if not animator or not animation then return end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then return end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.05)
	-- Em sincronia com o servidor (o Cast chega com o ping de atraso)
	local late = workspace:GetServerTimeNow() - (data.StartTime or workspace:GetServerTimeNow())
	if late > 0.02 then
		track.TimePosition = math.min(late, 0.3)
	end
	state.Track = track
	predictFromMarkers(state, track)
	if data.SkillId == "MarteloSangue" and state.Cfg.LeapDistance then
		task.delay(math.max(0, state.Cfg.LeapStart - late), leap, state)
	end
end

local handlers = {}

function handlers.Cast(data, fast)
	if typeof(data.Character) ~= "Instance" or type(data.CastId) ~= "string" then return end
	if typeof(data.Position) == "Vector3" and not near(data.Position) then return end
	if #order >= Config.MaxCasts then
		endCast(order[1])
	end
	local cfg = Config[data.SkillId]
	if not cfg then return end
	local state = {
		CastId = data.CastId,
		Character = data.Character,
		SkillId = data.SkillId,
		CastDirection = flatDirection(data.Direction, data.Character),
		StartTime = data.StartTime or workspace:GetServerTimeNow(),
		Cfg = cfg,
		Phase = "Form",
	}
	casts[data.CastId] = state
	table.insert(order, data.CastId)
	playAnimation(state, data)
	-- Sangue juntando na mão antes da arma aparecer
	local hand = rightHand(data.Character)
	if hand then
		BloodFX.Burst(hand.Position, Vector3.yAxis, { Amount = 6, Speed = { 3, 8 }, Spread = 80, Size = { 0.14, 0.26 }, Mist = 3, Fast = fast })
	end
	state.Weapon = newWeapon(if data.SkillId == "LancaSangue" then "BloodSpear" else "BloodHammer")
	state.Weapon:ScaleTo(0.05)
	state.Scale = 0.05
	state.Weapon.Parent = effectsFolder()
end

function spearLaunch(state, data, fast)
	state.Phase = "Flight"
	state.From = data.Position
	state.Direction = data.Direction.Unit
	state.Speed = tonumber(data.Speed) or 90
	state.Range = tonumber(data.Range) or 60
	state.LaunchTime = data.LaunchTime or workspace:GetServerTimeNow()
	state.NextDrip = 0
	-- Rastro: uma faixa fina atrás da lança
	local weapon = state.Weapon
	local core = weapon and weapon.PrimaryPart
	if core and not fast then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.18, -2)
		a0.Parent = core
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.18, -2)
		a1.Parent = core
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.2
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(GLOW, BLOOD_DARK)
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.FaceCamera = true
		trail.Parent = core
	end
end

function handlers.Launch(data, fast)
	local state = casts[data.CastId]
	if not state or typeof(data.Position) ~= "Vector3" or typeof(data.Direction) ~= "Vector3" then return end
	if state.Predicted then return end -- quem invocou já soltou a lança no marcador
	spearLaunch(state, data, fast)
end

local function spearImpact(state, data, fast)
	local position, normal = data.Position, data.Normal or Vector3.yAxis
	local direction = state.Direction or flatLook(state.Character)
	state.Phase = "Stuck"
	-- Crava: a ponta entra um pouco no alvo/parede e fica parada um instante
	if state.Weapon then
		state.Weapon:PivotTo(CFrame.lookAt(position - direction * (SPEAR_TIP - 0.6), position + direction))
		state.Weapon:ScaleTo(1)
	end
	BloodFX.Burst(position, normal + direction * -0.3, { Amount = 14, Speed = { 10, 24 }, Spread = 60, Fast = fast })
	if typeof(data.Target) == "Instance" then
		BloodFX.Splat(position, 2.5, fast)
	end
	task.delay(0.28, function()
		pressureRing(position, normal, 9, 0.35)
		if not fast then
			pressureRing(position, normal, 6, 0.3, 0.05)
		end
		flyingShards(position, normal, if fast then 4 else 8, 6)
		BloodFX.Burst(position, normal, { Amount = 22, Speed = { 14, 32 }, Spread = 75, Fast = fast })
		cameraKick(position, 0.7)
		dissolveWeapon(state, position, fast)
	end)
	task.delay(0.8, function()
		endCast(data.CastId)
	end)
end

function hammerImpact(state, data, fast)
	local position, normal = data.Position, data.Normal or Vector3.yAxis
	local radius = tonumber(data.Radius) or 12
	local direction = if typeof(data.Direction) == "Vector3" then data.Direction else flatLook(state.Character)
	state.Phase = "Planted"
	pressureRing(position, normal, radius * 2.2, 0.45)
	pressureRing(position, normal, radius * 1.4, 0.35, 0.06)
	if not fast then
		pressureRing(position, normal, radius * 2.8, 0.55, 0.1)
	end
	crescentWaves(position, normal, direction, radius, if fast then 4 else 8)
	groundSpikes(position, normal, radius, if fast then 6 else 12)
	flyingShards(position, normal, if fast then 4 else 10, radius * 0.6)
	BloodFX.Burst(position + normal, normal, { Amount = 30, Speed = { 16, 36 }, Spread = 70, Fast = fast })
	BloodFX.Splat(position, math.min(radius * 0.6, 6), fast)
	cameraKick(position, 1.3)
	task.delay(0.35, function()
		dissolveWeapon(state, position + normal * 2, fast)
	end)
	task.delay(1.2, function()
		endCast(data.CastId)
	end)
end

function handlers.Impact(data, fast)
	local state = casts[data.CastId]
	if typeof(data.Position) ~= "Vector3" then return end
	if not state then
		-- Chegou sem o Cast (longe quando começou): só o estouro
		if near(data.Position) then
			BloodFX.Burst(data.Position, data.Normal or Vector3.yAxis, { Amount = 18, Speed = { 12, 28 }, Spread = 70, Fast = fast })
		end
		return
	end
	if state.SkillId == "LancaSangue" then
		spearImpact(state, data, fast)
	elseif not state.Predicted then -- quem invocou já bateu o martelo no marcador
		hammerImpact(state, data, fast)
	end
end

function handlers.Dissolve(data, fast)
	local state = casts[data.CastId]
	if not state then return end
	state.Phase = "Done"
	local position = if typeof(data.Position) == "Vector3" then data.Position else (state.Weapon and state.Weapon:GetPivot().Position)
	if position then
		BloodFX.Burst(position, Vector3.yAxis, { Amount = 8, Speed = { 4, 10 }, Spread = 90, Fast = fast })
		dissolveWeapon(state, position, fast)
	end
	task.delay(0.5, function()
		endCast(data.CastId)
	end)
end

function handlers.Cancel(data, fast)
	local state = casts[data.CastId]
	if not state then return end
	local weapon = state.Weapon
	if weapon and weapon.Parent then
		BloodFX.Burst(weapon:GetPivot().Position, Vector3.yAxis, { Amount = 10, Speed = { 6, 16 }, Spread = 90, Fast = fast })
	end
	endCast(data.CastId)
end

-- Quadro a quadro: a arma na mão (crescendo) e a lança voando
RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local fast = FastMode.IsEnabled()
	for castId, state in casts do
		local character = state.Character
		local weapon = state.Weapon
		if not character.Parent then
			endCast(castId)
			continue
		end
		if not weapon or not weapon.Parent then continue end
		local t = now - state.StartTime
		local cfg = state.Cfg
		if state.Phase == "Form" or (state.Phase == "Planted" and not state.Frozen) then
			if state.Phase == "Form" then
				-- Cresce na mão a partir do FormTime
				local grow = smooth((t - cfg.FormTime) / GROW_TIME)
				local scale = math.max(0.05, grow)
				if math.abs(scale - state.Scale) > 0.01 then
					state.Scale = scale
					weapon:ScaleTo(scale)
				end
			else
				-- Primeiro quadro depois da batida (a pose do "Hit"): o martelo fica cravado ali e se desfaz
				state.Frozen = true
			end
			local hand = rightHand(character)
			if hand then
				if state.SkillId == "LancaSangue" then
					-- Apontada para a frente (e um pouco para cima), presa pela mão perto do cabo
					local forward = (flatLook(character) * math.cos(SPEAR_TILT) + Vector3.yAxis * math.sin(SPEAR_TILT)).Unit
					weapon:PivotTo(CFrame.lookAt(hand.Position, hand.Position + forward))
				else
					-- Martelo: o cabo na mão, inclinado para a frente do braço (HAMMER_GRIP)
					weapon:PivotTo(hand * HAMMER_GRIP)
				end
			end
		elseif state.Phase == "Flight" then
			local travelled = math.min(state.Range, state.Speed * math.max(0, now - state.LaunchTime))
			local point = state.From + state.Direction * travelled
			weapon:PivotTo(CFrame.lookAt(point, point + state.Direction))
			if state.Scale < 1 then
				state.Scale = 1
				weapon:ScaleTo(1)
			end
			if now >= state.NextDrip then
				state.NextDrip = now + (if fast then 0.16 else 0.07)
				BloodFX.Drip(point, 1, fast)
			end
		end
	end
end)

----------------------------------------------------------------------------------------------------
-- Início
----------------------------------------------------------------------------------------------------

Remotes.CombatFX.OnClientEvent:Connect(function(kind, data)
	if kind ~= "BloodFiend" or type(data) ~= "table" then return end
	local handler = handlers[data.Phase]
	if handler then
		handler(data, FastMode.IsEnabled())
	end
end)

task.spawn(function()
	assets = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("BloodFiend", 30)
	if not assets then return end
	-- Malhas e animações: só as malhas que carregaram entram (as outras ficam com a forma de reserva)
	-- As malhas entram no PreloadAsync como as próprias MeshParts: com o ID em texto ("rbxassetid://...") o Roblox
	-- devolve Failure até para malha que funciona (testado no Studio em 2026-10-02 com a Katana), e por isso o jogo usava
	-- as formas de reserva com as malhas do Sangue boas.
	local templates, ids = {}, {}
	for _, item in assets:GetDescendants() do
		if item:IsA("MeshPart") and item.MeshId ~= "" then
			table.insert(templates, item)
			table.insert(ids, item)
			local model = item:FindFirstAncestorOfClass("Model")
			partOffsets[item.Name] = if MESH_CENTERS[item.Name] then CFrame.new(MESH_CENTERS[item.Name])
				elseif model then model:GetPivot():ToObjectSpace(item.CFrame)
				else CFrame.identity
		elseif item:IsA("Animation") then
			table.insert(ids, item.AnimationId)
		end
	end
	local loaded = {}
	pcall(function()
		ContentProvider:PreloadAsync(ids, function(asset, status)
			if status == Enum.AssetFetchStatus.Success then
				loaded[asset] = true
			end
		end)
	end)
	local missing = {}
	for _, template in templates do
		if loaded[template.MeshId] then
			readyParts[template.Name] = template:Clone()
		else
			table.insert(missing, template.Name)
		end
	end
	if #missing > 0 then
		warn(`[BloodFiendVFX] Malhas que não carregaram (asset em análise ou recusado na moderação?): `
			.. `{table.concat(missing, ", ")}. Usando as formas de reserva.`)
	end
end)
