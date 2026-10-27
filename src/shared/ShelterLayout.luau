--!strict
-- Where everything stands in a shelter (DD-057 → DD-087), in shelter coordinates: the courtyard centre is
-- the origin, the bunker is at +Z, the gate at -Z (towards the grove's Tree), +X is screen-left from the
-- gate. One table for the own shelter (client/Base), the neighbours' (client/Settlement), the server's
-- spawn points and tests/grove (plots must not overlap). Each shelter is placed by its plot's frame
-- (shared/Grove).

local Layout = {}

-- Stations you walk up to (the HUD buttons do the same).
Layout.Stations = {
	armory = { art = "ARMORY", h = 6.5, x = -26, z = 12 },
	launch = { art = "BEACON", h = 9, x = 0, z = -30 },
}

-- Prepared spots (Meta.Home): rubble until restored, then the thing itself.
Layout.Spots = {
	GENERATOR = { art = "GENERATOR", h = 4.2, x = -11, z = 19, yaw = 0.3 },
	WORKBENCH = { art = "WORKBENCH", h = 5, x = 13, z = 13, yaw = -0.25 },
	RADIO = { art = "RADIO", h = 6.5, x = -24, z = -3, yaw = 0.35 },
	LAB = { art = "TANK_FRAME", h = 7.5, x = 27, z = 9, yaw = -0.3 },
	GARDEN = { art = "GARDEN", h = 4, x = -14, z = -14, yaw = 0.2 },
}

Layout.Lamps = { { -32, -20 }, { 32, -22 }, { -34, 24 }, { 34, 24 } }

-- The shelter's own grove: the bunker, trees, old ruins, a wreck by the gate. { art, height, x, z, yaw }.
-- DD-087: only what stands inside the plot (the settlement plants the woods between the plots).
Layout.Decor = {
	{ "SHELTER", 14, 0, 29, 0 },
	{ "OAK", 20, -42, 34, 0.4 },
	{ "OAK", 18, -50, -4, 1.2 },
	{ "OAK", 22, 6, 54, 1.7 },
	{ "OAK", 19, 46, 40, 2.1 },
	{ "BIRCH", 15, -26, 44, 0.3 },
	{ "BIRCH", 14, 28, 46, 1.1 },
	{ "BIRCH", 16, -48, 20, 2.2 },
	{ "BIRCH", 17, -16, 54, 0.8 },
	{ "BUSH", 3.2, -20, 26, 0 },
	{ "BUSH", 2.8, 20, 28, 1 },
	{ "BUSH", 3.4, -36, 8, 2 },
	{ "BUSH", 3.0, 38, -6, 0.5 },
	{ "BUSH", 3.0, 30, -36, 2.5 },
	{ "BUSH", 3.6, -8, 40, 0.2 },
	{ "BUSH", 2.8, 12, 42, 1.2 },
	{ "RUIN_WALL", 5, -11, -36, 0 },
	{ "RUIN_WALL", 5, 11, -36, math.pi },
	{ "RUIN_WALL", 4.5, -46, 8, 1.57 },
	{ "RUIN_WALL", 4.2, 26, 52, -0.15 },
	{ "RUIN_WALL", 4.5, -24, 50, 0.1 },
	{ "CAR_WRECK", 2.8, 18, -46, 0.5 },
	{ "CRATES", 3, -18, 24, 0.4 },
	{ "CRATES", 2.6, 19, 21, -0.6 },
}

-- The cableway terminal (DD-065): the cable comes out of the hill cave to here. The cave (DD-082) is at
-- the foot of the hill between this plot and the next (DD-087); fx, fz point out of it.
Layout.Terminal = { x = -37, z = -9 }
Layout.Cave = { x = -60, z = -40, fx = 0.6, fz = 0.8 }
-- The cableway's other mouth, in the funnel's north-west wall (world space, not shelter coordinates): the
-- server digs both (server/Portal), the client builds the portal and rides the cable (client/Cableway).
Layout.ArenaCave = { x = -120, z = 84, fx = 0.42, fz = -0.91 }

-- The showcase row in front of the bunker (DD-054): the gun at x = -2, the boss trophies from x = 8.
Layout.ShowZ = -16
Layout.Trophies = {
	{ op = "O01", kind = 10, name = "АЛЬФА", hunt = "вылазка 1" },
	{ op = "O05", kind = 7, name = "МАТЬ РОЯ", hunt = "вылазка 5" },
	{ op = "O07", kind = 9, name = "ПОЖИРАТЕЛЬ", hunt = "вылазка 7" },
}
function Layout.trophyX(i: number): number
	return 8 + (i - 1) * 9
end
Layout.SiegeX = -26

-- The shooting range (DD-055): the firing mark and three dummies east of the yard (screen-left).
Layout.RangeMark = { x = 36, z = -12 }
Layout.RangeDummies = { { 48, -6 }, { 51, -12 }, { 48, -18 } }

-- DD-087: the plot's sign and lantern by the road just outside the gate, and where people arrive.
Layout.Sign = { x = 8, z = -44 }
Layout.Spawns = { { 0, -4 }, { -5, -6 }, { 5, -6 }, { 0, -9 } }
Layout.Arrive = { x = 0, z = -52 } -- a visitor's quick way in: on the road, facing the gate

-- The lab's specimen gallery grows into the clearing behind the lab (SpecimenGallery): its deck.
Layout.GalleryDeck = { x = 16, z = 24, sx = 28, sz = 42 } -- relative to the LAB spot

return Layout
