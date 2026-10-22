-- W01 «Дуговая винтовка» acceptance checks against the real server sim + client data modules.
-- Usage (repo root): lune run tests/w01
local fs = require("@lune/fs")
local H = require("./harness")

local World = H.require("src/server/Sim/World")
local Combat = H.require("src/server/Sim/Combat")
local Defs = H.require("src/shared/Defs")
local Codec = H.require("src/shared/Codec")
local Models = H.require("src/client/Models")
local Feel = H.require("src/client/WeaponFeel")

local E = Codec.E
local ID = "W_ARC_RIFLE"
local W = Defs.Weapons[ID]
local DT = Defs.Run.SimStep

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. (if detail then "  (" .. detail .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number): boolean
	return math.abs(a - b) <= eps
end

-- A live world with one rifle player at the map start, no director spawns.
local function arena()
	local w = World.new({ seed = 7, players = { { id = 1, name = "T", weapon = ID } } })
	w.phase = "ACTIVE"
	w.director = function() end
	local p = w.players[1]
	return w, p
end
local function run(w, p, seconds: number)
	local n = math.floor(seconds / DT + 0.5)
	for _ = 1, n do
		w.t += DT
		w:rebuildGrid()
		Combat.updatePlayer(w, p, DT)
	end
end
local function count(w, kind: number): number
	local c = 0
	for _, ev in w.events do
		if ev[1] == kind then
			c += 1
		end
	end
	return c
end
local function enemyAt(w, p, kind: string, dist: number, facePlayer: boolean?)
	-- the line of fire is +X from the start position (clear of the reactor for 100 studs)
	local e = w:spawnEnemy(kind, p.x + dist, p.z, 0)
	e.state = Codec.State.CHASE or e.state
	e.fx, e.fz = if facePlayer == false then 1 else -1, 0
	return e
end

print("W01 · " .. W.name)

-- Data -------------------------------------------------------------------------------------------
check("starter weapon: index 1, free, evolves into ГРОМОВЕРЖЕЦ", W.index == 1 and W.cost == 0 and W.evolution == "EV_THUNDERLORD")
check("reload: tactical faster than empty", W.reloadEmpty > W.reload)
check("bloom: min < base spread < max", W.spreadMin < W.spread and W.spread < W.spreadMax and W.bloom > 0 and W.recover > 0)

-- Rate of fire ---------------------------------------------------------------------------------------
do
	local w, p = arena()
	w:setAim(1, 1, 0, true)
	run(w, p, 3)
	local shots = count(w, E.SHOT)
	check("rate: 3 s of fire ≈ 21 shots", near(shots, W.rate * 3, 1.01), tostring(shots))
	check("ammo spent = shots fired", p.ammo == W.magazine - shots, tostring(p.ammo))
end
do -- trigger spam (fire/release every tick) can never beat the rate
	local w, p = arena()
	for i = 1, 60 do
		w:setAim(1, 1, 0, i % 2 == 0)
		run(w, p, DT)
	end
	local shots = count(w, E.SHOT)
	check("rate: trigger spam stays ≤ rate", shots <= W.rate * 3 + 1, tostring(shots))
end

-- Accuracy bloom ---------------------------------------------------------------------------------------
do
	local w, p = arena()
	check("bloom: first shot uses the tight cone", near(p.spread, W.spreadMin, 1e-6))
	w:setAim(1, 1, 0, true)
	run(w, p, 5 / W.rate - DT / 2)
	local shots = count(w, E.SHOT)
	check("bloom: grows per shot", near(p.spread, W.spreadMin + shots * W.bloom, 1e-6), string.format("%.2f after %d", p.spread, shots))
	run(w, p, 2.5)
	check("bloom: capped during long bursts", near(p.spread, W.spreadMax, 1e-6), string.format("%.2f", p.spread))
	w:setAim(1, 1, 0, false)
	run(w, p, (W.spreadMax - W.spreadMin) / W.recover + 0.05)
	check("bloom: recovers when the trigger is released", near(p.spread, W.spreadMin, 1e-6), string.format("%.2f", p.spread))
end

-- Reload ------------------------------------------------------------------------------------------------
do
	local w, p = arena()
	w:setAim(1, 1, 0, true)
	local guard = 0
	while p.reloadT <= 0 and guard < 400 do
		guard += 1
		run(w, p, DT)
	end
	check("empty cell triggers the full reload", p.reloadT > 0 and p.reloadEmpty == true and near(p.reloadDur, W.reloadEmpty, 1e-6))
	w:setAim(1, 1, 0, false)
	local t0 = w.t
	while p.reloadT > 0 do
		run(w, p, DT)
	end
	check("full reload ≈ " .. W.reloadEmpty .. " s", near(w.t - t0, W.reloadEmpty, DT + 1e-6), string.format("%.2f", w.t - t0))
	check("cell refilled", p.ammo == W.magazine)
	local state = w:publicState().players[1]
	check("public state carries bloom / reload kind / pierce / multishot", state.spread ~= nil and state.reloadEmpty ~= nil and state.pierce ~= nil and state.multi ~= nil)
end
do
	local w, p = arena()
	p.ammo = 10
	w:reload(1)
	check("tactical reload uses the quick cell swap", p.reloadEmpty == false and near(p.reloadT, W.reload, 1e-6))
	run(w, p, W.reload + DT)
	check("tactical reload refills", p.ammo == W.magazine)
	p.ammo = W.magazine
	w:reload(1)
	check("full cell: reload ignored", p.reloadT == 0)
end

-- Damage, armor, range -------------------------------------------------------------------------------
do
	local w, p = arena()
	p.spread = 0
	p.stats.spreadMin, p.stats.spreadMax, p.stats.bloom = 0, 0, 0
	local e = enemyAt(w, p, "EN_RUNNER", 20)
	local hp = e.hp
	w:setAim(1, 1, 0, true)
	run(w, p, DT)
	check("hit: one bolt deals " .. W.damage, near(hp - e.hp, W.damage, 0.01), string.format("%.2f", hp - e.hp))

	local w2, p2 = arena()
	p2.stats.spreadMin, p2.stats.spreadMax, p2.stats.bloom, p2.spread = 0, 0, 0, 0
	local front = enemyAt(w2, p2, "EN_BULWARK", 20, true)
	local fhp = front.hp
	w2:setAim(1, 1, 0, true)
	run(w2, p2, DT)
	check("armor: frontal plate takes 35%", near(fhp - front.hp, W.damage * Defs.Bulwark.FrontArmor, 0.01), string.format("%.2f", fhp - front.hp))
	local w3, p3 = arena()
	p3.stats.spreadMin, p3.stats.spreadMax, p3.stats.bloom, p3.spread = 0, 0, 0, 0
	local back = enemyAt(w3, p3, "EN_BULWARK", 20, false)
	local bhp = back.hp
	w3:setAim(1, 1, 0, true)
	run(w3, p3, DT)
	check("armor: flank / back is the weak spot (full damage)", near(bhp - back.hp, W.damage, 0.01), string.format("%.2f", bhp - back.hp))

	local w4, p4 = arena()
	p4.stats.spreadMin, p4.stats.spreadMax, p4.stats.bloom, p4.spread = 0, 0, 0, 0
	local far = enemyAt(w4, p4, "EN_RUNNER", W.range + 6)
	local farHp = far.hp
	w4:setAim(1, 1, 0, true)
	run(w4, p4, 0.5)
	check("range: nothing beyond " .. W.range, far.hp == farHp)
end

-- Pierce upgrade ------------------------------------------------------------------------------------------
do
	local w, p = arena()
	p.ranks.UPG_PIERCE = 1
	Combat.recompute(p)
	p.stats.spreadMin, p.stats.spreadMax, p.stats.bloom, p.spread = 0, 0, 0, 0
	local a = enemyAt(w, p, "EN_BULWARK", 15, false)
	local b = enemyAt(w, p, "EN_BULWARK", 25, false)
	local ah, bh = a.hp, b.hp
	w:setAim(1, 1, 0, true)
	run(w, p, DT)
	check("ПРОБОЙ: bolt passes through, falloff on the second target", near(ah - a.hp, W.damage, 0.01) and near(bh - b.hp, W.damage * W.falloff, 0.01), string.format("%.2f / %.2f", ah - a.hp, bh - b.hp))
end

-- Evolution -----------------------------------------------------------------------------------------------
do
	local w, p = arena()
	p.ranks.UPG_CHAIN, p.ranks.UPG_RICOCHET, p.slots = 1, 1, 2
	p.hasCore = true
	Combat.recompute(p)
	Combat.checkEvolve(w, p)
	check("evolution unlocks with both keys + the core", p.canEvolve == true)
	check("evolution accepted", w:evolve(1) == true and p.evolved == "EV_THUNDERLORD")
	local m = Defs.Evolutions.EV_THUNDERLORD.mods
	check("ГРОМОВЕРЖЕЦ stats: +2 damage, +15% rate, 60 cell, refilled", p.stats.damage == W.damage + m.damageAdd and near(p.stats.rate, W.rate * m.rateMult, 1e-6) and p.stats.magazine == 60 and p.ammo == 60)
	w.paused = nil
	table.clear(w.events)
	-- target + a cluster behind it for the forks
	for i, dz in { 20, 24, 28, 32 } do
		local e = enemyAt(w, p, "EN_BULWARK", dz, false)
		e.z += (i % 2) * 1.5
	end
	p.stats.spreadMin, p.stats.spreadMax, p.stats.bloom, p.spread = 0, 0, 0, 0
	p.procBudget = 30
	w:setAim(1, 1, 0, true)
	run(w, p, DT)
	local arcs = 0
	for _, ev in w.events do
		if ev[1] == E.ARC and ev[6] == Codec.C.BLUE then
			arcs += 1
		end
	end
	check("ГРОМОВЕРЖЕЦ: each hit forks lightning to 3 more targets", arcs == #m.forks, tostring(arcs))
end

-- Model ---------------------------------------------------------------------------------------------------
do
	local SHAPES = { Block = true, Ball = true, Cylinder = true, Wedge = true }
	for _, evolved in { false, true } do
		local specs, meta = Models.weaponSpec(ID, evolved)
		local tag = if evolved then "evolved" else "base"
		local groups, names = {}, {}
		local bad = 0
		for _, sp in specs do
			if sp.group then
				groups[sp.group] = true
			end
			if sp.name then
				names[sp.name] = true
			end
			if not SHAPES[sp.shape] or sp.size.X <= 0 or sp.size.Y <= 0 or sp.size.Z <= 0 then
				bad += 1
			end
		end
		check(tag .. " model: valid parts", bad == 0, tostring(bad))
		check(tag .. " model: part budget", #specs <= (if evolved then 92 else 78), tostring(#specs))
		local need = { "bolt", "coil", "mag", "prongU", "prongD" }
		if evolved then
			for _, g in { "prongL", "prongR", "capL", "capR", "rod" } do
				table.insert(need, g)
			end
		end
		local missing = {}
		for _, g in need do
			if not groups[g] then
				table.insert(missing, g)
			end
		end
		check(tag .. " model: animated groups", #missing == 0, table.concat(missing, ","))
		check(tag .. " model: muzzle, charge windows, heat sleeve", meta.muzzle ~= nil and names.Cell1 and names.Cell2 and names.Cell3 and names.Heat)
		check(tag .. " model: muzzle sits between the prong tips", near(meta.muzzle.Z, meta.prongTips[1].Z, 1e-6) and meta.prongTips[1].Y > meta.muzzle.Y and meta.prongTips[2].Y < meta.muzzle.Y)
		check(tag .. " model: hands on grip + handguard, pivots for spinning groups", meta.grip and meta.fore and meta.fore.Z < -1 and meta.pivots and meta.pivots.coil)
		if evolved then
			check("evolved model: storm core", names.Core == true)
		end
	end
end

-- Feel / audio wiring ----------------------------------------------------------------------------------------
do
	local audio = fs.readFile("src/client/Audio.luau")
	local function cue(name: string): boolean
		return audio:find("\n\t" .. name .. " = {", 1, true) ~= nil
	end
	for _, evolved in { false, true } do
		local f = Feel.get(ID, evolved)
		local missing = {}
		local list = table.clone(f.sound)
		for _, c in f.beats or {} do
			table.insert(list, c)
		end
		table.insert(list, f.dry)
		table.insert(list, f.impact.wallSound)
		for _, c in list do
			if not cue(c) then
				table.insert(missing, c)
			end
		end
		check((if evolved then "evolved" else "base") .. " feel: every sound cue exists", #missing == 0, table.concat(missing, ","))
		check((if evolved then "evolved" else "base") .. " feel: cell reload + coil mechanism", f.reload == "cell" and f.action == "coil")
	end
	check("evolution changes the tracer, impact and sound", Feel.get(ID, true).tracer.style ~= Feel.get(ID, false).tracer.style and Feel.get(ID, true).sound[1] ~= Feel.get(ID, false).sound[1])
end

print(string.format("W01: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("W01 checks failed")
end
