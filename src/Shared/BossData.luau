
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
}

function BossData.Get(enemyType)
	return BossData.Bosses[enemyType]
end

return BossData
