-- Build styles (DD-017): synergy mechanics and "do the styles really play differently" runs.
-- Usage (repo root):
--   lune run tests/styles                 fast checks (draft + synergies)
--   lune run tests/styles run <STYLE> [weapon] [seed]   bot plays O01 drafting only that style
local process = require("@lune/process")
local H = require("./harness")
local Bot = require("./bot")

local Defs = H.require("src/shared/Defs")
local World = H.require("src/server/Sim/World")
local Combat = H.require("src/server/Sim/Combat")
local Codec = H.require("src/shared/Codec")

local failures = 0
local function check(ok: boolean, msg: string)
	print((if ok then "  PASS " else "  FAIL ") .. msg)
	if not ok then
		failures += 1
	end
end

local args = process.args
if args[1] == "run" then
	local style = args[2] or "CROWD"
	local weapon = args[3] or "W_ARC_RIFLE"
	local seed = tonumber(args[4]) or 20261023
	local out = Bot.run(weapon, 1, seed, args[5] == "v", nil, 1, nil, { op = "O01", orbit = 32, style = style })
	local r = out.result
	local me = r.players[1]
	local total = math.max(1, me.kills)
	local causes = {}
	for c, name in { [0] = "shot", [1] = "arc", [2] = "blast", [3] = "burn", [4] = "S01", [5] = "card" } do
		local n = me.causes[c] or 0
		if n > 0 then
			table.insert(causes, string.format("%s %d%%", name, math.floor(n / total * 100 + 0.5)))
		end
	end
	table.sort(causes)
	local cards = {}
	for _, u in me.upgrades do
		table.insert(cards, u[1]:sub(5) .. u[2])
	end
	print(
		string.format(
			"STYLE %-8s %s %s %s  kills %d  reactor %s  lowHP %d  hitsTaken %d  dmg %d\n  causes: %s\n  cards: %s",
			style,
			weapon,
			if r.victory then "VICTORY" else "DEFEAT",
			Bot.fmt(r.time),
			me.kills,
			if r.reactor then math.floor(r.reactor * 100) .. "%" else "-",
			math.floor(out.lowestHp),
			me.hitsTaken,
			me.damage,
			table.concat(causes, ", "),
			table.concat(cards, " ")
		)
	)
	process.exit(if r.victory then 0 else 2)
end

local function world(weapon, op)
	local w = World.new({ seed = 7, op = op or "O01", players = { { id = 1, weapon = weapon or "W_ARC_RIFLE" } } })
	w:step(5)
	w.t = 120
	for _, e in w.enemies do
		e.alive = false
	end
	local p = w.playerList[1]
	-- Stand somewhere with 40 studs of open ground to the north (+Z), away from the reactor.
	for x = -120, 120, 10 do
		for z = -120, 80, 10 do
			if w.nav.free(x, z, 3) and w.nav.ray(x, z, 0, 1, 40) >= 40 and (x * x + z * z) > 900 then
				p.x, p.z = x, z
				return w, p
			end
		end
	end
	return w, p
end

local function give(w, p, ranks)
	for id, r in ranks do
		p.ranks[id] = r
	end
	Combat.recompute(p)
end

do -- first offer: one card of each style
	local ok = true
	for seed = 1, 20 do
		local w = World.new({ seed = seed, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE" } } })
		local p = w.playerList[1]
		Combat.makeOffer(w, p)
		local seen = {}
		for _, c in p.offer.choices do
			seen[Defs.Upgrades[c].style] = true
		end
		ok = ok and seen.CROWD and seen.LINE and seen.CONTROL
	end
	check(ok == true, "first offer shows one card of each style (20 seeds)")
end

do -- every card has a style
	local ok = true
	for _, id in Defs.UpgradeOrder do
		ok = ok and Defs.Styles[Defs.Upgrades[id].style] ~= nil
	end
	check(ok, "all 12 cards belong to a style")
end

do -- the draft leans towards completing a started synergy
	local partner, base = 0, 0
	for seed = 1, 300 do
		local w = World.new({ seed = seed, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE" } } })
		local p = w.playerList[1]
		p.offersMade = 3
		give(w, p, { UPG_FREEZE = 1 })
		p.slots = 1
		Combat.makeOffer(w, p)
		if table.find(p.offer.choices, "UPG_SHIELD") then
			partner += 1
		end
		if table.find(p.offer.choices, "UPG_FIRERATE") then
			base += 1
		end
	end
	check(
		partner > base * 1.3,
		string.format("synergy partner offered more often (Барьер %d vs Разгон %d of 300)", partner, base)
	)
end

do -- ЛИНИЯ ОГНЯ: 3rd+ pierced targets are crits
	local w, p = world()
	give(w, p, { UPG_PIERCE = 3, UPG_CRIT = 1 })
	check(p.stats.lineFire, "Пробой + Точный удар enables ЛИНИЯ ОГНЯ")
	local line = {}
	for i = 1, 4 do
		local e = w:spawnEnemy("EN_RUNNER", p.x, p.z + 6 + i * 3.6, 0)
		e.hp, e.maxHp = 1e6, 1e6
		e.dmgFlags = 0
		table.insert(line, e)
	end
	p.aimX, p.aimZ = 0, 1
	p.spread = 0
	p.stats.spread, p.stats.spreadMin, p.stats.spreadMax = 0, 0, 0
	Combat.fire(w, p)
	local crit = Codec.DF.CRIT
	local c3 = bit32.band(line[3].dmgFlags, crit) ~= 0 and bit32.band(line[4].dmgFlags, crit) ~= 0
	check(c3, "3rd and 4th enemies in the line take crits")
	local hit3 = 1e6 - line[3].hp
	local hit2 = 1e6 - line[2].hp
	check(hit3 >= hit2 * 1.5, string.format("no falloff after the 2nd target (2nd %.1f, 3rd %.1f)", hit2, hit3))
end

do -- ЛЕДЯНОЙ ПАНЦИРЬ: a shielded hit freezes the crowd
	local w, p = world()
	give(w, p, { UPG_FREEZE = 1, UPG_SHIELD = 1 })
	local ring = {}
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local e = w:spawnEnemy("EN_RUNNER", p.x + math.cos(a) * 5, p.z + math.sin(a) * 5, 0)
		e.hp, e.maxHp = 1e6, 1e6
		table.insert(ring, e)
	end
	w:rebuildGrid()
	p.shield = 20
	p.iframeUntil, p.graceUntil = 0, 0
	w:hurtPlayer(p, 5, p.x + 1, p.z)
	local frozen = 0
	for _, e in ring do
		if e.stunUntil > w.t and e.slowUntil > w.t then
			frozen += 1
		end
	end
	check(frozen == 6, "shield hit freezes everyone nearby (" .. frozen .. "/6)")
	local before = ring[1].stunUntil
	p.graceUntil = 0
	w:hurtPlayer(p, 5, p.x + 1, p.z)
	check(ring[1].stunUntil == before, "frost burst has a cooldown")
end

do -- ЛЕДОЛОМ: dash shatters slowed enemies for double damage
	local w, p = world()
	give(w, p, { UPG_DASH_SHOCK = 1, UPG_FREEZE = 1 })
	local a = w:spawnEnemy("EN_RUNNER", p.x + 2, p.z, 0)
	local b = w:spawnEnemy("EN_RUNNER", p.x - 2, p.z, 0)
	for _, e in { a, b } do
		e.hp, e.maxHp = 1e6, 1e6
	end
	a.slow, a.slowUntil = 0.3, w.t + 5
	w:rebuildGrid()
	w:dash(1, 0, 1)
	Combat.updatePlayer(w, p, 1 / 30)
	local da, db = 1e6 - a.hp, 1e6 - b.hp
	check(
		db > 0 and math.abs(da - db * Defs.IceBreakMult) < 1,
		string.format("slowed target takes ×2 (%.0f vs %.0f)", da, db)
	)
end

do -- Крио: a slowed enemy killed by the weapon shatters into shards that chill neighbours
	local w, p = world()
	give(w, p, { UPG_FREEZE = 2 })
	local victim = w:spawnEnemy("EN_RUNNER", p.x, p.z + 12, 0)
	local around = {}
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		local e = w:spawnEnemy("EN_RUNNER", victim.x + math.cos(a) * 4, victim.z + math.sin(a) * 4, 0)
		e.hp, e.maxHp = 1e6, 1e6
		table.insert(around, e)
	end
	w:rebuildGrid()
	victim.slow, victim.slowUntil = 0.3, w.t + 2
	w:kill(victim, p, 0, 0)
	local hit, chilled = 0, 0
	for _, e in around do
		if e.hp < 1e6 then
			hit += 1
		end
		if e.slowUntil > w.t then
			chilled += 1
		end
	end
	local want = Defs.UpgradeValues.UPG_FREEZE.shards[2]
	check(
		hit == want and chilled == want,
		string.format("shatter hits and chills %d neighbours (%d/%d)", want, hit, chilled)
	)
	local unslowed = w:spawnEnemy("EN_RUNNER", p.x + 20, p.z, 0)
	w:rebuildGrid()
	local before = 0
	for _, e in around do
		before += e.hp
	end
	w:kill(unslowed, p, 0, 0)
	local after = 0
	for _, e in around do
		after += e.hp
	end
	check(before == after, "an unslowed kill does not shatter")
end

do -- Крио chills on impact: a one-shot kill (railgun) still shatters
	local w, p = world("W_RAILGUN")
	give(w, p, { UPG_FREEZE = 1 })
	local victim = w:spawnEnemy("EN_RUNNER", p.x, p.z + 12, 0)
	local around = {}
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2
		local e = w:spawnEnemy("EN_RUNNER", victim.x + math.cos(a) * 4, victim.z + math.sin(a) * 4, 0)
		e.hp, e.maxHp = 1e6, 1e6
		table.insert(around, e)
	end
	w:rebuildGrid()
	Combat.hit(w, p, victim, 1e4, 0, 1)
	local hit = 0
	for _, e in around do
		if e.hp < 1e6 then
			hit += 1
		end
	end
	check(
		not victim.alive and hit == Defs.UpgradeValues.UPG_FREEZE.shards[1],
		"one-shot kill with Крио shatters (" .. hit .. ")"
	)
end

do -- Вулкан + Крио: point-blank pellets stun small enemies, distant ones only slow
	local w, p = world("W_SCATTERGUN")
	give(w, p, { UPG_FREEZE = 2 })
	local near = w:spawnEnemy("EN_RUNNER", p.x, p.z + 6, 0)
	local far = w:spawnEnemy("EN_RUNNER", p.x, p.z + 25, 0)
	for _, e in { near, far } do
		e.hp, e.maxHp = 1e6, 1e6
	end
	Combat.hit(w, p, near, 1, 0, 1)
	Combat.hit(w, p, far, 1, 0, 1)
	check(
		near.stunUntil > w.t and far.stunUntil <= w.t and far.slowUntil > w.t,
		"point-blank freeze stuns, range only slows"
	)
end

do -- Вулкан's heavy frame takes 30% less damage
	local w = World.new({
		seed = 3,
		op = "O01",
		players = { { id = 1, weapon = "W_SCATTERGUN" }, { id = 2, weapon = "W_ARC_RIFLE" } },
	})
	w.t = 120
	local a, b = w.players[1], w.players[2]
	w:hurtPlayer(a, 10, a.x + 1, a.z)
	w:hurtPlayer(b, 10, b.x + 1, b.z)
	check(math.abs((a.maxHp - a.hp) - (b.maxHp - b.hp) * 0.7) < 1e-6, "Вулкан: −30% incoming damage")
end

do -- «Барьер» refill also shields the extractor (O06 is the first story sortie with one since DD-078), without stacking
	local w, p = world(nil, "O06")
	give(w, p, { UPG_SHIELD = 3 })
	p.shieldKills = 100
	local e = w:spawnEnemy("EN_RUNNER", p.x + 30, p.z, 0)
	w:kill(e, p, 0, 0)
	local rc = w.mission.reactor
	check(
		rc.shield == Defs.UpgradeValues.UPG_SHIELD.reactor[3],
		"Барьер shields the reactor (" .. rc.shield .. ")"
	)
	local hp = rc.hp
	w.mission:hurtReactor(10, 0, 30, false)
	check(rc.hp == hp and rc.shield < Defs.UpgradeValues.UPG_SHIELD.reactor[3], "reactor shield absorbs a hit first")
end

do -- synergy banner fires once when the pair completes
	local w = World.new({ seed = 7, op = "O02", players = { { id = 1, weapon = "W_ARC_RIFLE" } } })
	local p = w.playerList[1]
	p.slots = 0
	Combat.applyChoice(w, p, "UPG_PIERCE")
	w:drainEvents()
	Combat.applyChoice(w, p, "UPG_CRIT")
	local banners = 0
	for _, ev in w:drainEvents() do
		if ev[1] == Codec.E.BANNER and ev[2]:find("ЛИНИЯ ОГНЯ") then
			banners += 1
		end
	end
	Combat.applyChoice(w, p, "UPG_CRIT")
	for _, ev in w:drainEvents() do
		if ev[1] == Codec.E.BANNER and ev[2]:find("ЛИНИЯ ОГНЯ") then
			banners += 1
		end
	end
	check(banners == 1, "synergy announced once")
	-- O01 shows bare cards (DD-024): the synergy works but is not announced.
	local w1 = World.new({ seed = 7, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE" } } })
	local p1 = w1.playerList[1]
	p1.slots = 0
	Combat.applyChoice(w1, p1, "UPG_PIERCE")
	Combat.applyChoice(w1, p1, "UPG_CRIT")
	local quiet = true
	for _, ev in w1:drainEvents() do
		if ev[1] == Codec.E.BANNER and ev[2]:find("СИНЕРГИЯ") then
			quiet = false
		end
	end
	check(quiet and p1.synergies.SYN_PIERCE_CRIT == true, "O01: synergy active but not announced")
end

do -- a new profile's second O01 offer shows «Расщепление»
	local ok = 0
	for seed = 1, 10 do
		local w = World.new({ seed = seed, op = "O01", players = { { id = 1, weapon = "W_ARC_RIFLE", s01 = false } } })
		local p = w.playerList[1]
		Combat.makeOffer(w, p)
		local first = p.offer.choices
		Combat.applyChoice(w, p, first[1] ~= "UPG_MULTISHOT" and first[1] or first[2])
		Combat.makeOffer(w, p)
		if table.find(first, "UPG_MULTISHOT") or table.find(p.offer.choices, "UPG_MULTISHOT") then
			ok += 1
		end
	end
	check(ok == 10, "Расщепление shown in the first two O01 offers of a new profile (" .. ok .. "/10)")
end

if failures > 0 then
	print(failures .. " FAILURE(S)")
	process.exit(1)
end
print("ALL STYLE CHECKS PASSED")
