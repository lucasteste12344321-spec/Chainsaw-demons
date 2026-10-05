
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FastMode = require(script.Parent:WaitForChild("FastMode"))

local module = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("SmartBone", 30)
if not module then
	warn("[SmartBone] Módulo não encontrado em ReplicatedStorage.VFX.SmartBone: cabelos sem física")
	return
end

local okRequire, SmartBone = pcall(require, module)
if not okRequire then
	warn("[SmartBone] " .. tostring(SmartBone))
	return
end

local runtime -- instância devolvida por SmartBone.Start() (tem Stop())

local function apply()
	if FastMode.IsEnabled() then
		if runtime then
			pcall(runtime.Stop)
			runtime = nil
		end
	elseif not runtime then
		local ok, result = pcall(SmartBone.Start)
		if ok then
			runtime = result
		else
			warn("[SmartBone] " .. tostring(result))
		end
	end
end

FastMode.Changed:Connect(apply)
apply()
