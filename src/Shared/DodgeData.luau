-- Esquiva automática (desvio): chance de um golpe não pegar. Vale contra M1, skills, poderes e inimigos; só jogador
-- desvia. Sobe treinando com o Treinador (NPCId "Treinador"; missões no QuestData com a recompensa DodgeLevel): o nível
-- fica salvo no perfil (profile.DodgeLevel, atributo DodgeLevel do player). A chance do nível soma com a do clã e a dos
-- itens no atributo TreeDodgeChance (PlayerData) e com a do caminho, com o teto MaxChance (CombatRules).
-- Ao desviar pela chance: o personagem toca a animação do lado (Animations: Left/Right/Back, conforme de onde veio o
-- golpe), dá um passo de Step studs para esse lado e deixa um rastro (CombatFX "Dodge"; o passo e a animação são do
-- cliente de quem desviou, que é dono do próprio personagem).
local DodgeData = {}

DodgeData.MinPlayerLevel = 10 -- level para começar o treino com o Treinador
DodgeData.MaxChance = 0.35 -- teto da chance somada (treino + clã + itens + caminho)

-- Um por nível. Counter: contra-golpe; Rush: desvio rápido (ver abaixo)
DodgeData.Levels = {
	{ Chance = 0.03 },
	{ Chance = 0.06 },
	{ Chance = 0.09, Counter = true },
	{ Chance = 0.12, Counter = true },
	{ Chance = 0.15, Counter = true, Rush = true },
}
DodgeData.MaxLevel = #DodgeData.Levels

-- Contra-golpe (nível 3+): o primeiro M1 que acertar até Window segundos depois de desviar dá Bonus a mais de dano
DodgeData.Counter = { Window = 1.2, Bonus = 0.5 }
-- Desvio rápido (nível 5): Speed de velocidade a mais por Time segundos depois de desviar (StaminaDashRunscript)
DodgeData.Rush = { Time = 1.5, Speed = 6 }

-- O deslocamento é feito por código (CombatFX dodgeStep, parando antes de parede); as animações só mexem o corpo
-- (inclinar, pernas, braços), sem mover a raiz: root motion na animação faria o personagem "voltar" de posição.
DodgeData.Step = 2.2 -- passo para o lado ao desviar (studs)
DodgeData.StepTime = 0.12 -- em quanto tempo o passo acontece

-- Animações R6 do desvio, uma por lado (0 = sem animação). Sem a de trás, o desvio sorteia só esquerda/direita.
DodgeData.Animations = {
	Left = 73469238746441, -- esquiva para a esquerda (usuário, 2026-10-02, publicada na conta dele)
	Right = 79606409190712, -- esquiva para a direita
	Back = 0,
}
-- A animação para em no máximo AnimationMaxTime segundos (com uma transição curta): uma exportação com a linha do tempo
-- inteira prenderia o corpo na pose do fim (a da direita veio com 10,4 s, parada depois de 0,7 s).
DodgeData.AnimationMaxTime = 0.75

-- Dados do nível (nil para o nível 0 ou inválido)
function DodgeData.Get(level)
	if type(level) ~= "number" then return nil end
	return DodgeData.Levels[math.floor(level)]
end

-- Chance de desvio que o treino dá nesse nível (0 sem treino)
function DodgeData.Chance(level)
	local data = DodgeData.Get(level)
	return if data then data.Chance else 0
end

return DodgeData
