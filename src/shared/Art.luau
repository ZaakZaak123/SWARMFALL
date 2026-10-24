--!strict
-- SPOREFALL art set (DD-042): AI-generated textured meshes (Roblox Studio generation), referenced by
-- asset id. The server turns them into templates at start (ArtLoader -> ReplicatedStorage.ArtTemplates);
-- the arena, structures, FX and enemies clone those. Anything that fails to load falls back to the
-- procedural primitive version, so a missing asset never breaks a run.
-- size = the generated mesh's native size (studs); placements scale from it.

local Art = {}

Art.Meshes = {
	MUSHROOM = { mesh = "rbxassetid://127176737419976", tex = "rbxassetid://115346285824557", size = Vector3.new(19.45, 26.00, 19.56) },
	BLOOM = { mesh = "rbxassetid://89615528547561", tex = "rbxassetid://76787471648665", size = Vector3.new(26.00, 38.60, 25.91) },
	RIB = { mesh = "rbxassetid://76552285360656", tex = "rbxassetid://92198972359951", size = Vector3.new(17.89, 34.00, 5.45) },
	BOULDER = { mesh = "rbxassetid://107685891222586", tex = "rbxassetid://134921464973189", size = Vector3.new(9.31, 9.00, 7.92) },
	EXTRACTOR = { mesh = "rbxassetid://127921250773990", tex = "rbxassetid://128477091016348", size = Vector3.new(11.13, 24.00, 13.42) },
	DROPSHIP = { mesh = "rbxassetid://129613490677370", tex = "rbxassetid://125291318160921", size = Vector3.new(19.27, 14.00, 20.59) },
	CRYSTALS = { mesh = "rbxassetid://112145949782550", tex = "rbxassetid://136220619906967", size = Vector3.new(14.00, 16.33, 13.87) },
	SKULL = { mesh = "rbxassetid://82192057619826", tex = "rbxassetid://81798771343243", size = Vector3.new(33.47, 32.00, 34.13) },
	SPIRE = { mesh = "rbxassetid://94986255398164", tex = "rbxassetid://126474191942050", size = Vector3.new(13.82, 29.45, 14.00) },
	CORAL = { mesh = "rbxassetid://92825752917091", tex = "rbxassetid://127925072991301", size = Vector3.new(5.00, 4.21, 4.85) },
	SHROOMS = { mesh = "rbxassetid://130822987044504", tex = "rbxassetid://128593386257525", size = Vector3.new(2.52, 3.00, 3.02) },
	VERTEBRA = { mesh = "rbxassetid://134075089674530", tex = "rbxassetid://114885826516165", size = Vector3.new(4.31, 4.00, 4.31) },
	NEST = { mesh = "rbxassetid://117090663428529", tex = "rbxassetid://72630042741257", size = Vector3.new(10.82, 7.46, 11.00) },
	POD = { mesh = "rbxassetid://128575161451927", tex = "rbxassetid://123339923204332", size = Vector3.new(2.47, 4.00, 2.47) },
	PYLON = { mesh = "rbxassetid://101158805342441", tex = "rbxassetid://70501120745256", size = Vector3.new(5.00, 8.63, 4.77) },
	-- the Devourer (head mouth along -Z, segment ring along Z) and objective props
	WORM_HEAD = { mesh = "rbxassetid://79671816990444", tex = "rbxassetid://105313698074617", size = Vector3.new(12.00, 11.47, 13.85) },
	WORM_SEG = { mesh = "rbxassetid://74734924143594", tex = "rbxassetid://102711938528429", size = Vector3.new(10.00, 10.00, 5.79) },
	ACID_MOUND = { mesh = "rbxassetid://139925648626653", tex = "rbxassetid://110939098198125", size = Vector3.new(10.00, 3.88, 8.55) },
	NODE = { mesh = "rbxassetid://72526567722949", tex = "rbxassetid://78275345757328", size = Vector3.new(7.00, 11.88, 6.99) },
	-- outpost structures
	STING = { mesh = "rbxassetid://80090267900953", tex = "rbxassetid://103192068127186", size = Vector3.new(2.19, 5.00, 3.33) },
	ARC = { mesh = "rbxassetid://98095369516956", tex = "rbxassetid://79042425410058", size = Vector3.new(4.46, 8.00, 4.37) },
	MORTAR = { mesh = "rbxassetid://111403659986596", tex = "rbxassetid://139055413227105", size = Vector3.new(3.31, 5.00, 5.15) },
	SHIELD = { mesh = "rbxassetid://76777776984180", tex = "rbxassetid://130063375754441", size = Vector3.new(3.98, 8.46, 4.00) },
	HARVEST = { mesh = "rbxassetid://71957833199002", tex = "rbxassetid://137686635194541", size = Vector3.new(5.00, 4.45, 3.80) },
}

-- Terrain material variants (generated PBR sets; the MaterialVariants themselves are in
-- default.project.json), applied as base-material overrides at server start.
Art.Materials = {
	{ name = "SporeSoil", base = Enum.Material.Ground },
	{ name = "SporeMoss", base = Enum.Material.Grass },
	{ name = "SporeBasalt", base = Enum.Material.Basalt },
	{ name = "SporeCliff", base = Enum.Material.Slate },
}

return Art
