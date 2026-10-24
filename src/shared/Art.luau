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
	-- XP gem (drawn Neon, coloured by tier)
	GEM = { mesh = "rbxassetid://82319770548580", tex = "rbxassetid://106570994593008", size = Vector3.new(0.62, 1.60, 0.57) },
	HARVEST = { mesh = "rbxassetid://71957833199002", tex = "rbxassetid://137686635194541", size = Vector3.new(5.00, 4.45, 3.80) },
	-- base stations and furniture (DD-056)
	ARMORY = { mesh = "rbxassetid://121893845271506", tex = "rbxassetid://129955545877203", size = Vector3.new(5.94, 7.00, 3.66) },
	BUILDDESK = { mesh = "rbxassetid://124355537983434", tex = "rbxassetid://108790107511088", size = Vector3.new(7.00, 6.50, 7.00) },
	BEACON = { mesh = "rbxassetid://109356532071460", tex = "rbxassetid://80652932562427", size = Vector3.new(2.74, 10.00, 2.79) },
	BOARD = { mesh = "rbxassetid://76491411634190", tex = "rbxassetid://88214790030886", size = Vector3.new(6.46, 7.00, 1.84) },
	RADAR = { mesh = "rbxassetid://89625350262556", tex = "rbxassetid://73147736121457", size = Vector3.new(6.00, 8.43, 4.85) },
	FLOODLIGHT = { mesh = "rbxassetid://116061092931530", tex = "rbxassetid://91763926511926", size = Vector3.new(3.00, 4.50, 1.20) },
	PLINTH = { mesh = "rbxassetid://123821428304518", tex = "rbxassetid://83838900429311", size = Vector3.new(4.04, 2.00, 4.05) },
}

-- Swarm species (DD-048): segmented generated creatures, one mesh per animated piece. Coordinates are
-- the generation's local space: feet on Y = 0, centred in X/Z, head toward -Z (the enemy's forward).
-- { name, mesh id, texture id, native size, centre }. Names drive roles in Creatures: legs, scythes and
-- pincers swing on the gait; sac/bulb pulse; everything else is body. Duplicate leg pieces the
-- generator stacked on top of another leg are left out.
local function cr(rows)
	local parts = {}
	for _, r in rows do
		table.insert(parts, { name = r[1], mesh = "rbxassetid://" .. r[2], tex = "rbxassetid://" .. r[3], size = r[4], pos = r[5] })
	end
	return parts
end
local V = Vector3.new

Art.Creatures = {
	RUNNER = cr({
		{ "body", "79251309640500", "100846688083497", V(2.183, 2.013, 3.282), V(0.000, 1.394, 0.000) },
		{ "head", "87598764553824", "73290927395456", V(1.229, 0.754, 0.668), V(0.006, 0.991, -1.197) },
		{ "front left leg", "113754034295169", "114784540287821", V(0.967, 0.952, 0.834), V(0.807, 0.494, 0.889) },
		{ "front right leg", "131802768970184", "97613932311500", V(1.064, 0.921, 0.930), V(0.895, 0.461, -0.894) },
		{ "back left leg", "84606766733351", "89904208383078", V(0.974, 0.934, 0.829), V(-0.813, 0.493, 0.886) },
		{ "back right leg", "136035202735243", "78429528343242", V(1.076, 0.928, 0.934), V(-0.889, 0.476, -0.898) },
	}),
	STALKER = cr({
		{ "body", "104416472663983", "82987823482500", V(0.934, 2.379, 1.977), V(-0.007, 1.538, 0.214) },
		{ "head", "104647430402975", "74909120544030", V(1.280, 0.967, 0.683), V(-0.009, 3.149, -0.861) },
		{ "left scythe", "138727802886593", "110225159499191", V(1.739, 1.844, 0.367), V(-0.930, 2.188, -0.506) },
		{ "right scythe", "128293604594652", "74720544037381", V(1.123, 1.849, 0.388), V(1.238, 2.186, -0.522) },
		{ "left hind leg", "93839172504868", "88039160860386", V(1.507, 1.696, 0.464), V(-0.929, 0.856, -0.271) },
		{ "right hind leg", "71163644523809", "128794354416985", V(1.497, 1.703, 0.472), V(0.927, 0.852, -0.270) },
		{ "left front leg", "128640138058968", "72358384234480", V(1.443, 1.051, 0.393), V(-0.774, 2.586, -0.519) },
		{ "right front leg", "131740400243116", "102526667314802", V(0.806, 0.567, 0.238), V(0.446, 2.333, -0.455) },
	}),
	SPITTER = cr({
		{ "body", "139120767508887", "103550814971941", V(2.601, 2.096, 3.272), V(0.012, 1.382, 0.736) },
		{ "sac", "75765783592417", "93653550505465", V(2.188, 2.226, 2.604), V(0.001, 3.287, 0.832) },
		{ "head", "78221639359852", "136873919842991", V(2.091, 1.965, 2.699), V(0.007, 1.486, -1.022) },
		{ "front left leg", "90174847725846", "122421112250371", V(0.882, 1.134, 0.790), V(-1.014, 0.567, -0.667) },
		{ "front right leg", "72639375156265", "126079163992230", V(0.845, 1.134, 0.781), V(1.015, 0.570, -0.673) },
		{ "back left leg", "78437341190689", "81977978116433", V(0.836, 1.112, 0.854), V(-1.015, 0.561, 1.569) },
		{ "back right leg", "72447867597129", "94975073241072", V(0.850, 1.082, 0.876), V(1.030, 0.549, 1.573) },
	}),
	BOMBER = cr({
		{ "body", "74419781068425", "78612781719665", V(1.977, 1.815, 2.002), V(0.007, 1.013, 0.138) },
		{ "bulb", "118897065366959", "77270730987013", V(1.817, 2.004, 2.140), V(0.008, 2.398, -0.050) },
		{ "head", "92800882466963", "125983666339863", V(1.794, 1.284, 1.348), V(0.005, 2.021, -0.465) },
		{ "front left leg", "136612059349352", "125542466154357", V(0.477, 0.645, 0.348), V(-0.900, 0.322, 0.108) },
		{ "front right leg", "120780348439323", "135010504676346", V(0.459, 0.872, 0.359), V(1.136, 1.043, 0.061) },
		{ "back left leg", "85835187596423", "84469425859382", V(0.474, 0.669, 0.361), V(0.901, 0.335, 0.123) },
		{ "back right leg", "76678922437282", "130661172795716", V(0.464, 0.863, 0.348), V(-1.133, 1.044, 0.075) },
	}),
	BULWARK = cr({
		{ "body", "108668366624906", "84698681763618", V(4.225, 3.488, 4.566), V(0.000, 1.786, 0.000) },
		{ "shield", "108568921609836", "136554384748757", V(3.311, 2.518, 3.194), V(0.002, 2.741, 0.464) },
		{ "front left leg", "121523052887196", "95817823495736", V(0.603, 0.960, 0.649), V(1.038, 0.480, 1.462) },
		{ "front right leg", "133791239904304", "88059131331299", V(0.614, 0.956, 0.675), V(-1.042, 0.494, 1.460) },
		{ "middle left leg", "87468135339729", "86834956118605", V(0.591, 0.952, 0.645), V(1.042, 0.484, -1.483) },
		{ "middle right leg", "74936119760408", "132069499923141", V(0.683, 0.953, 0.556), V(-1.716, 0.486, 0.522) },
		{ "back left leg", "125481749304282", "74296468418446", V(0.655, 0.956, 0.553), V(1.704, 0.488, 0.519) },
		{ "back right leg", "84618436633129", "100918913513943", V(0.606, 0.946, 0.668), V(-1.036, 0.496, -1.477) },
	}),
	ELITE = cr({
		{ "body", "77683789659772", "97672707145228", V(4.022, 3.271, 4.401), V(-0.010, 2.920, 0.278) },
		{ "horn crest", "108790695448074", "98510196921988", V(3.211, 2.985, 1.817), V(-0.002, 5.007, -1.088) },
		{ "front left leg", "97880523921212", "131698981090765", V(1.906, 2.422, 1.929), V(1.725, 1.212, 1.727) },
		{ "front right leg", "76470940908546", "137590381839695", V(1.953, 2.419, 1.972), V(1.719, 1.210, -1.706) },
		{ "back left leg", "71580661682657", "79187539360260", V(1.919, 2.425, 1.944), V(-1.736, 1.213, 1.711) },
		{ "back right leg", "136109167287413", "136111449854406", V(1.921, 2.409, 1.974), V(-1.722, 1.204, -1.696) },
	}),
	ALPHA = cr({
		{ "body", "75037538599178", "140568338567919", V(2.776, 4.235, 4.876), V(-0.003, 3.247, -0.300) },
		{ "tail", "88502232756677", "114468230016806", V(2.029, 4.413, 2.194), V(0.005, 3.794, 2.350) },
		{ "left claw", "84848117858875", "94748914757947", V(1.491, 2.241, 2.284), V(-1.452, 2.404, -2.304) },
		{ "right claw", "83895642070485", "95182399349652", V(1.500, 2.236, 2.280), V(1.447, 2.415, -2.300) },
		{ "front left leg", "123926965378670", "106193296158377", V(1.260, 2.036, 1.302), V(-1.241, 1.018, -1.660) },
		{ "front right leg", "93151737850727", "85316680439773", V(1.238, 2.037, 1.304), V(1.239, 1.034, -1.659) },
		{ "back left leg", "84090897524441", "76820610885193", V(1.261, 2.042, 1.406), V(-1.238, 1.024, 0.575) },
		{ "back right leg", "129624017978789", "122471880023256", V(1.253, 2.041, 1.394), V(1.242, 1.023, 0.564) },
	}),
	BROOD = cr({
		{ "body", "117418773393349", "116354646586824", V(5.362, 7.125, 5.739), V(0.006, 8.438, 0.871) },
		{ "abdomen", "115049681537125", "130161468386583", V(3.993, 4.474, 5.349), V(0.005, 3.831, -0.657) },
		{ "left front legs", "115893872746258", "120889181810677", V(5.018, 6.058, 4.120), V(-3.928, 3.070, -3.264) },
		{ "left back legs", "87443191106755", "90885594608037", V(5.601, 6.654, 5.888), V(-3.658, 3.412, 2.404) },
		{ "right front legs", "132101391668505", "83354086395147", V(5.029, 6.122, 4.160), V(3.935, 3.061, -3.268) },
		{ "right back legs", "129152429420112", "78679056036372", V(5.595, 6.640, 5.890), V(3.661, 3.419, 2.395) },
	}),
}

-- Every creature piece is also an art template (key CR_<SPECIES>_<i>), so ArtLoader loads it.
for species, parts in Art.Creatures do
	for i, p in parts do
		Art.Meshes["CR_" .. species .. "_" .. i] = { mesh = p.mesh, tex = p.tex, size = p.size }
	end
end

-- Terrain material variants (generated PBR sets; the MaterialVariants themselves are in
-- default.project.json), applied as base-material overrides at server start.
Art.Materials = {
	{ name = "SporeSoil", base = Enum.Material.Ground },
	{ name = "SporeMoss", base = Enum.Material.Grass },
	{ name = "SporeBasalt", base = Enum.Material.Basalt },
	{ name = "SporeCliff", base = Enum.Material.Slate },
}

return Art
