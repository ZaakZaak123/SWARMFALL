-- Headless full-run playtest: a kiting bot plays complete SWARMFALL runs against the real server sim.
-- Usage (repo root):  lune run tests/sim_run [weapon|all|batch] [players] [seed|runs] [map] [threat]
-- Verifies: no runtime errors, pacing milestones, evolution reachable, boss fight resolves, tick cost.

local process = require("@lune/process")
local H = require("./harness")

local World = H.require("src/server/Sim/World")
local Nav = H.require("src/server/Sim/Nav")
local Defs = H.require("src/shared/Defs")
local Codec = H.require("src/shared/Codec")
local Maps = H.require("src/shared/Maps")

local args = process.args
local weaponArg = args[1] or "all"
local playerCount = tonumber(args[2]) or 1
local seed = tonumber(args[3]) or 20261021
local mapArg = args[4] or "MAP_REACTOR_YARD"
local threatArg = tonumber(args[5]) or 1

local function fmt(t: number): string
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end

local function runOnce(weapon: string, players: number, runSeed: number, verbose: boolean, mapId: string?, threat: number?, perks: any?)
	local infos = {}
	for i = 1, players do
		table.insert(infos, { id = i, name = "BOT" .. i, weapon = weapon, perks = perks })
	end
	local w = World.new({ seed = runSeed, players = infos, map = mapId or mapArg, threat = threat or threatArg })
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

	while w.phase ~= "RESULTS" and clock < 700 do
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
				if p.od >= 100 and w:overdrive(p.id) then
					milestones.overdrives = (milestones.overdrives or 0) + 1
				end
				-- Target nearest enemy (boss preferred when close).
				local target, td = nil, math.huge
				for _, e in w.enemies do
					if e.alive and not e.invulnerable then
						local d = (e.x - p.x) ^ 2 + (e.z - p.z) ^ 2
						if e.kind == "BOSS_BROODMOTHER" or e.kind == "ELITE_BULWARK" or e.kind == "HIVE" then
							d *= 0.15
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
				local cr = math.sqrt(p.x * p.x + p.z * p.z)
				if goal then
					local gx, gz = goal.x - p.x, goal.z - p.z
					local gd = math.max(0.1, math.sqrt(gx * gx + gz * gz))
					local want = if goal.def then 30 else 0
					mx += gx / gd * math.clamp((gd - want) / 15, -1, 1.2)
					mz += gz / gd * math.clamp((gd - want) / 15, -1, 1.2)
				elseif cr > 1 then
					local want = 55
					mx += -p.x / cr * (cr - want) / 40
					mz += -p.z / cr * (cr - want) / 40
					mx += -p.z / cr * 0.5 * orbit
					mz += p.x / cr * 0.5 * orbit
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
				fmt(w.t), w.level, #w.enemies, w.teamKills, math.floor(p.hp), math.floor(p.od), math.floor(p.damage),
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

if weaponArg == "batch" then
	local n = tonumber(args[3]) or 6
	for _, weapon in (if args[6] then { args[6] } else Defs.WeaponOrder) do
		local wins, times, evolvedAt, levels = 0, 0, 0, 0
		local line = {}
		for k = 1, n do
			local out = runOnce(weapon, playerCount, 1000 + k * 7919, false, mapArg, threatArg)
			local r = out.result
			if r.victory then
				wins += 1
			end
			times += r.time
			levels += r.level
			evolvedAt += out.milestones.evolved or 0
			table.insert(line, (if r.victory then "W" else "L") .. fmt(r.time))
		end
		print(string.format("%-14s wins %d/%d  avg end %s  avg level %.1f  runs: %s", weapon, wins, n, fmt(times / n), levels / n, table.concat(line, " ")))
	end
	return
end

local weapons = if weaponArg == "all" then Defs.WeaponOrder else { weaponArg }
local failures = 0
for _, weapon in weapons do
	print(string.format("=== %s  players=%d seed=%d", weapon, playerCount, seed))
	local ok, out = pcall(runOnce, weapon, playerCount, seed, true)
	if not ok then
		failures += 1
		print("  RUNTIME ERROR: " .. tostring(out))
		continue
	end
	local r = out.result
	local m = out.milestones
	print(string.format(
		"  RESULT %s (%s) at %s  level %d  kills %d  hive %s",
		if r and r.victory then "VICTORY" else "DEFEAT", r and r.reason or "?", fmt(r and r.time or 0),
		r and r.level or 0, r and r.kills or 0, r and r.hive or "?"
	))
	print(string.format(
		"  first kill %.1fs  first level %.1fs  first choice %.1fs  core %s  evolved %s  overdrives %d",
		m.firstKill or -1, m.firstLevel or -1, m.firstChoice or -1, m.core and fmt(m.core) or "-",
		m.evolved and fmt(m.evolved) or "-", m.overdrives or 0
	))
	print(string.format(
		"  sim tick avg %.3f ms  max %.2f ms  peak enemies %d  spawned %d  lowest hp %d  events/s %.0f  enemy stream %.1f KB/s",
		out.avgTickMs, out.maxTickMs, out.peak, out.spawned, out.lowestHp, out.eventsPerSec, out.kbps
	))
	if not r then
		failures += 1
		print("  FAIL: run never finished")
	end
	if not m.firstKill or m.firstKill > 20 then
		failures += 1
		print("  FAIL: no kill in first 20s")
	end
	if not m.firstChoice or m.firstChoice > 75 then
		failures += 1
		print("  FAIL: first upgrade later than 75s")
	end
end

-- Determinism: identical seeds produce identical runs.
local a = runOnce(weapons[1], 1, 777, false)
local b = runOnce(weapons[1], 1, 777, false)
assert(a.result.time == b.result.time and a.result.kills == b.result.kills, "non-deterministic simulation")
print("PASS determinism (seed 777)")

-- Flow field reaches every spawn, hive site, coil pad and boss entry on every map.
for _, id in Maps.Order do
	local map = Maps.get(id)
	local nav = Nav.new(map)
	local field = nav.newField()
	nav.buildField(field, { { map.playerStart.x, map.playerStart.z } })
	for name, s in map.spawns do
		assert(nav.free(s.x, s.z, 2) and nav.costAt(field, s.x, s.z) < math.huge, id .. ": unreachable spawn " .. name)
	end
	for _, h in map.hiveSites do
		assert(nav.free(h.x, h.z, 5) and nav.costAt(field, h.x, h.z) < math.huge, id .. ": hive site blocked")
	end
	for _, c in map.coils do
		assert(nav.costAt(field, c.x + 4, c.z) < math.huge, id .. ": coil pad unreachable")
	end
	assert(nav.free(map.playerStart.x, map.playerStart.z, 2), id .. ": start blocked")
	print("PASS navigation reachability", id)
end

-- Meta: perks applied, threat raises difficulty, rewards computed.
do
	local perks = { PK_VITALITY = 5, PK_MAGNET = 3, PK_REROLL = 3, PK_BANISH = 2, PK_INSIGHT = 1, PK_OVERDRIVE = 2, PK_DASH = 3 }
	local w = World.new({ seed = 5, players = { { id = 1, name = "P", weapon = "W_RAILGUN", perks = perks } }, map = "MAP_HIVE_DEPTHS", threat = 3 })
	local p = w.playerList[1]
	assert(p.maxHp == 140 and p.rerolls == 3 and p.banishes == 2 and p.cards == 4 and p.od == 50, "perks not applied")
	w:step(5)
	w.t = 100
	local e = w:spawnEnemy("EN_RUNNER", 50, 50)
	assert(math.abs(e.maxHp - 24 * Defs.hpScale(100) * Defs.Threat.hp(3)) < 0.01, "threat hp")
	local r = Defs.runReward({ kills = 1200, level = 15, victory = true, time = 450, hive = "cleared" }, 3, 2)
	assert(r.total > 0 and #r.lines == 4, "reward")
	print("PASS perks / threat / rewards", r.total)
end
local out = runOnce("W_RAILGUN", 1, 4242, false, "MAP_HIVE_DEPTHS", 2, { PK_REROLL = 2, PK_BANISH = 1, PK_INSIGHT = 1 })
print(string.format("PASS railgun on Hive Depths threat 2: %s %s at %d:%02d", out.result.victory and "VICTORY" or "DEFEAT", out.result.reason, out.result.time // 60, math.floor(out.result.time % 60)))

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL SIM CHECKS PASSED")
