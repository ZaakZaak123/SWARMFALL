--!strict
-- Deterministic xorshift32 RNG. Pure Luau so seeded runs replay identically in Studio and in Lune tests.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { s: number }, Rng))

function Rng.new(seed: number): Rng
	local s = math.floor(seed) % 4294967296
	if s == 0 then
		s = 0x9E3779B9
	end
	return setmetatable({ s = s }, Rng)
end

function Rng.next(self: Rng): number
	local s = self.s
	s = bit32.bxor(s, bit32.lshift(s, 13))
	s = bit32.bxor(s, bit32.rshift(s, 17))
	s = bit32.bxor(s, bit32.lshift(s, 5))
	self.s = s
	return s / 4294967296
end

function Rng.range(self: Rng, a: number, b: number): number
	return a + (b - a) * self:next()
end

function Rng.int(self: Rng, a: number, b: number): number
	return math.min(b, a + math.floor(self:next() * (b - a + 1)))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

-- weights: { [key]: number }, order: { key } for determinism
function Rng.weighted<K>(self: Rng, weights: { [K]: number }, order: { K }): K?
	local total = 0
	for _, k in order do
		total += weights[k] or 0
	end
	if total <= 0 then
		return nil
	end
	local roll = self:next() * total
	for _, k in order do
		roll -= weights[k] or 0
		if roll <= 0 then
			return k
		end
	end
	return order[#order]
end

return Rng
