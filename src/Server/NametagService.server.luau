local Players = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")

local NametagBillboard = script:WaitForChild("Nametag")


local Config = {

	-- Roblox Plus
	ShowRobloxPlus = true,
	PlusIcon = "",

	-- Verified Badge
	ShowVerifiedBadge = true,
	VerifiedIcon = "",

	-- Players in this list also receive the Verified icon.
	AdminVerified = {
		[3496725636] = true,
	},


	ShowCountryFlag = true,
	CountryStyle = "FLAG",

	-- Titles
	ShowTitles = true,

	Titles = {

		[312312332] = {
			Text = "Owner",
			Color = "#FF5555"
		},

		[987654321] = {
			Text = "Developer",
			Color = "#55AAFF"
		},

		[111111111] = {
			Text = "Admin",
			Color = "#FFD700"
		},

	},
}


local ActiveTags = {}
local CountryCache = {}
local CountryLoading = {}
local InitializedPlayers = {}


local function hexToColor3(hex)
	if type(hex) ~= "string" then
		return Color3.fromRGB(255, 255, 255)
	end

	hex = hex:gsub("#", "")

	if #hex ~= 6 then
		warn("[NametagsV2] Invalid HEX color: " .. tostring(hex))
		return Color3.fromRGB(255, 255, 255)
	end

	local red = tonumber(hex:sub(1, 2), 16)
	local green = tonumber(hex:sub(3, 4), 16)
	local blue = tonumber(hex:sub(5, 6), 16)

	if not red or not green or not blue then
		warn("[NametagsV2] Invalid HEX color: " .. tostring(hex))
		return Color3.fromRGB(255, 255, 255)
	end

	return Color3.fromRGB(red, green, blue)
end


local function countryCodeToFlag(countryCode)
	if type(countryCode) ~= "string" then
		return ""
	end

	countryCode = string.upper(countryCode)

	if #countryCode ~= 2 then
		return ""
	end

	local first = string.byte(countryCode, 1)
	local second = string.byte(countryCode, 2)

	if not first or not second then
		return ""
	end

	if first < 65 or first > 90 or second < 65 or second > 90 then
		return ""
	end

	local regionalIndicatorA = 0x1F1E6

	return utf8.char(
		regionalIndicatorA + (first - 65),
		regionalIndicatorA + (second - 65)
	)
end


local function formatCountry(countryCode)
	if not countryCode or countryCode == "" then
		return ""
	end

	if Config.CountryStyle == "CODE" then
		return "[" .. string.upper(countryCode) .. "]"
	end

	return countryCodeToFlag(countryCode)
end


local function isVerified(player)
	if player.HasVerifiedBadge then
		return true
	end

	if Config.AdminVerified[player.UserId] then
		return true
	end

	return false
end


local function getPlayerTitle(player)
	if not Config.ShowTitles then
		return nil
	end

	return Config.Titles[player.UserId]
end


local function updateNametag(player)
	local tag = ActiveTags[player]

	if not tag or not tag.Parent then
		return
	end

	local usernameLabel = tag:FindFirstChild("Username")
	local titleLabel = tag:FindFirstChild("Title")

	if not usernameLabel then
		return
	end

	local nameParts = {
		player.DisplayName
	}


	if Config.ShowRobloxPlus and player.HasRobloxSubscription then
		table.insert(nameParts, Config.PlusIcon)
	end


	if Config.ShowVerifiedBadge and isVerified(player) then
		table.insert(nameParts, Config.VerifiedIcon)
	end


	if Config.ShowCountryFlag then
		local countryCode = CountryCache[player.UserId]

		if countryCode and countryCode ~= "" then
			local countryDisplay = formatCountry(countryCode)

			if countryDisplay ~= "" then
				table.insert(nameParts, countryDisplay)
			end
		end
	end


	usernameLabel.Text = table.concat(nameParts, " ")


	if titleLabel then
		local titleData = getPlayerTitle(player)

		if titleData then
			titleLabel.Text = titleData.Text or ""
			titleLabel.TextColor3 = hexToColor3(titleData.Color or "#FFFFFF")
			titleLabel.Visible = true
		else
			titleLabel.Text = ""
			titleLabel.Visible = false
		end
	end
end


local function loadCountry(player)
	if not Config.ShowCountryFlag then
		return
	end

	local userId = player.UserId

	if CountryCache[userId] ~= nil then
		updateNametag(player)
		return
	end

	if CountryLoading[userId] then
		return
	end

	CountryLoading[userId] = true

	task.spawn(function()
		local success, countryCode = pcall(function()
			return LocalizationService:GetCountryRegionForPlayerAsync(player)
		end)

		CountryLoading[userId] = nil

		if success and countryCode then
			CountryCache[userId] = countryCode
		else
			CountryCache[userId] = ""

			warn(
				"[NametagsV2] Could not load country for "
					.. player.Name
			)
		end

		updateNametag(player)
	end)
end


local function onCharacterAdded(player, character)
	local head = character:WaitForChild("Head", 10)

	if not head then
		warn("[NametagsV2] Could not find Head for " .. player.Name)
		return
	end

	local oldTag = head:FindFirstChild("CustomNametag")

	if oldTag then
		oldTag:Destroy()
	end

	local newTag = NametagBillboard:Clone()

	newTag.Name = "CustomNametag"
	newTag.Parent = head

	ActiveTags[player] = newTag

	local usernameLabel = newTag:FindFirstChild("Username")

	if usernameLabel then
		usernameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		usernameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	end

	updateNametag(player)
	loadCountry(player)
end


local function onPlayerAdded(player)
	if InitializedPlayers[player] then
		return
	end

	InitializedPlayers[player] = true

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	player:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(function()
		updateNametag(player)
	end)

	player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		updateNametag(player)
	end)

	player:GetPropertyChangedSignal("HasVerifiedBadge"):Connect(function()
		updateNametag(player)
	end)

	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end


Players.PlayerRemoving:Connect(function(player)
	ActiveTags[player] = nil
	InitializedPlayers[player] = nil

	CountryCache[player.UserId] = nil
	CountryLoading[player.UserId] = nil
end)


Players.PlayerAdded:Connect(onPlayerAdded)


for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end