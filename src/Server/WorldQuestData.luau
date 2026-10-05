-- Side content uses the existing quest journal, completion flow and player save.
local Data = {}
Data.ObjectiveTypes = { Collect = true, Explore = true, Fish = true, WorldEvent = true }
Data.NPCs = {
	KuroYui = "Messenger Yui", KuroMika = "Ranger Mika", KuroRen = "Carpenter Ren",
	KuroHana = "Caretaker Hana", KuroSora = "Mountaineer Sora", KuroNori = "Cook Nori",
	KuroIori = "Researcher Iori", KuroDaichi = "Fisherman Daichi",
}
Data.Greetings = {
	KuroYui = { Available = "The roads are open again. I need to know who is still out there.", Active = "Did you find our villagers?", Idle = "Got a letter? I will deliver it." },
	KuroMika = { Available = "The forest seems calm. That is what worries me. Can you check a few places?", Active = "Follow the trails and come back in one piece.", Idle = "Urgent requests show up on the regional board." },
	KuroRen = { Available = "Without my tools, this sawmill will not run again.", Active = "Look for the marked cases near the riverbank.", Idle = "Good wood and willing people. That is what we need." },
	KuroHana = { Available = "The lanterns go out every time the fog rolls in. Bring what is missing to light them.", Active = "The offerings are scattered through the grove.", Idle = "Do not answer if you hear your name among the trees." },
	KuroSora = { Available = "I found an entrance in the mountain. I need someone with a sharp eye.", Active = "The grotto is above the last house.", Idle = "Up high you can hear the city breathe." },
	KuroNori = { Available = "The shelter is cold and the pot is empty. Any help counts.", Active = "The campfire marks the way back.", Idle = "A hot meal saves lives too." },
	KuroIori = { Available = "The water flows through the same places as the devils. I want to understand why.", Active = "The samples need to come from three different spots.", Idle = "There are a lot of strange things living in this river." },
	KuroDaichi = { Available = "Devils are not the only thing that bites around here. Want to learn to fish? Press R near me to get your rod.", Active = "Hook it when the bobber sinks. Reel in without snapping the line.", Idle = "Press R near me to see your fish, sell them or upgrade your rod." },
}
local function objective(kind, target, amount, text)
	return { Type = kind, Target = target, Amount = amount, Text = text }
end
local function back(npc)
	return objective("TalkTo", npc, 1, "Return to " .. Data.NPCs[npc])
end
Data.Quests = {
	{ Id = "Side_OpenRoads", Name = "People Beyond the Walls", Giver = "KuroYui", MinLevel = 1,
		Description = "Visit Mika at the forest lodge and Ren at the sawmill. Then bring news to Yui at the forest entrance.",
		Objectives = { objective("Explore", "RangersLodge", 1, "Find Mika at the lodge"), objective("Explore", "RiversideSawmill", 1, "Find Ren at the sawmill"), back("KuroYui") }, Rewards = { XP = 180, Gold = 65 } },
	{ Id = "Side_ForestSurvey", Name = "Mika's Rounds", Giver = "KuroMika", MinLevel = 1,
		Description = "Climb the watchtower and visit the old camp. The trail markers show the way.",
		Objectives = { objective("Explore", "Watchtower", 1, "Climb the watchtower"), objective("Explore", "ForestCamp", 1, "Visit the camp"), back("KuroMika") }, Rewards = { XP = 280, Gold = 90 } },
	{ Id = "Side_LostTools", Name = "Tools in the Current", Giver = "KuroRen", MinLevel = 3,
		Description = "Recover three different tool cases between the sawmill and the pier.",
		Objectives = { objective("Collect", "ToolCase", 3, "Tool cases recovered"), back("KuroRen") }, Rewards = { XP = 300, Gold = 110 } },
	{ Id = "Side_ShrineOfferings", Name = "Before It Gets Dark", Giver = "KuroHana", MinLevel = 3,
		Description = "Gather three offering bundles in the shrine grove and bring them back to Hana.",
		Objectives = { objective("Collect", "Offering", 3, "Offerings found"), back("KuroHana") }, Rewards = { XP = 320, Gold = 100 } },
	{ Id = "Side_MountainEcho", Name = "The Mountain's Echo", Giver = "KuroSora", MinLevel = 5,
		Description = "Explore inside the grotto and collect two mineral samples. Return to Sora's house in the village.",
		Objectives = { objective("Explore", "MountainGrotto", 1, "Explore the grotto"), objective("Collect", "OreSample", 2, "Mineral samples"), back("KuroSora") }, Rewards = { XP = 460, Gold = 140 } },
	{ Id = "Side_WarmShelter", Name = "A Place to Warm Up", Giver = "KuroNori", MinLevel = 3,
		Description = "Fetch three bundles of firewood near the frozen lake to stock the shelter.",
		Objectives = { objective("Collect", "Firewood", 3, "Firewood bundles"), back("KuroNori") }, Rewards = { XP = 330, Gold = 100 } },
	{ Id = "Side_RiverSamples", Name = "What the River Hides", Giver = "KuroIori", MinLevel = 4,
		Description = "Use the three marked sampling spots on the Kuro River: the spring, the pier and the sawmill bend.",
		Objectives = { objective("Collect", "WaterSample", 3, "River spots sampled"), back("KuroIori") }, Rewards = { XP = 350, Gold = 120 } },
	{ Id = "Side_FirstCatch", Name = "Not Everything Is Solved with Fists", Giver = "KuroDaichi", MinLevel = 1,
		Description = "Get the free rod from Daichi (R), press E at a fishing spot and catch three fish. They stay in your fishing basket.",
		Objectives = { objective("Fish", nil, 3, "Fish caught"), back("KuroDaichi") }, Rewards = { XP = 240, Gold = 80 } },
	{ Id = "Side_HotSupper", Name = "Supper at the End of the World", Giver = "KuroNori", MinLevel = 5, Requires = { "Side_WarmShelter" },
		Description = "Catch two carp and one trout to learn Nori's recipe. The fish you catch stay in your basket.",
		Objectives = { objective("Fish", "RiverCarp", 2, "Carp caught"), objective("Fish", "Trout", 1, "Trout caught"), back("KuroNori") }, Rewards = { XP = 420, Gold = 140 } },
	{ Id = "Side_ScarletKoi", Name = "A Red Flash in the Water", Giver = "KuroDaichi", MinLevel = 5, Requires = { "Side_FirstCatch" },
		Description = "Daichi saw a scarlet koi. Try the active schools of fish; better rods help too.",
		Objectives = { objective("Fish", "Koi", 1, "Scarlet koi caught"), back("KuroDaichi") }, Rewards = { XP = 500, Gold = 180 } },
	{ Id = "Side_RiverCleanup", Name = "The River Is Not a Dump", Giver = "KuroDaichi", MinLevel = 1, Repeatable = true,
		Description = "Pick up four bags of trash along the banks. Each spot can be used once per quest and takes a while to refill.",
		Objectives = { objective("Collect", "Litter", 4, "Trash collected"), back("KuroDaichi") }, Rewards = { XP = 160, Gold = 55 } },
	{ Id = "Side_RegionalHelp", Name = "When the Region Calls", Giver = "KuroMika", MinLevel = 3, Repeatable = true,
		Description = "Join an active regional request. Make at least two deliveries or repairs and help the group finish before time runs out.",
		Objectives = { objective("WorldEvent", nil, 1, "Regional request completed with your help"), back("KuroMika") }, Rewards = { XP = 260, Gold = 90 } },
}
Data.Events = {
	{ Id = "ShrineLights", Name = "Lights Against the Fog", Region = "Shrine", Action = "Light lantern", Goal = 8, XP = 100, Gold = 35, Description = "Light the shrine's marked lanterns." },
	{ Id = "SawmillSupplies", Name = "The Sawmill Needs Help", Region = "Sawmill", Action = "Deliver wood", Goal = 8, XP = 110, Gold = 40, Carry = true, Description = "Take wood from the piles and deliver it to the sawmill depot." },
	{ Id = "SnowSupplies", Name = "Shelter Before the Blizzard", Region = "Snow", Action = "Stock the shelter", Goal = 8, XP = 120, Gold = 45, Carry = true, Description = "Carry supplies from the camp to Nori's shelter." },
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
