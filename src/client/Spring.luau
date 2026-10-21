--!nonstrict
-- Damped springs (scalar or Vector3) for procedural animation: recoil, flinch, sway, camera kick.
-- freq = oscillations per second, damp = damping ratio (1 = critical, <1 = bouncy).

local Spring = {}
Spring.__index = Spring

function Spring.new(freq: number, damp: number, zero: any?)
	local z = zero or 0
	return setmetatable({ x = z, v = z * 0, target = z, f = freq, d = damp }, Spring)
end

function Spring:impulse(v)
	self.v += v
end

function Spring:step(dt: number)
	local w = self.f * 2 * math.pi
	local remaining = math.min(dt, 0.1)
	while remaining > 0 do
		local h = math.min(remaining, 1 / 120)
		remaining -= h
		local a = (self.target - self.x) * (w * w) - self.v * (2 * self.d * w)
		self.v += a * h
		self.x += self.v * h
	end
	return self.x
end

function Spring:reset(value)
	self.x = value
	self.v = value * 0
	self.target = value
end

return Spring
