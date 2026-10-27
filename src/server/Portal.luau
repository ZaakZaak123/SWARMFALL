--!nonstrict
-- The cableway's tunnel mouths in the ground (DD-091): the same dig in the grove's hill and in the
-- funnel's wall. The owner: the hill was good, the entrance stood crooked in front of it — make it a real
-- way under the ground. So the earth goes where an entrance needs it:
--   (grove only) the hill rises BEHIND the portal, with two shoulders flanking the approach;
--   a cutting in front of the face — vertical earth on both sides, the floor level with the ground;
--   the bore behind the face, a little wider and taller than the lining the client puts in it.
-- The client (client/Cableway.cave) stands the portal on that: a headwall and wing walls whose tops follow
-- the earth (it measures the terrain), the lined tunnel, the dark further in.

local Portal = {}

local M = Enum.Material

-- Size of what is dug, shared with the client's lining (keep in step with Cableway.cave).
Portal.CUT_W = 24 -- the cutting's width between its earth walls
Portal.CUT_L = 16 -- how far it runs out of the face
Portal.BORE_W = 25 -- (terrain is drawn on a 4-stud grid: dug with room, or its faces poke through the lining)
Portal.BORE_H = 24
Portal.BORE_D = 30

-- `mouth` is the floor centre of the face, `facing` points out of the tunnel (horizontal); `earth` is the
-- hill's material, `floor` the cutting's.
function Portal.dig(mouth: Vector3, facing: Vector3, hill: boolean, earth, floor)
	local terrain = workspace.Terrain
	local f = Vector3.new(facing.X, 0, facing.Z).Unit
	local r = f:Cross(Vector3.yAxis).Unit
	local ground = Vector3.new(mouth.X, 0, mouth.Z)
	if hill then
		local mat = earth or M.LeafyGrass
		-- the hill over the tunnel and the shoulders beside the cutting
		-- (sized so the hill keeps clear of both plots' roads to the square, checked against the layout)
		terrain:FillBall(ground - f * 18 + Vector3.new(0, -7, 0), 31, mat)
		terrain:FillBall(ground - f * 30 + Vector3.new(0, -9, 0), 22, mat)
		for _, s in { -1, 1 } do
			terrain:FillBall(ground + r * s * 21 - f * 3 + Vector3.new(0, -5, 0), 15, mat)
		end
		terrain:FillBall(ground - f * 26 + r * 4 + Vector3.new(0, 14, 0), 7, M.Rock)
	end
	local out = CFrame.lookAt(ground, ground + f) -- -Z = out of the tunnel
	-- the cutting in front of the face: dug below the floor, then the floor put back level (a dig that
	-- stops at the floor leaves the hill's slope in the bottom voxel layer — a grass hump in the way in;
	-- a fill up to -2 puts the surface exactly on 0, as everywhere else, DD-049)
	terrain:FillBlock(
		out * CFrame.new(0, -4 + 32, -Portal.CUT_L / 2),
		Vector3.new(Portal.CUT_W, 64, Portal.CUT_L),
		M.Air
	)
	terrain:FillBlock(
		out * CFrame.new(0, -7, -Portal.CUT_L / 2 + 0.5),
		Vector3.new(Portal.CUT_W, 10, Portal.CUT_L + 1),
		floor or M.Ground
	)
	-- the bore (down to -2: the lining's floor covers the step, as in the breach)
	terrain:FillBlock(
		out * CFrame.new(0, -2 + (Portal.BORE_H + 2) / 2, Portal.BORE_D / 2),
		Vector3.new(Portal.BORE_W, Portal.BORE_H + 2, Portal.BORE_D),
		M.Air
	)
end

return Portal
