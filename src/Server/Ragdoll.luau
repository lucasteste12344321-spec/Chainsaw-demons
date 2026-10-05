-- Ragdoll de R6 (servidor): o corpo cai mole no chão por um tempo e levanta sozinho.
-- As juntas dos braços, pernas e cabeça (Motor6D do Torso) são trocadas por BallSocketConstraint, e cada membro ganha
-- um colisor invisível (os membros do R6 não colidem). O personagem fica com o atributo "Ragdoll" = true: o cliente
-- do jogador (CombatInput) põe o Humanoid no estado Physics (a física do personagem é dele); em NPC o próprio servidor
-- faz isso. Quem usa: o Contra-agarrão dos Punhos (CombatService).
local Debris = game:GetService("Debris")

local Ragdoll = {}

local JOINTS = { "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" }
local LIMBS = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local active = {} -- [character] = função que desfaz

local function socket(motor)
	local part0, part1 = motor.Part0, motor.Part1
	if not part0 or not part1 then return nil end
	local a0 = Instance.new("Attachment")
	a0.Name = "RagdollA0"
	a0.CFrame = motor.C0
	a0.Parent = part0
	local a1 = Instance.new("Attachment")
	a1.Name = "RagdollA1"
	a1.CFrame = motor.C1
	a1.Parent = part1
	local constraint = Instance.new("BallSocketConstraint")
	constraint.Name = "RagdollSocket"
	constraint.Attachment0 = a0
	constraint.Attachment1 = a1
	constraint.LimitsEnabled = true
	constraint.TwistLimitsEnabled = true
	constraint.UpperAngle = if motor.Name == "Neck" then 45 else 90
	constraint.TwistLowerAngle = -45
	constraint.TwistUpperAngle = 45
	constraint.Parent = part0
	return { a0, a1, constraint }
end

-- Derruba o personagem por duration segundos (chamar de novo só estende). Devolve true se derrubou.
function Ragdoll.Apply(character, duration)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local torso = character and character:FindFirstChild("Torso")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not torso or not root then return false end

	local untilTime = os.clock() + duration
	character:SetAttribute("RagdollUntil", untilTime)
	if active[character] then return true end

	local created, disabled = {}, {}
	for _, name in JOINTS do
		local motor = torso:FindFirstChild(name)
		if motor and motor:IsA("Motor6D") and motor.Enabled then
			local parts = socket(motor)
			if parts then
				for _, instance in parts do
					table.insert(created, instance)
				end
				motor.Enabled = false
				table.insert(disabled, motor)
			end
		end
	end
	for _, name in LIMBS do
		local limb = character:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			local collider = Instance.new("Part")
			collider.Name = "RagdollCollider"
			collider.Size = Vector3.new(0.9, 1.6, 0.9)
			collider.Transparency = 1
			collider.Massless = true
			collider.CanCollide = true
			collider.CanQuery = false
			collider.CanTouch = false
			collider.CollisionGroup = limb.CollisionGroup
			collider.CFrame = limb.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = collider
			weld.Part1 = limb
			weld.Parent = collider
			collider.Parent = limb
			table.insert(created, collider)
		end
	end
	-- NPC: a IA vira o corpo com o AlignOrientation "EnemyFacing" (deixaria o boneco em pé)
	local facing = {}
	for _, child in root:GetChildren() do
		if child:IsA("AlignOrientation") and child.Enabled then
			child.Enabled = false
			table.insert(facing, child)
		end
	end
	for _, instance in created do
		Debris:AddItem(instance, duration + 5)
	end

	character:SetAttribute("Ragdoll", true)
	local isNPC = game:GetService("Players"):GetPlayerFromCharacter(character) == nil
	if isNPC then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	local function restore()
		if active[character] ~= restore then return end
		active[character] = nil
		for _, instance in created do
			instance:Destroy()
		end
		for _, motor in disabled do
			if motor.Parent then
				motor.Enabled = true
			end
		end
		for _, align in facing do
			if align.Parent then
				align.Enabled = true
			end
		end
		if character.Parent then
			character:SetAttribute("Ragdoll", nil)
			character:SetAttribute("RagdollUntil", nil)
		end
		if isNPC and humanoid.Parent and humanoid.Health > 0 then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	active[character] = restore

	-- Levanta quando o tempo acabar (cada Apply novo empurra o fim); morto, continua caído
	task.spawn(function()
		while active[character] == restore do
			local left = (character:GetAttribute("RagdollUntil") or 0) - os.clock()
			if left <= 0 or not character.Parent then break end
			task.wait(math.min(left, 0.25))
		end
		if humanoid.Parent and humanoid.Health > 0 then
			restore()
		elseif active[character] == restore then
			active[character] = nil -- morreu caído: o corpo some com o personagem
		end
	end)
	return true
end

function Ragdoll.IsRagdolled(character)
	return active[character] ~= nil
end

return Ragdoll
