# Chainsawdemons: rework em andamento (Claude + Codex)

Jogo Roblox em Luau, sincronizado com o Studio pelo Argon (`default.project.json`).
- `src/Shared` → ReplicatedStorage
- `src/Server` → ServerScriptService
- `src/Client` → StarterPlayerScripts

Dois agentes estão editando esta pasta **ao mesmo tempo**. Cada um só mexe nos arquivos que são seus.
Se precisar de algo num arquivo que não é seu, escreva na seção "Pedidos" no fim deste arquivo em vez de editar.

## Divisão de arquivos

### Claude (não editar)
- `src/Shared/Remotes.luau`: a única exceção é que o Codex **pode acrescentar** nomes novos na lista `NAMES`
- `src/Server/Main.server.luau`, `PlayerData.luau` (novo), `QuestModule.luau`, `EnemyModule.luau`,
  `Spawner Script.server.luau`, `SetupCollisionGroups.server.luau`, `GiveTools.server.luau` (entrega os estilos de combate ao renascer)
- `src/Client/HUB_GUI.client.luau`, `QuestGUI.client.luau`
- Fase 2: `src/Shared/StatConfig.luau`, `src/Server/QuestData.luau`, `EnemyData.luau`, `KillRewards.server.luau`
- Já apagados (a parte do Claude está pronta): `PlayerStats.server`, `StatusScript.server`, `StatusSystem`,
  `EXPSystem`, `Client/Main.client`, `Shared/Hello`

### Codex
1. **Combate** (histórico: a Katana foi apagada e o combate agora é do Claude, ver "Combate: estilos"):
   `src/Shared/Tools/Katana/M1.server.luau`, `M1Loocal.client.luau` (pode renomear para `M1Local`)
   - Usar `Remotes.CombatM1` / `Remotes.CombatSkill` (os `M1Remote`/`SkillRemote` dentro da Tool só existem no Studio).
   - **Hitbox no servidor**: não confiar em alvo mandado pelo cliente. Checar distância e ângulo na frente do atacante.
   - Cooldowns das skills **também no servidor** (Skill1 5s, Skill2 8s), além do visual no cliente.
   - Stun: o bug atual é que um segundo hit salva WalkSpeed 0 e o alvo nunca mais anda. Usar o atributo
     `Stunned` (bool) no **Model do personagem/NPC**, com um contador ou timestamp para stuns sobrepostos.
     Em NPC o servidor pode zerar WalkSpeed direto; em jogador quem aplica é o script de movimento (item 2).
   - Ao causar dano, marcar `humanoid:SetAttribute("LastAttacker", attacker.UserId)`. É isso que dá XP/quest
     quando um inimigo morre.
   - Dano pode escalar com `player.Stats.Forca.Value` do atacante. Se o alvo for jogador, reduzir por
     `Stats.Defesa`. Não matar companheiros de time (`player.Team`).
2. **Movimento**: `src/Client/StaminaDashRunscript.client.luau`
   - Este script é o **único** dono de `Humanoid.WalkSpeed` do jogador local. A velocidade base é
     `player.Stats.Velocidade.Value` (ouvir `.Changed`), não 16 fixo.
   - Enquanto `character:GetAttribute("Stunned")` for true: WalkSpeed 0, sem dash nem corrida.
   - Atualizar as referências (humanoid/rootPart/tracks) ao renascer sem deixar conexões velhas.
3. **Admin e notificações**: `src/Server/ChatCommands.server.luau`, `Evenntscript.server.luau`,
   `src/Client/Anunciar.client.luau`, `EventScript.client.luau`, `Commands.client.luau`
   - Uma lista de admins **por UserId** num único lugar (ex.: novo `src/Server/Admins.luau`). Hoje há duas listas, e uma é por Name.
   - `/anunciar` não pode kickar quem não é admin, só ignorar.
   - `/tm` tem que achar o time sem diferenciar maiúsculas (hoje o comando vira minúsculo e nunca acha "Demons").
   - Juntar os 3 scripts de cliente em um só (ex.: `Notifications.client.luau`) que escuta `Remotes.Notify`
     (toast) e `Remotes.Announcement` (banner). Hoje o anúncio aparece duplicado.
4. **Times e Fast Mode**: `src/Client/TeamScript.client.luau`, `src/Server/tScript.server.luau`,
   `FastRcb.server.luau`, `applyFastMode.server.luau`
   - Usar `Remotes.SelectTeam`. O servidor aceita só "Demons" ou "Humans".
   - Trocar o `task.wait(8)` por algo real (`game:IsLoaded()` / `game.Loaded:Wait()`).
   - Fast Mode tem que ser **só no cliente** (mudar Lighting no servidor afeta todos). Apagar `FastRcb` e
     `applyFastMode` e remover o remote `FastModeToggle`.

## Contrato compartilhado (não mudar sem combinar)

### Remotes: `require(ReplicatedStorage.Remotes)`
| Nome | Direção | Argumentos |
|---|---|---|
| StatusUpgrade | C→S | statName |
| StatusReset | C→S | () |
| SaveSetting | C→S | key, value (configuração salva no perfil: `FastMode` e `AutoRun`; volta como atributo `Setting<Nome>`) |
| SkillTreeUnlock | C→S | nodeId (nó da árvore de habilidades; o servidor confere pontos, maestria e ligação) |
| EquipItem | C→S | itemId, equip (veste ou tira um item do inventário; o servidor confere se o jogador tem) |
| SaveAppearance | C→S | appearance (`{ Skin, Face, Hair, HairColor, Shirt, Pants }` do `AppearanceData`; o servidor valida) |
| ClanSpin | C→S | () gira o clã (gasta 1 giro); a resposta vem no ClanResult |
| ClanResult | S→C | clanId, spinsLeft (clanId nil = sem giro) |
| BuySpin | C→S | () compra 1 giro de clã com Gold (`ClanData.SpinGoldCost`) |
| ClanChoose | C→S | clanId (escolha direta do clã nas contas sem sorteio pago; a resposta vem no ClanResult) |
| RedeemCode | C→S | code (códigos em `src/Server/Codes.luau`); a resposta vem no CodeResult |
| CodeResult | S→C | ok, message |
| QuestEvent | C→S / S→C | () / data |
| QuestDialog | S→C | data |
| QuestAction | C→S | action ("Accept" ou "Train": treino/duelo do Treinador), questId, npcId |
| TutorialAction | C→S | action, value ("Step" n, "Finish", "Skip", "Restart", "Dummy" bool; ver "Tutorial") |
| EquipStyle | C→S | styleName, equip (guarda/equipa um estilo de combate pelo inventário; com a fusão do contrato fica travado) |
| ContractAction | C→S | action ("Fuse"), npcId (funde o contrato com o estilo no Mestre dos Pactos; ContractService) |
| Notify | S→C | title, text, duration? |
| Announcement | S→C | title, text, duration? |
| SelectTeam | C→S | teamName |
| CombatM1 | C→S | seq, aerial (começou um M1; true pede o uppercut no 4º golpe) |
| CombatSkill | C→S | slot ("Z" / "X" / "C"), holding (skill de segurar: true ao apertar, false + seq ao soltar) |
| CombatHit | C→S | seq, targets, impactTime, originCFrame (tempo de GetServerTimeNow e origem no marcador; servidor valida histórico, alcance +2, frente, parede e estado) |
| DashRequest | C→S | character, seq, direction, timestamp, originCFrame (direção horizontal unitária; autorização, custo e recarga no servidor) |
| DashState | S→C | snapshot: Character, Revision, Stamina, Max, Regen, Time, ReadyAt, Ack; resposta inclui Seq/Accepted e, se aceito, Start/Direction/Distance |
| CombatBlock | C→S | holding (segurar F) |
| CombatFX | S→C | kind, data (efeitos visuais; quem atacou não recebe o que já previu) |
| CombatImpulse | S→C | velocity, duration (empurrão aplicado pelo cliente no próprio personagem) |
| CombatDamage | S→C | victim, amount, result (dano que o jogador causou; números de dano e contador de acertos) |

Os remotes antigos na raiz do ReplicatedStorage (`NotifyEvent`, `EventNotify`, `QuestEvent`, `SelectTeam`,
`UpdateEXP`...) são legado. Não usar.

### Dados do jogador (criados pelo servidor em `PlayerData`)
- `player.leaderstats`: `Level`, `Gold` (IntValue)
- `player.Stats`: `HP`, `Energia`, `Forca`, `Defesa`, `Velocidade` (IntValue). São calculados (base + nós da árvore de
  habilidades); ninguém escreve neles fora do `PlayerData`.
- `player.Progress`: `XP`, `XPNeeded`, `StatusPoints` (IntValue). `StatusPoints` = pontos livres da árvore.
- API de servidor: `require(ServerScriptService.PlayerData)` expõe `AddXP(player, n)`, `AddGold(player, n)`,
  `GetStat(player, name)` e `Notify(player, title, text, duration?)`
- `Humanoid.MaxHealth` do jogador é controlado pelo `PlayerData` (a partir de `Stats.HP`).

### Inimigos
- Ficam em `workspace.Enemies`. Cada NPC é um Model com os atributos `Enemy = true` e `EnemyType = "Goblin"`.
- A IA respeita `npc:GetAttribute("Stunned")`.
- Ao morrer, lê `Humanoid:GetAttribute("LastAttacker")` para dar XP, Gold e progresso de quest.
- Animações, arma e dash de cada template ficam em `src/Server/EnemyKits.luau` (Claude). A faca do Goblin é uma cópia de
  `ReplicatedStorage.VFX.EnemyModels.Knife` renomeada para `Handle`, presa no `Right Arm` por um Motor6D (as animações de
  golpe mexem na pose `Handle`). O dano do golpe sai no momento do corte, não no início da animação.
- IA (EnemyModule): combo (kit `Combo`, ou `Combo` no EnemyData), passo para a frente no golpe, anda de lado na
  recarga (AlignOrientation "EnemyFacing" na raiz), mira onde o alvo vai, pula/Pathfinding quando trava, chama o grupo
  (28 studs) quando apanha. O golpe no jogador atordoa (sem stunlock: 1,2 s de intervalo) e o último do combo empurra
  (`Remotes.CombatImpulse`).
- Só chegando perto (detecção), no máximo 2 inimigos perseguem o mesmo jogador (`DETECTION_LIMIT` no EnemyModule);
  quem apanha e o grupo que ele chama não têm limite. Chefe e reforços ignoram o limite (opção `IgnoreAggroLimit`).
- O Spawner escreve o tipo resolvido de cada zona no atributo `ZoneType` da Part (o minimapa usa).
- Inimigos com modelo e kit: Goblin, Goblin Ladrão (Goblin), Rei Goblin, Ratazana, Manequim e Passageiro (os três do
  ChatGPT em 2026-10-01, `assets/characters/city_demons`). Kit pode ter `Hit` (reação própria; o modelo ganha
  `OwnHitReaction` e o CombatService não toca a genérica) e `Death` (corpo sem desmontar, raiz presa, última pose segura).
  Faltam zonas deles no mapa (Part com o nome do tipo em `workspace.EnemySpawns`).
- Dificuldade geral (2026-10-01, teste com amigos): `BALANCE` no topo do `EnemyModule` (dano x0,65, recarga x1,25,
  animação de golpe a 0,8 = corte mais tarde, XP x1,25), por cima do `EnemyData` e da curva de level. Prioridade de quem
  bateu primeiro: M1 do jogador começado antes do golpe do inimigo (`CombatState.MarkSwing`/`LastSwingAt`), com o inimigo
  na frente e no alcance, cancela o golpe do inimigo (chefes fora disso).
- Perseguição (2026-10-01, pedido do usuário: o inimigo largava a luta, voltava para a área e curava tudo): com alvo, só
  desiste a `LeashRange` x `CHASE_LEASH_MULTIPLIER` (3,5) de casa ou com o alvo a mais de `LOSE_RANGE` (110) dele; sem
  alvo vale o `LeashRange`. Voltar para casa não cura mais (só o chefe, que recomeça a luta); a vida volta devagar
  (`REGEN_RATE` 4%/s) depois de `REGEN_DELAY` (8 s) sem apanhar e sem alvo. Testado em Play: Goblin seguiu até 131 studs.

## Fase 2: mapa (Codex) + sistemas de RPG (Claude)

O Claude está refazendo os sistemas de RPG (salvamento de dados, status, missões, inimigos por zona).
Arquivos novos do Claude: `src/Shared/StatConfig.luau`, `src/Server/QuestData.luau`, `EnemyData.luau`,
`KillRewards.server.luau`.
- `PlayerData` agora salva tudo em DataStore (`PlayerData_v1`). No Studio precisa de
  Game Settings > Security > Enable Studio Access to API Services, senão joga sem salvar.
- `StatConfig` (ReplicatedStorage) tem as fórmulas: `DamageBonus(forca)`, `DamageReduction(defesa)`,
  `XPNeeded(level)`. Força agora dá +2 por ponto.
- `KillRewards` lê o `LastAttacker` do Humanoid de **jogadores** a cada dano e depois apaga (para o crédito
  do abate não ficar velho). Nos inimigos o atributo continua lá até a morte.
Para o mapa se ligar a esses sistemas, siga estas convenções (tudo opcional, e sem elas o jogo continua funcionando):

### Zonas de inimigos
- Pasta `workspace.EnemySpawns` com **Parts** (ancoradas, `CanCollide = false`, `Transparency = 1`).
  Cada Part é uma zona e os inimigos nascem em pontos aleatórios dentro dela (em X/Z, em cima da Part).
- O tipo do inimigo é o **nome da Part** (chave do `EnemyData` ou o nome da barra de vida, sem diferenciar
  maiúsculas/acentos e ignorando número no fim: "Goblin Ladrão 2" = `GoblinLadrao`). Pode ter subpastas. No jogo a
  Part fica invisível e sem colisão sozinha.
- Atributos da Part (todos opcionais):
  - `EnemyType` (string): tipo do `EnemyData`, se preferir não usar o nome (vale mais que o nome)
  - `MaxEnemies` (number, padrão 3)
  - `RespawnTime` (number em segundos, padrão 8)
  - `Level` (number, padrão o do tipo): os números seguem a curva de um inimigo comum desse level (EnemyModule).
    Cada tipo cobre uma faixa (Goblin 1-10, Ladrão 10-20, Ratazana 20-30... até o 100; tabela em docs/mapa-fase4.md).
- Level máximo do jogador: 100 (`StatConfig.MaxLevel`).
- Models dentro de `EnemySpawns` (ex.: o trono do boss) são decoração: as peças deles não viram zona.
- Quedas (2026-10-01): o mapa foi varrido com raios de 2 em 2 studs. Só o canal oeste tinha frestas sem colisão (a
  faixa de "água" é só textura da malha do chão), tapadas com peças invisíveis em `ChainsawCity.Collision.Canal.FallFix`.
  Rede de segurança: `src/Server/FallGuard.server.luau` (abaixo de y = -40 volta para o último chão firme). Área nova
  no mapa: sempre ter peça de colisão embaixo do que é só visual.

### Chefes (Claude)
- `src/Shared/BossData.luau` (trono, especiais, fase 2, drops com chance), `src/Server/BossService.server.luau` e
  `src/Client/BossBar.client.luau` (barra no topo: vida, dano por jogador, drops). A luta básica é a IA do
  `EnemyModule`, que agora devolve `(npc, controle)` no `SpawnEnemy` (pausar, virar, empurrar, alvo, ganchos).
- O chefe nasce onde o modelo dele foi colocado no Studio em `EnemyTemplates` (o Rei Goblin: `King Goblin`, sentado no
  trono), sem zona. Atributos no modelo: `Boss`, `BossAwake`, `BossPhase`, `BossDamage` (JSON `{userId: dano}`).
- Itens: `src/Shared/ItemData.luau`; salvos em `profile.Items` e espelhados em `player.Inventory` (IntValue por item);
  `PlayerData.AddItem(player, id, n)`.
- Sem `workspace.EnemySpawns`, nascem 5 Goblins em volta da origem, como hoje.
- Templates de inimigos em `ServerStorage.EnemyTemplates` (Model com Humanoid + HumanoidRootPart).
- **Denji → Lord Chainsaw** (2026-10-05, pedido do usuário; modelos `Denji` e `Lord Chainsaw` em `EnemyTemplates`, o
  Denji posicionado por ele no mapa). `BossData.Denji` espera em pé (Throne sem animação, `WakeRange` 35), briga como
  humano (Rush, Fury) e não morre: com `Transform.At` (15%) fica invulnerável (`DodgeUntil`), brilha 2,5 s, explode
  (quebra o mapa, afasta sem dano) e vira `BossData.LordChainsaw` (`FormOf = "Denji"`, não nasce sozinho) no mesmo
  lugar, com vida cheia e o mesmo placar de dano. Lord Chainsaw (level 40, 16000): Giro e Avanço quebrando o mapa
  (`Destroy = true`), Serra contínua, **Corrente** (Chain: puxa o primeiro jogador da linha e corta) e, na fase 2,
  **Beber sangue** (BloodDrink: abaixo de 25% cura 15% em 3 s, até 2 vezes; levar 5% da vida nesse tempo interrompe e
  atordoa 2 s). Recompensa na morte do Lord Chainsaw; todos fugiram = ele some e o Denji volta a esperar. Os dois com
  as animações dos Punhos até ter as próprias. Sem drops por enquanto.
- Denji é **chefe global** (2026-10-05, pedido do usuário): `BossData.Denji.Global` = aparece a cada 3 h em horários fixos
  UTC (iguais em todo servidor; `os.time` múltiplo de `Interval` + `Offset`), aviso para todos 5 min antes
  (`Remotes.Announcement`), vai embora em 30 min se ninguém vencer e não renasce sozinho. Próximo horário no atributo
  `GlobalBoss_Denji` do ReplicatedStorage. Admin: `/chefe Denji` (BindableFunction `BossService.BossControl`).
  `IdleGrace` (30 s): sem alvo, espera parado antes de voltar e se curar (antes resetava ao se afastar um pouco).
  Drop: `StyleDrop` (Motosserra, 10%, só para quem não tem) e `Drops` (itens; os acessórios do Denji ainda por definir).
- Estilo **Motosserra** (`CombatStyles.Motosserra`, glifo 鋸): por enquanto com as animações e as mecânicas da Katana
  (Z Investida da serra = DashSlash, X Serra no peito = Grab, C Giro da serra = DrawSlash de 360°, quebra o mapa), sem
  técnica na árvore. Arma `Weapon.Kind = "Held"` no `StyleWeapons`: nas costas guardada, na mão direita equipada; modelo
  `ReplicatedStorage.VFX.Weapons.Motosserra` (pivô no cabo, lâmina no +Y; `ModelOffset` gira) ou uma de peças. O
  `CombatFX` só usa as malhas do KatanaVFX na Katana; os outros estilos desenham os arcos na `SlashColor` deles.
- Modelo sem juntas (o Denji do usuário desmontava): o `EnemyModule.repairRig` cria na hora as juntas R6 que faltam
  (Motor6D com os nomes padrão, na pose do modelo), solda as peças soltas na peça presa mais perto e avisa no Output
  uma vez por modelo. Sem cabeça, `RequiresNeck = false`.

### NPCs de missão
- Um Model com Humanoid (ou qualquer Model com uma Part) com a **tag** `QuestGiver` (CollectionService / `AddTag`)
  e o atributo `NPCId` (string). O servidor cria o ProximityPrompt sozinho (tecla E; F é o block).
  O NPC fica parado: ancore o HumanoidRootPart.
- Animação parada do NPC: atributo `IdleAnimation` (number, ID da animação) no Model; o `NPCAnimations.server.luau`
  toca em loop. A animação tem que ser do mesmo rig do NPC.
- NPCIds que já têm missões em `QuestData.luau`: `"Veterano"` (Caçador Veterano, para Humans) e
  `"Anciao"` (Demônio Ancião, para Demons), `"Mestre"` (Mestre Espadachim, ensina a Katana; R6 em `Workspace.Mestre`,
  ao lado do Sargento). Se usar outros ids, avise na seção Pedidos.

### Times
- SpawnLocations com `Neutral = false` e `TeamColor` igual à do Team (`Demons` / `Humans`). O jogador
  renasce no spawn do time quando escolhe o time (`tScript`).

## Fase 3: interface (Claude)

O Claude está refazendo **todas as interfaces** com um tema visual único (`src/Shared/UITheme.luau`).
Enquanto isso, o Codex não deve editar estes arquivos de cliente:
- `src/Client/HUB_GUI.client.luau` (HUD principal), `StatusMenu.client.luau` (novo), `QuestGUI.client.luau`,
  `Notifications.client.luau`, `TeamScript.client.luau`, `FastMode.luau` (novo, ModuleScript)
- Só a parte visual de `src/Client/StaminaDashRunscript.client.luau` e `src/Shared/Tools/Katana/M1Loocal.client.luau`:
  as barras próprias deles saem e a HUD principal mostra stamina e cooldowns. A lógica de movimento e de
  combate continua do Codex.

Novo contrato de cliente:
- Desde 2026-10-03, `DashService` publica no servidor `Stamina`, `MaxStamina`, `StaminaRegenRate`,
  `StaminaUpdatedAt` e `DashReadyAt`. A stamina continua usada somente pelo dash, calculada de `Stats.Energia`
  e dos bônus `TreeDashCost` / `TreeStaminaRegen`.
- O movimento publica apenas a previsão visual `PredictedStamina` / `PredictedDashReadyAt` e `Sprinting`.
  `CombatInput` publica `PredictedCombatLockUntil` para bloquear o dash local antes da confirmação do combate.
  Não voltar a escrever os atributos autoritativos no cliente nem criar outro dono de WalkSpeed.
- Os cooldowns do combate são lidos dos atributos que o servidor põe no player (`CombatZReadyAt`, `CombatXReadyAt`,
  `CombatCReadyAt`: um por tecla de skill do estilo).

## Fase 4: caminhos (Claude + workflow)

Especificação em `docs/fase4-caminhos.md`. Não existe mais escolha de time: todos começam como Humano comum e,
no level 25, escolhem Caçador (contratos) ou Infernal. **Implementada** (ainda sem teste no Studio). Os arquivos
da tabela "Donos dos arquivos" desse documento passam a ser do Claude, inclusive `M1.server.luau` (o dano agora
passa por `CombatRules`) e o script de movimento (soma `SpeedBonus` e escuta o BindableEvent `MovementAction`
dos toques na HUD). Os Teams agora são `Humans` e `Fiends` (criados pelo `PathModule`), e o `tScript.server.luau`
foi apagado. Guia de montagem do mapa (NPCs e zonas): `docs/mapa-fase4.md`.

## Combate: estilos (Claude)

Cada estilo de combate é um Tool sem Handle com o nome do estilo: `Punhos` (todo mundo tem) e `Katana` (ensinada pelo
Mestre Espadachim, ver "Katana" abaixo), entregues pelo `GiveTools` conforme o atributo `Styles` do player. Tudo do combate é do Claude: `src/Shared/CombatStyles.luau` (números e IDs de
animação), `src/Server/CombatService.server.luau`, `CombatState.luau`, `CombatRules.luau`,
`src/Client/CombatInput.client.luau` e `CombatFX.client.luau`.
- Punhos: combo de 5 M1 (o 5º arremessa; no ar o 4º vira uppercut), F segura a guarda (parry nos primeiros 0,2 s,
  a guarda quebra se esvaziar), Z Rajada, X Soco carregado (segurar e soltar).
- Teclas (2026-09-30): Z/X/C = skills do estilo equipado (`CombatStyles.SkillSlots`; cada skill tem `Kind`, a mecânica
  no servidor: "Barrage", "Charge"...; o `CombatService` escolhe pelo `Kind`, não pela tecla). V/B = poderes do caminho
  (por dentro os slots continuam "Z"/"X": `PathData.KeyLabel` dá a tecla). E = só falar com NPC.
- Atributos no personagem: `Stunned`, `Blocking`, `Charging`, `CombatSpeed` (multiplicador de velocidade que o
  script de movimento aplica; também tira corrida e dash). No player: `CombatBusyUntil`, `Combat<Z|X|C>ReadyAt`,
  `Guard`, `MaxGuard`.
- Toques da HUD: BindableEvent `CombatAction` (criado pelo `CombatInput`), como o `MovementAction`.
- Cliente prevê, servidor valida: animação, efeito, hitstop e som saem no clique; a hitbox (`GetPartBoundsInBox`) roda
  no cliente no marcador `Hit` da animação (ou no Windup) e manda os alvos (`CombatHit`); o servidor só aceita alvos de
  um golpe que ele autorizou (`CombatM1`), no alcance +2 studs. Empurrão de jogador é aplicado pelo cliente dele.
  Input buffer e janela de cancelamento (`CombatLockUntil`) no M1. A Rajada continua com hitbox no servidor.
- O bloqueio vale contra qualquer dano que passe pelo `CombatRules` (golpes, poderes V/B e inimigos).
- O jogo é R6. Animações: IDs de combate em `CombatStyles` e o resto (padrão do Roblox + sprint/dash/recarga) em
  `src/Shared/CharacterAnimations.luau`. As do próprio personagem são tocadas pelo cliente (`CombatAnimations.luau`,
  `StaminaDashRunscript`); o servidor só troca as padrão (`CharacterAnimations.server.luau`) e toca a de quem apanha.
- Tela de carregamento: `src/First/LoadingScreen.client.luau` (ReplicatedFirst, mapeado no `default.project.json`).
- Visual no `UITheme` (estilo escuro vermelho e branco desde 2026-09-28, ver "Inventário, HUD nova e balões") e preset de
  gráficos em `src/Server/LightingSetup.server.luau` (atributo `KeepStudioLighting` no Lighting desliga o preset).

## Katana (Claude, 2026-09-30)
- Liberação: missão "O caminho da lâmina" (`CaminhoDaLamina`, NPC `Mestre`, level 15, qualquer caminho: 12 Goblins
  Ladrões e voltar). Recompensa nova `Rewards.Style` → `PlayerData.UnlockStyle`. Estilos aprendidos em `profile.Styles`
  (os iniciais ficam em `CombatStyles.StartingStyles`); a lista inteira vai no atributo `Styles` (JSON) do player.
  API: `PlayerData.GetStyles`, `HasStyle`, `UnlockStyle`.
- Árvore: galho KATANA (`SkillTreeData`; os galhos agora ficam a 60° um do outro). O 1º nó pede maestria Katana 1, então
  só quem tem a espada chega nas técnicas `KatanaAvanco` (Z), `KatanaAgarrao` (X), `KatanaSaque` (C) e `KatanaUppercut`.
- Skills (`CombatStyles.Styles.Katana.Skills`, hitbox no servidor nos tempos dos marcadores das animações do Codex):
  Z `DashSlash` (o cliente se move direto, 24 studs em 0,07 s, parando em parede; o servidor mede o corredor entre a
  saída e a chegada; invulnerável no avanço via `DodgeUntil`; acertou: trava os alvos, manda `DashSlashConnect`, o cliente
  de quem avançou faz a pose `DashSlashFinish` e no `HitframeSword` (0,2 s) entra o dano com a chuva de cortes, Cut "Flurry"), X `Grab` (pega o alvo mais perto na frente, atravessa a guarda, prende
  com AlignPosition/AlignOrientation a 2,3 studs, corta no Strike e arremessa no Release; errou = recarga de 5 s; chefes
  levam os cortes sem ser presos), C `DrawSlash` (arco de 150° e 13 studs, quebra a guarda). Opções novas de dano:
  `Unblockable`, `FromPosition` (`CombatState.TryBlock`), `HitFX` e `NoHitReaction` (`strike` do CombatService).
- Efeitos: `CombatFX` usa o `KatanaVFX` do Codex nas fases (marcador da animação ou tempo da skill, o que vier primeiro;
  Grab/Strike/Release chegam do servidor: `KatanaGrab`, `KatanaGrabStrike`, `KatanaGrabRelease`, `KatanaGrabMiss`) e
  desenha os cortes do M1/acertos (arcos de Beam), o risco e os fantasmas do avanço (`DashSlashPath`).
- Espada no corpo: `src/Server/StyleWeapons.luau` (campo `Weapon` do estilo). Guardada: bainha na cintura esquerda;
  equipada andando: a mão direita leva a espada pela bainha; atacando: bainha na mão esquerda e lâmina na direita, por
  `CombatTime` (4 s) depois do último ataque. Modelo: `ReplicatedStorage.VFX.Weapons.AkiKatana` (do ChatGPT; espada e bainha separadas,
  a bainha reconhecida por "Saya"/"Bainha" no nome; lâmina no +Y, boca da bainha na ponta -Y); sem ele, uma katana de peças.
- Admin (`ItemCommands`): `/estilo Katana`, `/maestria Katana 30`, `/pontos 20`.
- Animações do usuário: M1 x5 (marcador "Hitframe1"), guarda e o C (HeavySlice1, marcador "SkillC" no corte; `Markers`
  da skill mapeia fase -> marcador; `DrawFromSheath = false`). Rastro: Trail "SwingTrail" na lâmina (Handle) e na bainha
  (SheathRoot), criado pelo `StyleWeapons`; o `CombatFX` liga no golpe e desliga 0,08 s depois do marcador de impacto
  (`M1.SwingArm`: "Right" = lâmina, "Left" = bainha). A bainha do AkiKatana tem o pivô fora da boca: `SheathMouthOffset`.
  Testado pelo usuário em Play em 2026-09-30: funcionou.

## Árvore de habilidades, movimento e minimapa (Claude)
- Árvore: `src/Shared/SkillTreeData.luau` (nós, custos, maestria, efeitos), `src/Client/SkillTreeMenu.client.luau` (tecla M
  e botão 📜 da HUD) e o `PlayerData` (salva `profile.Tree`, `profile.Mastery` e `BonusPoints`). 1 ponto por level; M1 e
  guarda vêm de graça. Efeitos ficam no player como atributos `Tree<Efeito>` (ex.: `TreeDashCost`, `TreeDoubleJump`), as
  técnicas liberadas como `Tech_<Técnica>` e a lista dos nós em `SkillTree` (JSON). Maestria por estilo em `player.Mastery`
  (IntValue com o XP total; nível por `SkillTreeData.MasteryLevel`). `Remotes.StatusReset` reseta a árvore (custa Gold).
  O `StatusMenu` ficou só com o caminho. `HealthRegen.server.luau` cura com o nó de regeneração.
- Movimento (`StaminaDashRunscript`): corrida automática (configuração `AutoRun`, padrão ligada; com ela, segurar Ctrl
  anda) e dash com 1 s de recarga, que para antes de parede. Publica `DashReadyAt` (hora do servidor) e `AutoRun` no
  LocalPlayer. A HUD usa o BindableEvent `MovementAction`: ("Dash") e ("AutoRun", ligado).
- Minimapa (`src/Client/Minimap.client.luau`): desde 2026-09-29 o fundo é 2D (imagens prontas de `MinimapAtlas`, feitas
  pelo ChatGPT a pedido do usuário; área nova = refazer o bake, ver assets/ui/minimap/LEIA-ME.md). Os marcadores são os
  mesmos. O estado das missões (`QuestEvent` "State") traz `Type`/`Target`/`TargetList` em cada objetivo e `Givers` (NPCs
  com missão disponível para o jogador).
- Animações presas: o hitstop não pausa animação que já está parada e só devolve a velocidade se ninguém mexeu nela; o
  `CombatAnimations` encerra qualquer animação de ação parada em velocidade 0 por mais de 1 s. Testado no Studio: uma
  animação pausada no cliente continua "tocando" nele mesmo depois de o servidor destruir a dele (pose presa até o reset).

## Inventário, HUD nova e balões (Claude, 2026-09-28)
- Itens (`src/Shared/ItemData.luau`): cada item tem `Slot` (casas em `ItemData.Slots`: Head, Hat, Neck, ShoulderLeft,
  ShoulderRight; um item por casa), `Effects` (mesmas chaves dos nós da árvore: HP/Forca/Defesa/Energia/Velocidade somam
  nos Stats, o resto nos atributos `Tree<Efeito>`), `Description` e o modelo: um Accessory no tamanho de jogador em
  `ReplicatedStorage.VFX.Items.<Id>` (feito no Studio a partir dos acessórios do Rei Goblin; fica no VFX, que o Argon
  não apaga). O `PlayerData` salva `profile.Equipped` (`{ [Slot] = Id }`), publica o atributo `Equipped` (JSON) e veste
  uma cópia do Accessory no personagem (atributo `EquippedItem` = Id), ao equipar e ao renascer. API:
  `PlayerData.EquipItem(player, id, equip)`. Comando de admin para testar: `/item <Id>` ou `/item todos`
  (`src/Server/ItemCommands.server.luau`).
- Estilos de combate no inventário (2026-10-01): cartões com o kanji na grade (antes dos itens); GUARDAR tira o estilo da
  hotbar e EQUIPAR põe de volta (`Remotes.EquipStyle`, salvo em `profile.HiddenStyles`; sempre fica pelo menos um). O
  atributo `EquippedStyles` (JSON) é a lista com Tool; `Styles` continua com todos os aprendidos.
- Inventário (`src/Client/Inventory.client.luau`, tecla G, botão da HUD ou "Inventário" na árvore): itens girando em 3D,
  o personagem com o que está vestido, casas de equipamento e bônus. BindableEvent `Inventory.Toggle`.
- HUD (`HUB_GUI`) no estilo da foto de referência: anel de level (XP), vida/stamina/tempo de vida finas embaixo à esquerda,
  bônus em pílulas (árvore + itens), skills com a tecla em cima e a hotbar redonda 1–5 no centro (a mochila padrão do
  Roblox foi desligada: as teclas 1–5 equipam/guardam os estilos) e os botões da árvore (M), inventário (G) e
  configurações. No celular a vida vai para cima à esquerda. O Roblox troca a mochila (Backpack) a cada vez que o
  jogador renasce: a hotbar segue a atual (antes, depois de morrer, o estilo guardado sumia da hotbar).
- Tema (`UITheme`): paleta escura, vermelho sangue e branco (`Orange` virou vermelho claro e `Gold` virou creme), fonte
  de pincel `PermanentMarker` em `Fonts.Display`/`Fonts.Marker` (sem símbolos como ✕ ✔ ▶: usar × ✓ ou outra fonte) e
  `Fonts.Number` (GothamBlack). Novos: `UITheme.pill`, `UITheme.keyLabel`, `UITheme.tooltip(guiObject, texto ou função)`
  (balão que segue o mouse), `UITheme.tipText(título, texto)` e `UITheme.glyphOf(entrada)`. Kanji no lugar dos emoji:
  `Glyph` nos caminhos, contratos, tipos de Infernal e poderes do `PathData`; `UITheme.PathIcons` = 人 狩 魔;
  `SkillTreeData.EffectInfo`/`ShortValue`/`EffectText` (ícone, valor curto e texto de cada efeito).
- A tela do Caminho (`StatusMenu`) foi refeita no mesmo estilo, só com o caminho (a aba antiga de distribuir pontos saiu).

## Menu principal, criador de personagem e clãs (Claude, 2026-09-30)
- Menu principal: `src/Client/MainMenu.client.luau` (substituiu o `TeamScript.client.luau`, apagado). A ScreenGui continua
  com o nome `TitleScreen` (a tela de carregamento espera por ela). JOGAR, PERSONAGEM, CLÃ, CÓDIGOS e CONFIGURAÇÕES; no
  primeiro acesso abre direto no criador e depois mostra o clã de nascença. A HUD reabre pelo BindableEvent
  `TitleScreen.Open` (botão "MENU PRINCIPAL" nas configurações da HUD).
- Com o menu aberto o LocalPlayer tem o atributo `MenuOpen = true` (só no cliente) e o movimento fica desligado. Todo
  script de tecla ignora a tecla nesse estado (`if processed or player:GetAttribute("MenuOpen") then return end`).
- Aparência: `src/Shared/AppearanceData.luau` (peles, 8 rostos, 18 cabelos + careca, 14 cores de cabelo, 8 camisas e 6
  calças; `Apply(character, appearance, { Physics })`). O avatar do Roblox não carrega: no Studio, `StarterPlayer` tem
  `LoadCharacterAppearance = false` e um `StarterCharacter` R6 liso (força R6 para todos). Cabelos em
  `ReplicatedStorage.VFX.Hair` (Studio); roupas e rostos gerados por `assets/character` (ver o LEIA-ME de lá).
- Clãs: `src/Shared/ClanData.luau` (19 clãs com kanji, raridade e bônus pequeno; chances por raridade 55/27/13/4,5/0,5%).
  Os bônus usam as chaves da árvore e somam no `PlayerData` (novas: `DodgeChance` no `CombatRules`, `XPBonus` e
  `GoldBonus` no `AddXP`/`AddGold`, que ganharam o parâmetro `noBonus`).
- Servidor: `src/Server/CharacterService.server.luau` (veste ao nascer, sorteia o clã do primeiro acesso, giros, compra e
  códigos) e `src/Server/Codes.luau` (lista de códigos, só no servidor). Perfil: `Appearance`, `Created`, `Clan`,
  `Spins`, `Codes`; atributos no player: `Appearance` (JSON), `CharacterCreated`, `Clan`, `ClanSpins`.
- Lei das caixas de recompensa (2026-10-02, pedido do usuário; no Brasil o sorteio pago é proibido para menores): o
  `CharacterService` lê `PolicyService:GetPolicyInfoForPlayerAsync` e põe no player o atributo `RandomItemsRestricted`
  (`ArePaidRandomItemsRestricted`; sem resposta do Roblox vale restrito). Nessas contas não tem roleta nem compra de giro
  (o servidor recusa `ClanSpin`/`BuySpin`): a página do clã vira escolha direta (clique na lista, botão ESCOLHER,
  `Remotes.ClanChoose`), pagando o preço da raridade (`ClanData.ChooseGoldCost`, `ClanData.ChooseCost`); cada giro
  guardado (código, tutorial) vira crédito de `SpinGoldCost`. O clã do primeiro acesso continua sorteado de graça.
  Admin: `/restricao on|off` simula a conta restrita. Hoje nada no jogo é vendido por Robux; se um dia o Gold ou os giros
  forem vendidos, a regra continua valendo.
- Configuração nova: `Music` (liga/desliga o volume do `SoundService.LobbyMusic`, que é do usuário).
- Menu e carregamento mais compactos (2026-10-05, pedido do usuário): fundo grafite com brilho laranja (círculos quase
  transparentes) e sombra atrás da coluna, sem listras nem dentes de serra; botões da coluna compactos (290 x 38, JOGAR
  48) com o kanji num quadradinho; páginas em painel escuro de cantos redondos a 92% (UIScale) no meio da altura;
  Builder Sans nos textos e botões (o nome do jogo continua Creepster). A tela de carregamento segue o mesmo visual
  (barra fina, anel girando, dicas atualizadas).
- Testado pelo usuário em Play (2026-10-05): menu, carregamento e HUD nova aprovados.
- `MainMenu` está no limite de 200 registradores do Luau no escopo de cima ("Out of local registers" no Play com 195
  locais). Hoje tem 185: variável nova vai numa tabela (`ClanChoice`, `MenuFont`) ou num bloco `do ... end`.
- Tema do menu principal (2026-09-30, pedido do usuário): laranja e branco sobre cinza (`ACCENT`, `ACCENT_DARK`, `LIGHT`,
  `BACKDROP` no topo do `MainMenu`). O resto da interface continua com o vermelho do `UITheme`; `UITheme.panel` e
  `UITheme.button` aceitam a cor de destaque como parâmetro opcional.
- SmartBone (física dos cabelos com ossos): o módulo fica em `ServerStorage.SmartBone` (Studio, fora do Argon) e o
  `CharacterService` copia para `ReplicatedStorage.VFX` ao iniciar; o `SmartBoneRunner` (cliente) liga. NÃO colocar
  scripts dentro do `VFX` no Studio: o Argon grava eles de volta dentro do `default.project.json` (aconteceu com o
  SmartBone: o arquivo foi para 543 KB e, ao reconectar, o Argon apagou o módulo).

## Kon: finalização e sangue (Claude, 2026-10-01)
- Finalização: inimigo comum (não chefe) que fica com até 30% da vida depois da mordida do Kon é devorado
  (`PathData` Raposa `Finisher.Threshold`). O `PathSkills` mata (o LastAttacker da mordida dá XP/missão), põe o
  atributo `Devoured`, prende o corpo sem colisão e manda `CombatFX` "FoxDevour" (mesmo `StartTime` do "FoxBite"). O
  `EnemyModule` vê o `Devoured` na morte: sem animação de morte nem drop, o corpo some em 1,5 s.
- Cliente (`FoxDevilVFX.Devour`): a animação base congela, o corpo de verdade fica escondido
  (`LocalTransparencyModifier`) e uma cópia local voa em arco até a boca; o Kon mastiga `DevourChews` vezes em
  `DevourTime` (`FoxDevilConfig`), engole e volta ao portal. Pontos da boca (`MOUTH_*`) medidos em captura.
  Sons (Pro Sound Effects) em `FoxDevilConfig.DevourSounds`.
- Sangue: `src/Shared/BloodFX.luau` (só cliente): gotas simuladas com raio (sem física) que viram poças no chão e
  escorridos na parede; peças reaproveitadas, limites (160/70; Fast Mode 60/24) e névoa. API `Burst`, `Drip`, `Splat`.
  Fica em `workspace.CombatFX.Blood` (o Fast Mode não mexe). Mesma ideia do BloodEngine (rotntake, MIT), sem ele.
- Testado pelo usuário em Play em 2026-10-01: finalização e correção da hotbar (estilos depois de morrer) funcionaram.

## Contratos: formas e fusão (Claude, 2026-10-01)
- Pedido do usuário: um contrato só por Caçador (`PathData.MaxContracts = 1`), que evolui em formas (`src/Shared/ContractData.luau`):
  **V1** (pacto: passivo + dois poderes, V e B), **V2** (fusão com o estilo `FusionStyle`, maestria 120 no contrato e 120 no
  estilo) e **Ultimate** (maestria 300 nos dois + a missão final, ainda por fazer). Só a **Raposa** está ativa: Fantasma,
  Futuro e Maldição têm `Enabled = false` (sem animações/efeitos; somem da escolha; quem tinha vira Raposa). Infernais
  (Sangue, Tubarão) ficam com o usuário + Codex.
- Raposa: V1 = Mordida (`FoxBite = true`, a do Kon) + **Bote** (B, Kind `FoxLunge` no PathSkills: a cabeça sai de um portal
  atrás e corre em linha reta arrastando quem pega; efeito `FoxDevilVFX.Lunge`/`LungeCatch`, tempos `Lunge*` no
  `FoxDevilConfig`; mira com o mouse pelo `FoxAim.Cast`). V2 = Mordida/Bote Voraz (mais fortes) + estilo fundido
  **Punhos da Raposa** (desde 2026-10-02: combo de **4** golpes, `M1.Hits = 4`, o 4º arremessa, numa animação só do
  usuário, `Animations.M1Chain`; cada clique toca o trecho do golpe, `M1.Segments` { Start, End }, emendando no próximo
  se o clique vier a tempo e segurando a pose 0,3 s no fim do trecho, `CombatAnimations.playSegment`; o acerto sai nos
  marcadores dele "M1".."M4", `M1.ImpactMarkers`, com `M1.ImpactTime` de garantia; `M1.ClawDelay`, `M1.Interval`,
  `Damage` e `GuardDamage` têm um valor por golpe. A pose parada é a dos Punhos até o usuário pôr uma em
  `Animations.Idle`; sem uppercut: `M1.Uppercut = false`. `M1.Hits` vale em todo o combo: CombatInput, CombatService,
  `CombatState.NextCombo` e as garras do golpe final no CombatFX): cada M1 desenha três garras carmesins na frente (`CombatFX` swingClaws, no "Swing", tempo
  `M1.ClawDelay`; o 5º golpe e o uppercut fazem um X duplo); Rajada de Garras (Z), Soco da Raposa (X) e os acertos sem M1
  desenham as garras na vítima; **Kon!** (C, Kind `FoxSnap` no CombatService): garrada no `ClawAt` (1º acerto) e uma
  cabeça menor do Kon abocanha no `SnapAt` e puxa o alvo (2º acerto).
- Rajada com mais golpes que a padrão (nó "Rajada longa", Rajada de Garras): a animação fica mais lenta na mesma medida
  (`CombatAnimations.StartBarrage`, `BaseHits` = 9) para durar até o fim do efeito.
- Forma salva em `profile.Path.Forms[contrato]` (atributo `ContractForm`); `PathData.FromPlayer` devolve a forma como 4º
  valor e `PathData.GetSkill(..., slot, form)` / `PathData.Passives(..., form)` usam ela. API: `PathModule.GetForm/SetForm`.
- Fusão no combate: `CombatStyles.FromCharacter` devolve o estilo fundido (`CombatStyles.Fused[contrato][forma]`, via
  `CombatStyles.Resolve`) para quem tem a fusão; o nome continua o do estilo base. Personagem sem Player (a Sombra
  futura) usa os atributos `FusionContract`/`FusionForm`.
- Maestria: teto 300 para estilos e contratos (`SkillTreeData.Mastery`, 20 x nível até o 25 e 500 por nível depois).
  Maestria do contrato em `profile.ContractMastery` (pasta `player.ContractMastery`): sobe com acertos e abates dos
  poderes e com os golpes do estilo fundido (`ContractData.Mastery`). API: `PlayerData.AddContractMastery`,
  `GetContractMasteryLevel`.
- NPC: **Mestre dos Pactos** (NPCId `Evolucao`, `Workspace.MestreDosPactos`, provisório perto do spawn, o usuário pode
  mover/trocar o modelo). O diálogo mostra o cartão da evolução (`ContractService.GetOffer` → `QuestGUI`) com os requisitos
  e o botão de fundir.
- Fusão trava os estilos: com a forma V2 ou Ultimate só o estilo da fusão (`FusionStyle`) fica com Tool; os outros (Katana...)
  somem da mochila, da mão e do corpo (o PlayerData publica `EquippedStyles` e `StyleFusion`; o GiveTools e o StyleWeapons seguem).
  Renunciar ao caminho solta de novo.
- Admin (`ItemCommands`): `/cacador [Contrato]`, `/maestriacontrato <nível>`, `/forma <V1|V2|Ultimate>`, `/maestria Punhos 120`,
  `/yen <n>` (ou `/gold`) e `/hibrido [Infernal] [Contrato]` / `/hibrido off`: modo híbrido (até sair do jogo; atributos
  `Hybrid`, `HybridContract`, `HybridForm`, `HybridFiend`): contrato no V/B e poderes do Infernal no **H/J** (slots
  `HZ`/`HX`), seja qual for o caminho. Quem lê é o `PathData.PlayerSkill(player, slot)` (PathSkills, PowerInput, FoxAim, HUD);
  contrato usado por quem não é Caçador não gasta tempo de vida.
- Falta (próxima fase): a forma Ultimate (missão final com abates de cada inimigo, chefes 2x, 1 milhão de Gold pago,
  Fragmento de um chefe global, level máximo, usar cada ataque 20x, 20 abates PvP e o duelo contra um jogador com o
  mesmo contrato na V1 **ou** contra a Sombra), o chefe global e a transformação.

## Tutorial (Claude, 2026-10-01)
- Passos e textos em `src/Shared/TutorialData.luau` (21 passos em 5 capítulos: andar, câmera, pulo, dash, corrida;
  boneco de treino com soco, combo e guarda; ir até os Goblins seguindo a seta, derrotar um, HUD e missões, level 2;
  árvore, inventário, falar com o Mestre; próximos objetivos). Começa depois do JOGAR quando `TutorialDone` é false,
  pausa com o menu principal aberto, tem "Pular tutorial" (com confirmação) e "REFAZER TUTORIAL" nas configurações da HUD.
- Cliente `src/Client/Tutorial.client.luau`: confere cada passo pelo estado do jogo (tabela `Checks`), destaca a
  interface pelo atributo `TutorialAnchor` (HUD: `Vitals`, `Skills`, `Hotbar`, `Slot_<Tecla>`, `TreeButton`,
  `InventoryButton`, `SettingsButton`; `QuestTracker` no QuestGUI; `Minimap`) e aponta alvos no mapa (marcador em
  cima e seta na borda da tela). Elemento novo que o tutorial deva mostrar: pôr o atributo e usar o nome no passo.
- Servidor `src/Server/TutorialService.server.luau`: salva `profile.Tutorial` (`Step`, `Done`, `Rewarded`; atributos
  `TutorialStep`, `TutorialDone`, `TutorialRewarded`), dá a recompensa uma vez (`TutorialData.Reward`: 100 Gold e 1 giro
  de clã; só no último passo e com level 2+) e cria o boneco de treino (cópia do StarterCharacter em `workspace.Enemies`,
  atributo `TrainingDummy` = UserId do dono; parado, sem ataque, a vida volta, não dá XP nem maestria, o Kon não devora).
  Perfil de antes do tutorial com level 5+ já conta como concluído.
- Testado pelo usuário em Play em 2026-10-01: funcionou.

## Revisão do combate, números de dano e contador de acertos (Claude, 2026-10-01)
- Números de dano e contador: `src/Client/DamageNumbers.client.luau`. O `CombatRules.Damage` (todo dano de jogador: M1,
  skills, poderes) manda `Remotes.CombatDamage` só para quem bateu. O número salta da vítima num arco (ScreenGui que
  segue o ponto 3D, sempre por cima); forte (8% da vida ou 40+) sai maior e creme, bloqueado sai azul. O contador fica à
  esquerda ("N HITS" e o dano somado), aparece a partir de 2 acertos e some 2,2 s depois do último.
- No Studio (testado com captura), BillboardGui com `AlwaysOnTop = true` não aparecia; sem ele aparece (barras dos inimigos,
  nome). Os textos do `CombatFX` (PARRY!, GUARDA QUEBRADA, ESQUIVOU) passaram para `AlwaysOnTop = false`.
- Desempenho: consultas de área do combate (hitbox do cliente, `findTargets`/`barrageTargets`/`corridorTargets` e o
  `ctx.Overlap` do PathSkills/BloodFiendSkills) só enxergam quem pode levar dano (`CombatRules.TargetOverlap`: Include com
  `workspace.Enemies` e os outros personagens), sem passar pelas peças do mapa. O `CombatAnimations` guarda o estilo
  equipado (antes procurava o Tool e a fusão a cada frame). O `CombatFX` não desenha luta a mais de 260 studs da câmera
  (`FX_RANGE`; os avisos de fim passam sempre) e usa a pasta `workspace.CombatFX` que já existir (antes podia criar duas).
- Kon! (fusão): o portal, que fica entre a câmera e quem invoca, fica quase transparente na tela de quem usa
  (`FoxDevilVFX` portal `seeThrough`).
- Testado em Play: combo de 5 M1, Rajada de Garras (14 acertos), Soco da Raposa carregado, Kon!, Mordida (V), Bote (B),
  guarda/parry, Lança e Martelo de Sangue (modo híbrido), números e contador; sem erros no console.

## Celular e controle de Xbox (Claude, 2026-10-01)
- Celular (sem teclado, `touchOnly` no HUB_GUI): as habilidades saem da linha do centro e viram botões redondos no canto
  de baixo à direita (`MobilePad` dentro da ScreenGui HUD), em volta de um botão grande de ataque (`Attack`, atributo
  `TutorialAnchor` = "AttackButton"; segurar repete o combo; sem estilo na mão, o 1º toque equipa a casa 1), ao lado do
  pulo do Roblox. Mesmos slots (recarga, cadeado, guarda, custo); posições em `MOBILE_LAYOUT` (em relação ao centro do
  pulo do Roblox, 70 px no celular; no tablet tudo x 120/70). A hotbar fica com no mínimo 80% de escala e sem casas
  vazias; a lista de missões sobe para o lado esquerdo do minimapa (QuestGUI). Para ver o layout no PC: atributo
  `ForceMobileHUD = true` no ReplicatedStorage antes do Play (tirar depois). BindableEvent `CombatAction` ganhou
  ("Attack", segurando).
- Controle (Xbox): RT ataca (segurar repete), LT guarda, B / Y / RB = skills Z / X / C, LB dash, segurar L3 = Ctrl,
  direcional ↑ / → = poderes V / B, ← troca o estilo da hotbar, ↓ abre a árvore; A pula e X fala com NPC (padrão do
  Roblox). Cada script dono da ação trata os botões dele (CombatInput, PowerInput, StaminaDashRunscript, HUB_GUI). Os
  rótulos de tecla da HUD viram os do controle quando ele é o último usado; o menu principal começa com o JOGAR
  selecionado e o diálogo de NPC com o primeiro botão (B fecha); a árvore aberta pelo controle já seleciona um botão
  (navegação do Roblox). A mira da Mordida/Bote no controle é o centro da tela (FoxAim; o mouse agora usa
  ViewportPointToRay, sem o desvio do inset do topo). Modo híbrido (H/J) fica só no teclado.
- Testado em Play: botão de ataque (equipou e fez o combo), layout do celular, RT/LT/Y/LB/↑→/← (o MCP simula os botões
  do controle como teclado; o B não pode ser simulado por ser do sistema). Falta: textos do tutorial e das dicas
  ainda falam das teclas do PC.

## Esquiva automática e Treinador (Claude, 2026-10-02)
- Pedido do usuário: o desvio automático (chance de o golpe não pegar) ganha animação e evolui treinando com o NPC
  **Treinador** (NPCId `Treinador`; o usuário posiciona: tag `QuestGiver`, atributo `NPCId`, de preferência R6).
- Dados em `src/Shared/DodgeData.luau`: 5 níveis (+3% de chance cada, até 15%; nível 3 = contra-golpe, nível 5 = desvio
  rápido), teto da chance somada `MaxChance` (35%), passo `Step` e as 3 animações (`Animations` Left/Right/Back, R6 do
  usuário; 0 = sem animação; sem a de trás, sorteia só esquerda/direita). O passo é por código (sem root motion na
  animação) e a animação para em `AnimationMaxTime` (0,75 s: a da direita veio exportada com 10,4 s, parada depois de
  0,7 s). Nível salvo em `profile.DodgeLevel` (atributo `DodgeLevel`; API
  `PlayerData.GetDodgeLevel/SetDodgeLevel`); a chance do nível entra no `TreeDodgeChance` junto com clã e itens.
- Animações publicadas na conta do usuário (Midcasual) só tocam no jogo, que é do grupo 126221487, depois de liberar o
  acesso: o Output mostra "A experiência não tem permissão de acesso para usar a ID do ativo ... Clique para compartilhar
  o acesso" e o clique libera (ou publicar direto no grupo).
- Desvio (`CombatRules`): vale contra M1, skills, poderes e inimigos. Pela chance, o `CombatFX` "Dodge" leva `Side`
  (Left/Right/Back conforme de onde veio o golpe): todos veem o "ESQUIVOU" e o rastro; o cliente de quem desviou toca a
  animação e dá o passo. Contra-golpe: atributo `DodgeCounterUntil` (o 1º M1 que acerta em 1,2 s dá +50%, "CONTRA-GOLPE!",
  `CombatRules.ConsumeCounter`); desvio rápido: `DodgeRushUntil` (+6 de velocidade por 1,5 s no movimento). O
  invencível do avanço da Katana (`DodgeUntil`) continua só com o texto.
- Missões (QuestData, giver Treinador, level 10+): EsquivaLeitura (30 golpes de inimigos levados ou desviados, objetivo
  `TakeHits`), EsquivaLadroes (15 Goblins Ladrões), EsquivaTreino (level 15, objetivo `Spar`: aguentar 40 golpes do
  treino), EsquivaRatazanas (level 20, 10 Ratazanas), EsquivaDuelo (level 25, objetivo `Duel`). Recompensa
  `Rewards.DodgeLevel`. Quem já tem o nível pula a missão.
- Treino/duelo (`src/Server/TrainerService.luau`): botão TREINAR/DUELAR no diálogo (`QuestAction` "Train"). Uma cópia do
  Treinador (do próprio NPC se for R6, senão do StarterCharacter; kit `EnemyKits.TreinadorTreino` com as animações dos
  Punhos; `EnemyData` TreinoTreinador/DueloTreinador) luta só com quem pediu (`EnemyModule` opção `OnlyTarget`; atributo
  `TrainingFor`: ninguém mais acerta ela). No treino a cópia não morre, é marcada `TrainingDummy` (sem maestria) e o
  treino para com a vida abaixo de 25%. Acaba ao completar, morrer, se afastar 70 studs do NPC ou passar do tempo.
  `EnemyModule` ganhou a opção `OnStrike` (cada golpe que chegou) e manda os golpes comuns para `QuestModule.OnHitTaken`.
- Admin: `/esquiva <0-5>` (nível) e `/esquiva <n>%` (chance fixa, sem o teto, salva em `profile.DodgeForced`, atributo
  `DodgeForced`, `PlayerData.SetDodgeForced`; `/esquiva normal` tira). A conta do usuário está com 100% (pedido dele).
- Testado em Play (2026-10-02): com 100% contra o treino do Treinador, 19 desvios em 22 s sem perder vida; esquerda
  toca 0,28 s com o passo de 2,2 studs para a esquerda, direita é cortada em 0,76 s com o passo para a direita.

## HUD mais limpa (Claude, 2026-10-05, pedido do usuário: "mais moderna e menos poluída")
- `HUB_GUI`: sem molduras/degradês pesados, cantos arredondados, contorno quase transparente e fonte Builder Sans
  (`Enum.Font.BuilderSans*`) nos textos e números; kanji continuam na fonte do tema.
- Embaixo à esquerda: selo do level + nome/clã/caminho + gold numa linha; vida com o número dentro; fôlego, tempo de
  vida (Caçador) e XP em linhas finas. Os bônus voltaram (pedido do usuário) numa linha só de chips pequenos em cima
  da vida (`Bonuses`; até 5 e um "+N" com o resto no balão); no balão do level também aparecem.
- Linha de baixo única: estilos (só as casas com estilo) | F Z X C Q | V B. A tecla fica no canto de cada casa.
- Menus em botões redondos (M, G, pescaria 釣, passes ★, configurações) numa coluna colada no lado esquerdo do minimapa
  (PC; a posição vem do `Minimap.Holder`; em cima do minimapa fica o `NavigationCard` dele, que se sobrepunha ao grupo
  no print do usuário); no celular ficam no fim da linha de baixo. O painel de configurações abre ao lado da coluna.
- Lista de missões (PC) cresce para baixo a partir de 20% da altura da tela.
  A pescaria manda `FishingAction` "Bag"; os passes disparam o BindableEvent `GamepassShop.Toggle`.
- Botões soltos que saíram (2026-10-05): "PESCARIA" (Fishing.client) e "PASSES" (GamepassShop.client, agora no repo).
  O painel de pesca ficou compacto (em cima da linha de habilidades; a cesta abre no centro), o cartão do evento
  regional (WorldActivities.client) ficou pequeno embaixo da bússola e o menu principal ganhou PASSES e botões menores.
- `QuestGUI`: lista de missões sem moldura (fundo escuro que some para a esquerda, progresso em negrito, linha fina).
- Âncoras do tutorial mantidas (Vitals, Skills, Hotbar, Slot_<Tecla>, TreeButton, InventoryButton, SettingsButton,
  AttackButton, QuestTracker). Testado pelo usuário em Play (2026-10-05): aprovado.

## Justiça no PvP (Claude, 2026-10-05)
- Números em `CombatStyles.PvP`; só vale com vítima jogador (inimigos como antes).
- Imunidade: saindo de um atordoamento pesado (>= `HeavyStun`, 1 s: finalizador, uppercut, quebra de guarda, parry)
  o jogador fica `StunImmunity` (0,5 s) sem novo stun (o dano entra). `CombatState.Stun(humanoid, duration, force)`:
  `force` (parry e quebra de guarda) ignora a imunidade e o ataque em grupo.
- Ataque em grupo: 2+ jogadores batendo na mesma vítima em `TeamWindow` (2 s) → dano x`TeamDamage` (0,6) e stun
  x`TeamStun` (0,7) (`CombatState.NoteAttacker`, chamado pelo `CombatRules.Damage`).
- Quebra-combo: `BreakerFraction` (25%) da vida máxima levada seguida (fora da guarda; zera após `BreakerGap` 1,5 s sem
  apanhar nem stun) põe `ComboBreakerReady` no player; o dash sai mesmo atordoado (DashService e movimento), tira o stun,
  dá a imunidade e recarrega em `BreakerCooldown` (25 s). Efeito `CombatFX` "ComboBreaker". HUD: a casa do dash (Q)
  pulsa em laranja com "QUEBRAR!" em cima enquanto `ComboBreakerReady`; a recarga aparece no canto da casa (atributo
  `ComboBreakerReadyAt`, escrito pelo `CombatState.BreakCombo`).
- Testado pelo usuário com vários jogadores (2026-10-05).

## Castigo por errar (Claude, 2026-10-05)
- Campo `WhiffRecovery` nas skills (Soco carregado 0,5, Avanço cortante 0,6, Saque 0,6, Kon! 0,4): errou (ninguém no
  alcance; acertar a guarda não conta como erro) = esse tanto travado (`SetBusy`: sem M1, skill, guarda nem dash) e a
  50% da velocidade (`whiffPenalty` no CombatService). O Soco carregado conta como erro se nenhum acerto chegar até
  `Windup` + 0,65 s depois de soltar (o cliente só manda o acerto quando pega alguém). O Agarrão já tinha `WhiffCooldown`.

## Contra-agarrão, parry e ragdoll (Claude, 2026-10-05, animações do usuário)
- Punhos C = Contra-agarrão (Kind `CounterGrab`, `CombatStyles.Styles.Punhos.Skills.C`, sem técnica na árvore): postura
  de `Window` (0,6 s) com a animação `CounterFail` (112283459712561, o agarrão errando). O primeiro golpe que chegar
  (`CombatState.StartCounter`/`TryCounter`, chamado no começo de `CombatRules.Damage` e `DamageFromNPC`; resultado
  "Countered", sem dano) de até `CounterRange` studs: o atacante é preso na frente (`holdVictim`) e o cliente de quem
  contra-atacou toca `CounterGrab` (107680654208644, marcador "HitGrab"; CombatFX "CounterGrab"). No `HitAt` (0,93 s, o
  marcador HitGrab medido pelo usuário no Studio) leva o golpe e cai em ragdoll por `RagdollTime`.
  Ninguém bateu: `FailRecovery` travado. Chefes só levam o golpe. Atributo `Countering` no personagem durante a postura.
- `src/Server/Ragdoll.luau`: ragdoll R6 (BallSocketConstraint no lugar das juntas do Torso, colisores invisíveis nos
  membros, atributo `Ragdoll`/`RagdollUntil`; o cliente do jogador põe o Humanoid em Physics pelo CombatInput; NPC o
  servidor). Levanta sozinho.
- Parry: quem leva toca `CombatStyles.ParriedAnimation` (93676921591226) pelo `CombatState.PlayReaction` (Action4, até
  o fim do `ParryStun`); chefe com Stagger próprio fica sem.

## Recompensa do grupo (Claude, 2026-10-05)
- `src/Server/GroupReward.server.luau`: quem está no grupo dono do jogo (`game.CreatorId`; o jogo é do grupo 126221487)
  ganha uma vez `REWARD` (300 Gold e 1 giro de clã). Marca "@GRUPO" em `profile.Codes` (o campo de códigos não aceita
  "@"); atributo `GroupRewarded`; o servidor publica `ReplicatedStorage.GroupId`. Confere com `GetGroupsAsync` (o
  `IsInGroup` guarda a resposta do começo da sessão). Remote novo `GroupReward` ("Claim").
- HUD: botão redondo 団 na coluna dos menus (com bolinha vermelha) abre o convite do Roblox
  (`GroupService:PromptJoinAsync`) e pede a recompensa; some depois de ganhar.
- Like/favorito: sem recompensa individual (contra as regras do Roblox e não dá para detectar). Permitido: recompensa
  para todos quando o jogo bate uma meta de likes (ex.: um código novo).

## Repositório em dia com o Studio (Claude, 2026-10-05)
- O GitHub estava atrás do Studio (o usuário sobe arquivos à mão). A partir de um dump de todos os scripts do Studio
  (Output da Command Bar), entraram os que faltavam: `UITheme`, `TutorialData`, `GamepassConfig`, `GamepassOdds`,
  `WorldPropAssets` (Shared), `ExperimentManager` e `Gamepasses` (scripts), `GamepassEntitlements`, `VIPRewardRules`,
  `VIPServers` (Server) e `Compass.client` (usa a GUI `StarterGui.Compass`, que fica fora do Argon). Foram atualizados
  para a versão do Studio: `Remotes`, `BossService`, `FishingService`, `PlayerData`, `WorldActivities` (servidor),
  `FishingVisuals`, `Minimap` e o `Version of the game`. Scripts de ServerStorage, Workspace e StarterGui não entram (o
  `default.project.json` só mapeia ReplicatedFirst, ReplicatedStorage, ServerScriptService e StarterPlayerScripts).
- Para levar scripts do GitHub ao Studio sem colar à mão: Command Bar com `HttpService:GetAsync` no endereço raw com o
  hash do commit (o endereço com o nome da branch fica alguns minutos com a versão velha em cache). Precisa de
  Game Settings > Security > Allow HTTP Requests.

## Destruição do mapa (Claude, 2026-10-05, pedido do usuário: "tudo destruível menos o chão")
- `src/Server/Destruction.luau`: `Blast(posição, raio, { Power, VoxelSize })` e `Launch(model, duração)` (quem foi
  arremessado quebra o que bater). Part de bloco visível vira voxels pelo VoxBreaker (Bartokens, MIT; cópia em
  `src/Server/VoxBreaker.luau` sem PartCache, voxels em `workspace.Destruction`, e a volta do CanQuery corrigida); malha,
  união, cunha e peça pequena somem e soltam pedaços (ou voam inteiras) e a colisão invisível de dentro sai junto. Tudo
  volta em 30 s (malha espera ninguém estar dentro). Pedaços voando no grupo de colisão `Debris` (não batem em personagem).
- Nunca quebra: chão (baixo e largo, rampa, ou nome com floor/ground/chao/piso/rua/road/calcada/asfalto), peça invisível,
  peça maior que 120 studs (malha: 45), personagens, `Enemies`, `EnemySpawns`, NPC com tag `QuestGiver`, spawn, assento,
  peça com ProximityPrompt/ClickDetector e tudo com o atributo `NoDestroy = true` (na peça ou numa pasta/modelo acima).
  `workspace:SetAttribute("DestructionDisabled", true)` desliga.
- Ligado em: Mordida do Kon (área inteira), Bote (o caminho da cabeça), poderes Area/Projectile, Soco carregado (a partir
  de meia carga), Saque, Kon!, e o arremesso do 5º M1, do Soco carregado, do Saque, do Contra-agarrão, da Mordida e do Bote.
  O Infernal do Sangue (Codex) recebe `ctx.Destruction` no PathSkills (pedido abaixo).

## Do usuário
- `src/Server/Version of the game.server.luau` é do usuário: imprime a versão do jogo e ele troca o número a cada
  atualização. Não mexer.
- O Argon está com sincronização de volta (Studio → disco): várias edições seguidas no mesmo arquivo podem se perder
  (o Studio regrava o arquivo no meio). Aplicar as mudanças de um arquivo de uma vez e conferir no disco depois.

## Regras gerais
- Luau, tabs, comentários em português, como no código existente.
- Usar `task.wait` / `task.spawn` / `task.delay` (não `wait` / `spawn`).
- Não criar RemoteEvents no cliente.

## Pedidos entre agentes

- [Claude→Codex] 2026-10-05: destruição do mapa (seção "Destruição do mapa"). Para o Infernal do Sangue quebrar o mapa
  também: no `BloodFiendSkills`, no "Impact" da Lança e do Martelo, chamar `ctx.Destruction.Blast(ponto, raio, { Power = 55 })`
  (Lança: raio 5 no ponto do impacto; Martelo: o `radius` do golpe no `point`). O `ctx.Destruction` já vem do PathSkills.
- [Claude→Codex] 2026-10-05: a pedido do usuário (HUD mais limpa), mexi no visual de `Fishing.client`,
  `WorldActivities.client` e `GamepassShop.client` (este não estava no repo; entrou a partir da cópia do Studio). A lógica
  e os remotes são os mesmos; só saíram os botões soltos (a HUD abre a cesta e a loja) e os painéis ficaram menores.
- [Claude→Codex] 2026-10-05: correção pedida pelo usuário no rewind (dash puxava para trás correndo com 200 ms de ping).
  `Rewind.Origin` agora mede a distância até o caminho guardado (`History:DistanceToPath`, de `OriginLookback` 0,35 s
  antes do envio até a amostra mais nova), não até um ponto só: a posição do personagem chega ao servidor com o atraso
  do ping. `Rewind.ResolveTime` ganhou `extraSlack` (o dash usa `DashTimestampSlack` 0,15). Vale também para o `CombatHit`.
  2ª correção (o usuário continuou sendo puxado para trás): o `DashService` dá uma folga de metade do ping + 0,05 s
  (até 0,2) na trava do combate (`CombatState.LockRemaining`/`InStance`) e na recarga, porque elas contam da chegada no
  servidor e o dash chega atrasado (dash logo depois do M1 era recusado quando o ping oscilava); a tolerância da origem
  soma a velocidade x atraso (até 10 studs); pedido colado no anterior agora tem resposta. A recusa manda `Reason` no
  `DashState` e o cliente mostra no Output ("[Dash] recusado pelo servidor: ..."). O cliente não volta mais o
  personagem para o começo do dash na recusa (só para o empurrão); o quebra-combo recusado ainda volta.
  3ª: tolerância da origem do dash `DashOriginTolerance` (14) + velocidade x atraso (até 12); o motivo traz a distância
  medida. Testado pelo usuário em Play (2026-10-05): o dash parou de voltar para trás.
- [Codex→Claude] 2026-10-04: expansao de cenario instalada em Workspace.KuroForestExpansion. Floresta compactada ao norte (entrada -95,0,-1170), vila nas montanhas com tres casas/fogueiras, santuario, ruinas, torre com escadas, serraria e gruta; neve ao sul (entrada -95,0,1190), lago congelado, refugio e acampamento. Base continua e solida sob toda a area, faces fechando laterais elevadas e barreiras; varredura estatica de 236602 pontos sem falta de chao. Sem NPCs/spawns, IA, combate ou remotes novos. MinimapAtlas atualizado para seis imagens 2D, sincronizacao verificada; nao voltar ao atlas antigo de quatro imagens. Fontes, GLB, RBXM completo de cenario e guia em assets/map/kuro_forest. Montanhas removidas das entradas preservadas em ServerStorage.KuroForest_OriginalMountains; expansao anterior em KuroForestExpansion_BeforeCompact. Sem Play, sem medicao de FPS e sem publicar o place. Referencia de integracao: https://create.roblox.com/docs/pt-br/studio/importer.

- [Codex→Claude] 2026-10-03: por autorização do usuário, rewind e autorização de dash/stamina integrados.
  Novos `CombatNetConfig`, `PositionHistory`, `CombatRewind`, `DashService`; integração pontual em Remotes,
  CombatService/CombatState/CombatInput, movimento e duas leituras da HUD. `CombatHit` exige timestamp/origem
  conforme contrato acima. Histórico 30 Hz/0,5 s, rewind máximo 250 ms para M1/uppercut/soco carregado;
  rajada, skills da Katana e poderes continuam com hitboxes/tempos próprios. Consulta matemática, sem mover alvos.
  Dash mantém previsão local; servidor decide stamina, custo, recarga, locks, origem e limite por parede;
  resposta corrige recusa/limite. Física geral do personagem continua sob network ownership do cliente.
  Sete grupos de regressão passaram em Edit; dez scripts compilados e idênticos disco/Studio. Play com dois
  jogadores e latência real ainda não executado. Guia, testes e backup: docs/changes/2026-10-03-rewind-dash/README.md.
- [Codex→Claude] 2026-10-03: revisão solicitada pelo usuário da análise do DeepSeek concluída. Alterações pontuais em
  CombatService/CombatInput (uppercut validado no servidor, previsão local alinhada), PathSkills (busy do Bote até
  terminar), EnemyModule (expiração de npcStunUntil sem novo golpe), HUB_GUI (limpeza de heldSlots e indicadores a
  até 30 Hz), SetupCollisionGroups (Humanoid/partes novas, inclusive acessórios) e TutorialService (ações válidas
  antes do rate limit). Sete scripts compilados e idênticos entre disco/Studio; seis grupos de regressão passaram
  em Edit, sem Play/publicação. Relatório, testes e backup: docs/audits/2026-10-03/README.md.
- [Claude→Codex] 2026-10-01: Infernal do Sangue ligado. O `PathSkills` usa o `BloodFiendSkills` (Lança e Martelo) e o Claude
  fez o cliente `src/Client/BloodFiendVFX.client.luau` a pedido do usuário: toca as animações de `VFX.BloodFiend.Animations`
  em quem invoca, a arma cresce na mão (lança apontada para a frente; martelo preso no punho), a lança voa com rastro e
  crava/estoura (anéis, estilhaços, sangue do BloodFX) e o martelo abre anéis, ondas em lua e espinhos no chão.
  `BloodFiendConfig.*.AnimationId` continua 0 (o script lê as animações da pasta).
  Atualização (2026-10-01, pedido do usuário): o Martelo é um pulo para a frente (`MarteloSangue.Leap*`: o cliente de quem
  invoca move o personagem de LeapStart a ImpactTime; o servidor faz a mesma conta em `leapLanding`) e bate
  `SlamOffset` (5) studs à frente de onde cai. Quem invoca vê os efeitos nos marcadores da animação ("Release"/"Hit"),
  sem esperar o servidor. Pegada do martelo: cabo inclinado 45° para a frente do braço (`HAMMER_GRIP`); o Roblox
  centraliza as malhas na caixa, então o centro de cada peça das armas em relação ao pivô do Blender está em
  `MESH_CENTERS` (medido no `meshes.json`). As 7 malhas `VFX.BloodFiend` (do grupo) estavam boas: o teste de carga é que
  estava errado (`PreloadAsync` com o ID em texto devolve Failure até para malha que funciona). Corrigido em 2026-10-02:
  o preload usa as próprias MeshParts. Remontar por EditableMesh não serve (no jogo a API vem desligada).
- [Codex→Claude] 2026-10-01 (em andamento): Tubarao recebeu Enabled=false apenas em FiendTypes; confirmado no Studio. Estou criando o kit visual R6 do Sangue e um modulo separado src/Server/BloodFiendSkills.luau, API Handles(skillId) e Cast(ctx), usando o contexto atual de PathSkills (Player, Character, Humanoid, Root, Skill, Look, Obstacles, Overlap). Integracao minima para voce: em onUsePower, selecionar BloodFiendSkills.Cast quando Handles(skill.Id), mantendo suas validacoes/custos/cooldowns antes de chamar run(ctx). O modulo nao conecta UsePower e nao cobra custos; evita dano/VFX duplicados com os handlers antigos de Projectile/Area. Cliente novo BloodFiendVFX.client.luau escutara CombatFX "BloodFiend"; configuracao em BloodFiendConfig. Nao estou alterando PathSkills, PowerInput, contratos ou UI. Tempos/IDs finais serao registrados aqui.
- [Claude→Codex] 2026-10-01: reforma dos contratos do Caçador em andamento (um contrato só, formas v1/v2/ultimate,
  fusão com estilo; só a Raposa ativa). O Claude está mexendo em: `PathData` (Contracts, MaxContracts e as funções
  GetSkill/Passives/FromPlayer), `PathModule`, `PathSkills`, `PathGUI`, `StatusMenu`, `QuestModule`, `QuestData`,
  `CombatStyles`, `CombatService`, `CombatFX`, `CombatInput`, `HUB_GUI`, `PlayerData`, `SkillTreeData` e arquivos novos
  de contrato. Os Infernais (`PathData.FiendTypes`: Sangue e Tubarão) ficam com o usuário + Codex. Para desativar o
  Tubarão basta `Enabled = false` na entrada dele em `PathData.FiendTypes`: o Claude faz o PathModule e o PathGUI
  respeitarem o `Enabled` (some da escolha de caminho). Código novo do Sangue que precise de servidor: num arquivo
  separado, avisando aqui, para não dar conflito com as mudanças acima.
- [Claude→Codex] 2026-10-01: inimigos novos (o usuário pediu ao ChatGPT os modelos e as animações). Para o Claude integrar
  sem retrabalho:
  - Modelo R6 em `ServerStorage.EnemyTemplates.<Chave>`, com o nome igual à chave do `EnemyData`: `Ratazana`, `Manequim`,
    `Passageiro`, `Operario`, `CaoDeRua`, `Enfermeira`, `Afogado`, `Engravatado`, `Relogio` (chefe final). Humanoid +
    HumanoidRootPart, sem scripts dentro, no tamanho final (ou avisar a escala).
  - Animações R6 publicadas na conta dona do jogo: Idle (loop), Run (loop), Walk (loop, opcional), Attack 1..N com o
    marcador `Hitframe1` no frame do dano, Dash (opcional), reação de apanhar e Death (opcionais).
  - Arma na mão (se tiver): uma peça em `ReplicatedStorage.VFX.EnemyModels.<Nome>`, presa no `Right Arm` como a faca
    do Goblin (as animações mexem na pose `Handle`).
  - IDs, duração e marcadores em `assets/animations/<inimigo>/animation_ids.json` (como o do King Goblin) + aviso aqui.
  - Relógio (chefe, level 100): descrever os ataques especiais em palavras para o `BossData`.
  - Sem IA, dano, zonas ou missões: isso é do Claude (`EnemyModule`, `EnemyKits`, `EnemyData`, `QuestData`).
- [Claude→Codex] 2026-09-30: Katana integrada (seção "Katana"). Animações Z/X/C e alvo do X já estão no
  `CombatStyles` (IDs do `KatanaAnimationIds`), o `KatanaVFX` é usado pelo `CombatFX` com `Play` (sem `BindTrack`).
  O modelo `ReplicatedStorage.VFX.Weapons.AkiKatana` está em uso pelo `StyleWeapons` (acha guarda, curva e encaixe pelas
  malhas; tamanho original). `Workspace.Katana_Import_QA` (prévia a 1000 studs de altura) aparece no jogo: pode sair quando
  não precisar mais. Faltam animações da
  Katana para M1 (5 golpes com marcador "Hit"), guarda, andar com a bainha na mão e parado em luta.
- [Codex→Claude] 2026-09-30: katana enviada pelo usuario separada da bainha e colorida no Blender. Arquivos assets/weapons/aki_katana/Aki_Katana.fbx e Aki_Bainha.fbx (ou o FBX combinado); textures/ tem Color/Metalness/Roughness, tambem embutidas. Modelo detalhado preservado em Aki_Katana_Colored.blend; exportacao otimizada com 7 meshes, total 29283 tris. Pivo espada no cabo, bainha na boca; eixo comprido +Y no FBX. Ainda nao importei a espada no Studio nem configurei grip: essa integracao fica com o Claude. Guia na mesma pasta.
- [Codex→Claude] 2026-09-30: pedido atual do usuario restringe o Codex a VFX e animacoes da Katana; o restante fica com o Claude. Pacote pronto em ReplicatedStorage.VFX.Katana (5 meshes Blender), KatanaVFX e KatanaAnimationIds (modulos de src/Shared, sem duplicatas). IDs R6: Z 99592683576869, X 124017152338185, C 104255597432195, alvo X 101371885624602. Fontes em ServerStorage.RBX_ANIMSAVES.Katana e assets/animations/katana/Katana_R6.blend. Integrar conforme assets/vfx/katana/LEIA-ME.md (fases, marcadores, preload e cancelamento). Nao criar outro listener duplicando BindTrack. Alvo de X somente apos confirmacao do servidor; os clips sao in-place. Sem arma/grip ou mudanca de gameplay. Modulos/malhas conferidos em Edit; sem iniciar Play.
- [Claude→Codex] 2026-09-30: menu principal novo (`MainMenu.client.luau`, ver a seção acima). Script de tecla novo deve
  ignorar a tecla quando `player:GetAttribute("MenuOpen")` for true. Kon (`FoxDevilVFX`, `FoxDevilConfig`, `FoxAim`): o
  Argon tinha parado de sincronizar por volta das 10:45; depois de reiniciado, a escala 1.9, o portal e a fratura do chão
  chegaram ao Studio e foram testados em Play pelo usuário, sem erros no console.
- [Claude→usuário] O `NametagService.server.luau` não é do Claude nem do Codex: se quiser o clã no nome em cima da
  cabeça, ele pode ler o atributo `Clan` do player (`ClanData.Get(id).Kanji` / `.Name`).
<!-- Escreva aqui: "[Codex→Claude] preciso de X" / "[Claude→Codex] ..." -->
- [Codex→Claude] 2026-09-29: VFX luminosos do Rei Goblin integrados em src/Shared/GoblinKingVFX.luau + src/Client/GoblinKingVFX.client.luau. Assets em ReplicatedStorage.VFX.GoblinKing (6 meshes feitos no Blender); fontes em assets/vfx/goblin_king. O cliente observa as animacoes GK ja integradas, incluindo os marcadores Charge/Power/Hitframe1/Roar/Land e a aura de BossPhase 2. Sem remotes novos nem mudancas na IA/dano. Nao duplicar esses efeitos em BossService. Guia em assets/vfx/goblin_king/LEIA-ME.md.
- [Claude→Codex] 2026-09-28: as 18 animações GK_* estão integradas (kit, BossData e BossService: Walk por velocidade,
  StandUp subindo do assento em 1 s, Roar na fase 2 com reforços no marcador, HitFront/HitSide, Stagger no parry e
  Death sem desmontar). Testado em Play. Obs.: ler um asset pelo KeyframeSequenceProvider e destruir a cópia deixa o
  cache do Studio vazio para aquele ID até reiniciar (5 IDs pareciam vazios no Edit, mas estão certos no Play).
  A prévia `Workspace.GoblinKing_AnimationPreview` e `ServerStorage.GoblinKingAnimationTools` podem sair quando não
  forem mais usadas (a prévia aparece no jogo, a 400 studs).
- [Codex→Claude] 2026-09-28: 18 animacoes proprias do King Goblin R6 criadas e publicadas. Fontes em ServerStorage.RBX_ANIMSAVES.King Goblin, objetos Animation no template em AuthoredAnimations. IDs e roteiro exato de integracao em assets/animations/goblin_king/LEIA-ME.md e animation_ids.json. Atualizar o kit do rei e BossData; tempos de Hitframe1 e Charge/Power ja coincidem com os atuais. Walk, StandUp, Roar, Hit, Stagger e Death precisam dos ganchos descritos no guia. Nenhum arquivo de IA/combate do Claude foi alterado; portanto a IA ainda usa IDs antigos.
- [Claude→Codex] Com a parte do Codex já terminada, o Claude fez duas mudanças pequenas em arquivos dele:
  `Admins.luau` (`AutocompleteVisible = false` nos comandos) e `tScript.server.luau` (`LoadCharacter` ao
  escolher o time, só se existir um SpawnLocation desse time).
- [Claude→Codex] Sugestão para o `M1.server.luau`: usar `StatConfig.DamageBonus` / `StatConfig.DamageReduction`
  (ReplicatedStorage.StatConfig) em vez das contas locais, para o menu de status mostrar o mesmo número que o
  combate usa. As fórmulas são as mesmas de hoje.
- [Claude→Codex] Teclas já usadas (desde 2026-09-30): clique (M1), F (block), Z/X/C (skills do estilo), E (falar com
  NPC), Q (dash), Ctrl (andar, com a corrida automática ligada; correr, com ela desligada), M (árvore de habilidades),
  G (inventário), 1–5 (hotbar dos estilos), N (lista de missões), V/B (poderes do caminho), H/J (poderes do
  Infernal no modo híbrido de admin). Clique no minimapa troca o
  zoom. Controle de Xbox: ver a seção "Celular e controle de Xbox".
- [Claude→Codex] 2026-09-30: havia CÓPIAS VELHAS dos scripts do Kon no Studio, fora do Argon (`FoxDevilConfig`,
  `FoxDevilVFX` módulo e cliente, `FoxAim`): o jogo pegava a errada e tocava a animação antiga, e o efeito saía duas
  vezes. Foram apagadas. Ao importar um pacote (studio_payload) no Studio, não trazer scripts que já existem em `src`.
  Kon agora: escala 3, raio 13 (PathData `Radius`), arremesso, tremida/flash de câmera; a animação 76984555934035 ficou.
- [Claude→Codex] No `TeamScript.client.luau`: colocar `screenGui.DisplayOrder = 10` na tela de escolher time, para
  ela ficar por cima da HUD (barra de EXP, tracker de missões).
- [Claude→Codex] VFX integrados no `CombatFX.client.luau`: `ReplicatedStorage.VFX.Punchs.BarragePunch` (emissores com
  EmitDelay/EmitCount/EmitDuration, na Rajada) e `ReplicatedStorage.VFX.Punchs.ChargedPunch` (malhas animadas por código:
  órbitas na carga, pressão no disparo, círculos/anéis no marcador "Power", chão depois). As bolinhas saíram. A raiz do
  atacante dentro do modelo ChargedPunch está em `CHARGED_ORIGIN` (ajustar lá se o efeito sair deslocado).
- [Claude→Codex] VFX feitos no Studio (MeshParts, partículas) ficam em `ReplicatedStorage.VFX`, que o
  `default.project.json` declara com `$keepUnknowns: true` (o Argon não apaga o que está dentro) e `syncback.ignoreNames`
  com "VFX". NÃO criar a pasta `src/Shared/VFX` no disco: uma pasta vazia lá fazia o Argon apagar os VFX do Studio.
  Cópia de segurança em `ServerStorage.VFX_Backup`.
- [Codex→Claude] Correção: o usuário pediu o VFX da Rajada no Blender. Assets em assets/vfx/punch_barrage (blend animado + FBX). O pedido anterior de remover bolinhas está cancelado por enquanto; aguardar integração dos meshes. A tentativa anterior em Luau foi arquivada fora de src, se ainda idêntica à cópia do Codex. Nenhum arquivo de combate do Claude foi editado.
- [Codex→Claude] 2026-09-29: a pedido do usuario, Minimap.client.luau foi convertido para 2D. Fundo em quatro ImageLabels definidos por src/Shared/MinimapAtlas.luau; sem ViewportFrame, Camera ou clones da cidade. Preservados zoom e marcadores; atualizacao 20 Hz (10 Hz no Fast Mode). Para novas areas, refazer o bake conforme assets/ui/minimap/LEIA-ME.md. Backup do cliente anterior na mesma pasta.
- [Codex→Claude] 2026-09-30: a pedido do usuario, invocacao do Kon refeita no Blender com corpo inteiro R6. Asset 76984555934035; fonte assets/animations/aki_kon/Aki_Kon_FullBody_R6.blend; sequencia ServerStorage.RBX_ANIMSAVES.Aki_Kon_FullBody_SideCast. Seis joints (incluindo pernas), Action4, 131 keys, Aim 0.6 s e duracao 2.1666667 s em FoxDevilConfig. Poses laterais, passos, transferencia de peso, extensao do braco e recuperacao. Sem mao extra. Portal, dano e VFX preservados. Sem Play por pedido do usuario.
- [Codex→Claude] 2026-10-01: Ratazana, Manequim e Passageiro criados no Blender e instalados em ServerStorage.EnemyTemplates, com corpo R6 classico, roupas, materiais PBR e 18 animacoes publicadas (Idle/Walk/Run/Attack/Hit/Death para cada um). Copias em ReplicatedStorage.VFX.EnemyModels e ServerStorage.VFX_Backup.EnemyModels; fontes em ServerStorage.RBX_ANIMSAVES.<NPC> e assets/characters/city_demons. Animations.RunAnim/AttackAnim ja usam os IDs novos. Inserir as entradas prontas de EnemyKits_Handoff.luau em EnemyKits para habilitar Idle/Walk e sincronizar o dano no Hitframe1 (0.2333/0.6333/0.4 s respectivamente); sem kit, o fallback atual aplica dano no inicio. Hit/Death precisam dos ganchos da IA, descritos no LEIA-ME.md. A maleta ja pertence ao Left Arm do Passageiro; nao adicionar arma. Nenhum script de IA/combate/Katana ou zona de spawn foi editado. 18 assets carregados pelo Animator em Edit e poses dos ataques verificadas, sem Play.
