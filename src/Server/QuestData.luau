
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PathData = require(ReplicatedStorage:WaitForChild("PathData"))

-- Texto do sacrifício de um contrato, tirado do PathData para não ficar desatualizado
local function sacrificeText(contractId)
	local contract = PathData.Contracts[contractId]
	local percent = if contract then math.floor((contract.HPCost or 0) * 100 + 0.5) else 0
	return `Sacrifice: -{percent}% max health while the contract lasts, and every use costs lifespan.`
end

return {
	-- NPCId -> nome mostrado no diálogo e no ProximityPrompt
	-- (o NPC no mapa precisa da tag "QuestGiver" e do atributo NPCId)
	NPCs = {
		-- Humano comum
		Sargento = "Sergeant Otávio",
		Celeste = "Madam Celeste",
		-- NPCs dos caminhos (a escolha acontece com eles)
		Veterano = "Veteran Hunter",
		Anciao = "Elder Devil",
		-- Rota Caçador
		Tabelia = "Notary Selma",
		Batedor = "Scout Caio",
		-- Rota Infernal
		Coveiro = "Gravedigger Jonas",
		Errante = "Wandering Fiend",
		-- Estilos de combate (qualquer caminho)
		Mestre = "Master Swordsman",
		-- Evolução dos contratos (ContractData/ContractService): fusão com o estilo e a forma Ultimate
		Evolucao = "Pact Master",
		-- Esquiva automática (DodgeData): treino e duelo com a cópia dele (TrainerService)
		Treinador = "Trainer",
	},

	-- Falas dos NPCs (opcional; sem entrada, usa as falas padrão do QuestModule)
	--   Available: tem missão nova | Active: só missões em andamento | Idle: nada para oferecer
	--   PathChoose: o jogador já pode escolher o caminho deste NPC
	--   Path + Rival: fala para quem seguiu o outro caminho
	Greetings = {
		Sargento = {
			Available = "We need hands. I have work for you.",
			Active = "Still waiting on that job, recruit.",
			Idle = "The guard has it covered for now. Come back later.",
		},
		Evolucao = {
			Available = "A pact does not have to stay the same size forever.",
			Active = "The trial goes on. Come back when you are done.",
			Idle = "Every pact can grow. Show me how well you master your devil and your style.",
		},
		Celeste = {
			Available = "Just who I wanted to see. I have a little job.",
			Active = "So, did you take care of that business?",
			Idle = "Information is expensive, dear. Come back when you have more experience.",
		},
		Veterano = {
			Path = "Hunter",
			Available = "I have a job. It is not for just anyone.",
			Active = "Not done yet? Devils do not wait.",
			Idle = "A devil contract is not a toy. Come back when you are ready.",
			PathChoose = "You have come far for an ordinary human. Want to hear about contracts?",
			Rival = "A Fiend walking around here like a person. Talk fast.",
		},
		Anciao = {
			Path = "Fiend",
			Available = "Come closer. I have a task for that body.",
			Active = "Still standing? Then you are not done yet.",
			Idle = "Your body is still too weak to interest me.",
			PathChoose = "That body can already hold a devil. Let us talk about what you want to become.",
			Rival = "A hunter in my graveyard? Brave. Or stupid.",
		},
		Tabelia = {
			Path = "Hunter",
			Available = "Sit down. Every pact starts with paperwork.",
			Active = "The pact is still pending. Do what was agreed.",
			Idle = "No devil wants to deal with you right now.",
			Rival = "Fiends do not sign pacts. I have nothing for you.",
		},
		Batedor = {
			Path = "Hunter",
			Available = "I found a fresh trail. Coming with me?",
			Active = "The trail will not wait forever.",
			Idle = "Nothing on the radar. Get some rest.",
			Rival = "Stay away. I know exactly what you are.",
		},
		Coveiro = {
			Path = "Fiend",
			Available = "There is dirty work, just the way you like it.",
			Active = "The graves are still not at peace.",
			Idle = "The dead are quiet today.",
			Rival = "A hunter in the graveyard only comes to dig his own grave.",
		},
		Errante = {
			Path = "Fiend",
			Available = "Hungry? Me too. Let us hunt.",
			Active = "I still smell fresh blood out there.",
			Idle = "I have nothing to teach you right now. Live a little longer.",
			Rival = "That smell of a contract... Get out before I change my mind.",
		},
		Mestre = {
			Available = "You fight with your bare hands... Want to learn to hold a real blade?",
			Active = "The blade does not wait. Finish what I asked.",
			Idle = "Come back when you have more experience. I only teach from level 15.",
		},
		Treinador = {
			Available = "You take too many hits. Want to learn not to be where the blow lands?",
			Active = "The body only learns by doing. Finish the training.",
			Idle = "It is too early for you. Come back at level 10, or when I have something new to teach.",
		},
	},

	Quests = {
		-- ================= Humano comum (level 1 a 25) =================
		{
			Id = "Tutorial1",
			Name = "First Blood",
			Description = "Goblins, the weakest devils, have taken the street where you woke up. Clench your fists and show what you can do.",
			Main = true,
			Path = "None",
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 5, Text = "Goblins defeated" },
			},
			Rewards = { XP = 60, Gold = 15 },
		},
		{
			Id = "Tutorial2",
			Name = "Getting Stronger",
			Description = "Every level gives skill points. Spend yours (key M) and reach level 3.",
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
			Name = "Street Cleanup",
			Description = "Goblins keep crawling out of the cracks. Deal with them before they reach the houses.",
			Path = "None",
			Requires = { "Tutorial1" },
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 12, Text = "Goblins defeated" },
			},
			Rewards = { XP = 150, Gold = 40 },
		},
		{
			Id = "ChamadoSargento",
			Name = "The Guard's Call",
			Description = "The city guard takes anyone who can hold a sword. Find Sergeant Otávio.",
			Main = true,
			Path = "None",
			MinLevel = 3,
			Requires = { "Tutorial2" },
			Objectives = {
				{ Type = "TalkTo", Target = "Sargento", Amount = 1, Text = "Talk to Sergeant Otávio" },
			},
			Rewards = { XP = 100, Gold = 20 },
		},
		{
			Id = "Contrato",
			Name = "Extermination Job",
			Description = "Standing guard job: 15 devils of any kind per job. Repeatable.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 3,
			Requires = { "ChamadoSargento" },
			Repeatable = true,
			Objectives = {
				{ Type = "Kill", Amount = 15, Text = "Devils of any kind" },
			},
			Rewards = { XP = 200, Gold = 50 },
		},
		{
			Id = "EsgotoInfestado",
			Name = "Infested Sewer",
			Description = "Something is breeding in the sewer. Go down there and thin out the Goblins before they climb into the streets.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 5,
			Requires = { "ChamadoSargento" },
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 15, Text = "Goblins defeated" },
			},
			Rewards = { XP = 500, Gold = 90, StatusPoints = 1 },
		},
		{
			Id = "RondaNoturna",
			Name = "Quarry Patrol",
			Description = "The attacks come from the quarry cave. Clear the entrance and take the report to Madam Celeste, who funds the guard.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 8,
			Requires = { "EsgotoInfestado" },
			Objectives = {
				{ Type = "Kill", Target = "Goblin", Amount = 20, Text = "Goblins defeated" },
				{ Type = "TalkTo", Target = "Celeste", Amount = 1, Text = "Deliver the report to Madam Celeste" },
			},
			Rewards = { XP = 900, Gold = 120 },
		},
		{
			Id = "PatrulhaLadroes",
			Name = "Alley Thieves",
			Description = "Goblin Thieves are robbing the houses in the lower district. The Sergeant wants the alleys cleared.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 10,
			Requires = { "RondaNoturna" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 10, Text = "Goblin Thieves defeated" },
			},
			Rewards = { XP = 1000, Gold = 150, StatusPoints = 1 },
		},
		{
			Id = "InformanteCeleste",
			Name = "The Informant",
			Description = "They say Madam Celeste knows where the devils are coming from. Go talk to her.",
			Main = true,
			Path = "None",
			MinLevel = 10,
			Requires = { "Tutorial2" },
			Objectives = {
				{ Type = "TalkTo", Target = "Celeste", Amount = 1, Text = "Talk to Madam Celeste" },
			},
			Rewards = { XP = 400, Gold = 50 },
		},
		{
			Id = "CargaRoubada",
			Name = "Stolen Cargo",
			Description = "The Goblin Thieves took Madam Celeste's medicine crates to their hideout. Get the cargo back the hard way.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 11,
			Requires = { "InformanteCeleste" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 15, Text = "Goblin Thieves defeated" },
			},
			Rewards = { XP = 1000, Gold = 150, StatusPoints = 1 },
		},
		{
			Id = "PantanoVenenoso",
			Name = "Poisoned Water",
			Description = "The Goblin Thieves are poisoning the canal water to empty the houses and loot everything. Madam Celeste wants it stopped.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 13,
			Requires = { "CargaRoubada" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 18, Text = "Goblin Thieves defeated" },
			},
			Rewards = { XP = 1300, Gold = 180 },
		},
		{
			Id = "SangueNaPraca",
			Name = "Blood in the Square",
			Description = "Goblin Thieves attacked the market. Madam Celeste lost two suppliers and wants justice.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 16,
			Requires = { "PantanoVenenoso" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 20, Text = "Goblin Thieves defeated" },
			},
			Rewards = { XP = 1800, Gold = 220, StatusPoints = 1 },
		},
		{
			Id = "RumoresCaminhos",
			Name = "Two Paths",
			Description = "Ordinary humans cannot win this war alone. Some make contracts with devils; others agree to share their own body with one. Meet who speaks for each side.",
			Main = true,
			Path = "None",
			MinLevel = 18,
			Requires = { "Tutorial2" },
			Objectives = {
				{ Type = "TalkTo", Target = "Veterano", Amount = 1, Text = "Talk to the Veteran Hunter" },
				{ Type = "TalkTo", Target = "Anciao", Amount = 1, Text = "Talk to the Elder Devil" },
			},
			Rewards = { XP = 1500, Gold = 100 },
		},
		{
			Id = "CidadeEmCinzas",
			Name = "District in Ashes",
			Description = "The old district burned down and the Goblin Thieves are looting the rubble. Clear the area for rebuilding.",
			Giver = "Celeste",
			Path = "None",
			MinLevel = 18,
			Requires = { "SangueNaPraca" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 20, Text = "Goblin Thieves defeated" },
			},
			Rewards = { XP = 2400, Gold = 260 },
		},
		{
			Id = "ProvaVeterano",
			Name = "The Veteran's Eye",
			Description = "The Veteran Hunter introduces no devil to someone who dies easily. Clear out the thieves and take down the Goblin King, the master of them all.",
			Giver = "Veterano",
			Path = "None",
			MinLevel = 20,
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 15, Text = "Goblin Thieves defeated" },
				{ Type = "Kill", Target = "ReiGoblin", Amount = 1, Text = "Goblin King defeated" },
			},
			Rewards = { XP = 2500, Gold = 200, StatusPoints = 1 },
		},
		{
			Id = "SussurroAnciao",
			Name = "Whispers in the Graveyard",
			Description = "The Elder Devil wants to know if your body can handle what he has to offer. Bring Canal Rat and Goblin blood.",
			Giver = "Anciao",
			Path = "None",
			MinLevel = 20,
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Canal Rats defeated" },
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 10, Text = "Goblin Thieves defeated" },
			},
			Rewards = { XP = 2500, Gold = 200, StatusPoints = 1 },
		},
		{
			Id = "Brutamontes",
			Name = "Rats on the Bridge",
			Description = "A pack of Canal Rats climbed onto the main bridge. The guard needs it open by the end of the week.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 21,
			Requires = { "RondaNoturna" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 20, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3000, Gold = 320, StatusPoints = 2 },
		},
		{
			Id = "SombrasDoPorto",
			Name = "Harbor Shadows",
			Description = "The Canal Rats attack the canal boats at night. It is the last job the Sergeant has for an ordinary human.",
			Giver = "Sargento",
			Path = "None",
			MinLevel = 23,
			Requires = { "Brutamontes" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 25, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3600, Gold = 350 },
		},
		{
			-- Id exato usado por PathData.RequiredQuest: completar libera a escolha de caminho
			Id = "Encruzilhada",
			Name = "Crossroads",
			Description = "You have reached the limit of an ordinary human. Talk to the Veteran Hunter to make a contract with a devil, or to the Elder Devil to become a Fiend. The choice is permanent.",
			Main = true,
			Path = "None",
			MinLevel = 25,
			Objectives = {
				{
					Type = "TalkTo",
					TargetList = { "Veterano", "Anciao" },
					Amount = 1,
					Text = "Talk to the Veteran Hunter or the Elder Devil",
				},
			},
			Rewards = { XP = 1000, Gold = 300, StatusPoints = 3 },
		},

		-- ================= Caçador =================
		{
			Id = "NovoCacador",
			Name = "Pact Registry",
			Description = "Every hunter in the city registers their contracts. Find Notary Selma: she keeps the pacts and knows which devils still deal.",
			Main = true,
			Path = "Hunter",
			Objectives = {
				{ Type = "TalkTo", Target = "Tabelia", Amount = 1, Text = "Talk to Notary Selma" },
			},
			Rewards = { XP = 500, Gold = 100 },
		},
		{
			Id = "CacadorJuramento",
			Name = "The Hunter's Oath",
			Description = "A contract is worthless if you are afraid to use it. Use your devil's power (V/B) in combat and clear the canal.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 25,
			Objectives = {
				{ Type = "UsePower", Amount = 5, Text = "Powers used" },
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3000, Gold = 300 },
		},
		{
			Id = "PrecoDoPacto",
			Name = "The Price of the Pact",
			Description = "Every use of a contract burns a piece of your lifespan. The Notary wants you to feel that price before you think about a second pact.",
			Giver = "Tabelia",
			Path = "Hunter",
			MinLevel = 26,
			Requires = { "NovoCacador" },
			Objectives = {
				{ Type = "UsePower", Amount = 15, Text = "Powers used" },
				{ Type = "Kill", Target = "Ratazana", Amount = 20, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3500, Gold = 350 },
		},
		{
			-- 2º contrato: só um dos dois pactos (ExclusiveWith)
			Id = "PactoFuturo",
			Name = "Pact with the Future",
			Description = "The Future Devil wants to live in your eye and watch your future up close. In return, you see attacks before they happen. "
				.. sacrificeText("Futuro")
				.. " You can only sign one of these two pacts.",
			Giver = "Tabelia",
			Path = "Hunter",
			MinLevel = 30,
			Requires = { "PrecoDoPacto" },
			ExclusiveWith = { "PactoMaldicao" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 20, Text = "Mannequins defeated" },
				{ Type = "UsePower", Amount = 10, Text = "Powers used" },
				{ Type = "TalkTo", Target = "Tabelia", Amount = 1, Text = "Return to Notary Selma to sign" },
			},
			Rewards = { XP = 4000, Gold = 300, Contract = "Futuro" },
		},
		{
			Id = "PactoMaldicao",
			Name = "Pact with the Curse",
			Description = "The Curse Devil lends its nails to whoever pays in life, and charges up front in devil blood. "
				.. sacrificeText("Maldicao")
				.. " You can only sign one of these two pacts.",
			Giver = "Tabelia",
			Path = "Hunter",
			MinLevel = 30,
			Requires = { "PrecoDoPacto" },
			ExclusiveWith = { "PactoFuturo" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 30, Text = "Mannequins defeated" },
				{ Type = "TalkTo", Target = "Tabelia", Amount = 1, Text = "Return to Notary Selma to sign" },
			},
			Rewards = { XP = 4000, Gold = 300, Contract = "Maldicao" },
		},
		{
			Id = "CacaInfernal",
			Name = "Fiend Hunt",
			Description = "Fiends walk the city wearing the corpses of people who died here. The Veteran pays for every one you take down. Repeatable.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 26,
			Requires = { "CacadorJuramento" },
			Repeatable = true,
			Objectives = {
				{ Type = "KillPlayer", Target = "Fiends", Amount = 3, Text = "Different Fiends defeated" },
			},
			Rewards = { XP = 4000, Gold = 500 },
		},
		{
			Id = "RastroCarnica",
			Name = "Trail to the Graveyard",
			Description = "Scout Caio followed the Canal Rats to the graveyard. They eat the dead, and where there are dead there are Fiends nearby.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 27,
			Requires = { "CacadorJuramento" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 25, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3800, Gold = 380, StatusPoints = 1 },
		},
		{
			Id = "BordaDoAbismo",
			Name = "Empty Windows",
			Description = "In the Market's abandoned shops the Mannequins move when nobody is looking. The Scout needs someone to hold the street while he maps the building.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 32,
			Requires = { "RastroCarnica" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 25, Text = "Mannequins defeated" },
			},
			Rewards = { XP = 5000, Gold = 450 },
		},
		{
			Id = "PatrulhaCacador",
			Name = "Hunter Patrol",
			Description = "The Scout's standing job: 20 devils of level 30 or higher per patrol. Repeatable.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 30,
			Requires = { "RastroCarnica" },
			Repeatable = true,
			Objectives = {
				{ Type = "Kill", MinEnemyLevel = 30, Amount = 20, Text = "Level 30+ devils (any kind)" },
			},
			Rewards = { XP = 3500, Gold = 400 },
		},
		{
			Id = "CabecaAPremio",
			Name = "Bounties",
			Description = "The oldest Fiends are organizing attacks on hunters. The Veteran wants to send a clear message.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 32,
			Requires = { "CacaInfernal" },
			Objectives = {
				{ Type = "KillPlayer", Target = "Fiends", Amount = 5, Text = "Different Fiends defeated" },
			},
			Rewards = { XP = 8000, Gold = 1000, StatusPoints = 2 },
		},
		{
			Id = "CarneCorrompida",
			Name = "Glass Eyes",
			Description = "The Mannequins are stepping out of the windows and taking over the Market streets. The Scout wants to know how many there are; the right answer is none.",
			Giver = "Batedor",
			Path = "Hunter",
			MinLevel = 36,
			Requires = { "BordaDoAbismo" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 30, Text = "Mannequins defeated" },
			},
			Rewards = { XP = 6500, Gold = 550, StatusPoints = 2 },
		},
		{
			Id = "NinhoCacador",
			Name = "The Last Train",
			Description = "The Scout found the station the Subway Passengers come from. They show up behind people waiting for the train: take them down.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 40,
			Requires = { "CarneCorrompida" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 20, Text = "Passengers defeated" },
			},
			Rewards = { XP = 9000, Gold = 800 },
		},
		{
			Id = "CoroaCacador",
			Name = "Ghost Line",
			Description = "The Passengers have taken the whole line. No hunter has come back from the last car with both arms. Use everything your contracts offer.",
			Giver = "Veterano",
			Path = "Hunter",
			MinLevel = 45,
			Requires = { "NinhoCacador" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 30, Text = "Passengers defeated" },
				{ Type = "UsePower", Amount = 15, Text = "Powers used" },
			},
			Rewards = { XP = 12000, Gold = 1500, StatusPoints = 3 },
		},

		-- ================= Infernal =================
		{
			Id = "NovoInfernal",
			Name = "Borrowed Body",
			Description = "Your body is now a devil's home. The Elder sent you to find Gravedigger Jonas: he knows where the fresh bodies are, and who is hunting people like you.",
			Main = true,
			Path = "Fiend",
			Objectives = {
				{ Type = "TalkTo", Target = "Coveiro", Amount = 1, Text = "Talk to Gravedigger Jonas" },
			},
			Rewards = { XP = 500, Gold = 100 },
		},
		{
			Id = "DominarCorpo",
			Name = "Mastering the Corpse",
			Description = "A new corpse is slow to obey. Use your powers (V/B) until the body moves as if it had always been yours.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 25,
			Objectives = {
				{ Type = "UsePower", Amount = 5, Text = "Powers used" },
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3000, Gold = 300 },
		},
		{
			Id = "CovasRasas",
			Name = "Shallow Graves",
			Description = "The Canal Rats are eating the graveyard's dead before any Fiend can use them. The Gravedigger wants the graves at peace.",
			Giver = "Coveiro",
			Path = "Fiend",
			MinLevel = 26,
			Requires = { "NovoInfernal" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 15, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3500, Gold = 350 },
		},
		{
			Id = "FomeDeSangue",
			Name = "Bloodthirst",
			Description = "The Wandering Fiend has been changing corpses for decades. She teaches that a Fiend's power costs their own blood, and that you must learn to pay without falling.",
			Giver = "Errante",
			Path = "Fiend",
			MinLevel = 27,
			Requires = { "DominarCorpo" },
			Objectives = {
				{ Type = "UsePower", Amount = 15, Text = "Powers used" },
				{ Type = "Kill", Target = "Ratazana", Amount = 20, Text = "Canal Rats defeated" },
			},
			Rewards = { XP = 3800, Gold = 380, StatusPoints = 1 },
		},
		{
			Id = "CacaCacadores",
			Name = "Hunting the Hunters",
			Description = "Hunters sell pieces of their own lives to kill people like us. The Elder wants them to learn the price. Only Hunters count: leave ordinary humans alone. Repeatable.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 26,
			Requires = { "DominarCorpo" },
			Repeatable = true,
			Objectives = {
				{ Type = "KillPlayer", Target = "Humans", VictimPath = "Hunter", Amount = 3, Text = "Different Hunters defeated" },
			},
			Rewards = { XP = 4000, Gold = 500 },
		},
		{
			Id = "AbismoChama",
			Name = "Who Rules the Street",
			Description = "The Market Mannequins refuse to share the city with Fiends. The Gravedigger wants you to show who rules the surface.",
			Giver = "Coveiro",
			Path = "Fiend",
			MinLevel = 30,
			Requires = { "CovasRasas" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 25, Text = "Mannequins defeated" },
			},
			Rewards = { XP = 5000, Gold = 450 },
		},
		{
			Id = "PatrulhaInfernal",
			Name = "Night Hunt",
			Description = "The Wanderer hunts every night to keep her body strong: 20 devils of level 30 or higher. Repeatable.",
			Giver = "Errante",
			Path = "Fiend",
			MinLevel = 30,
			Requires = { "FomeDeSangue" },
			Repeatable = true,
			Objectives = {
				{ Type = "Kill", MinEnemyLevel = 30, Amount = 20, Text = "Level 30+ devils (any kind)" },
			},
			Rewards = { XP = 3500, Gold = 400 },
		},
		{
			Id = "TrofeusCacador",
			Name = "Hunter Trophies",
			Description = "The Elder collects the broken contracts of fallen hunters. Bring more for the collection.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 32,
			Requires = { "CacaCacadores" },
			Objectives = {
				{ Type = "KillPlayer", Target = "Humans", VictimPath = "Hunter", Amount = 5, Text = "Different Hunters defeated" },
			},
			Rewards = { XP = 8000, Gold = 1000, StatusPoints = 2 },
		},
		{
			Id = "PeleCorrompida",
			Name = "Plastic Skin",
			Description = "The Mannequins tear the skin off corpses to dress themselves. The Wanderer wants the area clear before her next body spoils.",
			Giver = "Errante",
			Path = "Fiend",
			MinLevel = 36,
			Requires = { "AbismoChama" },
			Objectives = {
				{ Type = "Kill", Target = "Manequim", Amount = 30, Text = "Mannequins defeated" },
			},
			Rewards = { XP = 6500, Gold = 550, StatusPoints = 2 },
		},
		{
			Id = "TronoDoNinho",
			Name = "The Station",
			Description = "Whoever rules the subway rules the city's lesser devils. The Elder wants the station free of Passengers.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 40,
			Requires = { "PeleCorrompida" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 20, Text = "Passengers defeated" },
			},
			Rewards = { XP = 9000, Gold = 800 },
		},
		{
			Id = "CoroaDeOssos",
			Name = "Last Car",
			Description = "The Elder wants the whole line. Take down the Subway Passengers using everything your blood allows.",
			Giver = "Anciao",
			Path = "Fiend",
			MinLevel = 45,
			Requires = { "TronoDoNinho" },
			Objectives = {
				{ Type = "Kill", Target = "Passageiro", Amount = 30, Text = "Passengers defeated" },
				{ Type = "UsePower", Amount = 15, Text = "Powers used" },
			},
			Rewards = { XP = 12000, Gold = 1500, StatusPoints = 3 },
		},

		-- ================= Estilos de combate (qualquer caminho) =================
		{
			Id = "CaminhoDaLamina",
			Name = "The Way of the Blade",
			Description = "The Master Swordsman only teaches those who have survived the streets. The Goblin Thieves took the dojo's blades: defeat them and come back for your katana.",
			Giver = "Mestre",
			MinLevel = 15,
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 12, Text = "Goblin Thieves defeated" },
				{ Type = "TalkTo", Target = "Mestre", Amount = 1, Text = "Return to the Master Swordsman" },
			},
			Rewards = { XP = 1500, Style = "Katana" },
		},

		-- ================= Esquiva automática: Treinador (qualquer caminho, DodgeData) =================
		-- Cada missão dá um nível de esquiva (Rewards.DodgeLevel). Spar/Duel: botão TREINAR/DUELAR no diálogo dele
		-- (TrainerService: uma cópia do Treinador luta só com quem pediu).
		{
			Id = "EsquivaLeitura",
			Name = "Reading the Blow",
			Description = "Before you can dodge, you have to understand the blow. Go take hits from the city's devils: every blow that comes close teaches you something.",
			Giver = "Treinador",
			MinLevel = 10,
			Objectives = {
				{ Type = "TakeHits", Amount = 30, Text = "Enemy hits taken (or dodged)" },
				{ Type = "TalkTo", Target = "Treinador", Amount = 1, Text = "Return to the Trainer" },
			},
			Rewards = { XP = 600, DodgeLevel = 1 },
		},
		{
			Id = "EsquivaLadroes",
			Name = "Quick Hands",
			Description = "Goblin Thieves strike fast and from the side. Defeat a bunch of them without running from the fight.",
			Giver = "Treinador",
			MinLevel = 10,
			Requires = { "EsquivaLeitura" },
			Objectives = {
				{ Type = "Kill", Target = "GoblinLadrao", Amount = 15, Text = "Goblin Thieves defeated" },
				{ Type = "TalkTo", Target = "Treinador", Amount = 1, Text = "Return to the Trainer" },
			},
			Rewards = { XP = 1200, DodgeLevel = 2 },
		},
		{
			Id = "EsquivaTreino",
			Name = "Training with the Trainer",
			Description = "Now with me. Take my hits without going down: dodging counts too. Press TRAIN when you are ready.",
			Giver = "Treinador",
			MinLevel = 15,
			Requires = { "EsquivaLadroes" },
			Objectives = {
				{ Type = "Spar", Amount = 40, Text = "Training hits endured (or dodged)" },
			},
			Rewards = { XP = 2000, DodgeLevel = 3 },
		},
		{
			Id = "EsquivaRatazanas",
			Name = "Pack in the Sewers",
			Description = "Canal Rats attack in packs, from every side. Come back in one piece after defeating a few.",
			Giver = "Treinador",
			MinLevel = 20,
			Requires = { "EsquivaTreino" },
			Objectives = {
				{ Type = "Kill", Target = "Ratazana", Amount = 10, Text = "Canal Rats defeated" },
				{ Type = "TalkTo", Target = "Treinador", Amount = 1, Text = "Return to the Trainer" },
			},
			Rewards = { XP = 3000, DodgeLevel = 4 },
		},
		{
			Id = "EsquivaDuelo",
			Name = "The Final Test",
			Description = "Enough training. Beat me in a real duel and I will teach you everything I know. Press DUEL when you are ready.",
			Giver = "Treinador",
			MinLevel = 25,
			Requires = { "EsquivaRatazanas" },
			Objectives = {
				{ Type = "Duel", Amount = 1, Text = "Duel against the Trainer won" },
			},
			Rewards = { XP = 5000, DodgeLevel = 5 },
		},
	},
}
