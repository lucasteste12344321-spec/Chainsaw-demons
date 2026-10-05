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
	Inicio = "FIRST STEPS",
	Combate = "COMBAT",
	Caca = "THE HUNT",
	Forca = "GETTING STRONGER",
	Fim = "NEXT STEPS",
}

TutorialData.Steps = {
	-- ================= Primeiros passos =================
	{
		Id = "Welcome",
		Chapter = "Inicio",
		Title = "Welcome, hunter",
		Text = "The city is infested with devils. This quick guide shows the basics: moving, fighting, quests and how to "
			.. "get stronger. It takes about 5 minutes and there is a reward at the end.",
		Button = "START",
	},
	{
		Id = "Move",
		Chapter = "Inicio",
		Title = "Moving",
		Text = "Move with {W} {A} {S} {D}.",
		TouchText = "Drag the stick on the left side of the screen to move.",
		Check = "Move",
		Goal = 30,
		Unit = "m",
	},
	{
		Id = "Camera",
		Chapter = "Inicio",
		Title = "Camera",
		Text = "Hold the {right mouse button} and drag to turn the camera. The scroll wheel zooms in and out.",
		TouchText = "Drag your finger across the middle of the screen to turn the camera. Pinch to zoom.",
		Check = "Camera",
		Goal = 180,
		Unit = "°",
	},
	{
		Id = "Jump",
		Chapter = "Inicio",
		Title = "Jumping",
		Text = "Jump with {Space}.",
		TouchText = "Tap the jump button at the bottom right.",
		Check = "Jump",
		Goal = 2,
	},
	{
		Id = "Dash",
		Chapter = "Inicio",
		Title = "Dash",
		Text = "Press {Q} while moving to dash. It uses stamina (the white bar) and recharges in 1 s: great for "
			.. "escaping an attack.",
		TouchText = "Tap the Q button at the bottom to dash. It uses stamina (the white bar).",
		Check = "Dash",
		Goal = 2,
		Anchor = "Slot_Q",
	},
	{
		Id = "Run",
		Chapter = "Inicio",
		Title = "Auto run",
		Text = "You run automatically while moving. Hold {Ctrl} to walk slowly. You can turn it off in the settings (≡).",
		TouchText = "You run automatically while moving. You can turn it off in the settings (≡).",
		Anchor = "SettingsButton",
	},

	-- ================= Combate =================
	{
		Id = "Punch",
		Chapter = "Combate",
		Title = "First punch",
		Text = "A training dummy appeared in front of you. With your Fists equipped (key {1}), {click} it to punch.",
		TouchText = "A training dummy appeared in front of you. With your Fists equipped (button 1), tap the attack button to punch.",
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
		Text = "Now land {5 punches in a row} without stopping. The 5th hit of the combo knocks the enemy away.",
		Check = "DummyCombo",
		Goal = 5,
		Target = "Dummy",
		Dummy = true,
	},
	{
		Id = "Block",
		Chapter = "Combate",
		Title = "Guard",
		Text = "Hold {F} to raise your guard. Right at the start of it, an enemy hit becomes a {parry} and the attacker is "
			.. "stunned. If your guard runs out, it breaks.",
		TouchText = "Hold the F button to raise your guard. Right at the start of it, an enemy hit becomes a parry.",
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
		Title = "Techniques",
		Text = "{Z} {X} {C} are the techniques of the style you are holding. They start locked: fighting earns mastery "
			.. "and you unlock each one in the skill tree.",
		Anchor = "Skills",
	},

	-- ================= Caçada =================
	{
		Id = "Travel",
		Chapter = "Caca",
		Title = "Goblin Street",
		Text = "Goblins, the weakest devils, are on the other side of the city. Follow the {red arrow}. The minimap "
			.. "also shows the way.",
		Check = "ReachGoblins",
		Target = "GoblinZone",
		Anchor = "Minimap",
	},
	{
		Id = "Kill",
		Chapter = "Caca",
		Title = "First blood",
		Text = "Defeat a Goblin. It fights back: when it raises its knife, raise your guard ({F}) or get away with a "
			.. "dash ({Q}).",
		TouchText = "Defeat a Goblin. When it raises its knife, hold F to guard or use the dash (Q).",
		Check = "Kill",
		Goal = 1,
		Target = "Goblin",
	},
	{
		Id = "Vitals",
		Chapter = "Caca",
		Title = "Health and XP",
		Text = "Every devil you defeat gives XP and Gold. The ring fills up to the next level. The red bar is your health "
			.. "and the white one is your dash stamina.",
		Anchor = "Vitals",
	},
	{
		Id = "Quests",
		Chapter = "Caca",
		Title = "Quests",
		Text = "Your quests are listed here. Main quests start on their own and give a lot of XP. {N} shows or hides the list.",
		TouchText = "Your quests are listed here. Main quests start on their own and give a lot of XP. Tap the title to "
			.. "show or hide the list.",
		Anchor = "QuestTracker",
	},
	{
		Id = "Level",
		Chapter = "Caca",
		Title = "Leveling up",
		Text = "Keep hunting Goblins until you reach {level 2}.",
		Check = "Level",
		Goal = 2,
		Target = "Goblin",
		Anchor = "Vitals",
	},

	-- ================= Ficando mais forte =================
	{
		Id = "OpenTree",
		Chapter = "Forca",
		Title = "Skill tree",
		Text = "Every level gives 1 skill point. Open the tree with {M} or with this button.",
		TouchText = "Every level gives 1 skill point. Tap this button to open the tree.",
		Check = "TreeOpen",
		Anchor = "TreeButton",
	},
	{
		Id = "Unlock",
		Chapter = "Forca",
		Title = "Spending the point",
		Text = "Click a node connected to the center, like {Vigor I} (more health) or {Iron Fist I} (more strength), and unlock it.",
		TouchText = "Tap a node connected to the center, like Vigor I (more health) or Iron Fist I (more strength), and unlock it.",
		Check = "Unlock",
	},
	{
		Id = "CloseTree",
		Chapter = "Forca",
		Title = "Done!",
		Text = "The bonus is already active. Close the tree ({M} or the ×).",
		TouchText = "The bonus is already active. Close the tree with the ×.",
		Check = "TreeClosed",
	},
	{
		Id = "Inventory",
		Chapter = "Forca",
		Title = "Inventory",
		Text = "Bosses drop items. Open the inventory with {G} to wear them and get their bonuses.",
		TouchText = "Bosses drop items. Tap this button to open the inventory and wear your items.",
		Check = "InventoryOpen",
		Anchor = "InventoryButton",
	},
	{
		Id = "Talk",
		Chapter = "Forca",
		Title = "Master Swordsman",
		Text = "Talk to the Master Swordsman (get close and press {E}). NPCs give quests, and he teaches the {Katana} "
			.. "from level 15.",
		TouchText = "Talk to the Master Swordsman (get close and tap Talk). He teaches the Katana from level 15.",
		Check = "Dialog",
		Target = "NPC:Mestre",
	},

	-- ================= Próximos passos =================
	{
		Id = "Finish",
		Chapter = "Fim",
		Title = "All set!",
		Text = "Your next goals:\n• {Level 3}: Sergeant Otávio calls you to join the guard.\n• {Level 15}: the Katana from the "
			.. "Master Swordsman.\n• {Level 25}: choose your path, Hunter (contracts with devils) or Fiend.\n\n"
			.. "Reward: $REWARD.", -- $REWARD vem de TutorialData.Reward (o cliente escreve)
		Button = "FINISH",
		Final = true,
	},
}

TutorialData.Count = #TutorialData.Steps

return TutorialData
