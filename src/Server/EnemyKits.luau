-- Kit de cada modelo de inimigo (chave = nome do template em ServerStorage.EnemyTemplates): animações, arma na mão
-- e dash. Vida, dano, alcance e recarga do golpe continuam no EnemyData (por tipo). Todos os tipos que usam o mesmo
-- template usam o mesmo kit. Template sem kit usa a pasta Animations dele (RunAnim/AttackAnim), como antes.
-- IDs de animação: 0 = não toca (no Run, 0 usa o RunAnim da pasta Animations do template).
-- Hit (opcional): reação própria ao apanhar, no lugar da genérica dos Punhos (o modelo ganha o atributo OwnHitReaction).
-- Death (opcional): morte própria; o corpo não desmonta (BreakJointsOnDeath = false), a raiz fica presa e a última pose
-- segura até o corpo sumir. DeathTime = duração da animação (reserva, enquanto ela carrega).
local EnemyKits = {}

EnemyKits.Goblin = {
	Animations = {
		Idle = 111245111448922, -- parado (em loop, por baixo de tudo)
		Run = 0, -- correndo: o RunAnim do template
		Attack = { 91190384138327, 80612228854019 }, -- golpes com a faca, alternados
		Dash = 71933055748206,
	},
	-- Quando o golpe acerta (segundos depois do início de cada animação de Attack). Se a animação tiver um dos
	-- marcadores de HitMarker, vale o que vier primeiro.
	AttackHitTime = { 0.23, 0.17 },
	HitMarker = { "Hitframe1", "Hitframe", "Hit" },

	-- Combo: golpes seguidos antes da recarga (AttackCooldown do EnemyData). O EnemyData pode mudar por tipo
	-- com o campo Combo. ComboInterval = tempo entre o início de um golpe e o do próximo.
	Combo = 2,
	ComboInterval = 0.45,
	HitStun = 0.3, -- atordoamento de quem leva o golpe (corta o combo e a guarda do jogador)
	FinisherStun = 0.5, -- último golpe do combo
	FinisherDamage = 1.25, -- multiplicador do dano do último golpe
	FinisherKnockback = 38, -- empurrão do último golpe (studs/s)
	Lunge = 24, -- passo para a frente no golpe quando o alvo está um pouco longe (studs/s)
	Strafe = true, -- na recarga anda de lado em volta do alvo, virado para ele

	-- Arma: uma cópia desta peça vira o "Handle" do inimigo, preso no braço por um Motor6D (Part0 = braço,
	-- Part1 = Handle). É assim que as animações de golpe mexem na faca (a pose "Handle" delas).
	-- Fora do golpe a faca fica em HoldC0, que é a pose de início e fim dos golpes (faca na mão).
	Weapon = {
		Path = { "VFX", "EnemyModels", "Knife" }, -- dentro do ReplicatedStorage
		Arm = "Right Arm",
		HoldC0 = CFrame.new(-0.3, -0.75, -0.71) * CFrame.Angles(math.pi, 0, 0),
		-- C1 do Motor6D: gira a faca no próprio eixo. A malha da Knife tem a ponta do lado oposto da faca usada ao
		-- animar, então vai virada 180° (sem isso o Goblin segura pela lâmina).
		Grip = CFrame.Angles(0, math.pi, 0),
	},

	-- Dash para encurtar distância (sem dano): alvo entre MinRange e MaxRange studs, uma vez a cada Cooldown s.
	-- Para um pouco antes do alvo, no alcance do golpe.
	Dash = {
		MinRange = 8,
		MaxRange = 20,
		Cooldown = 4,
		Speed = 70, -- studs por segundo
		Duration = 0.3, -- máximo
	},
}

-- ===== NPCs urbanos (ChatGPT, 2026-10-01; modelos e fontes em assets/characters/city_demons) =====
-- Uma animação de golpe cada, com o marcador "Hitframe1". ComboInterval perto da duração do golpe (o próximo golpe ou o
-- andar não cortam a animação no meio). Sem arma separada: a maleta do Passageiro faz parte do Left Arm.

-- Ratazana (20-30): bando rápido. Garra lateral (0,67 s, corte em 0,23 s), bote para chegar perto, anda em volta.
EnemyKits.Ratazana = {
	Animations = {
		Idle = 127446519069154,
		Walk = 117471676522461,
		Run = 111307086567265,
		Attack = { 96501034597324 },
		Hit = 89787284499638,
		Death = 131880673593738,
	},
	AttackHitTime = { 0.2333 },
	HitMarker = { "Hitframe1" },
	DeathTime = 1.3,
	Combo = 1,
	ComboInterval = 0.55,
	HitStun = 0.25,
	FinisherStun = 0.4,
	FinisherDamage = 1,
	FinisherKnockback = 25,
	Lunge = 26,
	Strafe = true,
	Dash = {
		MinRange = 8,
		MaxRange = 18,
		Cooldown = 5,
		Speed = 65,
		Duration = 0.3,
	},
}

-- Manequim (30-40): tanque lento. Pancada com os dois braços (1,2 s, corte em 0,63 s): bem avisada, atordoa mais.
EnemyKits.Manequim = {
	Animations = {
		Idle = 133374380582077,
		Walk = 76383977566589,
		Run = 124195271231911,
		Attack = { 89947510417347 },
		Hit = 77514339147721,
		Death = 97551196377983,
	},
	AttackHitTime = { 0.6333 },
	HitMarker = { "Hitframe1" },
	DeathTime = 1.3,
	Combo = 1,
	ComboInterval = 1,
	HitStun = 0.6,
	FinisherStun = 0.6,
	FinisherDamage = 1,
	FinisherKnockback = 30,
	Lunge = 14,
	Strafe = false,
}

-- Passageiro (40-50): assassino. Golpe de maleta (0,93 s, corte em 0,4 s) em combo de 2, o último empurra; dash longo.
EnemyKits.Passageiro = {
	Animations = {
		Idle = 79552305444321,
		Walk = 123531400114212,
		Run = 81450326893885,
		Attack = { 132341465717938 },
		Hit = 111417402124349,
		Death = 71879588032469,
	},
	AttackHitTime = { 0.4 },
	HitMarker = { "Hitframe1" },
	DeathTime = 1.3,
	Combo = 2,
	ComboInterval = 0.75,
	HitStun = 0.3,
	FinisherStun = 0.5,
	FinisherDamage = 1.25,
	FinisherKnockback = 40,
	Lunge = 28,
	Strafe = true,
	Dash = {
		MinRange = 8,
		MaxRange = 22,
		Cooldown = 4,
		Speed = 75,
		Duration = 0.3,
	},
}

-- Boss Rei Goblin (EnemyData.ReiGoblin): golpes comuns. Trono, especiais, fase 2, reações e drops ficam no BossData.
-- Animações próprias (GK_*, fontes em ServerStorage.RBX_ANIMSAVES.King Goblin; lista em
-- assets/animations/goblin_king/animation_ids.json).
EnemyKits["King Goblin"] = {
	Animations = {
		Idle = 133645768933142, -- GK_Idle: guarda pesada
		Walk = 112559274057133, -- GK_Walk: andando de lado na recarga
		Run = 123505920591956, -- GK_Run
		Attack = { 93468668046583, 132226941758894, 115173943864342, 97997804028159 }, -- GK_Attack1 a 4
		Dash = 135026883273212, -- GK_Dash
	},
	AttackHitTime = { 0.25, 0.17, 0.25, 0.23 }, -- os golpes têm o marcador "Hitframe1"; isto é só o reserva
	HitMarker = { "Hitframe1", "Hitframe", "Hit" },
	Combo = 3,
	ComboInterval = 0.45,
	HitStun = 0.35,
	FinisherStun = 0.6,
	FinisherDamage = 1.3,
	FinisherKnockback = 55,
	Lunge = 30,
	Strafe = true,
	Dash = {
		MinRange = 12,
		MaxRange = 30,
		Cooldown = 5,
		Speed = 80,
		Duration = 0.35,
	},
}

-- Chefe Lord Chainsaw (EnemyData.LordChainsaw): por enquanto com as animações dos Punhos (R6), até ele ganhar as
-- próprias. Especiais, fase 2 e a cura ficam no BossData.
EnemyKits["Lord Chainsaw"] = {
	Animations = {
		Idle = 80129783780208, -- pose de luta dos Punhos
		Run = 80849474243778, -- corrida (CharacterAnimations.Sprint)
		Walk = 136976781107133, -- andando em guarda (Punhos)
		Attack = { 83586198824517, 107945896681556, 98990181706005, 89779080311699 }, -- M1 1 a 4 dos Punhos
	},
	AttackHitTime = { 0.25, 0.25, 0.3, 0.25 },
	HitMarker = { "Hitframe1", "Hitframe", "Hit" },
	Combo = 4,
	ComboInterval = 0.4,
	HitStun = 0.3,
	FinisherStun = 0.6,
	FinisherDamage = 1.35,
	FinisherKnockback = 55,
	Lunge = 32,
	Strafe = true,
	Dash = {
		MinRange = 10,
		MaxRange = 30,
		Cooldown = 4,
		Speed = 85,
		Duration = 0.35,
	},
}

-- Cópia do Treinador (TrainerService): luta com as animações dos Punhos (R6; a cópia é sempre R6)
EnemyKits.TreinadorTreino = {
	Animations = {
		Idle = 80129783780208, -- pose de luta dos Punhos
		Run = 80849474243778, -- corrida (CharacterAnimations.Sprint)
		Walk = 136976781107133, -- andando em guarda (Punhos)
		Attack = { 83586198824517, 107945896681556, 98990181706005, 89779080311699 }, -- M1 1 a 4 dos Punhos
	},
	AttackHitTime = { 0.25, 0.25, 0.3, 0.25 }, -- reserva (o marcador Hitframe1 vale o que vier primeiro)
	HitMarker = { "Hitframe1", "Hitframe", "Hit" },
	Combo = 3,
	ComboInterval = 0.42,
	HitStun = 0.25,
	FinisherStun = 0.45,
	FinisherDamage = 1.3,
	FinisherKnockback = 34,
	Lunge = 22,
	Strafe = true,
	Dash = {
		MinRange = 8,
		MaxRange = 22,
		Cooldown = 3.5,
		Speed = 72,
		Duration = 0.3,
	},
}

return EnemyKits
