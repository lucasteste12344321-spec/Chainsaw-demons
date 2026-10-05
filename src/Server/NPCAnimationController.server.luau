local CollectionService = game:GetService("CollectionService")

local IDLE_R6 = 81917163455965
local IDLE_R15 = 87560833546455

local npcs = {}

local function findHumanoid(npc)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")

	if humanoid then
		return humanoid
	end

	for _, obj in npc:GetDescendants() do
		if obj:IsA("Humanoid") then
			return obj
		end
	end

	return nil
end

local function setupNPC(npc)
	if npcs[npc] then
		return
	end

	local humanoid = findHumanoid(npc)

	if not humanoid then
		warn("NPC sem Humanoid:", npc:GetFullName())
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")

	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local id

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		id = IDLE_R6
	else
		id = IDLE_R15
	end

	if not id or id == 0 then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	animation:Destroy()

	if not success or not track then
		warn(
			"Falha ao carregar idle:",
			npc.Name,
			humanoid.RigType.Name
		)
		return
	end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play(0.2)

	npcs[npc] = {
		Humanoid = humanoid,
		Track = track,
	}


end

local function removeNPC(npc)
	local data = npcs[npc]

	if data and data.Track then
		data.Track:Stop(0.2)
		data.Track:Destroy()
	end

	npcs[npc] = nil
end

for _, npc in CollectionService:GetTagged("QuestGiver") do
	setupNPC(npc)
end

CollectionService:GetInstanceAddedSignal("QuestGiver"):Connect(setupNPC)
CollectionService:GetInstanceRemovedSignal("QuestGiver"):Connect(removeNPC)