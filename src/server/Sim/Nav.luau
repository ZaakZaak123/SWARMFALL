--!strict
-- Analytic arena navigation for one map: circle-vs-obstacle resolution, segment line-of-sight, ray casts
-- and a multi-source flow field. Pure Luau on numbers (no Vector3 allocations in hot loops).
-- Nav.new(map) returns a cached instance whose functions close over flattened per-map arrays.

local Nav = {}

local instances = {}

local DIRS = {
	{ 1, 0, 10 }, { -1, 0, 10 }, { 0, 1, 10 }, { 0, -1, 10 },
	{ 1, 1, 14 }, { 1, -1, 14 }, { -1, 1, 14 }, { -1, -1, 14 },
}

export type Field = { cost: { number }, dirX: { number }, dirZ: { number } }

function Nav.new(map: any)
	if instances[map.id] then
		return instances[map.id]
	end
	local self: any = {}
	local MIN_X = -map.halfX + map.wall
	local MAX_X = map.halfX - map.wall
	local MIN_Z = -map.halfZ + map.wall
	local MAX_Z = map.halfZ - map.wall
	self.MinX, self.MaxX, self.MinZ, self.MaxZ = MIN_X, MAX_X, MIN_Z, MAX_Z

	local count = #map.obstacles
	local isRound = table.create(count, false)
	local ox = table.create(count, 0)
	local oz = table.create(count, 0)
	local hx = table.create(count, 0)
	local hz = table.create(count, 0)
	for i, o in map.obstacles do
		isRound[i] = o.shape == "round"
		ox[i], oz[i] = o.x, o.z
		hx[i], hz[i] = o.w / 2, o.d / 2
	end

	function self.free(x: number, z: number, r: number): boolean
		if x - r < MIN_X or x + r > MAX_X or z - r < MIN_Z or z + r > MAX_Z then
			return false
		end
		for i = 1, count do
			local dx, dz = x - ox[i], z - oz[i]
			if isRound[i] then
				local rr = hx[i] + r
				if dx * dx + dz * dz < rr * rr then
					return false
				end
			elseif math.abs(dx) < hx[i] + r and math.abs(dz) < hz[i] + r then
				return false
			end
		end
		return true
	end

	function self.resolve(x: number, z: number, r: number): (number, number)
		for i = 1, count do
			local dx, dz = x - ox[i], z - oz[i]
			if isRound[i] then
				local rr = hx[i] + r
				local d2 = dx * dx + dz * dz
				if d2 < rr * rr then
					local d = math.sqrt(d2)
					if d < 1e-4 then
						dx, dz, d = 1, 0, 1
					end
					x = ox[i] + dx / d * rr
					z = oz[i] + dz / d * rr
				end
			else
				local ex, ez = hx[i] + r, hz[i] + r
				if math.abs(dx) < ex and math.abs(dz) < ez then
					local px, pz = ex - math.abs(dx), ez - math.abs(dz)
					if px < pz then
						x = ox[i] + (if dx >= 0 then ex else -ex)
					else
						z = oz[i] + (if dz >= 0 then ez else -ez)
					end
				end
			end
		end
		return math.clamp(x, MIN_X + r, MAX_X - r), math.clamp(z, MIN_Z + r, MAX_Z - r)
	end

	-- Distance along a ray (unit dx,dz) to the first obstacle or wall, up to maxDist.
	function self.ray(x: number, z: number, dx: number, dz: number, maxDist: number): number
		local best = maxDist
		if dx > 1e-6 then
			best = math.min(best, (MAX_X - x) / dx)
		elseif dx < -1e-6 then
			best = math.min(best, (MIN_X - x) / dx)
		end
		if dz > 1e-6 then
			best = math.min(best, (MAX_Z - z) / dz)
		elseif dz < -1e-6 then
			best = math.min(best, (MIN_Z - z) / dz)
		end
		for i = 1, count do
			local cx, cz = ox[i] - x, oz[i] - z
			if isRound[i] then
				local b = cx * dx + cz * dz
				local c = cx * cx + cz * cz - hx[i] * hx[i]
				if b > 0 or c < 0 then
					local disc = b * b - c
					if disc >= 0 then
						local t = b - math.sqrt(disc)
						if t >= 0 and t < best then
							best = t
						end
					end
				end
			else
				local tmin, tmax = 0, best
				local hit = true
				for axis = 1, 2 do
					local o = if axis == 1 then -cx else -cz
					local d = if axis == 1 then dx else dz
					local h = if axis == 1 then hx[i] else hz[i]
					if math.abs(d) < 1e-6 then
						if o < -h or o > h then
							hit = false
							break
						end
					else
						local t1, t2 = (-h - o) / d, (h - o) / d
						if t1 > t2 then
							t1, t2 = t2, t1
						end
						tmin = math.max(tmin, t1)
						tmax = math.min(tmax, t2)
						if tmin > tmax then
							hit = false
							break
						end
					end
				end
				if hit and tmin < best then
					best = tmin
				end
			end
		end
		return math.max(0, best)
	end

	function self.clear(ax: number, az: number, bx: number, bz: number, r: number): boolean
		local dx, dz = bx - ax, bz - az
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-4 then
			return self.free(ax, az, r)
		end
		local steps = math.ceil(len / math.max(1, r))
		for s = 1, steps do
			local t = s / steps
			if not self.free(ax + dx * t, az + dz * t, r) then
				return false
			end
		end
		return true
	end

	-- Flow field --------------------------------------------------------------------------------------
	local CELL = 4
	local NX = math.ceil((MAX_X - MIN_X) / CELL)
	local NZ = math.ceil((MAX_Z - MIN_Z) / CELL)
	self.Cell, self.NX, self.NZ = CELL, NX, NZ

	local walkable = table.create(NX * NZ, false)
	local function idx(cx: number, cz: number): number
		return cz * NX + cx + 1
	end
	local function center(cx: number, cz: number): (number, number)
		return MIN_X + (cx + 0.5) * CELL, MIN_Z + (cz + 0.5) * CELL
	end
	for cz = 0, NZ - 1 do
		for cx = 0, NX - 1 do
			local x, z = center(cx, cz)
			walkable[idx(cx, cz)] = self.free(x, z, 1.4)
		end
	end
	self.walkable = walkable

	function self.cellOf(x: number, z: number): (number, number)
		return math.clamp(math.floor((x - MIN_X) / CELL), 0, NX - 1), math.clamp(math.floor((z - MIN_Z) / CELL), 0, NZ - 1)
	end

	function self.newField(): Field
		local n = NX * NZ
		return { cost = table.create(n, math.huge), dirX = table.create(n, 0), dirZ = table.create(n, 0) }
	end

	-- Multi-source Dijkstra on an 8-connected grid (no corner cutting) using a bucket queue.
	function self.buildField(field: Field, sources: { { number } })
		local cost, dirX, dirZ = field.cost, field.dirX, field.dirZ
		local n = NX * NZ
		for i = 1, n do
			cost[i] = math.huge
			dirX[i], dirZ[i] = 0, 0
		end
		local buckets: { [number]: { number } } = {}
		local maxBucket = 0
		local function push(i: number, c: number)
			local b = buckets[c]
			if not b then
				b = {}
				buckets[c] = b
			end
			table.insert(b, i)
			if c > maxBucket then
				maxBucket = c
			end
		end
		for _, s in sources do
			local cx, cz = self.cellOf(s[1], s[2])
			local best, bi = math.huge, nil
			for r = 0, 3 do
				for dz = -r, r do
					for dx = -r, r do
						local x, z = cx + dx, cz + dz
						if x >= 0 and x < NX and z >= 0 and z < NZ and walkable[idx(x, z)] then
							local d = dx * dx + dz * dz
							if d < best then
								best, bi = d, idx(x, z)
							end
						end
					end
				end
				if bi then
					break
				end
			end
			if bi and cost[bi] > 0 then
				cost[bi] = 0
				push(bi, 0)
			end
		end
		local c = 0
		while c <= maxBucket do
			local b = buckets[c]
			if b then
				local k = 1
				while k <= #b do
					local i = b[k]
					k += 1
					if cost[i] == c then
						local cz = (i - 1) // NX
						local cx = (i - 1) - cz * NX
						for _, d in DIRS do
							local x, z = cx + d[1], cz + d[2]
							if x >= 0 and x < NX and z >= 0 and z < NZ then
								local j = idx(x, z)
								if walkable[j] then
									local diagonalOk = d[3] == 10 or (walkable[idx(cx + d[1], cz)] and walkable[idx(cx, cz + d[2])])
									if diagonalOk then
										local nc = c + d[3]
										if nc < cost[j] then
											cost[j] = nc
											push(j, nc)
										end
									end
								end
							end
						end
					end
				end
				buckets[c] = nil
			end
			c += 1
		end
		for i = 1, n do
			if walkable[i] and cost[i] > 0 and cost[i] < math.huge then
				local cz = (i - 1) // NX
				local cx = (i - 1) - cz * NX
				local best, bx, bz = cost[i], 0, 0
				for _, d in DIRS do
					local x, z = cx + d[1], cz + d[2]
					if x >= 0 and x < NX and z >= 0 and z < NZ then
						local j = idx(x, z)
						if cost[j] < best then
							local diagonalOk = d[3] == 10 or (walkable[idx(cx + d[1], cz)] and walkable[idx(cx, cz + d[2])])
							if diagonalOk then
								best, bx, bz = cost[j], d[1], d[2]
							end
						end
					end
				end
				local m = math.sqrt(bx * bx + bz * bz)
				if m > 0 then
					dirX[i], dirZ[i] = bx / m, bz / m
				end
			end
		end
	end

	function self.flow(field: Field, x: number, z: number): (number, number)
		local cx, cz = self.cellOf(x, z)
		local i = idx(cx, cz)
		if walkable[i] then
			return field.dirX[i], field.dirZ[i]
		end
		local best, bx, bz = math.huge, 0, 0
		for _, d in DIRS do
			local nx, nz = cx + d[1], cz + d[2]
			if nx >= 0 and nx < NX and nz >= 0 and nz < NZ then
				local j = idx(nx, nz)
				if walkable[j] and field.cost[j] < best then
					best = field.cost[j]
					local tx, tz = center(nx, nz)
					local ddx, ddz = tx - x, tz - z
					local m = math.sqrt(ddx * ddx + ddz * ddz)
					if m > 1e-4 then
						bx, bz = ddx / m, ddz / m
					end
				end
			end
		end
		return bx, bz
	end

	function self.costAt(field: Field, x: number, z: number): number
		local cx, cz = self.cellOf(x, z)
		return field.cost[idx(cx, cz)]
	end

	instances[map.id] = self
	return self
end

return Nav
