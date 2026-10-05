
local CombatStyles = {}

CombatStyles.Styles = {
	Punhos = {
		DisplayName = "Punhos",
		Icon = "👊",
		Color = Color3.fromRGB(255, 170, 60),

		Animations = {
			Equip = 114507247907869, -- ao equipar os punhos
			Idle = 80129783780208, -- pose de luta com os punhos equipados, parado (em loop)
			IdleWhileMoving = false,
			Walk = 136976781107133, -- andando com os punhos equipados (sem correr; em loop)
			M1 = { 83586198824517, 107945896681556, 98990181706005, 89779080311699, 115493012383970 }, -- um por golpe do combo
			Uppercut = 82317685578737, -- 4º golpe no ar (Espaço + M1)
			Block = 136027104473016, -- em loop enquanto segura F
			BlockHit = 78729640565453, -- levou golpe com a guarda levantada
			Barrage = 103050213897648, -- Rajada (em loop enquanto dura)
			Charge = 0, 
			ChargedPunch = 107106515079108,
			-- Contra-agarrão (C, do usuário, 2026-10-05): a postura com o agarrão errando, e o agarrão que pegou
			-- (marcador "HitGrab" no golpe; o dano sai no HitAt da skill)
			CounterFail = 112283459712561,
			CounterGrab = 107680654208644,
			Hit = { 72799792874416, 132312783465078, 94168986140063, 75926009688934}, -- quem apanha (sorteado)
		},
		-- Aceita qualquer um desses nomes (o Roblox diferencia maiúsculas). Sem nenhum, o golpe acerta em 70% da animação.
		HitMarker = { "Hitframe1", "Hitframe", "Hit" },

		-- Sons (IDs do Creator Store; 0 = sem som). Tocados no cliente, no lugar do golpe.
		Sounds = {
			Swing = 108317638843283, -- soco no ar
			Hit = 89589573386788, -- soco acertando
			HeavyHit = 76526684684667, -- 5º golpe, uppercut, soco carregado
			Block = 3546610106, -- golpe na guarda
			Parry = 78486904849971,
			GuardBreak = 90129038412237,
		},

		Hitstop = 0.05, -- pausa das animações quando o golpe conecta (segundos)
		HeavyHitstop = 0.09,

		-- Combo de 5 golpes. O 5º arremessa; no ar, o 4º vira um uppercut que lança o alvo para cima.
		M1 = {
			Damage = { 14, 14, 14, 16, 22 },
			GuardDamage = { 12, 12, 12, 14, 25 }, -- quanto cada golpe gasta da guarda de quem bloqueia
			Range = 6.5,
			MinDot = 0.3, -- quão de frente o alvo precisa estar (1 = exatamente na frente)
			Windup = 0.12, -- tempo entre o clique e o acerto (quando a animação não tem o marcador Hit)
			Interval = 0.36, -- tempo entre golpes do combo
			EndLag = 2, -- pausa depois do 5º golpe
			CancelWindow = 0.2, -- depois disso, o fim do golpe pode ser cancelado com skill, block ou dash
			Buffer = 0.35, -- clique no meio de um golpe fica guardado por esse tempo e sai sozinho
			SpeedMultiplier = 0.75, -- anda mais devagar socando (sem travar)
			ComboReset = 1.2, -- sem golpe por esse tempo, o combo volta ao 1º
			Stun = 0.55, -- golpes 1 a 4 (o suficiente para o combo seguinte encaixar)
			FinalStun = 1.1,
			Knockback = 55, -- 5º golpe: velocidade do empurrão (studs/s)
			KnockbackUp = 18,
			-- Technique: técnica da árvore de habilidades (SkillTreeData) que libera o golpe; sem ela é um M1 comum
			Uppercut = { Damage = 16, Launch = 55, Stun = 1.2, Technique = "PunhosUppercut" },
		},

		-- Bloqueio (segurar F). Bloquear logo antes do golpe (ParryWindow) é um parry: anula e atordoa quem atacou.
		Block = {
			DamageTaken = 0.15, -- fração do dano que passa pela guarda
			MaxGuard = 100,
			GuardRegen = 18, -- por segundo, sem bloquear
			RegenDelay = 1.5, -- espera depois de levar golpe na guarda
			MinGuard = 15, -- abaixo disso não dá para levantar a guarda
			ParryWindow = 0.2,
			ParryStun = 1.3,
			BreakStun = 2,
			RefillAfterBreak = 0.5, -- a guarda volta com essa fração depois do atordoamento
			RepressCooldown = 0.4, -- soltar e apertar F de novo (evita parry infinito)
			SpeedMultiplier = 0.45,
			FrontDot = -0.1, -- golpe vindo de trás (dot menor que isso) atravessa a guarda
		},

		-- Skills nas teclas Z, X e C (CombatStyles.SkillSlots). Kind escolhe a mecânica no servidor (CombatService):
		-- "Barrage" (golpes seguidos no lugar) e "Charge" (segurar e soltar).
		Skills = {
			Z = {
				Kind = "Barrage",
				Id = "Rajada",
				Technique = "PunhosRajada", -- desbloqueada na árvore de habilidades (SkillTreeData)
				Name = "Rajada",
				Icon = "👊",
				Description = "Uma sequência rápida de socos que prende o alvo na sua frente.",
				Cooldown = 8,
				Hits = 9,
				HitInterval = 0.12, -- 9 x 0,12 = 1,08 s, perto da animação (1,17 s)
				Damage = 6,
				ForcaScale = 0.35, -- a Força conta menos por soco (são muitos golpes)
				GuardDamage = 9,
				Range = 6.5,
				MinDot = 0.3,
				Stun = 0.45,
				FinalKnockback = 30,
				SpeedMultiplier = 0.3,
				-- VFX (ReplicatedStorage.VFX.Punchs.BarragePunch): a peça base (crash4) fica VFXForward studs à frente
				-- e VFXHeight acima da raiz, virada para a frente. O servidor usa a mesma conta para a hitbox.
				VFXForward = 2,
				VFXHeight = 0.4,
				-- Hitbox = o volume dessa peça do VFX (tamanho e posição dela no modelo). Se ela for minúscula (um ponto
				-- de partículas), vale a maior peça dentro dela. Sem o VFX: hitbox redonda de Range studs.
				HitboxPart = "Crash1",
			},
			X = {
				Kind = "Charge",
				Id = "SocoCarregado",
				Technique = "PunhosCarregado", -- desbloqueada na árvore de habilidades (SkillTreeData)
				Name = "Soco carregado",
				Icon = "💥",
				Description = "Segure para carregar e solte: quanto mais carregado, mais forte e mais longe arremessa. Carga máxima quebra a guarda.",
				Hold = true,
				ChargeMarker = { "Charge", "charge" }, -- a animação para aqui enquanto o R está pressionado
				HitMarker = { "Power", "power" }, -- frame do impacto (hitbox)
				MarkerTimeout = 1, -- tempo máximo entre soltar e o impacto
				Cooldown = 10,
				CancelCooldown = 3, -- recarga se for interrompido carregando
				WhiffRecovery = 0.5, -- errou (soltou sem acertar ninguém): fica esse tanto travado e lento (CombatService)
				MaxCharge = 1.5, -- segundos até a carga máxima
				MaxHold = 2.5, -- solta sozinho depois disso
				DamageMin = 22,
				DamageMax = 65,
				ForcaScale = 1.5,
				GuardDamageMin = 30,
				KnockbackMin = 35,
				KnockbackMax = 110,
				RangeMin = 9,
				RangeMax = 14,
				HitboxWidth = 9, -- largura da hitbox do cliente (os M1 usam 5,5)
				MinDot = 0.1, -- aceita alvos bem de lado (0 = até 90° da frente)
				Stun = 1.2,
				Windup = 0.12,
				SpeedMultiplier = 0.5,
			},
			-- Contra-agarrão: postura curta; quem bater nela (golpe, skill, poder ou inimigo, até CounterRange studs) não
			-- causa dano, é agarrado e, no HitAt (marcador "HitGrab" da animação), leva o golpe e cai em ragdoll. Ninguém
			-- bateu: a postura acaba e fica FailRecovery travado (a animação do agarrão errando).
			C = {
				Kind = "CounterGrab",
				Id = "ContraAgarrao",
				Name = "Contra-agarrão",
				Icon = "🤼",
				Glyph = "返",
				Description = "Fique em postura: se alguém te atacar nesse instante, você agarra, derruba e ele cai no chão. "
					.. "Se ninguém atacar, você fica aberto por um momento.",
				Animation = "CounterFail", -- toca ao apertar (Animations.CounterFail)
				SuccessAnimation = "CounterGrab", -- toca quando pega
				Cooldown = 12,
				Window = 0.6, -- duração da postura que pega o golpe
				FailRecovery = 0.5, -- ninguém bateu: travado esse tanto depois da postura
				HitAt = 1.5, -- depois de pegar: o golpe (marcador "HitGrab" da animação, medido no Studio)
				Recovery = 0.35, -- depois do golpe, até poder agir
				CounterRange = 12, -- quem bateu de mais longe que isso (projétil, poder de longe) não é agarrado
				HoldDistance = 2.5, -- a vítima fica presa a essa distância na frente até o golpe
				Damage = 30,
				ForcaScale = 1.2,
				RagdollTime = 1.6, -- tempo caído no chão
				Knockback = 22,
				KnockbackUp = 8,
				SpeedMultiplier = 0.2,
			},
		},
	},

	-- Katana: ensinada pelo Mestre Espadachim (missão "O caminho da lâmina", level 15; QuestData). As técnicas Z/X/C
	-- saem na árvore (galho KATANA). Efeitos das skills: KatanaVFX (Codex). Os tempos das skills seguem os marcadores
	-- das animações do Codex (assets/animations/katana/build_clips.py); se mudar a animação, mude os tempos aqui.
	Katana = {
		DisplayName = "Katana",
		Icon = "🗡️",
		Glyph = "刀",
		Color = Color3.fromRGB(235, 235, 245),
		HitFX = "Slash", -- acerto e golpe no ar desenham cortes (CombatFX), no lugar do impacto redondo dos socos

		-- Espada e bainha no personagem (StyleWeapons):
		--   estilo guardado: bainha na cintura esquerda, espada dentro;
		--   equipado, andando: a mão direita (CarryHand) leva a espada pela bainha;
		--   atacando (M1, skill, guarda): a bainha passa para a mão esquerda (FightHand) e a direita luta com a lâmina;
		--   CombatTime segundos sem atacar: a lâmina volta para a bainha (o Saque também guarda no marcador "Sheathe").
		-- Modelo: ReplicatedStorage.VFX.Weapons.<Model>: a katana do Aki feita pelo ChatGPT (assets/weapons/aki_katana), com
		-- a espada e a bainha ("Saya") separadas. Sem ele, uma katana simples feita de peças.
		Weapon = {
			Model = "AkiKatana",
			Scale = 1, -- tamanho do modelo (1 = como o ChatGPT fez: espada de 4,96 studs)
			-- Centro da boca da bainha em relação ao pivô dela (medido nos vértices do Saya_Lacquer: o pivô fica fora da boca)
			SheathMouthOffset = Vector3.new(-0.5, 0.06, 0),
			GripBelowGuard = 0.4, -- a mão segura o cabo esse tanto abaixo da guarda
			BladeRoll = -90, -- giro da lâmina na mão (graus): com -90 o fio fica para baixo com o braço solto
			-- Mão: C0 da junta no braço. No espaço da mão o +Y aponta para a frente do braço e o +Z sobe o braço.
			Hand = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0),
			CarryHand = "Right Arm",
			FightHand = "Left Arm",
			-- Bainha na mão: direção da ponta (para trás e para baixo) e onde a mão segura (studs abaixo da boca)
			SheathInHand = Vector3.new(0, -0.87, -0.5),
			SheathGrip = 0.35,
			-- Na cintura: boca da bainha em relação ao Torso (o brilho do Saque do KatanaVFX sai daqui) e direção da ponta
			SheathMouth = Vector3.new(-1.2, -0.5, -0.35),
			SheathDirection = Vector3.new(0, -0.45, 1),
			CombatTime = 4,
		},

		Animations = {
			-- Do usuário (2026-09-30). Sem Idle/Walk: andando, os braços balançam normal com a bainha na mão.
			Equip = 0,
			Idle = 0,
			IdleWhileMoving = false,
			Walk = 0,
			-- Marcador "Hitframe1" em 0,167 / 0,183 / 0,15 / 0,15 / 0,133 s. Todos batem com a direita (a lâmina).
			M1 = { 106433825984282, 136389770824254, 134328832033708, 91543752915698, 117560116007678 },
			Uppercut = 91543752915698, -- provisório: o M4 (falta um corte subindo próprio)
			Block = 73715390505740,
			BlockHit = 0,
			-- Skills (ChatGPT/Codex, 2026-09-30; lista com os marcadores em ReplicatedStorage.KatanaAnimationIds)
			DashSlash = 99592683576869, -- Katana_Z_AdvanceCut: "Dash" 0,15, "Slash" 0,35
			DashSlashFinish = 104492273646156, -- pose do corte depois de acertar o avanço (do usuário): "HitframeSword" 0,2
			Grab = 124017152338185, -- Katana_X_GrabCut: "Reach" 0,13, "Grab" 0,3, "Strike" 0,73, "Release" 1,02
			GrabTarget = 101371885624602, -- Katana_X_Target: quem foi agarrado (tocada pelo servidor na vítima)
			DrawSlash = 104238494972646, -- HeavySlice1 (do usuário): "SkillC" 0,52. A do ChatGPT: 104255597432195
			Hit = { 72799792874416, 132312783465078, 94168986140063, 75926009688934 }, -- quem apanha (as mesmas dos Punhos)
		},
		HitMarker = { "Hitframe1", "Hitframe", "Hit" },

		-- Sons: uma lista = variações tocadas em sequência (1, 2, 1, 2...). SwingOnMiss: o som Swing só toca quando o golpe
		-- pega no ar, no frame do corte (acertando, toca o Hit).
		SwingOnMiss = true,
		Sounds = {
			Swing = 74215939319319, -- Katana Slash Wind 1 (golpe no ar)
			Hit = { 131827079767703, 126421203319100 }, -- Katana Hit 1 e 2 (do usuário)
			HeavyHit = 107511172337368, -- Katana Slash
			Block = 9119747138, -- Sword Impact 202
			Parry = 131228981149448, -- Impact_Metal 02
			GuardBreak = 9113224751, -- Axe Clang Twice
			Equip = 76330370205277, -- Unsheathe/Sword Equip
			Draw = 106990193581136, -- saque (C)
			Dash = 140180249061198, -- Katana Slash Wind 2 (Z)
		},

		Hitstop = 0.06,
		HeavyHitstop = 0.1,

		-- Combo de 5 cortes: mais alcance e mais dano que os socos, um pouco mais lento
		M1 = {
			Damage = { 16, 16, 17, 18, 26 },
			GuardDamage = { 14, 14, 14, 16, 30 },
			Range = 8,
			HitboxWidth = 7, -- corte pega mais de lado que o soco (5,5)
			MinDot = 0.25,
			Windup = 0.16,
			Interval = 0.42,
			EndLag = 2,
			CancelWindow = 0.22,
			Buffer = 0.35,
			SpeedMultiplier = 0.7,
			ComboReset = 1.2,
			Stun = 0.55,
			FinalStun = 1.1,
			Knockback = 60,
			KnockbackUp = 16,
			Uppercut = { Damage = 18, Launch = 55, Stun = 1.2, Technique = "KatanaUppercut", SwingArm = "Right" },
			-- Rastro de cada golpe (CombatFX): "Right" = na lâmina, "Left" = na bainha (golpe com a bainha na mão esquerda)
			SwingArm = { "Right", "Right", "Right", "Right", "Right" },
		},

		-- Guarda com a lâmina: parry um pouco maior, deixa passar um pouco mais de dano
		Block = {
			DamageTaken = 0.2,
			MaxGuard = 100,
			GuardRegen = 18,
			RegenDelay = 1.5,
			MinGuard = 15,
			ParryWindow = 0.22,
			ParryStun = 1.4,
			BreakStun = 2,
			RefillAfterBreak = 0.5,
			RepressCooldown = 0.4,
			SpeedMultiplier = 0.45,
			FrontDot = -0.1,
		},

		-- Hitbox das três no servidor. Os tempos (segundos desde o aperto) batem com os marcadores das animações.
		Skills = {
			Z = {
				Kind = "DashSlash",
				Id = "Avanco",
				Technique = "KatanaAvanco",
				Name = "Avanço cortante",
				Icon = "⚡",
				Glyph = "閃",
				Description = "Avança num piscar de olhos. Quem ficou no caminho trava e, um instante depois, leva uma chuva de cortes. Não leva dano durante o avanço.",
				Cooldown = 9,
				WhiffRecovery = 0.6, -- errou: fica esse tanto travado e lento no fim do avanço (CombatService)
				Animation = "DashSlash",
				DashAt = 0.15, -- marcador "Dash": começa a andar
				DashTime = 0.07, -- bem rápido, parece um teleporte (o personagem é movido direto, sem física)
				SlashAt = 0.35, -- marcador "Slash" (efeito do Codex)
				Recovery = 0.3, -- sem acertar ninguém: depois do corte, até poder agir de novo
				-- Acertou: quem ficou no caminho trava (stun, sem dano) e quem avançou faz a pose do corte (FinishAnimation);
				-- no marcador dela os cortes saem e o dano entra. A pose fica parada FinishHold segundos no fim.
				FinishAnimation = "DashSlashFinish",
				FinishMarker = "HitframeSword",
				FinishHitAt = 0.2, -- tempo do marcador na animação (sem ela, o dano sai nesse tempo)
				FinishHold = 0.35,
				Distance = 24,
				Width = 7, -- largura do corredor que acerta
				Damage = 30,
				ForcaScale = 1,
				GuardDamage = 35,
				Stun = 0.9,
				Knockback = 18,
				KnockbackUp = 14,
				SpeedMultiplier = 0,
			},
			X = {
				Kind = "Grab",
				Id = "Agarrao",
				Technique = "KatanaAgarrao",
				Name = "Agarrão",
				Icon = "✊",
				Glyph = "掴",
				Description = "Agarra quem está na sua frente (atravessa a guarda), corta segurando e arremessa.",
				Cooldown = 12,
				WhiffCooldown = 5, -- errou: recarga menor
				Animation = "Grab",
				TargetAnimation = "GrabTarget",
				ReachAt = 0.13, -- marcador "Reach": estende a mão (só efeito)
				GrabAt = 0.3, -- marcador "Grab": pega quem estiver na frente
				StrikeAt = 0.73, -- marcador "Strike": corte segurando
				ReleaseAt = 1.02, -- marcador "Release": corte final que arremessa
				Range = 5.5, -- pega o alvo mais perto na frente
				HoldDistance = 2.3, -- a vítima fica presa a essa distância na frente (a animação pede 2 a 2,5)
				GrabDamage = 6,
				StrikeDamage = 14,
				FinalDamage = 24,
				ForcaScale = 0.8,
				FinalStun = 1.1,
				FinalKnockback = 70,
				FinalKnockbackUp = 22,
				SpeedMultiplier = 0,
			},
			C = {
				Kind = "DrawSlash",
				Id = "Saque",
				Technique = "KatanaSaque",
				Name = "Saque",
				Icon = "🌙",
				Glyph = "居",
				Description = "Um corte pesado e largo na sua frente. Quebra a guarda.",
				Cooldown = 11,
				WhiffRecovery = 0.6, -- errou: fica esse tanto travado e lento depois do corte (CombatService)
				Animation = "DrawSlash",
				-- Animação do usuário (HeavySlice1, 0,98 s): um marcador só, "SkillC", no corte. Com a do ChatGPT
				-- (104255597432195) eram "Charge" 0,23, "Slash" 0,47 e "Sheathe" 1,02, com DrawFromSheath = true.
				Markers = { Slash = "SkillC" }, -- nome do marcador de cada fase (sem a entrada, o nome da fase)
				SlashAt = 0.52, -- o corte
				DrawFromSheath = false, -- true: a lâmina volta para a bainha no aperto e sai no corte (saque)
				Recovery = 0.35,
				Range = 13,
				Arc = 150, -- graus na frente
				Damage = 42,
				ForcaScale = 1.3,
				GuardBreak = true,
				Stun = 1.2,
				Knockback = 45,
				KnockbackUp = 14,
				SpeedMultiplier = 0.1,
			},
		},
	},
}

-- Estilos que todo jogador tem desde o começo; os outros ficam salvos no perfil (PlayerData.UnlockStyle)
CombatStyles.StartingStyles = { "Punhos" }

-- Estilo equipado: o Tool do personagem cujo nome é um estilo. Devolve (nome, dados, tool) ou nil.
-- Quem tem a fusão do contrato com esse estilo (ContractData, forma V2 em diante) recebe os dados do estilo
-- fundido (CombatStyles.Resolve); o nome continua o do estilo base (maestria, árvore, ferramenta).
function CombatStyles.FromCharacter(character)
	if not character then return nil end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			local style = CombatStyles.Styles[child.Name]
			if style then
				return child.Name, CombatStyles.Resolve(character, child.Name) or style, child
			end
		end
	end
	return nil
end

-- Teclas das skills dos estilos (os poderes do caminho ficam em V e B, no PowerInput)
CombatStyles.SkillSlots = { "Z", "X", "C" }

-- Skill do estilo com essa mecânica (Kind). Devolve (slot, dados) ou nil.
function CombatStyles.SkillOfKind(style, kind)
	if not style or not style.Skills then return nil end
	for _, slot in CombatStyles.SkillSlots do
		local skill = style.Skills[slot]
		if skill and skill.Kind == kind then
			return slot, skill
		end
	end
	return nil
end

-- Quem leva parry (atacante, jogador ou inimigo) toca esta animação (do usuário, 2026-10-05). Chefe com reação própria
-- (Stagger do BossService) fica sem ela.
CombatStyles.ParriedAnimation = 93676921591226

-- Tolerância de alcance do servidor ao conferir um acerto que o cliente mandou (compensa o ping)
CombatStyles.HitTolerance = 2
-- Tempo máximo entre o golpe e o acerto que o cliente manda (maior que qualquer windup/marcador + ping)
CombatStyles.HitDeadline = 1.5

-- Justiça no PvP (só quando a vítima é jogador; inimigos continuam como antes). CombatState e CombatRules.
CombatStyles.PvP = {
	-- Imunidade: depois de um atordoamento pesado (finalizador, uppercut, quebra de guarda) o jogador fica StunImmunity s
	-- sem poder ser atordoado de novo (o dano entra), para dar tempo de dash/guarda e não recomeçar o combo
	HeavyStun = 1,
	StunImmunity = 0.5,
	-- Ataque em grupo: com golpes de 2+ jogadores diferentes na mesma vítima dentro de TeamWindow s, cada golpe
	-- dá TeamDamage do dano e TeamStun do atordoamento
	TeamWindow = 2,
	TeamDamage = 0.6,
	TeamStun = 0.7,
	-- Quebra-combo: levar BreakerFraction da vida máxima seguida (sem BreakerGap s de folga) libera um dash mesmo
	-- atordoado (atributo ComboBreakerReady no player); usar tira o stun, dá a imunidade e recarrega em BreakerCooldown s
	BreakerFraction = 0.25,
	BreakerGap = 1.5,
	BreakerCooldown = 25,
}

-- Onde fica a peça base do VFX da Rajada (crash4): VFXForward à frente e VFXHeight acima da raiz, deitada,
-- com a face de cima (+Y) apontando para a frente e o X para baixo (o mesmo giro do modelo). Usada pelo efeito
-- (CombatFX) e pela hitbox (CombatService), para os dois baterem.
function CombatStyles.BarrageBaseCFrame(rootCFrame, skill)
	local look = rootCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.001 then flat.Unit else Vector3.new(0, 0, -1)
	local forward = skill and skill.VFXForward or 2
	local height = skill and skill.VFXHeight or 0.4
	local position = rootCFrame.Position + flat * forward + Vector3.new(0, height, 0)
	return CFrame.fromMatrix(position, Vector3.new(0, -1, 0), flat)
end

-- Nomes de marcador: aceita um texto ou uma lista (ex.: { "Hitframe1", "Hitframe" })
function CombatStyles.MarkerNames(value)
	if type(value) == "string" then
		return { value }
	elseif type(value) == "table" then
		return value
	end
	return {}
end

-- Conecta todos os nomes de marcador de uma AnimationTrack a um callback. Devolve as conexões.
function CombatStyles.OnMarker(track, names, callback)
	local connections = {}
	for _, name in CombatStyles.MarkerNames(names) do
		table.insert(connections, track:GetMarkerReachedSignal(name):Connect(callback))
	end
	return connections
end

-- Som do estilo ("rbxassetid://...") ou nil. Com uma lista de variações, index escolhe qual (dá a volta na lista;
-- sem index, a primeira).
function CombatStyles.Sound(style, name, index)
	local value = style and style.Sounds and style.Sounds[name]
	if type(value) == "table" then
		if #value == 0 then return nil end
		value = value[((index or 1) - 1) % #value + 1]
	end
	return if type(value) == "number" and value > 0 then "rbxassetid://" .. value else nil
end

-- Quantas variações o som tem (1 para um ID só, 0 sem som)
function CombatStyles.SoundCount(style, name)
	local value = style and style.Sounds and style.Sounds[name]
	return if type(value) == "table" then #value elseif type(value) == "number" and value > 0 then 1 else 0
end

-- ID da animação (número > 0) ou nil quando o estilo ainda não tem essa animação
function CombatStyles.Animation(style, move, index)
	local value = style and style.Animations and style.Animations[move]
	if type(value) == "table" then
		value = value[index or 1]
	end
	return if type(value) == "number" and value > 0 then value else nil
end

-- ================= Fusão com o contrato (ContractData) =================
-- Na forma V2 (e na Ultimate) o contrato do Caçador funde com o estilo dele (FusionStyle): os dados do estilo base com
-- os campos do Fusion por cima (cópia profunda; tabelas com chaves entram por dentro, listas trocam inteiras e
-- Skills troca slot por slot). Cada estilo fundido tem Fusion = id do contrato, FusionForm e BaseStyle.

local Players = game:GetService("Players")
local ContractData = require(script.Parent:WaitForChild("ContractData"))

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function isList(value)
	return type(value) == "table" and #value > 0
end

local function overlay(target, source)
	for key, value in source do
		if key == "Skills" and type(value) == "table" then
			-- Slot que o estilo base já tem: os campos entram na skill dele; slot novo entra inteiro
			target.Skills = target.Skills or {}
			for slot, skill in value do
				if type(target.Skills[slot]) == "table" then
					overlay(target.Skills[slot], skill)
				else
					target.Skills[slot] = deepCopy(skill)
				end
			end
		elseif type(value) == "table" and type(target[key]) == "table" and not isList(value) and not isList(target[key]) then
			overlay(target[key], value)
		else
			target[key] = deepCopy(value)
		end
	end
end

CombatStyles.Fused = {} -- [contrato][forma] = dados do estilo fundido
for contractId, entry in ContractData.Contracts do
	local base = entry.FusionStyle and CombatStyles.Styles[entry.FusionStyle]
	if base and entry.Forms then
		for _, form in ContractData.FormOrder do
			local fusion = ContractData.Fusion(contractId, form)
			if fusion then
				local fused = deepCopy(base)
				overlay(fused, fusion)
				fused.Fusion = contractId
				fused.FusionForm = form
				fused.BaseStyle = entry.FusionStyle
				CombatStyles.Fused[contractId] = CombatStyles.Fused[contractId] or {}
				CombatStyles.Fused[contractId][form] = fused
			end
		end
	end
end

-- Contrato e forma de quem luta: do Player (atributos Path, Contracts e ContractForm, que o servidor replica) ou, num
-- personagem sem Player (ex.: a Sombra da missão Ultimate), dos atributos FusionContract e FusionForm dele
local function fusionOf(character)
	local owner = Players:GetPlayerFromCharacter(character)
	if owner then
		if owner:GetAttribute("Path") ~= "Hunter" then return nil end
		local contracts = owner:GetAttribute("Contracts")
		local contractId = if type(contracts) == "string" then string.split(contracts, ",")[1] else nil
		return contractId, owner:GetAttribute("ContractForm")
	end
	return character:GetAttribute("FusionContract"), character:GetAttribute("FusionForm")
end

-- Dados do estilo para este personagem: o fundido, se ele tiver a fusão do contrato com esse estilo; senão nil
function CombatStyles.Resolve(character, styleName)
	if not character then return nil end
	local contractId, form = fusionOf(character)
	if type(contractId) ~= "string" or ContractData.FormRank(form) < 2 then return nil end
	local forms = CombatStyles.Fused[contractId]
	local fused = forms and forms[form]
	if fused and fused.BaseStyle == styleName then
		return fused
	end
	return nil
end

return CombatStyles
