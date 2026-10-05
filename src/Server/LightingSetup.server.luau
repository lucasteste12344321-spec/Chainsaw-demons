-- Preset de gráficos do jogo (vale para todos): tarde com sol quente, neblina de cidade, brilho, cor de filme
-- (contraste alto, um pouco dessaturado), raios de sol, desfoque leve no fundo e nuvens.
-- O Fast Mode de cada jogador desliga o que é pesado só no cliente dele.
--
-- No Studio (script não consegue mudar): Lighting > LightingStyle = Realistic e PrioritizeLightingQuality ligado.
-- Para usar a iluminação feita à mão no Studio em vez deste preset: atributo KeepStudioLighting = true no Lighting.
local Lighting = game:GetService("Lighting")

local PRESET = {
	Lighting = {
		ClockTime = 14.5,
		GeographicLatitude = 35,
		Brightness = 3,
		ExposureCompensation = 0.15,
		Ambient = Color3.fromRGB(30, 24, 26),
		OutdoorAmbient = Color3.fromRGB(128, 118, 120),
		ColorShift_Top = Color3.fromRGB(255, 232, 205),
		ColorShift_Bottom = Color3.fromRGB(40, 20, 22),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		GlobalShadows = true,
		ShadowSoftness = 0.2,
		FogEnd = 100000,
	},
	-- [classe] = propriedades (usa o que já existe no Lighting ou cria)
	Effects = {
		Atmosphere = {
			Density = 0.3,
			Offset = 0.2,
			Color = Color3.fromRGB(205, 190, 185),
			Decay = Color3.fromRGB(110, 85, 85),
			Glare = 0.35,
			Haze = 1.4,
		},
		BloomEffect = {
			Enabled = true,
			Intensity = 0.7,
			Size = 28,
			Threshold = 1.5,
		},
		ColorCorrectionEffect = {
			Enabled = true,
			Brightness = 0.02,
			Contrast = 0.14,
			Saturation = -0.06,
			TintColor = Color3.fromRGB(255, 244, 238),
		},
		SunRaysEffect = {
			Enabled = true,
			Intensity = 0.07,
			Spread = 0.75,
		},
		DepthOfFieldEffect = {
			Enabled = true,
			FarIntensity = 0.15,
			FocusDistance = 40,
			InFocusRadius = 90,
			NearIntensity = 0,
		},
	},
	Clouds = {
		Cover = 0.6,
		Density = 0.55,
		Color = Color3.fromRGB(235, 232, 236),
	},
}

local function apply(instance, properties)
	for property, value in properties do
		local ok, err = pcall(function()
			instance[property] = value
		end)
		if not ok then
			warn(`[LightingSetup] {instance.ClassName}.{property}: {err}`)
		end
	end
end

if Lighting:GetAttribute("KeepStudioLighting") == true then
	print("[LightingSetup] KeepStudioLighting ligado: usando a iluminação do Studio")
	return
end

apply(Lighting, PRESET.Lighting)

for className, properties in PRESET.Effects do
	local effect = Lighting:FindFirstChildOfClass(className)
	if not effect then
		effect = Instance.new(className)
		effect.Parent = Lighting
	end
	apply(effect, properties)
end

local terrain = workspace:FindFirstChildOfClass("Terrain")
if terrain then
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = terrain
	end
	apply(clouds, PRESET.Clouds)
end

-- Aviso se o estilo de iluminação não for o de melhor qualidade (só dá para mudar no Studio)
local ok, realistic = pcall(function()
	return Lighting.LightingStyle == Enum.LightingStyle.Realistic
end)
if ok and not realistic then
	warn("[LightingSetup] Para a melhor qualidade: Lighting > LightingStyle = Realistic e PrioritizeLightingQuality ligado (no Studio)")
end
