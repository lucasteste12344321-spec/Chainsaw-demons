-- Side content uses the existing quest journal, completion flow and player save.
local Data = {}
Data.ObjectiveTypes = { Collect = true, Explore = true, Fish = true, WorldEvent = true }
Data.NPCs = {
	KuroYui = "Mensageira Yui", KuroMika = "Guarda-florestal Mika", KuroRen = "Carpinteiro Ren",
	KuroHana = "Zeladora Hana", KuroSora = "Montanhista Sora", KuroNori = "Cozinheira Nori",
	KuroIori = "Pesquisador Iori", KuroDaichi = "Pescador Daichi",
}
Data.Greetings = {
	KuroYui = { Available = "As estradas voltaram a abrir. Preciso saber quem ainda está lá fora.", Active = "Encontrou nossos moradores?", Idle = "Chegou uma carta? Eu levo." },
	KuroMika = { Available = "A floresta parece calma. É isso que me preocupa. Pode conferir alguns lugares?", Active = "Siga as trilhas e volte inteiro.", Idle = "Os pedidos urgentes aparecem no quadro da região." },
	KuroRen = { Available = "Sem minhas ferramentas, essa serraria não volta a funcionar.", Active = "Procure as caixas marcadas perto da margem.", Idle = "Madeira boa e gente disposta. É disso que precisamos." },
	KuroHana = { Available = "As lanternas se apagam toda vez que a névoa chega. Traga o que falta para acendê-las.", Active = "As oferendas estão espalhadas pelo bosque.", Idle = "Não responda se ouvir seu nome entre as árvores." },
	KuroSora = { Available = "Achei uma entrada na montanha. Preciso de alguém que saiba observar.", Active = "A gruta fica acima da última casa.", Idle = "Nas alturas dá para ouvir a cidade respirar." },
	KuroNori = { Available = "O abrigo está frio e a panela, vazia. Toda ajuda serve.", Active = "A fogueira marca o caminho de volta.", Idle = "Uma refeição quente também salva vidas." },
	KuroIori = { Available = "A água passa pelos mesmos lugares que os demônios. Quero entender por quê.", Active = "As amostras precisam vir de três pontos diferentes.", Idle = "Há muita coisa estranha vivendo nesse rio." },
	KuroDaichi = { Available = "Demônio não é a única coisa que morde por aqui. Quer aprender a pescar? Use R comigo para pegar sua vara.", Active = "Fisgue quando a boia afundar. Recolha sem deixar a linha estourar.", Idle = "Use R comigo para ver seus peixes, vender ou melhorar a vara." },
}
local function objective(kind, target, amount, text)
	return { Type = kind, Target = target, Amount = amount, Text = text }
end
local function back(npc)
	return objective("TalkTo", npc, 1, "Voltar a " .. Data.NPCs[npc])
end
Data.Quests = {
	{ Id = "Side_OpenRoads", Name = "Gente além dos muros", Giver = "KuroYui", MinLevel = 1,
		Description = "Visite Mika no alojamento da floresta e Ren na serraria. Depois leve notícias para Yui, na entrada da floresta.",
		Objectives = { objective("Explore", "RangersLodge", 1, "Encontrar Mika no alojamento"), objective("Explore", "RiversideSawmill", 1, "Encontrar Ren na serraria"), back("KuroYui") }, Rewards = { XP = 180, Gold = 65 } },
	{ Id = "Side_ForestSurvey", Name = "A ronda de Mika", Giver = "KuroMika", MinLevel = 1,
		Description = "Suba à torre de observação e visite o acampamento antigo. Os marcos nas trilhas indicam os locais.",
		Objectives = { objective("Explore", "Watchtower", 1, "Subir à torre de observação"), objective("Explore", "ForestCamp", 1, "Visitar o acampamento"), back("KuroMika") }, Rewards = { XP = 280, Gold = 90 } },
	{ Id = "Side_LostTools", Name = "Ferramentas na correnteza", Giver = "KuroRen", MinLevel = 3,
		Description = "Recupere três caixas de ferramentas diferentes entre a serraria e o píer.",
		Objectives = { objective("Collect", "ToolCase", 3, "Caixas de ferramentas recuperadas"), back("KuroRen") }, Rewards = { XP = 300, Gold = 110 } },
	{ Id = "Side_ShrineOfferings", Name = "Antes que escureça", Giver = "KuroHana", MinLevel = 3,
		Description = "Reúna três pacotes de oferendas no bosque do santuário e devolva-os a Hana.",
		Objectives = { objective("Collect", "Offering", 3, "Oferendas encontradas"), back("KuroHana") }, Rewards = { XP = 320, Gold = 100 } },
	{ Id = "Side_MountainEcho", Name = "O eco da montanha", Giver = "KuroSora", MinLevel = 5,
		Description = "Investigue o interior da gruta e recolha duas amostras minerais. Volte à casa de Sora na vila.",
		Objectives = { objective("Explore", "MountainGrotto", 1, "Investigar a gruta"), objective("Collect", "OreSample", 2, "Amostras minerais"), back("KuroSora") }, Rewards = { XP = 460, Gold = 140 } },
	{ Id = "Side_WarmShelter", Name = "Um lugar para aquecer", Giver = "KuroNori", MinLevel = 3,
		Description = "Busque três feixes de lenha perto do lago congelado para abastecer o abrigo.",
		Objectives = { objective("Collect", "Firewood", 3, "Feixes de lenha"), back("KuroNori") }, Rewards = { XP = 330, Gold = 100 } },
	{ Id = "Side_RiverSamples", Name = "O que o rio esconde", Giver = "KuroIori", MinLevel = 4,
		Description = "Use os três pontos de coleta sinalizados no rio Kuro: nascente, píer e curva da serraria.",
		Objectives = { objective("Collect", "WaterSample", 3, "Pontos do rio analisados"), back("KuroIori") }, Rewards = { XP = 350, Gold = 120 } },
	{ Id = "Side_FirstCatch", Name = "Nem tudo se resolve no soco", Giver = "KuroDaichi", MinLevel = 1,
		Description = "Pegue a vara gratuita com Daichi (R), use E em um ponto de pesca e capture três peixes. Eles ficam na sua cesta de pesca.",
		Objectives = { objective("Fish", nil, 3, "Peixes capturados"), back("KuroDaichi") }, Rewards = { XP = 240, Gold = 80 } },
	{ Id = "Side_HotSupper", Name = "Jantar no fim do mundo", Giver = "KuroNori", MinLevel = 5, Requires = { "Side_WarmShelter" },
		Description = "Capture duas carpas e uma truta para aprender a receita de Nori. Os peixes capturados continuam na cesta.",
		Objectives = { objective("Fish", "RiverCarp", 2, "Carpas capturadas"), objective("Fish", "Trout", 1, "Truta capturada"), back("KuroNori") }, Rewards = { XP = 420, Gold = 140 } },
	{ Id = "Side_ScarletKoi", Name = "Uma mancha vermelha na água", Giver = "KuroDaichi", MinLevel = 5, Requires = { "Side_FirstCatch" },
		Description = "Daichi viu uma koi escarlate. Tente os cardumes ativos; varas melhores também ajudam.",
		Objectives = { objective("Fish", "Koi", 1, "Koi escarlate capturada"), back("KuroDaichi") }, Rewards = { XP = 500, Gold = 180 } },
	{ Id = "Side_RiverCleanup", Name = "O rio não é lixeira", Giver = "KuroDaichi", MinLevel = 1, Repeatable = true,
		Description = "Recolha quatro sacos de resíduos nas margens. Cada ponto pode ser usado uma vez por missão e demora para repor.",
		Objectives = { objective("Collect", "Litter", 4, "Resíduos recolhidos"), back("KuroDaichi") }, Rewards = { XP = 160, Gold = 55 } },
	{ Id = "Side_RegionalHelp", Name = "Quando a região chama", Giver = "KuroMika", MinLevel = 3, Repeatable = true,
		Description = "Participe de um pedido regional ativo. Faça ao menos duas entregas ou reparos e ajude o grupo a concluir antes do tempo acabar.",
		Objectives = { objective("WorldEvent", nil, 1, "Pedido regional concluído com participação"), back("KuroMika") }, Rewards = { XP = 260, Gold = 90 } },
}
Data.Events = {
	{ Id = "ShrineLights", Name = "Luzes contra a névoa", Region = "Santuário", Action = "Acender lanterna", Goal = 8, XP = 100, Gold = 35, Description = "Acenda as lanternas marcadas do santuário." },
	{ Id = "SawmillSupplies", Name = "A serraria precisa de ajuda", Region = "Serraria", Action = "Entregar madeira", Goal = 8, XP = 110, Gold = 40, Carry = true, Description = "Pegue madeira nas pilhas e entregue no depósito da serraria." },
	{ Id = "SnowSupplies", Name = "Abrigo antes da nevasca", Region = "Neve", Action = "Abastecer abrigo", Goal = 8, XP = 120, Gold = 45, Carry = true, Description = "Leve provisões do acampamento até o abrigo de Nori." },
}
Data.EventPeriod = 480
Data.EventDuration = 360

function Data.Reconcile(saved)
	local claims = {}
	if type(saved) == "table" and type(saved.EventClaims) == "table" then
		for _, event in Data.Events do
			local value = saved.EventClaims[event.Id]
			if type(value) == "number" and value == value and value >= 0 and value < 1e10 then claims[event.Id] = math.floor(value) end
		end
	end
	return { EventClaims = claims }
end

function Data.Register(target)
	local ids = {}
	for _, quest in target.Quests do ids[quest.Id] = true end
	for id, name in Data.NPCs do target.NPCs[id] = name; target.Greetings[id] = Data.Greetings[id] end
	for _, quest in Data.Quests do if not ids[quest.Id] then table.insert(target.Quests, quest); ids[quest.Id] = true end end
end

return Data
