--!nonstrict
-- Shot presentation: turns "a gun fired these rounds" into muzzle flash, light, smoke, travelling
-- projectiles, impacts (enemy / wall), ejected casings, body recoil, camera and reticle response and
-- sound — all styled by the weapon's WeaponFeel profile. Used for the local player's predicted shots
-- and for teammates' replicated shots alike.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Defs = require(Shared:WaitForChild("Defs"))

local Fx = require(script.Parent.Fx)
local Rig = require(script.Parent.Rig)
local Audio = require(script.Parent.Audio)
local CameraRig = require(script.Parent.CameraRig)
local EnemyView = require(script.Parent.EnemyView)
local Feel = require(script.Parent.WeaponFeel)

local Shots = {}

local hud = nil
function Shots.setHud(h)
	hud = h
end

-- DD-112 stage 3: the own gun's mastery step (Defs.masteryTier) — a thicker, brighter tracer and flash.
local masteryTier = 0
function Shots.setMastery(tier: number)
	masteryTier = tier
end

function Shots.color(weapon: string, evolved: boolean): Color3
	if evolved then
		return Defs.Evolutions[Defs.Weapons[weapon].evolution].color
	end
	return Defs.Weapons[weapon].color
end

local function impact(feel, item, dir: Vector3, color: Color3, vk: number)
	if item.hits then
		for _, h in item.hits do
			Fx.impact(feel.impact.style, h.pos, dir, color, feel.impact.size * (0.6 + 0.4 * vk), feel.impact.fire)
			if h.id then
				EnemyView.impulse(h.id, dir.X, dir.Z, feel.impact.knock)
			end
		end
	end
	if item.wall then
		Fx.impactWall(
			item.to,
			item.normal or -dir,
			color,
			if feel.tracer and feel.tracer.style == "rail" then 2 else 0.9
		)
		if feel.impact.wallSound then
			Audio.at(feel.impact.wallSound, item.to, 0.7)
		end
	end
end

-- One trigger pull. character may be nil (fallback origin). items = { {to, hits = {{pos, id}}, wall, normal} }
-- ammoFrac (local shots) lets the sound tell the player the cell is running dry.
function Shots.fire(
	character: Model?,
	weapon: string,
	evolved: boolean,
	fallback: Vector3,
	items,
	isLocal: boolean,
	quiet: boolean?,
	ammoFrac: number?
)
	local feel = Feel.get(weapon, evolved)
	local color = Shots.color(weapon, evolved)
	local tier = if isLocal then masteryTier else 0
	if tier > 0 then
		color = color:Lerp(Color3.new(1, 1, 1), 0.07 * tier)
	end
	local mk = 1 + 0.12 * tier -- tracer width and flash size
	local mcf = character and Rig.muzzleCFrame(character)
	local first = items[1]
	if not mcf then
		local dir = if first then (first.to - fallback) else Vector3.zAxis
		dir = Vector3.new(dir.X, 0, dir.Z)
		mcf = CFrame.lookAt(fallback, fallback + (if dir.Magnitude > 0.01 then dir.Unit else Vector3.zAxis))
	end
	local origin = mcf.Position
	-- Readability: effects grow with camera distance so they still read from the tactical view.
	local vk = math.clamp((workspace.CurrentCamera.CFrame.Position - origin).Magnitude / 22, 1, 2.4)

	if not quiet then
		local fl = feel.flash
		Fx.muzzle(mcf, fl.style, color, fl.size * (0.6 + 0.4 * vk) * mk, fl.life)
		Fx.light(origin, color, fl.light * (1 + 0.25 * tier), 0.07)
		if fl.arc and character and not Fx.busy(40) then
			-- the charge jumps between the emitter electrodes as the bolt leaves
			local a, b = Rig.prongTips(character)
			if a and b then
				Fx.lightning(a, b, color, 0.1 * vk, 0.05)
			end
		end
		if fl.smoke then
			Fx.emit("muzzleSmoke", origin, fl.smoke, mcf.LookVector)
		end
		if fl.fire then
			Fx.emit("fire", origin + mcf.LookVector, 2)
		end
		if character then
			Rig.fire(character)
		end
		local sh = feel.shell
		if sh and character then
			task.delay(sh.delay or 0, function()
				local cf = Rig.ejectCFrame(character)
				if cf then
					Fx.shell(cf, sh.kind, color)
				end
			end)
		end
		for i, cue in feel.sound do
			if isLocal then
				Audio.play(cue, if i > 1 then 0.6 else 1)
			else
				Audio.at(cue, origin, if i > 1 then 0.3 else 0.55)
			end
		end
		if isLocal and feel.lowAmmo and ammoFrac and ammoFrac < feel.lowAmmo then
			-- the dry tick rises in pitch as the cell empties
			Audio.play("rifleLow", 1, 1 + (feel.lowAmmo - ammoFrac) * 1.6)
		end
		if feel.actionSound then
			local cue, delay = feel.actionSound[1], feel.actionSound[2]
			task.delay(delay, function()
				if isLocal then
					Audio.play(cue)
				else
					Audio.at(cue, origin, 0.4)
				end
			end)
		end
		if isLocal then
			local cam = feel.cam
			local look = mcf.LookVector
			CameraRig.recoil(cam.kick, Vector3.new(look.X, 0, look.Z), cam.push, cam.fov)
			if cam.shake > 0 then
				CameraRig.shake(cam.shake)
			end
			if hud then
				hud.recoil(cam.reticle)
			end
		end
	end

	local tr = feel.tracer
	for _, item in items do
		local to = item.to
		local delta = to - origin
		local dir = if delta.Magnitude > 0.01 then delta.Unit else mcf.LookVector
		if tr.style == "rail" then
			Fx.rail(origin, to, color, tr.width * (0.7 + 0.3 * vk) * mk, tr.stars)
			impact(feel, item, dir, color, vk)
		elseif tr.style == "lightning" then
			Fx.lightning(origin, to, color, tr.width * vk * mk, 0.12)
			Fx.projectile(origin, to, color, tr.width * vk * mk, tr.speed, tr.length, nil)
			impact(feel, item, dir, color, vk)
		else
			local speed = tr.speed * (0.9 + math.random() * 0.2)
			Fx.projectile(origin, to, color, tr.width * vk * mk, speed, tr.length * (0.7 + 0.3 * vk), function()
				impact(feel, item, dir, color, vk)
				if tr.fire and math.random() < 0.4 then
					Fx.emit("ember", to, 1)
				end
			end)
		end
	end
end

-- Continuous beam (owner renders every frame; teammates from BEAM events).
local beamOn = {}
function Shots.beam(
	key: any,
	character: Model?,
	weapon: string,
	evolved: boolean,
	fallback: Vector3,
	to: Vector3,
	hitEnemy: boolean,
	isLocal: boolean
)
	local feel = Feel.get(weapon, evolved)
	local color = Shots.color(weapon, evolved)
	-- DD-112: the own beam shows its mastery step like the bolts do (brighter, thicker)
	local tier = if isLocal then masteryTier else 0
	if tier > 0 then
		color = color:Lerp(Color3.new(1, 1, 1), 0.07 * tier)
	end
	local from = (character and Rig.muzzle(character)) or fallback
	local b = feel.beam or { width = 0.8, helix = 0.5, spin = 18 }
	local vk = math.clamp((workspace.CurrentCamera.CFrame.Position - from).Magnitude / 22, 1, 2)
	Fx.beamDraw(key, from, to, color, b.width * (0.7 + 0.3 * vk) * (1 + 0.12 * tier), b.helix, b.spin)
	if character then
		Rig.buzz(character, 1)
	end
	if math.random() < 0.35 then
		local dir = (to - from).Unit
		if hitEnemy then
			Fx.emit("hitViolet", to, 2, (-dir + Vector3.yAxis * 0.5).Unit)
		else
			Fx.emit("hitWhite", to, 1, (-dir + Vector3.yAxis).Unit)
		end
	end
	if math.random() < 0.15 then
		Fx.light(to, color, 10, 0.08)
	end
	if not beamOn[key] then
		beamOn[key] = true
		if isLocal then
			CameraRig.recoil(0, Vector3.zero, 0, 1.5)
		end
	end
	if isLocal then
		CameraRig.shake(0.006)
	end
end

function Shots.beamStop(key: any, character: Model?)
	if beamOn[key] then
		beamOn[key] = nil
		Fx.beamHide(key)
		if character then
			Rig.buzz(character, 0)
		end
	end
end

-- Replicated shot from a teammate (one event per pellet). Pellets in the same burst share one flash.
local lastBurst = {}
function Shots.remote(
	pid: number,
	character: Model?,
	weapon: string,
	evolved: boolean,
	ox: number,
	oz: number,
	ex: number,
	ez: number,
	range: number
)
	local now = os.clock()
	local quiet = lastBurst[pid] ~= nil and now - lastBurst[pid] < 0.03
	if not quiet then
		lastBurst[pid] = now
	end
	local to = Vector3.new(ex, 3, ez)
	local item = { to = to }
	local dx, dz = ex - ox, ez - oz
	local d = math.sqrt(dx * dx + dz * dz)
	if d > 0.01 then
		local hitD, rec = EnemyView.raycast(ox, oz, dx / d, dz / d, d + 1.5)
		if rec and hitD and hitD > d - 3 then
			item.hits = { { pos = to, id = rec.id } }
		elseif d < range - 1.5 then
			item.wall = true
			item.normal = Vector3.new(-dx / d, 0, -dz / d)
		end
	end
	Shots.fire(character, weapon, evolved, Vector3.new(ox, 3, oz), { item }, false, quiet)
end

return Shots
