-- Tutorial guiado (Tutorial.client.luau mostra e confere; TutorialService.server.luau salva o passo e dá a recompensa).
-- Começa quando o jogador aperta JOGAR pela primeira vez (atributo TutorialDone = false) e pode ser refeito nas
-- configurações da HUD. Cada passo:
--   Id      quem confere é o cliente (Tutorial.client.luau, tabela Checks), pelo estado do jogo: posição, atributos,
--           vida dos inimigos, telas abertas... Passo sem Check é de leitura (botão CONTINUAR).
--   Goal    número a alcançar (studs andados, graus de câmera, golpes, segundos de guarda...); a barra mostra o avanço
--   Unit    o que aparece depois do número na barra ("m", "°", "s"); sem Unit, mostra "2/5"
--   Anchor  elemento da interface que pisca (atributo TutorialAnchor nos GuiObjects da HUD, missões e minimapa)
--   Target  alvo no mapa com seta e marcador: "Dummy", "GoblinZone", "Goblin" ou "NPC:<NPCId>"
--   Dummy   o boneco de treino fica na frente do jogador durante o passo (o servidor cria e apaga)
-- Texto: {Tecla} vira uma tecla destacada. TouchText (opcional) é o texto para celular/tablet.
local TutorialData = {}

TutorialData.Reward = { Gold = 100, Spins = 1 } -- só na primeira vez que o jogador conclui (pular não dá)
TutorialData.MinLevelForReward = 2 -- o servidor confere: quem concluiu de verdade passou do level 1 caçando
TutorialData.SkipForLevel = 5 -- perfil de antes do tutorial com este level ou mais já conta como concluído
TutorialData.CompleteSound = 138029541636833 -- "to_checkpoint" (Audioscape)

TutorialData.Chapters = {
	Inicio = "PRIMEIROS PASSOS",
	Combate = "COMBATE",
	Caca = "CAÇADA",
	Forca = "FICANDO MAIS FORTE",
	Fim = "PRÓXIMOS PASSOS",
}

TutorialData.Steps = {
	-- ================= Primeiros passos =================
	{
		Id = "Welcome",
		Chapter = "Inicio",
		Title = "Bem-vindo, caçador",
		Text = "A cidade está infestada de demônios. Este guia rápido mostra o básico: andar, lutar, missões e como ficar "
			.. "mais forte. Leva uns 5 minutos e no fim tem recompensa.",
		Button = "COMEÇAR",
	},
	{
		Id = "Move",
		Chapter = "Inicio",
		Title = "Andando",
		Text = "Ande com {W} {A} {S} {D}.",
		TouchText = "Arraste o controle no canto esquerdo da tela para andar.",
		Check = "Move",
		Goal = 30,
		Unit = "m",
	},
	{
		Id = "Camera",
		Chapter = "Inicio",
		Title = "Câmera",
		Text = "Segure o {botão direito} do mouse e arraste para girar a câmera. A rodinha aproxima e afasta.",
		TouchText = "Arraste o dedo no meio da tela para girar a câmera. Faça pinça para aproximar.",
		Check = "Camera",
		Goal = 180,
		Unit = "°",
	},
	{
		Id = "Jump",
		Chapter = "Inicio",
		Title = "Pulo",
		Text = "Pule com {Espaço}.",
		TouchText = "Toque no botão de pulo, embaixo à direita.",
		Check = "Jump",
		Goal = 2,
	},
	{
		Id = "Dash",
		Chapter = "Inicio",
		Title = "Dash",
		Text = "Aperte {Q} enquanto anda para dar um dash. Ele gasta fôlego (a barra branca) e recarrega em 1 s: ótimo "
			.. "para fugir de um golpe.",
		TouchText = "Toque no botão Q, embaixo, para dar um dash. Ele gasta fôlego (a barra branca).",
		Check = "Dash",
		Goal = 2,
		Anchor = "Slot_Q",
	},
	{
		Id = "Run",
		Chapter = "Inicio",
		Title = "Corrida automática",
		Text = "Ao andar você já corre sozinho. Segure {Ctrl} para andar devagar. Dá para desligar nas configurações (≡).",
		TouchText = "Ao andar você já corre sozinho. Dá para desligar nas configurações (≡).",
		Anchor = "SettingsButton",
	},

	-- ================= Combate =================
	{
		Id = "Punch",
		Chapter = "Combate",
		Title = "Primeiro soco",
		Text = "Um boneco de treino apareceu na sua frente. Com os Punhos na mão (tecla {1}), {clique} nele para socar.",
		TouchText = "Um boneco de treino apareceu na sua frente. Com os Punhos na mão (botão 1), toque na tela para socar.",
		Check = "DummyHits",
		Goal = 3,
		Target = "Dummy",
		Dummy = true,
		Anchor = "Hotbar",
	},
	{
		Id = "Combo",
		Chapter = "Combate",
		Title = "Combo",
		Text = "Agora acerte {5 socos seguidos} sem parar. O 5º golpe do combo arremessa o inimigo.",
		Check = "DummyCombo",
		Goal = 5,
		Target = "Dummy",
		Dummy = true,
	},
	{
		Id = "Block",
		Chapter = "Combate",
		Title = "Guarda",
		Text = "Segure {F} para levantar a guarda. Bem no começo dela, o golpe inimigo vira {parry} e quem bateu fica "
			.. "atordoado. Se a guarda esvaziar, ela quebra.",
		TouchText = "Segure o botão F para levantar a guarda. Bem no começo dela, o golpe inimigo vira parry.",
		Check = "Block",
		Goal = 2,
		Unit = "s",
		Target = "Dummy",
		Dummy = true,
		Anchor = "Slot_F",
	},
	{
		Id = "Skills",
		Chapter = "Combate",
		Title = "Técnicas",
		Text = "{Z} {X} {C} são as técnicas do estilo na mão. Elas começam travadas: lutando você ganha maestria e "
			.. "libera cada uma na árvore de habilidades.",
		Anchor = "Skills",
	},

	-- ================= Caçada =================
	{
		Id = "Travel",
		Chapter = "Caca",
		Title = "Rua dos Goblins",
		Text = "Os Goblins, os demônios mais fracos, estão do outro lado da cidade. Siga a {seta vermelha}. O minimapa "
			.. "também mostra o caminho.",
		Check = "ReachGoblins",
		Target = "GoblinZone",
		Anchor = "Minimap",
	},
	{
		Id = "Kill",
		Chapter = "Caca",
		Title = "Primeiro sangue",
		Text = "Derrote um Goblin. Ele bate de volta: quando ele erguer a faca, levante a guarda ({F}) ou saia com o "
			.. "dash ({Q}).",
		TouchText = "Derrote um Goblin. Quando ele erguer a faca, segure F para a guarda ou use o dash (Q).",
		Check = "Kill",
		Goal = 1,
		Target = "Goblin",
	},
	{
		Id = "Vitals",
		Chapter = "Caca",
		Title = "Vida e XP",
		Text = "Cada demônio derrotado dá XP e Gold. O anel enche até o próximo level. A barra vermelha é sua vida e a "
			.. "branca o fôlego do dash.",
		Anchor = "Vitals",
	},
	{
		Id = "Quests",
		Chapter = "Caca",
		Title = "Missões",
		Text = "Suas missões ficam aqui. As principais começam sozinhas e dão bastante XP. {N} mostra ou esconde a lista.",
		TouchText = "Suas missões ficam aqui. As principais começam sozinhas e dão bastante XP. Toque no título para "
			.. "mostrar ou esconder a lista.",
		Anchor = "QuestTracker",
	},
	{
		Id = "Level",
		Chapter = "Caca",
		Title = "Subindo de level",
		Text = "Continue caçando Goblins até chegar ao {level 2}.",
		Check = "Level",
		Goal = 2,
		Target = "Goblin",
		Anchor = "Vitals",
	},

	-- ================= Ficando mais forte =================
	{
		Id = "OpenTree",
		Chapter = "Forca",
		Title = "Árvore de habilidades",
		Text = "Cada level dá 1 ponto de habilidade. Abra a árvore com {M} ou com este botão.",
		TouchText = "Cada level dá 1 ponto de habilidade. Toque neste botão para abrir a árvore.",
		Check = "TreeOpen",
		Anchor = "TreeButton",
	},
	{
		Id = "Unlock",
		Chapter = "Forca",
		Title = "Gastando o ponto",
		Text = "Clique num nó ligado ao centro, como {Vigor I} (mais vida) ou {Punho firme I} (mais força), e desbloqueie.",
		TouchText = "Toque num nó ligado ao centro, como Vigor I (mais vida) ou Punho firme I (mais força), e desbloqueie.",
		Check = "Unlock",
	},
	{
		Id = "CloseTree",
		Chapter = "Forca",
		Title = "Pronto!",
		Text = "O bônus já vale. Feche a árvore ({M} ou o ×).",
		TouchText = "O bônus já vale. Feche a árvore no ×.",
		Check = "TreeClosed",
	},
	{
		Id = "Inventory",
		Chapter = "Forca",
		Title = "Inventário",
		Text = "Os chefes deixam itens. Abra o inventário com {G} para vestir e ganhar os bônus deles.",
		TouchText = "Os chefes deixam itens. Toque neste botão para abrir o inventário e vestir os itens.",
		Check = "InventoryOpen",
		Anchor = "InventoryButton",
	},
	{
		Id = "Talk",
		Chapter = "Forca",
		Title = "Mestre Espadachim",
		Text = "Fale com o Mestre Espadachim (chegue perto e aperte {E}). Os NPCs dão missões, e ele ensina a {Katana} a "
			.. "partir do level 15.",
		TouchText = "Fale com o Mestre Espadachim (chegue perto e toque em Falar). Ele ensina a Katana a partir do level 15.",
		Check = "Dialog",
		Target = "NPC:Mestre",
	},

	-- ================= Próximos passos =================
	{
		Id = "Finish",
		Chapter = "Fim",
		Title = "Tudo pronto!",
		Text = "Seus próximos objetivos:\n• {Level 3}: o Sargento Otávio te chama para a guarda.\n• {Level 15}: a Katana com o "
			.. "Mestre Espadachim.\n• {Level 25}: escolha seu caminho, Caçador (contratos com demônios) ou Infernal.\n\n"
			.. "Recompensa: $REWARD.", -- $REWARD vem de TutorialData.Reward (o cliente escreve)
		Button = "CONCLUIR",
		Final = true,
	},
}

TutorialData.Count = #TutorialData.Steps

return TutorialData
