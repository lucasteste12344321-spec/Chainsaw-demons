-- Inicializa os sistemas de servidor que são módulos.
-- Ordem: dados do jogador, depois caminhos (precisa dos perfis), depois missões (usa os dois).
local ServerScriptService = game:GetService("ServerScriptService")

require(ServerScriptService:WaitForChild("PlayerData")).Init()
require(ServerScriptService:WaitForChild("PathModule")).Init()
require(ServerScriptService:WaitForChild("ContractService")).Init()
require(ServerScriptService:WaitForChild("QuestModule")).Init()
