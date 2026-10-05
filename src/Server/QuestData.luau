
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PathData = require(ReplicatedStorage:WaitForChild("PathData"))

-- Texto do sacrifício de um contrato, tirado do PathData para não ficar desatualizado
local function sacrificeText(contractId)
	local contract = PathData.Contracts[contractId]
	local percent = if contract then math.floor((contract.HPCost or 0) * 100 + 0.5) else 0
	return `Sacrifício: -{percent}% de vida máxima enquanto o contrato existir, e cada uso gasta tempo de vida.`
end

return {
	-- NPCId -> nome mostrado no diálogo e no ProximityPrompt
	-- (o NPC no mapa precisa da tag "QuestGiver" e do atributo NPCId)
	NPCs = {
		-- Humano comum
		Sargento = "Sargento Otávio",
		Celeste = "Dona Celeste",
		-- NPCs dos caminhos (a escolha acontece com eles)
		Veterano = "Caçador Veterano",
		Anciao = "Demônio Ancião",
		-- Rota Caçador
		Tabelia = "Tabeliã Selma",
		Batedor = "Batedor Caio",
		-- Rota Infernal
		Coveiro = "Coveiro Jonas",
		Errante = "Infernal Errante",
		-- Estilos de combate (qualquer caminho)
		Mestre = "Mestre Espadachim",
		-- Evolução dos contratos (ContractData/ContractService): fusão com o estilo e a forma Ultimate
		Evolucao = "Mestre dos Pactos",
		-- Esquiva automática (DodgeData): treino e duelo com a cópia dele (TrainerService)
		Treinador = "Treinador",
	},

	-- Falas dos NPCs (opcional; sem entrada, usa as falas padrão do QuestModule)
	--   Available: tem missão nova | Active: só missões em andamento | Idle: nada para oferecer
	--   PathChoose: o jogador já pode escolher o caminho deste NPC
	--   Path + Rival: fala para quem seguiu o outro caminho
	Greetings = {
		Sargento = {
			Available = "Precisamos de braços. Tenho trabalho para você.",
			Active = "Ainda esperando aquele serviço, recruta.",
			Idle = "Por enquanto a guarda dá conta. Volte mais tarde.",
		},
		Evolucao = {
			Available = "Um pacto não precisa ficar do mesmo tamanho para sempre.",
			Active = "A provação continua. Volte quando tiver terminado.",
			Idle = "Todo pacto pode crescer. Mostre o quanto você domina o seu demônio e o seu estilo.",
		},
		Celeste = {
			Available = "Justo quem eu queria ver. Tenho um servicinho.",
			Active = "E então, resolveu aquele assunto?",
			Idle = "Informação custa caro, querido. Volte quando tiver mais experiência.",
		},
		Veterano = {
			Path = "Hunter",
			Available = "Tenho um trabalho. Não é para qualquer um.",
			Active = "Ainda não terminou? Demônio não espera.",
			Idle = "Contrato com demônio não é brinquedo. Volte quando estiver pronto.",
			PathChoose = "Você chegou longe para um humano comum. Quer ouvir sobre os contratos?",
			Rival = "Um Infernal andando por aqui como se fosse gente. Fale rápido.",
		},
		Anciao = {
			Path = "Fiend",
			Available = "Aproxime-se. Tenho uma tarefa para esse corpo.",
			Active = "Ainda está de pé? Então ainda não terminou.",
			Idle = "Seu corpo ainda é fraco demais para me interessar.",
			PathChoose = "Esse corpo já aguenta um demônio. Vamos conversar sobre o que você quer ser.",
			Rival = "Um caçador no meu cemitério? Corajoso. Ou burro.",
		},
		Tabelia = {
			Path = "Hunter",
			Available = "Sente-se. Todo pacto começa com papelada.",
			Active = "O pacto ainda está pendente. Cumpra o que foi combinado.",
			Idle = "Nenhum demônio quer negociar com você agora.",
			Rival = "Infernais não assinam pactos. Não tenho nada para você.",
		},
		Batedor = {
			Path = "Hunter",
			Available = "Achei rastro novo. Vem comigo?",
			Active = "Os rastros não vão esperar para sempre.",
			Idle = "Nada no radar. Descanse um pouco.",
			Rival = "Fique longe. Eu sei muito bem o que você é.",
		},
		Coveiro = {
			Path = "Fiend",
			Available = "Tem trabalho sujo, do jeito que você gosta.",
			Active = "As covas ainda não estão em paz.",
			Idle = "Os mortos estão quietos hoje.",
			Rival = "Caçador no cemitério só vem para cavar a própria cova.",
		},
		Errante = {
			Path = "Fiend",
			Available = "Com fome? Eu também. Vamos caçar.",
			Active = "Ainda sinto cheiro de sangue fresco lá fora.",
			Idle = "Não tenho nada para ensinar agora. Viva mais um pouco.",
			Rival = "Esse cheiro de contrato... Saia daqui antes que eu mude de ideia.",
		},
		Mestre = {
			Available = "Você briga com as mãos nuas... Quer aprender a segurar uma lâmina de verdade?",
			Active = "A lâmina não espera. Termine o que eu pedi.",
			Idle = "Volte quando tiver mais estrada. Eu só ensino a partir do level 15.",
		},
		Treinador = {
			Available = "Você apanha demais. Quer aprender a não estar onde o golpe cai?",
			Active = "O corpo só aprende fazendo. Termine o treino.",
			Idle = "Ainda é cedo para você. Volte no level 10, ou quando eu tiver algo novo para ensinar.",
		},
	},

	Quests = {
		-- ================= Humano comum (level 1 a 25) =================
		{
			Id = "Tutorial1",
			Name = "Primeiro sangue",
			Description = "Goblins, os demônios mais fracos, tomaram a rua onde você acordou. Feche os punhos e mostre do que é capaz.",
			Main = true,
			Path = "None",
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 5, Text = "Goblins derrotados" },
			},
			Rewards = { XP = 60, Gold = 15 },
		},
		{
			Id = "Tutorial2",
			Name = "Ficando mais forte",
			Description = "Cada level dá pontos de status. Distribua os seus (tecla M) e chegue ao level 3.",
			Main = true,
			Path = "None",
			Requires = { "Tutorial1" },
			Objectives = {
				{ Type = "ReachLevel", Amount = 3, Text = "Level" },
			},
			Rewards = { Gold = 30, StatusPoints = 2 },
		},
		{
			Id = "Limpeza",
			Name = "Limpeza da rua",
			Description = "Os Goblins continuam saindo das frestas. Dê um jeito neles antes que cheguem às casas.",
			Path = "None",
			Requires = { "Tutorial1" },
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 12, Text = "Goblins derrotados" },
			},
			Rewards = { XP = 150, Gold = 40 },
		},
		{
			Id = "ChamadoSargento",
			Name = "O chamado da guarda",
			Description = "A guarda da cidade aceita qualquer um que saiba segurar uma espada. Procure o Sargento Otávio.",
			Main = true,
			Path = "None",
			MinLevel = 3,
			Requires = { "Tutorial2" },
			Objectives = {
				{ Type = "TalkTo", Target = "Sargento", Amount = 1, Text = "Falar com o Sargento Otávio" },
			},
			Rewards = { XP = 100, Gold = 20 },
		},
		{
			Id = "Contrato",
			Name = "Serviço de extermínio",
			Description = "Trabalho fixo da guarda: 15 demônios de qualquer tipo por serviço. Pode ser repetido.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 3,
			Requires = { "ChamadoSargento" },
			Repeatable = true,
			Objectives = {
				{ Type = "Kill", Amount = 15, Text = "Demônios de qualquer tipo" },
			},
			Rewards = { XP = 200, Gold = 50 },
		},
		{
			Id = "EsgotoInfestado",
			Name = "Esgoto infestado",
			Description = "Algo está se reproduzindo no esgoto. Desça até lá e diminua o número de Goblins antes que eles subam para as ruas.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 5,
			Requires = { "ChamadoSargento" },
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 15, Text = "Goblins derrotados" },
			},
			Rewards = { XP = 500, Gold = 90, StatusPoints = 1 },
		},
		{
			Id = "RondaNoturna",
			Name = "Ronda na pedreira",
			Description = "Os ataques vêm da caverna da pedreira. Limpe a entrada e leve o relatório para a Dona Celeste, que financia a guarda.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 8,
			Requires = { "EsgotoInfestado" },
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 20, Text = "Goblins derrotados" },
				{ Type = "TalkTo", Target = "Celeste", Amount = 1, Text = "Entregar o relatório à Dona Celeste" },
			},
			Rewards = { XP = 900, Gold = 120 },
		},
		{
			Id = "PatrulhaLadroes",
			Name = "Ladrões de beco",
			Description = "Goblins Ladrões estão roubando as casas do bairro de baixo. O Sargento quer os becos limpos.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 10,
			Requires = { "RondaNoturna" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 10, Text = "Goblins Ladrões derrotados" },
			},
			Rewards = { XP = 1000, Gold = 150, StatusPoints = 1 },
		},
		{
			Id = "InformanteCeleste",
			Name = "A informante",
			Description = "Dizem que a Dona Celeste sabe de onde os demônios estão vindo. Vá falar com ela.",
			Main = true,
			Path = "None",
			MinLevel = 10,
			Requires = { "Tutorial2" },
			Objectives = {
				{ Type = "TalkTo", Target = "Celeste", Amount = 1, Text = "Falar com a Dona Celeste" },
			},
			Rewards = { XP = 400, Gold = 50 },
		},
		{
			Id = "CargaRoubada",
			Name = "Carga roubada",
			Description = "Os Goblins Ladrões levaram as caixas de remédio da Dona Celeste para o esconderijo deles. Recupere a carga do jeito difícil.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 11,
			Requires = { "InformanteCeleste" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 15, Text = "Goblins Ladrões derrotados" },
			},
			Rewards = { XP = 1000, Gold = 150, StatusPoints = 1 },
		},
		{
			Id = "PantanoVenenoso",
			Name = "Água envenenada",
			Description = "Os Goblins Ladrões estão envenenando a água do canal para esvaziar as casas e saquear tudo. A Dona Celeste quer isso parado.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 13,
			Requires = { "CargaRoubada" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 18, Text = "Goblins Ladrões derrotados" },
			},
			Rewards = { XP = 1300, Gold = 180 },
		},
		{
			Id = "SangueNaPraca",
			Name = "Sangue na praça",
			Description = "Goblins Ladrões atacaram a feira. A Dona Celeste perdeu dois fornecedores e quer justiça.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 16,
			Requires = { "PantanoVenenoso" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 20, Text = "Goblins Ladrões derrotados" },
			},
			Rewards = { XP = 1800, Gold = 220, StatusPoints = 1 },
		},
		{
			Id = "RumoresCaminhos",
			Name = "Dois caminhos",
			Description = "Humanos comuns não vencem essa guerra sozinhos. Alguns fazem contratos com demônios; outros aceitam dividir o próprio corpo com um. Conheça quem fala por cada lado.",
			Main = true,
			Path = "None",
			MinLevel = 18,
			Requires = { "Tutorial2" },
			Objectives = {
				{ Type = "TalkTo", Target = "Veterano", Amount = 1, Text = "Falar com o Caçador Veterano" },
				{ Type = "TalkTo", Target = "Anciao", Amount = 1, Text = "Falar com o Demônio Ancião" },
			},
			Rewards = { XP = 1500, Gold = 100 },
		},
		{
			Id = "CidadeEmCinzas",
			Name = "Bairro em cinzas",
			Description = "O bairro velho pegou fogo e os Goblins Ladrões estão saqueando os escombros. Limpe a área para a reconstrução.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 18,
			Requires = { "SangueNaPraca" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 20, Text = "Goblins Ladrões derrotados" },
			},
			Rewards = { XP = 2400, Gold = 260 },
		},
		{
			Id = "ProvaVeterano",
			Name = "O olhar do veterano",
			Description = "O Caçador Veterano não apresenta demônio nenhum a quem morre fácil. Limpe os ladrões e derrube o Rei Goblin, o dono de todos eles.",
			Giver = "Veterano",
			Path = "None",
			MinLevel = 20,
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 15, Text = "Goblins Ladrões derrotados" },
				{ Type = "Kill", Target = "ReiGoblin", Amount = 1, Text = "Rei Goblin derrotado" },
			},
			Rewards = { XP = 2500, Gold = 200, StatusPoints = 1 },
		},
		{
			Id = "SussurroAnciao",
			Name = "Sussurros no cemitério",
			Description = "O Demônio Ancião quer saber se o seu corpo aguenta o que ele tem para oferecer. Traga sangue de Ratazana e de Goblin.",
			Giver = "Anciao",
			Path = "None",
			MinLevel = 20,
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Ratazanas derrotadas" },
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 10, Text = "Goblins Ladrões derrotados" },
			},
			Rewards = { XP = 2500, Gold = 200, StatusPoints = 1 },
		},
		{
			Id = "Brutamontes",
			Name = "Ratos na ponte",
			Description = "Um bando de Ratazanas do Canal subiu para a ponte principal. A guarda precisa dela aberta até o fim da semana.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 21,
			Requires = { "RondaNoturna" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 20, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3000, Gold = 320, StatusPoints = 2 },
		},
		{
			Id = "SombrasDoPorto",
			Name = "Sombras do porto",
			Description = "As Ratazanas atacam os barcos do canal à noite. É o último trabalho que o Sargento tem para um humano comum.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 23,
			Requires = { "Brutamontes" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 25, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3600, Gold = 350 },
		},
		{
			-- Id exato usado por PathData.RequiredQuest: completar libera a escolha de caminho
			Id = "Encruzilhada",
			Name = "Encruzilhada",
			Description = "Você chegou ao limite de um humano comum. Fale com o Caçador Veterano para fazer um contrato com um demônio, ou com o Demônio Ancião para se tornar um Infernal. A escolha é permanente.",
			Main = true,
			Path = "None",
			MinLevel = 25,
			Objectives = {
				{
					Type = "TalkTo",
					TargetList = { "Veterano", "Anciao" },
					Amount = 1,
					Text = "Falar com o Caçador Veterano ou o Demônio Ancião",
				},
			},
			Rewards = { XP = 1000, Gold = 300, StatusPoints = 3 },
		},

		-- ================= Caçador =================
		{
			Id = "NovoCacador",
			Name = "Registro de pacto",
			Description = "Todo caçador da cidade registra os seus contratos. Procure a Tabeliã Selma: ela guarda os pactos e sabe quais demônios ainda aceitam negociar.",
			Main = true,
			Path = "Hunter",
			Objectives = {
				{ Type = "TalkTo", Target = "Tabelia", Amount = 1, Text = "Falar com a Tabeliã Selma" },
			},
			Rewards = { XP = 500, Gold = 100 },
		},
		{
			Id = "CacadorJuramento",
			Name = "O juramento do caçador",
			Description = "Um contrato não serve de nada se você tiver medo de usá-lo. Use o poder do seu demônio (Z/X) em combate e limpe o canal.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 25,
			Objectives = {
				{ Type = "UsePower", Amount = 5, Text = "Poderes usados" },
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3000, Gold = 300 },
		},
		{
			Id = "PrecoDoPacto",
			Name = "O preço do pacto",
			Description = "Cada uso de um contrato gasta um pedaço do seu tempo de vida. A Tabeliã quer que você sinta esse preço antes de pensar num segundo pacto.",
			Giver = "Tabelia",
			Path = "Hunter",
			MinLevel = 26,
			Requires = { "NovoCacador" },
			Objectives = {
				{ Type = "UsePower", Amount = 15, Text = "Poderes usados" },
				{ Type = "Kill", Target = "Ratazana", Amount = 20, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3500, Gold = 350 },
		},
		{
			-- 2º contrato: só um dos dois pactos (ExclusiveWith)
			Id = "PactoFuturo",
			Name = "Pacto com o Futuro",
			Description = "O Demônio do Futuro quer morar no seu olho e assistir ao seu futuro de perto. Em troca, você enxerga os golpes antes que aconteçam. "
				.. sacrificeText("Futuro")
				.. " Só é possível firmar um destes dois pactos.",
			Giver = "Tabelia",
			Path = "Hunter",
			MinLevel = 30,
			Requires = { "PrecoDoPacto" },
			ExclusiveWith = { "PactoMaldicao" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 20, Text = "Manequins derrotados" },
				{ Type = "UsePower", Amount = 10, Text = "Poderes usados" },
				{ Type = "TalkTo", Target = "Tabelia", Amount = 1, Text = "Voltar à Tabeliã Selma para assinar" },
			},
			Rewards = { XP = 4000, Gold = 300, Contract = "Futuro" },
		},
		{
			Id = "PactoMaldicao",
			Name = "Pacto com a Maldição",
			Description = "O Demônio da Maldição empresta os seus pregos a quem paga em vida, e cobra adiantado em sangue de demônio. "
				.. sacrificeText("Maldicao")
				.. " Só é possível firmar um destes dois pactos.",
			Giver = "Tabelia",
			Path = "Hunter",
			MinLevel = 30,
			Requires = { "PrecoDoPacto" },
			ExclusiveWith = { "PactoFuturo" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 30, Text = "Manequins derrotados" },
				{ Type = "TalkTo", Target = "Tabelia", Amount = 1, Text = "Voltar à Tabeliã Selma para assinar" },
			},
			Rewards = { XP = 4000, Gold = 300, Contract = "Maldicao" },
		},
		{
			Id = "CacaInfernal",
			Name = "Caça aos Infernais",
			Description = "Infernais andam pela cidade vestindo o cadáver de gente que morreu aqui. O Veterano paga por cada um que você derrubar. Pode ser repetido.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 26,
			Requires = { "CacadorJuramento" },
			Repeatable = true,
			Objectives = {
				{ Type = "KillPlayer", Target = "Fiends", Amount = 3, Text = "Infernais diferentes derrotados" },
			},
			Rewards = { XP = 4000, Gold = 500 },
		},
		{
			Id = "RastroCarnica",
			Name = "Rastro no cemitério",
			Description = "O Batedor Caio seguiu as Ratazanas do Canal até o cemitério. Elas comem os mortos, e onde há mortos há Infernais por perto.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 27,
			Requires = { "CacadorJuramento" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 25, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3800, Gold = 380, StatusPoints = 1 },
		},
		{
			Id = "BordaDoAbismo",
			Name = "Vitrines vazias",
			Description = "Nas lojas abandonadas do Mercado os Manequins se mexem quando ninguém está olhando. O Batedor precisa que alguém segure a rua enquanto ele mapeia o prédio.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 32,
			Requires = { "RastroCarnica" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 25, Text = "Manequins derrotados" },
			},
			Rewards = { XP = 5000, Gold = 450 },
		},
		{
			Id = "PatrulhaCacador",
			Name = "Patrulha dos caçadores",
			Description = "Serviço fixo do Batedor: 20 demônios de level 30 ou mais por patrulha. Pode ser repetido.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 30,
			Requires = { "RastroCarnica" },
			Repeatable = true,
			Objectives = {
				{ Type = "Kill", MinEnemyLevel = 30, Amount = 20, Text = "Demônios de level 30+ (qualquer tipo)" },
			},
			Rewards = { XP = 3500, Gold = 400 },
		},
		{
			Id = "CabecaAPremio",
			Name = "Cabeças a prêmio",
			Description = "Os Infernais mais velhos estão organizando ataques contra os caçadores. O Veterano quer mandar uma mensagem clara.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 32,
			Requires = { "CacaInfernal" },
			Objectives = {
				{ Type = "KillPlayer", Target = "Fiends", Amount = 5, Text = "Infernais diferentes derrotados" },
			},
			Rewards = { XP = 8000, Gold = 1000, StatusPoints = 2 },
		},
		{
			Id = "CarneCorrompida",
			Name = "Olhos de vidro",
			Description = "Os Manequins estão saindo das vitrines e tomando as ruas do Mercado. O Batedor quer saber quantos são; a resposta certa é nenhum.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 36,
			Requires = { "BordaDoAbismo" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 30, Text = "Manequins derrotados" },
			},
			Rewards = { XP = 6500, Gold = 550, StatusPoints = 2 },
		},
		{
			Id = "NinhoCacador",
			Name = "O último trem",
			Description = "O Batedor achou a estação de onde saem os Passageiros do Metrô. Eles aparecem pelas costas de quem espera o trem: derrube-os.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 40,
			Requires = { "CarneCorrompida" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 20, Text = "Passageiros derrotados" },
			},
			Rewards = { XP = 9000, Gold = 800 },
		},
		{
			Id = "CoroaCacador",
			Name = "Linha fantasma",
			Description = "Os Passageiros tomaram a linha inteira. Nenhum caçador voltou do último vagão com os dois braços. Use tudo o que os seus contratos oferecem.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 45,
			Requires = { "NinhoCacador" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 30, Text = "Passageiros derrotados" },
				{ Type = "UsePower", Amount = 15, Text = "Poderes usados" },
			},
			Rewards = { XP = 12000, Gold = 1500, StatusPoints = 3 },
		},

		-- ================= Infernal =================
		{
			Id = "NovoInfernal",
			Name = "Corpo emprestado",
			Description = "Seu corpo agora é a casa de um demônio. O Ancião mandou você procurar o Coveiro Jonas: ele sabe onde estão os corpos frescos, e quem anda caçando gente como você.",
			Main = true,
			Path = "Fiend",
			Objectives = {
				{ Type = "TalkTo", Target = "Coveiro", Amount = 1, Text = "Falar com o Coveiro Jonas" },
			},
			Rewards = { XP = 500, Gold = 100 },
		},
		{
			Id = "DominarCorpo",
			Name = "Dominar o cadáver",
			Description = "Um cadáver novo demora a obedecer. Use os seus poderes (Z/X) até o corpo se mexer como se sempre tivesse sido seu.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 25,
			Objectives = {
				{ Type = "UsePower", Amount = 5, Text = "Poderes usados" },
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3000, Gold = 300 },
		},
		{
			Id = "CovasRasas",
			Name = "Covas rasas",
			Description = "As Ratazanas do Canal estão comendo os mortos do cemitério antes que qualquer Infernal possa usá-los. O Coveiro quer as covas em paz.",
			Giver = "Coveiro",
			Path = "Fiend",
			MinLevel = 26,
			Requires = { "NovoInfernal" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3500, Gold = 350 },
		},
		{
			Id = "FomeDeSangue",
			Name = "Fome de sangue",
			Description = "A Infernal Errante troca de cadáver há décadas. Ela ensina que o poder de um Infernal custa o próprio sangue, e que é preciso aprender a pagar sem cair.",
			Giver = "Errante",
			Path = "Fiend",
			MinLevel = 27,
			Requires = { "DominarCorpo" },
			Objectives = {
				{ Type = "UsePower", Amount = 15, Text = "Poderes usados" },
				{ Type = "Kill", Target = "Ratazana", Amount = 20, Text = "Ratazanas derrotadas" },
			},
			Rewards = { XP = 3800, Gold = 380, StatusPoints = 1 },
		},
		{
			Id = "CacaCacadores",
			Name = "Caça aos caçadores",
			Description = "Caçadores vendem pedaços da própria vida para matar gente como nós. O Ancião quer que eles aprendam o preço disso. Só Caçadores contam: deixe os humanos comuns em paz. Pode ser repetido.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 26,
			Requires = { "DominarCorpo" },
			Repeatable = true,
			Objectives = {
				{ Type = "KillPlayer", Target = "Humans", VictimPath = "Hunter", Amount = 3, Text = "Caçadores diferentes derrotados" },
			},
			Rewards = { XP = 4000, Gold = 500 },
		},
		{
			Id = "AbismoChama",
			Name = "Quem manda na rua",
			Description = "Os Manequins do Mercado não aceitam dividir a cidade com Infernais. O Coveiro quer que você mostre quem manda na superfície.",
			Giver = "Coveiro",
			Path = "Fiend",
			MinLevel = 30,
			Requires = { "CovasRasas" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 25, Text = "Manequins derrotados" },
			},
			Rewards = { XP = 5000, Gold = 450 },
		},
		{
			Id = "PatrulhaInfernal",
			Name = "Caçada noturna",
			Description = "A Errante caça toda noite para manter o corpo forte: 20 demônios de level 30 ou mais. Pode ser repetido.",
			Giver = "Errante",
			Path = "Fiend",
			MinLevel = 30,
			Requires = { "FomeDeSangue" },
			Repeatable = true,
			Objectives = {
				{ Type = "Kill", MinEnemyLevel = 30, Amount = 20, Text = "Demônios de level 30+ (qualquer tipo)" },
			},
			Rewards = { XP = 3500, Gold = 400 },
		},
		{
			Id = "TrofeusCacador",
			Name = "Troféus de caçador",
			Description = "O Ancião coleciona os contratos quebrados dos caçadores que caem. Traga mais para a coleção.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 32,
			Requires = { "CacaCacadores" },
			Objectives = {
				{ Type = "KillPlayer", Target = "Humans", VictimPath = "Hunter", Amount = 5, Text = "Caçadores diferentes derrotados" },
			},
			Rewards = { XP = 8000, Gold = 1000, StatusPoints = 2 },
		},
		{
			Id = "PeleCorrompida",
			Name = "Pele de plástico",
			Description = "Os Manequins arrancam a pele dos cadáveres para se vestir. A Errante quer a área limpa antes que o seu próximo corpo estrague.",
			Giver = "Errante",
			Path = "Fiend",
			MinLevel = 36,
			Requires = { "AbismoChama" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 30, Text = "Manequins derrotados" },
			},
			Rewards = { XP = 6500, Gold = 550, StatusPoints = 2 },
		},
		{
			Id = "TronoDoNinho",
			Name = "A estação",
			Description = "Quem manda no metrô manda nos demônios menores da cidade. O Ancião quer a estação livre dos Passageiros.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 40,
			Requires = { "PeleCorrompida" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 20, Text = "Passageiros derrotados" },
			},
			Rewards = { XP = 9000, Gold = 800 },
		},
		{
			Id = "CoroaDeOssos",
			Name = "Último vagão",
			Description = "O Ancião quer a linha inteira. Derrube os Passageiros do Metrô usando tudo o que o seu sangue permite.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 45,
			Requires = { "TronoDoNinho" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 30, Text = "Passageiros derrotados" },
				{ Type = "UsePower", Amount = 15, Text = "Poderes usados" },
			},
			Rewards = { XP = 12000, Gold = 1500, StatusPoints = 3 },
		},

		-- ================= Estilos de combate (qualquer caminho) =================
		{
			Id = "CaminhoDaLamina",
			Name = "O caminho da lâmina",
			Description = "O Mestre Espadachim só ensina quem já sobreviveu às ruas. Os Goblins Ladrões levaram as lâminas do dojo: derrote-os e volte para receber a sua katana.",
			Giver = "Mestre",
			MinLevel = 15,
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 12, Text = "Goblins Ladrões derrotados" },
				{ Type = "TalkTo", Target = "Mestre", Amount = 1, Text = "Voltar ao Mestre Espadachim" },
			},
			Rewards = { XP = 1500, Style = "Katana" },
		},

		-- ================= Esquiva automática: Treinador (qualquer caminho, DodgeData) =================
		-- Cada missão dá um nível de esquiva (Rewards.DodgeLevel). Spar/Duel: botão TREINAR/DUELAR no diálogo dele
		-- (TrainerService: uma cópia do Treinador luta só com quem pediu).
		{
			Id = "EsquivaLeitura",
			Name = "Ler o golpe",
			Description = "Antes de desviar, é preciso entender o golpe. Vá apanhar dos demônios da cidade: cada golpe que chegar perto ensina alguma coisa.",
			Giver = "Treinador",
			MinLevel = 10,
			Objectives = {
				{ Type = "TakeHits", Amount = 30, Text = "Golpes de inimigos levados (ou desviados)" },
				{ Type = "TalkTo", Target = "Treinador", Amount = 1, Text = "Voltar ao Treinador" },
			},
			Rewards = { XP = 600, DodgeLevel = 1 },
		},
		{
			Id = "EsquivaLadroes",
			Name = "Mãos rápidas",
			Description = "Os Goblins Ladrões atacam rápido e de lado. Derrote vários deles sem fugir da briga.",
			Giver = "Treinador",
			MinLevel = 10,
			Requires = { "EsquivaLeitura" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 15, Text = "Goblins Ladrões derrotados" },
				{ Type = "TalkTo", Target = "Treinador", Amount = 1, Text = "Voltar ao Treinador" },
			},
			Rewards = { XP = 1200, DodgeLevel = 2 },
		},
		{
			Id = "EsquivaTreino",
			Name = "Treino com o Treinador",
			Description = "Agora comigo. Aguente meus golpes sem cair: desviar também conta. Aperte TREINAR quando estiver pronto.",
			Giver = "Treinador",
			MinLevel = 15,
			Requires = { "EsquivaLadroes" },
			Objectives = {
				{ Type = "Spar", Amount = 40, Text = "Golpes do treino aguentados (ou desviados)" },
			},
			Rewards = { XP = 2000, DodgeLevel = 3 },
		},
		{
			Id = "EsquivaRatazanas",
			Name = "Bando nos esgotos",
			Description = "As Ratazanas atacam em bando, de todos os lados. Volte inteiro depois de derrotar algumas.",
			Giver = "Treinador",
			MinLevel = 20,
			Requires = { "EsquivaTreino" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 10, Text = "Ratazanas derrotadas" },
				{ Type = "TalkTo", Target = "Treinador", Amount = 1, Text = "Voltar ao Treinador" },
			},
			Rewards = { XP = 3000, DodgeLevel = 4 },
		},
		{
			Id = "EsquivaDuelo",
			Name = "O último teste",
			Description = "Chega de treino. Me derrote num duelo de verdade e eu te ensino tudo o que sei. Aperte DUELAR quando estiver pronto.",
			Giver = "Treinador",
			MinLevel = 25,
			Requires = { "EsquivaRatazanas" },
			Objectives = {
				{ Type = "Duel", Amount = 1, Text = "Duelo contra o Treinador vencido" },
			},
			Rewards = { XP = 5000, DodgeLevel = 5 },
		},
	},
}
