--!strict
local Guard = {}
function Guard.finite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
function Guard.direction(v: any): boolean
	return typeof(v) == "Vector3" and Guard.finite(v.X) and Guard.finite(v.Y)
		and Guard.finite(v.Z) and math.abs(v.Y) <= 0.01 and v.Magnitude >= 0.95 and v.Magnitude <= 1.05
end
function Guard.sequence(n: any, previous: number): boolean
	return Guard.finite(n) and n % 1 == 0 and n > previous and n <= 2147483647
end
function Guard.bucket(bucket, now: number, rate: number, capacity: number): boolean
	bucket.tokens = math.min(capacity, bucket.tokens + math.max(0, now - bucket.time) * rate)
	bucket.time = now
	if bucket.tokens < 1 then return false end
	bucket.tokens -= 1
	return true
end
return Guard
