-- Minimal Roblox module environment for running pure-Luau game modules under Lune.
-- Maps Instance-style paths (script.Parent.X, game:GetService("ReplicatedStorage").Shared.X) to files.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Harness = {}

local SERVICE_DIR = {
	ReplicatedStorage = "src",
	ServerScriptService = "src/server",
}
local ALIAS = { Shared = "shared", Sim = "Sim" }

local cache: { [string]: any } = {}
local nodeMeta = {}

local function node(path: string)
	return setmetatable({ __path = path }, nodeMeta)
end

local function parentOf(path: string): string
	return path:match("^(.*)/[^/]+$") or path
end

local function child(path: string, name: string)
	return node(path .. "/" .. (ALIAS[name] or name))
end

nodeMeta.__index = function(self, key)
	local path = rawget(self, "__path")
	if key == "Parent" then
		return node(parentOf(path))
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(_, name)
			return child(path, name)
		end
	elseif key == "Name" then
		return path:match("([^/]+)$")
	end
	return child(path, key)
end

local game = {
	GetService = function(_, name)
		return node(assert(SERVICE_DIR[name], "service " .. tostring(name)))
	end,
}

local requireModule

local function load(path: string)
	local file = path .. ".luau"
	assert(fs.isFile(file), "module not found: " .. file)
	local env = setmetatable({
		game = game,
		script = node(path),
		require = requireModule,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		Vector2 = roblox.Vector2,
		math = math,
		table = table,
		string = string,
		bit32 = bit32,
		buffer = buffer,
		os = os,
		print = print,
		warn = print,
		error = error,
		assert = assert,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		type = type,
		typeof = typeof,
		tostring = tostring,
		tonumber = tonumber,
		select = select,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		pcall = pcall,
		unpack = table.unpack,
	}, {})
	local fn = luau.load(fs.readFile(file), { debugName = file, environment = env })
	return fn()
end

function requireModule(target)
	local path = if type(target) == "table" then rawget(target, "__path") else target
	assert(type(path) == "string", "bad require target")
	local cached = cache[path]
	if cached == nil then
		cached = load(path)
		cache[path] = cached
	end
	return cached
end

Harness.require = requireModule
Harness.Color3 = roblox.Color3
Harness.Enum = roblox.Enum

return Harness
