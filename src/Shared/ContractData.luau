-- Formas dos contratos do Caçador (2026-10-01). Cada Caçador tem UM contrato, que evolui em três formas:
--   V1        ao fazer o pacto (Veterano): passivo e dois poderes, V e B (slots "Z" e "X" por dentro)
--   V2        fusão com o estilo de luta (FusionStyle), feita com o Mestre dos Pactos (NPC "Evolucao"): o estilo
--             muda (Fusion: M1 no tema do contrato, skills Z/X/C próprias), os poderes e o passivo ficam mais fortes
--   Ultimate  missão mais difícil do jogo, também com o Mestre dos Pactos (QuestData)
-- Requires de cada forma: Mastery (maestria do contrato), StyleMastery (maestria do FusionStyle) e Quest (missão).
-- A forma salva fica no perfil (profile.Path.Forms[contrato]) e no atributo ContractForm do player.
-- Enabled = false: o contrato some da escolha (sem animações nem efeitos por enquanto); quem tinha vira Raposa.
-- Os poderes seguem o formato das habilidades do PathData (Kind, Cooldown, Damage...). FoxBite = true: a mordida do
-- Kon (mira com FoxAim, efeito FoxDevilVFX, finalização).
local ContractData = {}

ContractData.FormOrder = { "V1", "V2", "Ultimate" }
ContractData.FormNames = { V1 = "Pacto", V2 = "Fusão", Ultimate = "Ultimate" }
ContractData.FormGlyphs = { V1 = "壱", V2 = "弐", Ultimate = "極" }

-- Maestria do contrato: mesma curva dos estilos (SkillTreeData.Mastery, até 300). XP por:
ContractData.Mastery = {
	PowerHitXP = 8, -- cada alvo atingido por um poder do contrato (V/B)
	PowerKillXP = 20, -- inimigo derrotado por um poder do contrato
	FusionHitXP = 1, -- cada golpe do estilo fundido que conecta (V2 em diante; o estilo também ganha o dele)
}

ContractData.EvolutionNPC = "Evolucao" -- QuestData.NPCs

-- ===================== Raposa (Kon) =====================

local MORDIDA = {
	Id = "MordidaRaposa",
	Name = "Mordida da Raposa",
	Icon = "🦊",
	Glyph = "狐",
	Description = "Segure para mirar e solte: a cabeça da raposa sai de um portal e morde o ponto mirado, arremessando "
		.. "tudo em volta. Inimigos comuns com pouca vida são devorados.",
	Kind = "Cone",
	FoxBite = true,
	Cooldown = 10,
	Damage = 70,
	Range = 14,
	Angle = 70,
	Radius = 13, -- área da mordida em volta do ponto mirado (FoxAim)
	Knockback = 45, -- arremesso para longe do centro
	KnockbackUp = 30,
	Stun = 1.2,
	LifespanCost = 8,
	-- Finalização: inimigo comum (não chefe) que fica com até Threshold da vida depois da mordida é devorado
	-- (PathSkills mata e manda CombatFX "FoxDevour"; o Kon mastiga no cliente, FoxDevilVFX)
	Finisher = { Threshold = 0.3 },
}

local BOTE = {
	Id = "BoteRaposa",
	Name = "Bote da Raposa",
	Icon = "🦊",
	Glyph = "突",
	Description = "A cabeça da raposa sai de um portal atrás de você e avança em linha reta de boca aberta, arrastando "
		.. "quem estiver no caminho e fechando a mordida no fim.",
	Kind = "FoxLunge",
	Cooldown = 12,
	Damage = 55,
	Range = 32, -- comprimento da investida
	Width = 8, -- largura do corredor
	Stun = 1,
	Knockback = 20,
	KnockbackUp = 35,
	LifespanCost = 10,
}

-- Versão mais forte de um poder (V2/Ultimate): copia e troca só o que muda
local function stronger(base, changes)
	local copy = table.clone(base)
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

ContractData.Contracts = {
	Raposa = {
		Enabled = true,
		FusionStyle = "Punhos",
		Forms = {
			V1 = {
				Description = "O Kon atende ao seu chamado: mordida mirada (V) e bote em linha reta (B).",
				Passive = { SpeedBonus = 2 },
				Skills = { Z = MORDIDA, X = BOTE },
			},
			V2 = {
				Description = "Punhos e raposa viram uma coisa só: os socos rasgam como garras, as técnicas mudam e o Kon "
					.. "morde mais forte e mais longe.",
				Requires = { Mastery = 120, StyleMastery = 120 },
				Passive = { SpeedBonus = 3, LifeSteal = 0.05 },
				Skills = {
					Z = stronger(MORDIDA, {
						Id = "MordidaRaposa2",
						Name = "Mordida Voraz",
						Cooldown = 9,
						Damage = 95,
						Radius = 16,
						LifespanCost = 7,
						Finisher = { Threshold = 0.35 },
					}),
					X = stronger(BOTE, {
						Id = "BoteRaposa2",
						Name = "Bote Voraz",
						Cooldown = 10,
						Damage = 75,
						Range = 40,
						Width = 10,
						LifespanCost = 8,
					}),
				},
				-- Estilo fundido (CombatStyles.Fused): mesmo estilo base com estes campos por cima (Skills: os campos
				-- entram na skill do mesmo slot; slot novo entra inteiro).
				-- Theme: o CombatFX desenha os golpes no tema (garras laranja da raposa).
				Fusion = {
					DisplayName = "Punhos da Raposa",
					Theme = "Raposa",
					Color = Color3.fromRGB(255, 140, 30),
					Animations = {
						FoxSnap = 76984555934035, -- gesto de invocação do Kon (o mesmo da mira, trecho rápido)
						-- Combo de 4 golpes numa animação só (usuário, 2026-10-02): cada clique toca o trecho do golpe
						-- (M1.Segments, CombatAnimations)
						M1Chain = 125042720712491,
						Idle = nil, -- espaço para a pose de luta parada da raposa: ponha o ID aqui (nil = a dos Punhos)
						Uppercut = 0,
					},
					-- Combo de 4 (o 4º arremessa), sincronizado com os marcadores do usuário na animação M1Chain (1,217 s):
					-- "M1" 0,167 s, "M2" 0,483 s, "M3" 0,783 s e "M4" 1,05 s. Cada golpe toca o trecho dele (Segments: do fim
					-- do anterior até o corpo voltar, medido nos keyframes); o acerto sai no marcador (ImpactMarkers, com o
					-- ImpactTime de garantia), as garras no mesmo tempo contado do clique (ClawDelay = marcador - Start) e o
					-- próximo golpe libera no fim do trecho (Interval = End - Start; o 4º usa o EndLag). Sem uppercut (pedido do
					-- usuário): o 4º golpe no ar é um M1 comum.
					M1 = {
						Hits = 4,
						Segments = {
							{ Start = 0, End = 0.37 },
							{ Start = 0.37, End = 0.67 },
							{ Start = 0.67, End = 0.88 },
							{ Start = 0.88, End = 1.217 },
						},
						ImpactMarkers = { "M1", "M2", "M3", "M4" },
						ImpactTime = { 0.167, 0.483, 0.783, 1.05 },
						ClawDelay = { 0.167, 0.113, 0.113, 0.17 },
						Interval = { 0.37, 0.3, 0.21 },
						Damage = { 14, 14, 16, 22 },
						GuardDamage = { 12, 12, 14, 25 },
						Buffer = 0.45,
						Uppercut = false,
					},
					Skills = {
						Z = {
							Name = "Rajada de Garras",
							Description = "Uma sequência de garradas que prende o alvo na sua frente.",
							Hits = 11,
						},
						X = {
							Name = "Soco da Raposa",
							Description = "Segure para carregar e solte: o soco rasga como uma garra. Carga máxima quebra a guarda.",
						},
						-- "Kon!": garrada carmesim na frente (ClawAt) e, logo depois, uma cabeça menor do Kon sai de um portal,
						-- abocanha e puxa para perto (emenda combo)
						C = {
							Kind = "FoxSnap",
							Id = "KonSnap",
							Name = "Kon!",
							Icon = "🦊",
							Glyph = "狐",
							Description = "Uma garrada carmesim rasga quem está na frente e, logo depois, uma cabeça menor do "
								.. "Kon abocanha e puxa o alvo para perto de você, pronto para o próximo combo.",
							Cooldown = 6,
							WhiffRecovery = 0.4, -- errou as duas partes: travado e lento esse tanto (CombatService)
							ClawAt = 0.15, -- a garrada (primeiro acerto)
							ClawDamage = 16,
							ClawRange = 8,
							ClawArc = 120,
							Damage = 26, -- a mordida (segundo acerto, no SnapAt)
							ForcaScale = 0.8,
							GuardDamage = 30,
							Range = 11,
							Arc = 100,
							Stun = 1,
							Pull = 30, -- velocidade (studs/s) puxando o alvo na direção de quem invocou
							SnapAt = 0.45, -- a mordida (FoxDevilConfig.ImpactDelay: o efeito usa o mesmo tempo)
							Recovery = 0.25,
							SpeedMultiplier = 0.4,
							Animation = "FoxSnap",
							AnimationStart = 0.25,
							AnimationSpeed = 1.6,
						},
					},
				},
			},
			Ultimate = {
				Description = "O Kon se manifesta por inteiro ao seu lado.",
				Requires = { Mastery = 300, StyleMastery = 300, Quest = "UltimaRaposa" },
				Passive = { SpeedBonus = 4, LifeSteal = 0.1, DodgeChance = 0.05 },
				Skills = nil, -- mesmos da V2 até a forma Ultimate ficar pronta
				Fusion = nil, -- idem
			},
		},
	},
	-- Sem animações nem efeitos ainda: fora da escolha (2026-10-01)
	Fantasma = { Enabled = false },
	Futuro = { Enabled = false },
	Maldicao = { Enabled = false },
}

----------------------------------------------------------------------------------------------------
-- Consultas
----------------------------------------------------------------------------------------------------

function ContractData.Get(contractId)
	return if type(contractId) == "string" then ContractData.Contracts[contractId] else nil
end

-- Sem entrada aqui o contrato vale como ativo (contratos antigos do PathData)
function ContractData.IsEnabled(contractId)
	local entry = ContractData.Get(contractId)
	return entry == nil or entry.Enabled ~= false
end

-- Posição da forma (V1 = 1, V2 = 2, Ultimate = 3); forma desconhecida conta como V1
function ContractData.FormRank(form)
	return table.find(ContractData.FormOrder, form) or 1
end

function ContractData.IsForm(form)
	return table.find(ContractData.FormOrder, form) ~= nil
end

function ContractData.NextForm(form)
	return ContractData.FormOrder[ContractData.FormRank(form) + 1]
end

-- Campo de uma forma, procurando para trás quando a forma não define (Ultimate sem Skills usa as da V2...)
local function lookup(contractId, form, field)
	local entry = ContractData.Get(contractId)
	if not entry or not entry.Forms then return nil end
	for rank = ContractData.FormRank(form), 1, -1 do
		local data = entry.Forms[ContractData.FormOrder[rank]]
		if data and data[field] ~= nil then
			return data[field]
		end
	end
	return nil
end

function ContractData.Form(contractId, form)
	local entry = ContractData.Get(contractId)
	return entry and entry.Forms and entry.Forms[form] or nil
end

-- Poder do slot ("Z" = tecla V, "X" = tecla B) na forma, ou nil (contrato sem formas: o PathData decide)
function ContractData.GetSkill(contractId, form, slot)
	local skills = lookup(contractId, form, "Skills")
	return skills and skills[slot] or nil
end

function ContractData.HasForms(contractId)
	local entry = ContractData.Get(contractId)
	return entry ~= nil and entry.Forms ~= nil
end

function ContractData.Passive(contractId, form)
	return lookup(contractId, form, "Passive")
end

-- Estilo fundido da forma: { Style = nome do estilo base, ...campos do Fusion } ou nil (V1 não tem fusão)
function ContractData.Fusion(contractId, form)
	if ContractData.FormRank(form) < 2 then return nil end
	local entry = ContractData.Get(contractId)
	local fusion = lookup(contractId, form, "Fusion")
	if not entry or not fusion or not entry.FusionStyle then return nil end
	return fusion, entry.FusionStyle
end

return ContractData
