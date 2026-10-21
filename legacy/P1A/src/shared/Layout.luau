--!strict
-- Canonical geometry for both build.py and gameplay. Axis-aligned solid bounds.
return {
	HalfX = 180, HalfZ = 160,
	Obstacles = {
		{"CoreCoverW", -23, 0, 8, 8, 5}, {"CoreCoverE", 23, 0, 8, 8, 5},
		{"ConduitW1", -30, 65, 8, 18, 7}, {"ConduitE1", 30, 65, 8, 18, 7},
		{"ConduitW2", -30, 108, 8, 18, 7}, {"ConduitE2", 30, 108, 8, 18, 7},
		{"RailsNorth", 112, 30, 18, 8, 5}, {"RailsSouth", 112, -30, 18, 8, 5},
		{"RefineryW", -34, -94, 18, 18, 9}, {"RefineryE", 34, -94, 18, 18, 9},
		{"RefineryCenter", 0, -125, 8, 8, 6},
		{"HangarNW", -125, 31, 18, 8, 8}, {"HangarSW", -125, -31, 18, 8, 8},
		{"HangarCargo", -103, 0, 8, 18, 6},
	},
	Spawns = {
		{"N", 0, 145}, {"E", 165, 0}, {"NE", 125, 130}, {"SE", 125, -130},
		{"S", 0, -145}, {"W", -165, 0}, {"SW", -125, -130}, {"NW", -125, 130},
	},
}
