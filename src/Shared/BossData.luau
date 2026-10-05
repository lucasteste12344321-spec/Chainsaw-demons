
local BossData = {}

BossData.Bosses = {
	ReiGoblin = {
		Title = "Rei dos Goblins",
		Throne = {
			Animation = 70965080373542, -- GK_ThroneIdle: sentado no trono
			-- A animação dobra as pernas mas não abaixa o corpo (num Seat quem abaixa é o assento): sentado, o
			-- modelo desce isso a partir de onde foi colocado. Mais negativo = mais baixo.
			SitOffset = Vector3.new(0, -3.1, 0),
			WakeRange = 30,
			StandUpAnimation = 134180060131769, -- GK_StandUp: sobe do assento enquanto toca
			StandUpTime = 1,
		},
		RespawnTime = 300,
		MinContribution = 0.03,
		MinStun = 1.25,
		KnockbackImmune = true,

		Reactions = {
			Front = 135675568020167, -- GK_HitFront
			Side = 98304933386395, -- GK_HitSide
			Interval = 0.6, -- intervalo mínimo entre duas reações (ele não para de atacar por apanhar)
			Stagger = 93129962885175, -- GK_Stagger: parry / atordoamento longo
			Death = 83778916363984, -- GK_Death
			LandMarker = "Land",
		},

		Specials = {
			Cooldown = 6, -- entre um especial e outro
			FirstDelay = 3, -- depois de levantar
			-- Pisão: círculo em volta dele; quem estiver dentro no fim leva dano, é arremessado e fica atordoado
			Slam = {
				Radius = 16,
				Telegraph = 1.2,
				Damage = 1.6,
				Knockback = 60,
				Stun = 0.8,
				Animation = 86561393184958, -- GK_Slam (congela no "Charge", solta para o "Power" bater no fim do aviso)
				ChargeMarker = { "Charge", "charge" },
				PowerTime = 0.36, -- do "Charge" (0,28) ao "Power" (0,64)
			},
			-- Investida: faixa até o alvo; ele atravessa a faixa e acerta quem estiver no caminho
			Rush = {
				MinRange = 12,
				Distance = 45,
				Width = 8,
				Telegraph = 0.8,
				Speed = 90,
				Damage = 1.3,
				Knockback = 70,
				Stun = 0.6,
				Animation = 90630684692933, -- GK_Rush (em loop enquanto avança)
				Looped = true,
			},
			-- Fúria: retângulo na frente; rajada de socos rápidos, o último arremessa
			Fury = {
				Range = 11,
				Width = 10,
				Telegraph = 0.5,
				Hits = 8,
				Interval = 0.13, -- os 8 "Hitframe1" da GK_Fury estão a cada 0,13 s
				Damage = 0.35,
				Stun = 0.2,
				Knockback = 45,
				Animation = 135794360022292, -- GK_Fury
			},
		},

		Phase2 = {
			At = 0.5,
			SpeedMultiplier = 1.25,
			CooldownMultiplier = 0.65,
			RoarAnimation = 108032274433784, -- GK_Roar
			RoarMarker = "Roar", -- 0,48 s: o aviso e os reforços chegam aqui
			Summon = { Type = "GoblinLadrao", Count = 3, Level = 18 },
			Message = "O Rei Goblin ficou furioso e chamou reforços!",
		},

		-- Os itens são os acessórios de dentro do modelo "King Goblin"
		Drops = {
			{ Item = "OgreHorns", Chance = 0.3 },
			{ Item = "OgreShoulderRight", Chance = 0.15 },
			{ Item = "OgreShoulderLeft", Chance = 0.15 },
			{ Item = "OgreChain", Chance = 0.08 },
			{ Item = "OgreHead", Chance = 0.03 },
		},
	},

	-- Denji (modelo "Denji" em EnemyTemplates, no lugar do mapa onde o usuário colocou): espera em pé até alguém chegar
	-- perto (Throne sem animação) e, se todos fugirem, volta para lá curado. Briga como humano; com 15% da vida puxa a
	-- cordinha e vira o Lord Chainsaw (Transform), que tem a vida cheia e continua o mesmo placar de dano.
	Denji = {
		Title = "Denji",
		Throne = {
			WakeRange = 35,
			StandUpTime = 0.2,
			WakeMessage = "Quer brigar? Então vem!",
		},
		-- Chefe global: aparece a cada 3 horas (00h, 03h, 06h... UTC = 21h, 00h, 03h... de Brasília), avisa 5 min antes e
		-- vai embora em 30 min se ninguém vencer. Não renasce sozinho (/chefe Denji chama na hora, para testar).
		Global = {
			Interval = 3 * 3600,
			Offset = 0,
			Warning = 300,
			Duration = 30 * 60,
			WarningMessage = "O Denji aparece em %d minutos! Junte o pessoal.",
			SpawnMessage = "O Denji apareceu! Corra até ele antes que vá embora.",
			LeaveMessage = "Ninguém derrotou o Lord Chainsaw. Ele foi embora...",
			DefeatMessage = "O Lord Chainsaw foi derrotado! Volta daqui a algumas horas.",
		},
		IdleGrace = 30, -- sem alvo, espera 30 s antes de voltar para o lugar e se curar
		MinStun = 1.25,
		KnockbackImmune = true,

		Specials = {
			Cooldown = 6,
			FirstDelay = 3,
			-- Investida: ombrada atravessando a faixa
			Rush = {
				MinRange = 12,
				Distance = 40,
				Width = 7,
				Telegraph = 0.8,
				Speed = 85,
				Damage = 1.2,
				Knockback = 60,
				Stun = 0.6,
			},
			-- Socos: retângulo na frente, socos rápidos, o último arremessa
			Fury = {
				Range = 9,
				Width = 8,
				Telegraph = 0.5,
				Hits = 7,
				Interval = 0.14,
				Damage = 0.3,
				Stun = 0.2,
				Knockback = 45,
			},
		},

		Transform = {
			At = 0.15,
			Into = "LordChainsaw",
			Time = 2.5, -- parado e invulnerável, brilhando, até explodir
			Radius = 16, -- a explosão quebra o mapa e afasta quem está perto (sem dano)
			Message = "Denji puxou a cordinha do peito...",
		},
	},

	-- Lord Chainsaw: a forma do Denji (FormOf). Nasce só pela transformação, no lugar dele, com a vida cheia. É quem dá
	-- a recompensa (para todo mundo que somou MinContribution da vida dele, contando o dano no Denji).
	LordChainsaw = {
		Title = "Lord Chainsaw",
		FormOf = "Denji",
		IdleGrace = 30,
		-- Motosserra (estilo de combate, CombatStyles.Motosserra): sorteada para cada um que ajudou e ainda não tem
		StyleDrop = { Style = "Motosserra", Chance = 0.1 },
		-- Os acessórios do modelo do Denji (ItemData, Source)
		Drops = {
			{ Item = "DenjiEyepatch", Chance = 0.12 },
			{ Item = "Pochita", Chance = 0.03 },
		},
		MinContribution = 0.03,
		MinStun = 1.25,
		KnockbackImmune = true,

		Specials = {
			Cooldown = 5,
			FirstDelay = 2,
			-- Giro: as serras abertas em volta dele; quebra o mapa em volta (Destroy)
			Slam = {
				Radius = 15,
				Telegraph = 1,
				Damage = 1.5,
				Knockback = 65,
				Stun = 0.8,
				Destroy = true,
			},
			-- Avanço da motosserra: atravessa a faixa cortando tudo, inclusive o mapa no caminho
			Rush = {
				MinRange = 12,
				Distance = 55,
				Width = 8,
				Telegraph = 0.75,
				Speed = 100,
				Damage = 1.4,
				Knockback = 75,
				Stun = 0.7,
				Destroy = true,
			},
			-- Serra contínua: retângulo na frente, cortes rápidos, o último arremessa
			Fury = {
				Range = 10,
				Width = 9,
				Telegraph = 0.5,
				Hits = 10,
				Interval = 0.12,
				Damage = 0.3,
				Stun = 0.2,
				Knockback = 50,
			},
			-- Corrente: linha até o alvo; o primeiro jogador na linha é puxado até ele e leva um corte
			Chain = {
				MinRange = 10,
				Range = 38,
				Width = 4,
				Telegraph = 0.7,
				PullSpeed = 90,
				Damage = 0.4, -- ao pegar
				SlashDamage = 1.2, -- no corte, quando chega
				SlashKnockback = 55,
				Stun = 0.5,
			},
			-- Beber sangue: abaixo de At da vida (na fase 2), para e cura Heal da vida máxima em Duration s.
			-- Levar InterruptDamage da vida máxima nesse tempo interrompe (fica atordoado InterruptStun s).
			BloodDrink = {
				At = 0.25,
				Uses = 2,
				Duration = 3,
				Heal = 0.15,
				InterruptDamage = 0.05,
				InterruptStun = 2,
				Message = "Está bebendo sangue para se curar! Bata nele para interromper!",
			},
		},

		Phase2 = {
			At = 0.5,
			SpeedMultiplier = 1.3,
			CooldownMultiplier = 0.6,
			Message = "Lord Chainsaw acelerou as motosserras!",
		},

	},
}

function BossData.Get(enemyType)
	return BossData.Bosses[enemyType]
end

return BossData
