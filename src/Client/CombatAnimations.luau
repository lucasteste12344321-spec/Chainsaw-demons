-- Animações de combate do próprio personagem. Quem toca é este cliente (dono do personagem), então todos veem.
-- Pose de luta parada, golpes (na hora do clique, sem esperar o servidor), guarda, guarda levando golpe, rajada,
-- carga, soco carregado e as skills das teclas Z/X/C. Estilo sem o ID (CombatStyles.Animations = 0): não toca nada.
-- ModuleScript: o CombatInput chama PlayAttack/CancelAttack; o movimento chama CancelAttack no dash; o resto reage
-- aos atributos e ao Remotes.CombatFX.
--
-- Camadas de prioridade (uma camada de cima sobrepõe as de baixo; iguais se cancelam):
--   Action3: golpes (M1, uppercut, soco carregado) e guarda levando golpe
--   Action2: posturas (guarda, carga, rajada), equipar e reação de quem apanha (tocada pelo servidor)
--   Action:  dash e recarga (StaminaDashRunscript)
--   Movement / Idle / Core: correr, pose de luta, andar e parado (Animate)
local ATTACK = Enum.AnimationPriority.Action3
local STANCE = Enum.AnimationPriority.Action2

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))

local player = Players.LocalPlayer

local CombatAnimations = {}

local character, humanoid, animator
local tracks = {} -- [id] = AnimationTrack do personagem atual
local loops = {} -- [nome] = AnimationTrack tocando em loop
local characterConnections = {}

local function getTrack(id)
	if not id or not animator or not animator.Parent then return nil end
	local track = tracks[id]
	if track then return track end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, loaded = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not loaded then return nil end
	tracks[id] = loaded
	return loaded
end

local function playOnce(id, priority, fade)
	local track = getTrack(id)
	if not track then return nil end
	track.Priority = priority
	track.Looped = false
	if track.IsPlaying then
		track:Stop(0)
	end
	track:Play(fade or 0.05)
	return track
end

local function startLoop(name, id, priority)
	local track = getTrack(id)
	local current = loops[name]
	if current and current == track and current.IsPlaying then return end
	if current then
		current:Stop(0.15)
	end
	loops[name] = track
	if track then
		track.Priority = priority
		track.Looped = true
		track:Play(0.15)
	end
end

local function stopLoop(name, fade)
	local track = loops[name]
	if track then
		loops[name] = nil
		track:Stop(fade or 0.15)
	end
end

-- Estilo equipado, guardado: a pose de luta confere a cada frame e procurar o Tool (e a fusão do contrato) toda vez
-- criava lixo à toa. Vale até trocar de Tool, de caminho/contrato/forma ou de personagem.
local cachedStyle, styleDirty = nil, true
local function currentStyle()
	if styleDirty then
		local _, style = CombatStyles.FromCharacter(character)
		cachedStyle, styleDirty = style, false
	end
	return cachedStyle
end
for _, attribute in { "Path", "Contracts", "ContractForm" } do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		styleDirty = true
	end)
end

local attackTrack -- golpe tocando agora (para cancelar)
local attackId = 0 -- muda a cada golpe novo ou cancelado (o CombatInput descarta hitbox de golpe cortado)

function CombatAnimations.AttackId()
	return attackId
end

-- Combo numa animação só (Animations.M1Chain + M1.Segments { Start, End } por golpe, ex.: Punhos da Raposa): cada
-- clique toca o trecho do golpe. Se o trecho anterior ainda está na tela, segue dele sem cortar (emenda); no fim do
-- trecho a pose segura CHAIN_HOLD esperando o próximo clique e, sem ele, solta.
local CHAIN_HOLD = 0.3

local function playSegment(id, segment)
	local myAttack = attackId
	local track = getTrack(id)
	if not track then return nil end
	if attackTrack and attackTrack ~= track and attackTrack.IsPlaying then
		attackTrack:Stop(0.03)
	end
	if track.IsPlaying and attackTrack == track then
		-- Emenda: o trecho anterior parou onde este começa (pula para o começo se ficou longe)
		if math.abs(track.TimePosition - segment.Start) > 0.1 then
			track.TimePosition = segment.Start
		end
		track:AdjustSpeed(1)
	else
		track = playOnce(id, ATTACK, 0.05)
		if not track then return nil end
		if segment.Start > 0 then
			track.TimePosition = segment.Start
		end
	end
	attackTrack = track
	task.spawn(function()
		while attackId == myAttack and track.IsPlaying and track.TimePosition < segment.End do
			task.wait()
		end
		if attackId ~= myAttack or not track.IsPlaying then return end
		track:AdjustSpeed(0) -- segura a pose (menos de 1 s: a rede de segurança de animação parada não mexe)
		task.wait(CHAIN_HOLD)
		if attackId == myAttack and track.IsPlaying then
			track:Stop(0.2)
		end
	end)
	return track
end

-- Golpe do próprio jogador, tocado na hora do clique (move = "M1", "Uppercut" ou "ChargedPunch"; combo = 1 a 5).
-- Devolve a AnimationTrack (para esperar o marcador de impacto) ou nil se o estilo não tem essa animação.
function CombatAnimations.PlayAttack(style, move, combo)
	attackId += 1
	local chainId = if move == "M1" then CombatStyles.Animation(style, "M1Chain") else nil
	local segment = chainId and style.M1 and style.M1.Segments and style.M1.Segments[combo]
	if segment then
		return playSegment(chainId, segment)
	end
	local id = CombatStyles.Animation(style, move, combo)
	if not id then return nil end
	if attackTrack and attackTrack.IsPlaying then
		attackTrack:Stop(0.03)
	end
	attackTrack = playOnce(id, ATTACK, 0.03)
	return attackTrack
end

-- Skill com animação própria (as da Katana: move = campo Animation da skill no CombatStyles). Devolve a track (o
-- CombatFX segue os marcadores dela) ou nil quando o estilo ainda não tem a animação.
-- startAt / speed (opcionais): começa no meio da animação e/ou mais rápido (ex.: o Kon! usa um trecho do gesto da mira)
function CombatAnimations.PlaySkill(style, move, startAt, speed)
	CombatAnimations.CancelAttack()
	local id = CombatStyles.Animation(style, move)
	if not id then return nil end
	attackTrack = playOnce(id, ATTACK, 0.05)
	if attackTrack then
		if type(speed) == "number" and speed > 0 then
			attackTrack:AdjustSpeed(speed)
		end
		if type(startAt) == "number" and startAt > 0 then
			attackTrack.TimePosition = startAt
		end
	end
	return attackTrack
end

-- Pose que segura no fim: toca move, para no tempo holdAt (o marcador da pose) e solta depois de hold segundos.
-- Usada pelo Avanço cortante quando acerta (a pose do corte antes da chuva de cortes).
function CombatAnimations.PlayHeldPose(style, move, holdAt, hold)
	CombatAnimations.CancelAttack()
	local id = CombatStyles.Animation(style, move)
	if not id then return nil end
	local track = playOnce(id, ATTACK, 0.03)
	if not track then return nil end
	attackTrack = track
	local myAttack = attackId
	task.delay(math.max(0, holdAt - 0.02), function()
		if attackId ~= myAttack or not track.IsPlaying then return end
		track:AdjustSpeed(0) -- segura a pose (menos de 1 s: a rede de segurança de animação parada não mexe)
		task.delay(hold or 0.3, function()
			if track.IsPlaying and track.Speed == 0 then
				track:Stop(0.2)
			end
		end)
	end)
	return track
end

-- Corta o golpe que está tocando (dash, skill ou guarda cancelando o fim do M1)
function CombatAnimations.CancelAttack()
	attackId += 1
	if attackTrack and attackTrack.IsPlaying then
		attackTrack:Stop(0.08)
	end
	attackTrack = nil
end

-- ================= Soco carregado (skill Kind "Charge") =================
-- Uma animação só: começa ao apertar, congela no marcador de carga (ChargeMarker) enquanto a tecla está pressionada
-- e continua ao soltar até o marcador de impacto (HitMarker, esperado pelo CombatInput).

local chargeTrack -- animação do soco carregado esperando o jogador soltar
local chargeReleased = false
local chargeSince = 0 -- os.clock em que a carga começou (rede de segurança de animação parada)

local function stopCharge()
	if chargeTrack and chargeTrack.IsPlaying then
		chargeTrack:Stop(0.12)
	end
	chargeTrack = nil
end

-- Apertou a tecla da carga (o servidor ainda vai confirmar pelo atributo Charging)
function CombatAnimations.StartCharge(style)
	local _, cfg = CombatStyles.SkillOfKind(style, "Charge")
	local id = CombatStyles.Animation(style, "ChargedPunch")
	if not cfg or not id then return nil end
	CombatAnimations.CancelAttack()
	local track = playOnce(id, ATTACK, 0.05)
	if not track then return nil end
	attackTrack = track
	chargeTrack = track
	chargeReleased = false
	chargeSince = os.clock()
	if cfg.ChargeMarker then
		local connections
		connections = CombatStyles.OnMarker(track, cfg.ChargeMarker, function()
			for _, connection in connections do
				connection:Disconnect()
			end
			if chargeTrack == track and not chargeReleased then
				track:AdjustSpeed(0) -- segura a pose de carga
			end
		end)
	end
	-- O servidor recusou a carga (recarga, stun no caminho): não deixa a pose presa
	task.delay(0.6, function()
		if chargeTrack == track and not chargeReleased and character and character:GetAttribute("Charging") ~= true then
			stopCharge()
		end
	end)
	return track
end

-- Soltou a tecla: a animação continua de onde parou. Devolve a track (para esperar o impacto) ou nil.
function CombatAnimations.ReleaseCharge()
	local track = chargeTrack
	chargeReleased = true
	chargeTrack = nil
	if not track or not track.IsPlaying then return nil end
	track:AdjustSpeed(1)
	attackId += 1
	attackTrack = track
	return track
end

-- A carga acabou sem soltar o soco (stun, trocou de arma, servidor recusou)
function CombatAnimations.StopCharge()
	chargeReleased = true
	stopCharge()
end

-- ================= Rajada (skill Kind "Barrage") =================

-- Apertou a tecla: a animação começa na hora (o servidor manda o fim pelo CombatFX "BarrageEnd")
function CombatAnimations.StartBarrage(style)
	local _, cfg = CombatStyles.SkillOfKind(style, "Barrage")
	local id = CombatStyles.Animation(style, "Barrage")
	if not cfg or not id then return end
	CombatAnimations.CancelAttack()
	-- Toca uma vez (a animação tem o tamanho da rajada), guardada em loops para o "BarrageEnd" poder parar
	local previous = loops.Barrage
	if previous then
		previous:Stop(0.1)
	end
	local track = playOnce(id, STANCE, 0.1)
	loops.Barrage = track
	-- Se o servidor recusar (sem "BarrageEnd"), para sozinha no fim do tempo da rajada (com os golpes extras da árvore)
	local extraHits = player:GetAttribute("TreeRajadaHits")
	local hits = cfg.Hits + (if type(extraHits) == "number" then math.floor(extraHits) else 0)
	-- A animação foi feita para a rajada padrão (BaseHits golpes, um pouco mais longa que eles): com mais golpes
	-- ("Rajada longa" na árvore, Rajada de Garras da fusão) ela fica mais lenta na mesma medida, para durar até o fim
	local baseHits = cfg.BaseHits or 9
	if track and hits > baseHits then
		track:AdjustSpeed(math.max(0.45, baseHits / hits))
	end
	task.delay(hits * cfg.HitInterval + 0.4, function()
		if loops.Barrage == track then
			stopLoop("Barrage")
		end
	end)
end

-- ================= Guarda e carga (pelos atributos que o servidor escreve) =================

local function updateStance()
	if not character then return end
	local style = currentStyle()
	if character:GetAttribute("Blocking") == true then
		CombatAnimations.CancelAttack()
		startLoop("Block", CombatStyles.Animation(style, "Block"), STANCE)
	else
		stopLoop("Block")
	end
	if character:GetAttribute("Charging") == true then
		-- A animação do soco carregado já começou no clique; só corta outro golpe que estivesse tocando
		if not chargeTrack then
			CombatAnimations.CancelAttack()
		end
		startLoop("Charge", CombatStyles.Animation(style, "Charge"), STANCE)
	else
		stopLoop("Charge", 0.05)
		-- Carga acabou sem soltar (stun, tempo esgotado no servidor): a pose de carga não fica presa
		if chargeTrack and not chargeReleased then
			CombatAnimations.StopCharge()
		end
	end
end

-- ================= Eventos do servidor para o próprio personagem =================

Remotes.CombatFX.OnClientEvent:Connect(function(kind, data)
	if type(data) ~= "table" or data.Character == nil or data.Character ~= character then return end
	local style = currentStyle()
	if kind == "Blocked" or kind == "Parry" then
		playOnce(CombatStyles.Animation(style, "BlockHit"), ATTACK, 0.03)
	elseif kind == "Barrage" then
		-- Normalmente já está tocando desde o clique (StartBarrage); aqui só garante
		if not loops.Barrage then
			CombatAnimations.StartBarrage(style)
		end
	elseif kind == "BarrageEnd" then
		stopLoop("Barrage")
	elseif kind == "KatanaGrabMiss" then
		CombatAnimations.CancelAttack() -- agarrão errou (ou soltou antes): não termina a animação no vazio
	elseif kind == "DashSlashConnect" then
		-- Avanço acertou: pose do corte, parada no marcador enquanto os alvos esperam os cortes
		local _, skill = CombatStyles.SkillOfKind(style, "DashSlash")
		if skill and skill.FinishAnimation then
			CombatAnimations.PlayHeldPose(style, skill.FinishAnimation, skill.FinishHitAt or 0.2, skill.FinishHold)
		end
	end
	-- O soco carregado é controlado pelo CombatInput (StartCharge ao apertar, ReleaseCharge ao soltar)
end)

-- ================= Pose de luta e andar com o estilo =================

-- Com um estilo equipado, no chão e sem estar em outra ação: parado toca a pose de luta do estilo; andando (sem
-- correr) toca o andar do estilo, acima do andar padrão. Correndo fica a corrida do StaminaDashRunscript.
local walkSpeedScale
local function updateIdle()
	local style = currentStyle()
	local free = style ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and character:GetAttribute("Stunned") ~= true
		and character:GetAttribute("Blocking") ~= true
		and character:GetAttribute("Charging") ~= true
		and humanoid.FloorMaterial ~= Enum.Material.Air
	local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude >= 0.1
	local idleId = style and CombatStyles.Animation(style, "Idle")
	if free and idleId and (style.Animations.IdleWhileMoving == true or not moving) then
		startLoop("Idle", idleId, Enum.AnimationPriority.Idle)
	else
		stopLoop("Idle", 0.2)
	end
	local walkId = style and CombatStyles.Animation(style, "Walk")
	if free and walkId and moving and player:GetAttribute("Sprinting") ~= true then
		startLoop("Walk", walkId, Enum.AnimationPriority.Movement)
		-- Acompanha a velocidade como o Animate faz (16 = velocidade normal), para o pé não escorregar
		local scale = math.clamp(humanoid.WalkSpeed / 16, 0.5, 2)
		local track = loops.Walk
		if track and scale ~= walkSpeedScale then
			walkSpeedScale = scale
			track:AdjustSpeed(scale)
		end
	else
		walkSpeedScale = nil
		stopLoop("Walk", 0.2)
	end
end

-- Rede de segurança: qualquer animação de ação do personagem (golpe, guarda, dash, reação de levar hit tocada pelo
-- servidor...) parada em velocidade 0 por mais de STUCK_LIMIT segundos é encerrada. Testado no Studio: uma reação
-- do servidor que ficou em velocidade 0 no cliente continua "tocando" para sempre, mesmo depois de o servidor
-- destruir a dele, e o personagem fica preso na pose até o reset.
-- As pausas de acerto (hitstop) duram menos de 0,1 s. Poses paradas de propósito têm prazo maior: a do soco carregado
-- enquanto a tecla está pressionada (chargeTrack; se o servidor não está mais carregando, ela venceu) e a mira do Kon
-- (AllowAimHold, até o MaxHoldTime de 8 s do FoxDevilConfig). Core/Idle/Movement ficam de fora (o Animate para a
-- animação de escalar parado na escada de propósito).
-- A contagem fica numa tabela comum (sem chave fraca): com chave fraca a entrada da AnimationTrack podia sumir na coleta
-- de lixo entre duas conferências, a contagem recomeçava e a pose ficava presa (o bug voltou em 2026-10-02).
local STUCK_LIMIT = 1
local HOLD_LIMIT = 9 -- carga e mira do Kon
local STUCK_CHECK = 0.2 -- intervalo entre as conferências
local WATCHED_PRIORITIES = {
	[Enum.AnimationPriority.Action] = true,
	[Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true,
	[Enum.AnimationPriority.Action4] = true,
}
local stuckSince = {} -- [track] = os.clock() de quando parou (limpa abaixo, sem vazar)
local nextStuckCheck = 0

local function releaseStuckTracks()
	local clock = os.clock()
	if clock < nextStuckCheck or not animator or not animator.Parent then return end
	nextStuckCheck = clock + STUCK_CHECK
	local stopped = {}
	-- Carga que o servidor já não confirma (o atributo Charging sumiu) não é mais pose de propósito
	local chargeStale = chargeTrack ~= nil and clock - chargeSince > 1.5
		and (character == nil or character:GetAttribute("Charging") ~= true)
	for _, track in animator:GetPlayingAnimationTracks() do
		if WATCHED_PRIORITIES[track.Priority] and track.Speed == 0 then
			local held = (track == chargeTrack and not chargeStale)
				or (track.Animation ~= nil and track.Animation:GetAttribute("AllowAimHold") == true)
			stopped[track] = true
			local since = stuckSince[track]
			if not since then
				stuckSince[track] = clock
			elseif clock - since > (if held then HOLD_LIMIT else STUCK_LIMIT) then
				stuckSince[track] = nil
				track:Stop(0.15)
				if track == chargeTrack then
					chargeTrack = nil
					chargeReleased = true
				end
			end
		end
	end
	-- Quem voltou a andar (ou parou de tocar) sai da contagem
	for track in stuckSince do
		if not stopped[track] then
			stuckSince[track] = nil
		end
	end
end

RunService.Heartbeat:Connect(function()
	if character and humanoid then
		-- A rede de segurança roda antes e não depende da pose de luta (um erro lá não pode desligar ela)
		releaseStuckTracks()
		updateIdle()
	end
end)

-- ================= Personagem =================

local function onCharacter(newCharacter)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(tracks)
	table.clear(loops)
	table.clear(stuckSince)
	walkSpeedScale = nil
	attackTrack = nil
	chargeTrack = nil
	chargeReleased = false
	character, humanoid, animator = newCharacter, nil, nil
	styleDirty = true

	local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)
	local newAnimator = newHumanoid and newHumanoid:WaitForChild("Animator", 10)
	if character ~= newCharacter or not newAnimator then return end
	humanoid, animator = newHumanoid, newAnimator

	for _, attribute in { "Blocking", "Charging" } do
		table.insert(characterConnections, newCharacter:GetAttributeChangedSignal(attribute):Connect(updateStance))
	end
	-- Equipou um estilo: animação de equipar (abaixo dos golpes, então um soco logo em seguida corta ela)
	table.insert(characterConnections, newCharacter.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			styleDirty = true
		end
		if child:IsA("Tool") and CombatStyles.Styles[child.Name] then
			-- Com a fusão do contrato, a animação do estilo fundido (CombatStyles.Resolve)
			local style = CombatStyles.Resolve(newCharacter, child.Name) or CombatStyles.Styles[child.Name]
			playOnce(CombatStyles.Animation(style, "Equip"), STANCE, 0.1)
		end
	end))
	-- Trocou de estilo ou guardou: larga guarda e carga visuais
	table.insert(characterConnections, newCharacter.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			styleDirty = true
		end
		if child:IsA("Tool") and CombatStyles.Styles[child.Name] then
			stopLoop("Block")
			stopLoop("Charge")
			stopLoop("Barrage")
			CombatAnimations.StopCharge()
		end
	end))
	updateStance()
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

return CombatAnimations
