-- Armas dos estilos de combate no personagem (campo Weapon do estilo no CombatStyles; hoje só a Katana).
-- Quem tem o estilo (atributo Styles do player, escrito pelo PlayerData) carrega espada e bainha o tempo todo:
--   "Hip"   estilo guardado: bainha na cintura esquerda, espada dentro;
--   "Carry" equipado, andando: a CarryHand (direita) leva a espada pela bainha;
--   "Fight" atacando: a bainha passa para a FightHand (esquerda) e a direita segura a lâmina.
-- O CombatService chama MarkCombat a cada ataque (M1, skill, guarda); depois de CombatTime segundos sem atacar a lâmina
-- volta para a bainha. SetDrawn(false) guarda a lâmina na bainha na mão (Saque) e Sheathe encerra o combate na hora.
-- Juntas (todas criadas uma vez, só uma de cada peça ligada): espada = "<Estilo>Hand" (Motor6D no Right Arm) ou
-- "<Estilo>InSheath" (Weld na bainha); bainha = "<Estilo>SheathHip" (Weld no Torso), "<Estilo>SheathCarry" ou
-- "<Estilo>SheathFight" (Motor6D nos braços). As animações não mexem nelas.
-- Referências: a espada gira em volta da peça "Handle" (origem na guarda, lâmina no +Y); a bainha em volta da peça
-- "SheathRoot" (origem na boca, ponta no +Y). As duas são invisíveis; as peças visíveis ficam soldadas nelas.
-- Modelo: ReplicatedStorage.VFX.Weapons.<Weapon.Model>, com um Model da espada (pivô no cabo, lâmina no +Y) e um da
-- bainha (nome com "Saya"/"Bainha"; pivô na boca, ponta no +Y), como o AkiKatana do ChatGPT. A guarda, a curva e o encaixe
-- da lâmina na bainha saem das malhas. Sem o modelo, uma katana simples feita de peças.
-- Rastro: Trail "SwingTrail" desligado na lâmina (Handle) e na bainha (SheathRoot); o CombatFX liga no golpe.
-- Tudo no servidor (as juntas replicam para todos). Só R6 (Torso, Right Arm, Left Arm).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))

local StyleWeapons = {}

local combatUntil = setmetatable({}, { __mode = "k" }) -- [character] = { [estilo] = os.clock() }
local lastCombat = setmetatable({}, { __mode = "k" }) -- [character] = { [estilo] = os.clock() do último ataque }
local sheathedOverride = setmetatable({}, { __mode = "k" }) -- [character] = { [estilo] = true } lâmina guardada à força
local warned = {}

-- ================= Peças =================

local STEEL = Color3.fromRGB(205, 210, 220)
local WRAP = Color3.fromRGB(26, 22, 28)
local BRASS = Color3.fromRGB(122, 96, 52)
local LACQUER = Color3.fromRGB(14, 12, 16)
local CORD = Color3.fromRGB(150, 20, 28)

local function prepare(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function rootPart(name, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one * 0.1
	part.Transparency = 1
	part.CastShadow = false
	prepare(part)
	part.Parent = parent
	return part
end

-- Solda part no root, com offset no espaço do root
local function attachTo(root, part, offset)
	prepare(part)
	part.CFrame = root.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = offset
	weld.C1 = CFrame.identity
	weld.Parent = part
end

local function piece(parent, name, className, size, color, material)
	local part = Instance.new(className)
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Katana feita de peças (enquanto não existe o modelo no VFX). Devolve (model, Handle, SheathRoot).
local function buildKatana()
	local model = Instance.new("Model")
	local handle = rootPart("Handle", model)
	local sheathRoot = rootPart("SheathRoot", model)
	model.PrimaryPart = handle
	-- Espada (origem na guarda): cabo abaixo, lâmina acima
	attachTo(handle, piece(model, "Grip", "Part", Vector3.new(0.2, 1.1, 0.2), WRAP, Enum.Material.Fabric), CFrame.new(0, -0.59, 0))
	attachTo(handle, piece(model, "Pommel", "Part", Vector3.new(0.24, 0.1, 0.24), BRASS, Enum.Material.Metal), CFrame.new(0, -1.19, 0))
	local guard = piece(model, "Guard", "Part", Vector3.new(0.08, 0.62, 0.62), BRASS, Enum.Material.Metal)
	guard.Shape = Enum.PartType.Cylinder
	attachTo(handle, guard, CFrame.Angles(0, 0, math.pi / 2))
	attachTo(handle, piece(model, "Collar", "Part", Vector3.new(0.1, 0.14, 0.28), BRASS, Enum.Material.Metal), CFrame.new(0, 0.11, 0))
	-- Lâmina larga no X, com o fio no -X (mesma regra do modelo importado)
	local blade = piece(model, "Blade", "Part", Vector3.new(0.24, 3, 0.05), STEEL, Enum.Material.Metal)
	blade.Reflectance = 0.25
	attachTo(handle, blade, CFrame.new(0, 1.68, 0))
	attachTo(handle, piece(model, "Edge", "Part", Vector3.new(0.05, 3, 0.055), Color3.fromRGB(245, 247, 255)), CFrame.new(-0.1, 1.68, 0))
	local tip = piece(model, "Tip", "WedgePart", Vector3.new(0.05, 0.36, 0.24), STEEL, Enum.Material.Metal)
	tip.Reflectance = 0.25
	attachTo(handle, tip, CFrame.new(0, 3.36, 0) * CFrame.Angles(0, math.pi / 2, 0))
	-- Bainha (origem na boca)
	attachTo(sheathRoot, piece(model, "Sheath", "Part", Vector3.new(0.34, 3.5, 0.18), LACQUER), CFrame.new(0, 1.75, 0))
	attachTo(sheathRoot, piece(model, "Cord", "Part", Vector3.new(0.38, 0.12, 0.22), CORD, Enum.Material.Fabric), CFrame.new(0, 0.28, 0))
	handle:SetAttribute("TrailTip", Vector3.new(0, 3.25, 0))
	sheathRoot:SetAttribute("TrailTip", Vector3.new(0, 3.4, 0))
	return model, handle, sheathRoot, CFrame.identity
end

-- ================= Modelo importado (ReplicatedStorage.VFX.Weapons.<Model>) =================

local function nameHas(instance, words)
	local lower = string.lower(instance.Name)
	for _, word in words do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

local SHEATH_WORDS = { "saya", "bainha", "sheath", "scabbard" }

-- Separa as peças do modelo em espada e bainha (pelo nome da peça ou de um Model/Folder acima dela)
local function splitParts(template)
	local sword, sheath = {}, {}
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") then
			local isSheath = false
			local node = part
			while node and node ~= template do
				if nameHas(node, SHEATH_WORDS) then
					isSheath = true
					break
				end
				node = node.Parent
			end
			table.insert(if isSheath then sheath else sword, part)
		end
	end
	return sword, sheath
end

-- Pivô do grupo: o do Model de cima (o ChatGPT deixa o da espada no centro do cabo e o da bainha na boca), ou o da
-- primeira peça
local function groupPivot(parts, template)
	local node = parts[1]
	while node and node ~= template do
		if node:IsA("Model") then
			return node:GetPivot()
		end
		node = node.Parent
	end
	return CFrame.new(parts[1]:GetPivot().Position)
end

-- Peça mais longa no eixo Y (lâmina / corpo da bainha)
local function longestPart(parts)
	local best
	for _, part in parts do
		if not best or part.ExtentsSize.Y > best.ExtentsSize.Y then
			best = part
		end
	end
	return best
end

-- Ponta do rastro: perto do fim da peça longa, puxada para o lado das costas (+X), onde a curva leva a ponta.
-- inset = quanto fica para dentro da borda +X (meia largura da lâmina/bainha)
local function tipOf(frame, part, scale, inset)
	local center = frame:PointToObjectSpace(part.ExtentsCFrame.Position)
	local size = part.ExtentsSize
	return Vector3.new(center.X + size.X / 2 - inset, center.Y + size.Y / 2 - 0.1, center.Z) * scale
end

-- Guarda: a peça mais larga e mais baixa (tsuba)
local function guardPart(parts)
	local best, bestScore
	for _, part in parts do
		local size = part.ExtentsSize
		local score = size.X * size.Z / math.max(size.Y, 0.01)
		if not bestScore or score > bestScore then
			best, bestScore = part, score
		end
	end
	return best
end

-- Copia um grupo de peças, escala e solda num root que fica em frame (lâmina no +Y do frame)
local function mountGroup(model, rootName, parts, scale, frame)
	local root = rootPart(rootName, model)
	local origin = frame
	for _, source in parts do
		local part = source:Clone()
		for _, child in part:GetChildren() do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end
		local offset = origin:ToObjectSpace(source.CFrame)
		offset = offset.Rotation + offset.Position * scale
		part.Size = source.Size * scale
		part.Parent = model
		attachTo(root, part, offset)
	end
	return root
end

-- Modelo com a espada (pivô no cabo, lâmina no +Y) e a bainha (lâmina guardada no +Y). A lâmina e a bainha do AkiKatana
-- curvam para o mesmo lado (+X), então não precisam girar: a espada vai com a face de cima da guarda na boca da bainha.
-- O pivô da bainha não fica no centro da boca: cfg.SheathMouthOffset (medido nos vértices da malha). Devolve (model,
-- Handle, SheathRoot, posição da espada guardada em relação à bainha).
local function importedKatana(template, cfg)
	local swordParts, sheathParts = splitParts(template)
	if #swordParts == 0 then return nil end
	local scale = cfg.Scale or 1
	local model = Instance.new("Model")

	-- Espada: root na face de cima da guarda
	local swordPivot = groupPivot(swordParts, template)
	local guard = guardPart(swordParts)
	local guardTop = swordPivot:PointToObjectSpace(guard.ExtentsCFrame.Position).Y + guard.ExtentsSize.Y / 2
	local swordFrame = swordPivot * CFrame.new(0, guardTop, 0)
	local handle = mountGroup(model, "Handle", swordParts, scale, swordFrame)
	handle:SetAttribute("TrailTip", tipOf(swordFrame, longestPart(swordParts), scale, 0.08))
	model.PrimaryPart = handle

	-- Bainha: root no centro da boca
	local sheathRoot
	if #sheathParts > 0 then
		local sheathPivot = groupPivot(sheathParts, template)
		local sheathFrame = sheathPivot * CFrame.new(cfg.SheathMouthOffset or Vector3.zero)
		sheathRoot = mountGroup(model, "SheathRoot", sheathParts, scale, sheathFrame)
		sheathRoot:SetAttribute("TrailTip", tipOf(sheathFrame, longestPart(sheathParts), scale, 0.12))
	else
		sheathRoot = rootPart("SheathRoot", model)
	end
	return model, handle, sheathRoot, cfg.SheathedOffset or CFrame.identity
end

local BUILDERS = { Katana = buildKatana }

local function newWeapon(styleName, cfg)
	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local folder = vfx and vfx:FindFirstChild("Weapons")
	local template = folder and folder:FindFirstChild(cfg.Model or styleName)
	local model, handle, sheathRoot, sheathed
	if template then
		model, handle, sheathRoot, sheathed = importedKatana(template, cfg)
		if not model and not warned[styleName .. "model"] then
			warned[styleName .. "model"] = true
			warn(`[StyleWeapons] O modelo VFX.Weapons.{template.Name} não tem peças de espada: usando a katana de peças`)
		end
	end
	if not model and BUILDERS[styleName] then
		model, handle, sheathRoot, sheathed = BUILDERS[styleName]()
	end
	if not model then
		if not warned[styleName] then
			warned[styleName] = true
			warn(`[StyleWeapons] Sem modelo para a arma de {styleName} (ReplicatedStorage.VFX.Weapons.{cfg.Model or styleName})`)
		end
		return nil
	end
	model.Name = styleName .. "Weapon"
	return model, handle, sheathRoot, sheathed
end

-- Rastro do golpe: Trail "SwingTrail" entre a guarda e a ponta (atributo TrailTip do root), desligado. Quem liga é o
-- CombatFX de cada cliente, no golpe (o rastro segue a lâmina porque está preso nela).
local TRAIL_COLOR = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(240, 31, 52))
local TRAIL_ALPHA = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
local TRAIL_WIDTH = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.35) })

local function addTrail(root)
	local tip = root:GetAttribute("TrailTip")
	if typeof(tip) ~= "Vector3" then return end
	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = Vector3.new(0, 0.3, 0)
	base.Parent = root
	local tipAttachment = Instance.new("Attachment")
	tipAttachment.Name = "TrailTip"
	tipAttachment.Position = tip
	tipAttachment.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tipAttachment
	trail.Lifetime = 0.16
	trail.MinLength = 0
	trail.FaceCamera = false
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = TRAIL_COLOR
	trail.Transparency = TRAIL_ALPHA
	trail.WidthScale = TRAIL_WIDTH
	trail.Enabled = false
	trail.Parent = root
end

-- ================= Montagem no personagem =================

-- Frame com o +Y em direction e o +X o mais perto possível de spine (lado das costas da lâmina: o fio fica no -X)
local function frameAlong(position, direction, spine)
	direction = direction.Unit
	local side = spine or Vector3.xAxis
	side = side - direction * side:Dot(direction)
	if side.Magnitude < 0.05 then
		side = Vector3.zAxis - direction * direction.Z
	end
	return CFrame.fromMatrix(position, side.Unit, direction)
end

local function newJoint(className, name, part0, part1, c0, c1, parent)
	local joint = Instance.new(className)
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = c1 or CFrame.identity
	joint.Enabled = false
	joint.Parent = parent
	return joint
end

-- Cria (uma vez por personagem) a arma e as juntas. Devolve a tabela de juntas ou nil.
local rigs = setmetatable({}, { __mode = "k" }) -- [character] = { [estilo] = { Model, Joints } }
local function ensureWeapon(character, styleName, cfg)
	local list = rigs[character]
	local rig = list and list[styleName]
	if rig and rig.Model.Parent == character then return rig end

	local torso = character:FindFirstChild("Torso")
	local right = character:FindFirstChild("Right Arm")
	local carryArm = character:FindFirstChild(cfg.CarryHand or "Right Arm")
	local fightArm = character:FindFirstChild(cfg.FightHand or "Left Arm")
	if not (torso and right and carryArm and fightArm) then return nil end
	local model, handle, sheathRoot, sheathed = newWeapon(styleName, cfg)
	if not model then return nil end
	addTrail(handle)
	addTrail(sheathRoot)

	local hand = cfg.Hand or CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	-- Guardada (cintura e na mão), a katana vai com o fio para cima: costas da lâmina (+X) para baixo
	local hipFrame = frameAlong(cfg.SheathMouth or Vector3.new(-1.05, -0.5, -0.3), cfg.SheathDirection or Vector3.new(0, -0.45, 1),
		Vector3.new(0, -1, 0))
	local inHand = (cfg.SheathInHand or Vector3.new(0, -0.87, -0.5)).Unit
	local handFrame = frameAlong(-inHand * (cfg.SheathGrip or 0.35), inHand, Vector3.new(0, 0, -1)) -- -Z da mão = descendo o braço
	-- Na mão: gira a lâmina em volta do próprio eixo (BladeRoll, graus) e segura GripBelowGuard abaixo da guarda
	local gripPoint = (CFrame.Angles(0, math.rad(cfg.BladeRoll or 0), 0) * CFrame.new(0, cfg.GripBelowGuard or 0.3, 0)):Inverse()

	handle.CFrame = torso.CFrame * hipFrame
	sheathRoot.CFrame = torso.CFrame * hipFrame
	local joints = {
		SwordHand = newJoint("Motor6D", styleName .. "Hand", right, handle, hand, gripPoint, right),
		SwordInSheath = newJoint("Weld", styleName .. "InSheath", sheathRoot, handle, sheathed, nil, sheathRoot),
		SheathHip = newJoint("Weld", styleName .. "SheathHip", torso, sheathRoot, hipFrame, nil, torso),
		SheathCarry = newJoint("Motor6D", styleName .. "SheathCarry", carryArm, sheathRoot, hand * handFrame, nil, carryArm),
		SheathFight = newJoint("Motor6D", styleName .. "SheathFight", fightArm, sheathRoot, hand * handFrame, nil, fightArm),
	}
	model.Parent = character

	rig = { Model = model, Joints = joints, State = nil }
	rigs[character] = list or {}
	rigs[character][styleName] = rig
	return rig
end

-- O estilo está em uso (atributo EquippedStyles do PlayerData: guardado no inventário ou travado pela fusão do
-- contrato não conta, e a arma some do corpo)
local function ownsStyle(player, styleName)
	local raw = player:GetAttribute("EquippedStyles") or player:GetAttribute("Styles")
	if type(raw) ~= "string" then
		return table.find(CombatStyles.StartingStyles, styleName) ~= nil
	end
	local ok, list = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return ok and type(list) == "table" and table.find(list, styleName) ~= nil
end

local function isEquipped(character, styleName)
	local tool = character:FindFirstChild(styleName)
	return tool ~= nil and tool:IsA("Tool")
end

local STATE_JOINTS = {
	Hip = { "SwordInSheath", "SheathHip" },
	Carry = { "SwordInSheath", "SheathCarry" },
	Fight = { "SwordHand", "SheathFight" },
	Sheathing = { "SwordInSheath", "SheathFight" }, -- Saque: lâmina na bainha, bainha na mão esquerda
}

local function refreshStyle(player, character, styleName, cfg)
	if not ownsStyle(player, styleName) then
		local list = rigs[character]
		if list and list[styleName] then
			list[styleName].Model:Destroy()
			list[styleName] = nil
		end
		return
	end
	local rig = ensureWeapon(character, styleName, cfg)
	if not rig then return end
	local state = "Hip"
	if isEquipped(character, styleName) then
		local untilTime = combatUntil[character] and combatUntil[character][styleName] or 0
		local forced = sheathedOverride[character] and sheathedOverride[character][styleName]
		state = if forced then "Sheathing" elseif os.clock() < untilTime then "Fight" else "Carry"
	end
	if rig.State == state then return end
	rig.State = state
	-- Desliga todas antes de ligar as do estado (duas juntas ativas na mesma peça brigam)
	for _, joint in rig.Joints do
		joint.Enabled = false
	end
	for _, name in STATE_JOINTS[state] do
		rig.Joints[name].Enabled = true
	end
end

local function refresh(player)
	local character = player.Character
	if not character or not character.Parent then return end
	for styleName, style in CombatStyles.Styles do
		if style.Weapon then
			refreshStyle(player, character, styleName, style.Weapon)
		end
	end
end

local function refreshCharacter(character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		refresh(player)
	end
end

local function styleTable(map, character)
	local entry = map[character]
	if not entry then
		entry = {}
		map[character] = entry
	end
	return entry
end

-- Atacou (M1, skill, guarda): lâmina na mão por CombatTime segundos
function StyleWeapons.MarkCombat(character, styleName)
	local style = character and CombatStyles.Styles[styleName]
	if not style or not style.Weapon then return end
	local duration = style.Weapon.CombatTime or 4
	local clock = os.clock()
	styleTable(lastCombat, character)[styleName] = clock
	local until_ = styleTable(combatUntil, character)
	until_[styleName] = clock + duration
	refreshCharacter(character)
	task.delay(duration + 0.05, function()
		if (until_[styleName] or 0) <= os.clock() then
			refreshCharacter(character)
		end
	end)
end

-- Guarda a lâmina na hora (marcador "Sheathe" do Saque), se não houve ataque depois de since (os.clock)
function StyleWeapons.Sheathe(character, styleName, since)
	if not character then return end
	local last = lastCombat[character] and lastCombat[character][styleName] or 0
	if since and last > since then return end
	styleTable(combatUntil, character)[styleName] = 0
	refreshCharacter(character)
end

-- drawn = false: lâmina dentro da bainha (na mão esquerda) mesmo lutando; nil volta ao normal
function StyleWeapons.SetDrawn(character, styleName, drawn)
	if not character then return end
	styleTable(sheathedOverride, character)[styleName] = if drawn == false then true else nil
	refreshCharacter(character)
end

local function onCharacter(player, character)
	character:WaitForChild("Torso", 10)
	character:WaitForChild("Right Arm", 10)
	character:WaitForChild("Left Arm", 10)
	if player.Character ~= character then return end
	refresh(player)
	local function onTool(child)
		if child:IsA("Tool") and CombatStyles.Styles[child.Name] then
			refresh(player)
		end
	end
	character.ChildAdded:Connect(onTool)
	character.ChildRemoved:Connect(onTool)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	player:GetAttributeChangedSignal("EquippedStyles"):Connect(function()
		refresh(player)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end

return StyleWeapons
