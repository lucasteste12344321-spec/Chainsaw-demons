-- Animação parada dos NPCs de missão (tag QuestGiver). No Studio, coloque no Model do NPC o atributo
-- IdleAnimation (number) com o ID da animação; ela toca em loop, tocada pelo servidor (todos veem).
-- A animação precisa ser do mesmo rig do NPC (R6 ou R15) e estar publicada na conta ou grupo dono do jogo.
-- Mudar o atributo durante o jogo troca a animação na hora.
local CollectionService = game:GetService("CollectionService")

local NPC_TAG = "QuestGiver"

local playing = setmetatable({}, { __mode = "k" }) -- [model] = AnimationTrack

-- O Humanoid pode estar no próprio Model ou num Model de dentro (ex.: Tabelia > Dummy)
local function findHumanoid(model)
	return model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
end

local function applyIdle(model)
	local old = playing[model]
	if old then
		old:Stop(0.2)
		old:Destroy()
		playing[model] = nil
	end

	local id = model:GetAttribute("IdleAnimation")
	if type(id) ~= "number" or id <= 0 then return end
	local humanoid = findHumanoid(model)
	if not humanoid then
		warn(`[NPCAnimations] {model:GetFullName()} tem IdleAnimation, mas não tem Humanoid`)
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(`[NPCAnimations] Não consegui carregar a animação {id} em {model:GetFullName()}: {track}`)
		return
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play(0.2)
	playing[model] = track
end

local function setup(model)
	if not model:IsA("Model") then return end
	model:GetAttributeChangedSignal("IdleAnimation"):Connect(function()
		applyIdle(model)
	end)
	applyIdle(model)
end

for _, model in CollectionService:GetTagged(NPC_TAG) do
	task.spawn(setup, model)
end
CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(setup)
