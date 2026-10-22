-- Headless bot that plays a full SWARMFALL run against the real server sim (shared by test scripts).
-- Bot.run(weapon, players, seed, verbose, mapId?, threat?, perks?, opts?)
--   opts.op      operation id (default: from map, legacy)
--   opts.anchor  {x, z} the bot orbits (default reactor/centre); far away = "does not defend"

local H = require("./harness")

local World = H.require("src/server/Sim/World")
local Defs = H.require("src/shared/Defs")
local Codec = H.require("src/shared/Codec")

local Bot = {}

local function fmt(t: number): string
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end
Bot.fmt = fmt

function Bot.run(weapon: string, players: number, runSeed: number, verbose: boolean, mapId: string?, threat: number?, perks: any?, opts: any?)
	opts = opts or {}
	local infos = {}
	for i = 1, players do
		table.insert(infos, { id = i, name = "BOT" .. i, weapon = weapon, perks = perks, s01 = (opts or {}).s01 })
	end
	local w = World.new({ seed = runSeed, players = infos, op = opts.op, map = mapId, threat = threat or 1 })
	local ax, az = 0, 0
	if opts.anchor then
		ax, az = opts.anchor[1], opts.anchor[2]
	end
	local orbitR = opts.orbit or 55
	if opts.onSpawn then
		local spawn = w.spawnEnemy
		w.spawnEnemy = function(self, kind, ...)
			opts.onSpawn(kind)
			return spawn(self, kind, ...)
		end
	end
	local Nav = w.nav
	local dt = 1 / 30
	local clock = 0
	local milestones = {}
	local nextReport = 30
	local totalTickMs, ticks = 0, 0
	local lowestHp = 100
	local decodeBuf = {}
	local eventCount = 0
	local bytes = 0
	local orbit = 1

	while w.phase ~= "RESULTS" and clock < (opts.stopAt or 700) do
		clock += dt
		-- Bot brains
		for _, p in w.playerList do
			if p.alive then
				-- Choose upgrades: evolution keys first, then the first card.
				if p.offer and p.rerolls > 0 and not milestones.rerolled then
					milestones.rerolled = w:reroll(p.id)
				end
				if p.offer then
					local evo = Defs.Evolutions[p.weaponDef.evolution]
					local pickIndex = 1
					for i, c in p.offer.choices do
						if table.find(evo.keys, c) then
							pickIndex = i
							break
						end
					end
					local ok = w:choose(p.id, p.offer.id, pickIndex)
					assert(ok, "choose failed")
					if not milestones.firstChoice then
						milestones.firstChoice = w.t
					end
				end
				if p.canEvolve then
					assert(w:evolve(p.id), "evolve rejected")
					milestones.evolved = w.t
				end
				if w.paused == "S01" and w:gravihammer(p.id) then
					milestones.s01Tutorial = w.t
				end
				-- Target nearest enemy (boss preferred when close).
				local target, td = nil, math.huge
				for _, e in w.enemies do
					if e.alive and not e.invulnerable then
						local d = (e.x - p.x) ^ 2 + (e.z - p.z) ^ 2
						if e.kind == "BOSS_BROODMOTHER" or e.kind == "ELITE_BULWARK" or e.kind == "HIVE" then
							d *= 0.15
						elseif e.role == "R" and not opts.ignoreReactor then
							d *= 0.4
						end
						if d < td then
							target, td = e, d
						end
					end
				end
				local range = p.stats.range
				if target then
					w:setAim(p.id, target.x - p.x, target.z - p.z, math.sqrt(td) < range * 1.1)
				else
					w:setAim(p.id, 0, 1, false)
				end
				-- Kite: repel from enemies and hazards, orbit the core, stay inside.
				local mx, mz = 0, 0
				local close = 0
				for _, e in w.enemies do
					if e.alive then
						local dx, dz = p.x - e.x, p.z - e.z
						local d2 = dx * dx + dz * dz
						local rr = 16 + e.def.radius * 2
						if d2 < rr * rr and d2 > 0.01 then
							local d = math.sqrt(d2)
							local f = (rr - d) / rr * (if e.def.big then 2.2 else 1)
							mx += dx / d * f
							mz += dz / d * f
							if d < 6 + e.def.radius then
								close += 1
							end
						end
					end
				end
				for _, h in w.hazards do
					if World.inShape(h, p.x, p.z, 4) then
						local dx, dz = p.x - h.x, p.z - h.z
						if h.shape == Codec.Shape.LINE then
							local side = dx * h.dz - dz * h.dx
							dx, dz = h.dz * (if side >= 0 then 1 else -1), -h.dx * (if side >= 0 then 1 else -1)
						end
						local d = math.max(0.1, math.sqrt(dx * dx + dz * dz))
						mx += dx / d * 3
						mz += dz / d * 3
					end
				end
				local goal = nil
				for _, o in w.orbs do
					if o.kind ~= 0 and (o.kind == 2 or p.hp < 70) then
						goal = o
						break
					end
				end
				if not goal and target and target.def.big and target.kind ~= "EN_BULWARK" and close == 0 then
					goal = target
				end
				-- Objective awareness: guard the relay while it charges.
				local gx0, gz0, gr = ax, az, orbitR
				local mm = w.mission
				if not opts.anchor and mm.relay and mm.relay.coil and mm.relay.coil.alive and mm.state == "FIGHT" then
					gx0, gz0, gr = mm.relay.coil.x, mm.relay.coil.z, 16
				end
				local rx, rz = p.x - gx0, p.z - gz0
				local cr = math.sqrt(rx * rx + rz * rz)
				if goal then
					local gx, gz = goal.x - p.x, goal.z - p.z
					local gd = math.max(0.1, math.sqrt(gx * gx + gz * gz))
					local want = if goal.def then 30 else 0
					mx += gx / gd * math.clamp((gd - want) / 15, -1, 1.2)
					mz += gz / gd * math.clamp((gd - want) / 15, -1, 1.2)
				elseif cr > 1 then
					local want = gr
					mx += -rx / cr * (cr - want) / 40
					mz += -rz / cr * (cr - want) / 40
					mx += -rz / cr * 0.5 * orbit
					mz += rx / cr * 0.5 * orbit
				end
				if close >= 4 and p.s01 and w.t >= p.s01Ready and w:gravihammer(p.id) then
					milestones.overdrives = (milestones.overdrives or 0) + 1
				end
				local m = math.sqrt(mx * mx + mz * mz)
				local speed = Defs.Player.Speed
				if w.t < p.dashUntil then
					speed = Defs.Player.DashDistance / Defs.Player.DashTime
					mx, mz, m = p.dashX, p.dashZ, 1
				elseif close >= 3 and w.t >= p.dashReady and m > 0.1 then
					w:dash(p.id, mx / m, mz / m)
				end
				if m > 0.05 and not w.paused then
					local nx, nz = p.x + mx / m * speed * dt, p.z + mz / m * speed * dt
					if not Nav.free(nx, nz, Defs.Player.Radius) then
						orbit = -orbit
					end
					nx, nz = Nav.resolve(nx, nz, Defs.Player.Radius)
					w:setPlayerPosition(p.id, nx, nz)
				end
			end
		end

		local before = w.stats.lastTickMs
		w:step(dt)
		if w.stats.lastTickMs ~= before then
			totalTickMs += w.stats.lastTickMs
			ticks += 1
		end
		local ev = w:drainEvents()
		eventCount += #ev
		for _, e in ev do
			if e[1] == Codec.E.LEVEL and not milestones.firstLevel then
				milestones.firstLevel = w.t
			elseif e[1] == Codec.E.KILL and e[2] and not milestones.firstKill then
				milestones.firstKill = w.t
			elseif e[1] == Codec.E.COMPONENT then
				milestones.component = w.t
			elseif e[1] == Codec.E.ASSAULT then
				milestones.assaults = (milestones.assaults or 0) + 1
			elseif e[1] == Codec.E.CORE and not milestones.core then
				milestones.core = w.t
			elseif e[1] == Codec.E.BANNER and verbose then
				print(string.format("  [%s] BANNER %s — %s", fmt(w.t), e[2], e[3]))
			end
		end
		-- Exercise replication encoding every 1/15 s.
		if math.floor(clock * 15) ~= math.floor((clock - dt) * 15) then
			local b = w:encodeEnemies()
			bytes += buffer.len(b)
			local n = Codec.decodeEnemies(b, decodeBuf)
			assert(n == #w.enemies, "codec count mismatch")
			local st = w:publicState()
			assert(st.phase and st.players, "bad public state")
		end
		for _, p in w.playerList do
			lowestHp = math.min(lowestHp, p.hp)
		end
		if verbose and w.t >= nextReport then
			nextReport += 30
			local p = w.playerList[1]
			local ups = {}
			for id, r in p.ranks do
				table.insert(ups, id:sub(5, 8) .. r)
			end
			table.sort(ups)
			print(string.format(
				"  %s  lvl %2d  enemies %3d  kills %4d  hp %3d  od %3d  dmg %7d  %s%s",
				fmt(w.t), w.level, #w.enemies, w.teamKills, math.floor(p.hp), p.s01Stats.casts, math.floor(p.damage),
				table.concat(ups, " "), if p.evolved then "  [" .. p.evolved .. "]" else ""
			))
		end
	end
	local r = w.result
	return {
		result = r,
		milestones = milestones,
		avgTickMs = totalTickMs / math.max(1, ticks),
		maxTickMs = w.stats.maxTickMs,
		peak = w.stats.peak,
		spawned = w.stats.spawned,
		lowestHp = lowestHp,
		eventsPerSec = eventCount / math.max(1, w.t),
		kbps = bytes / math.max(1, clock) / 1024,
		world = w,
	}
end
return Bot
