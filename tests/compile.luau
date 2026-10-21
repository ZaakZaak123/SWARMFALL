-- Syntax/bytecode compile check for every Luau source. Usage: lune run tests/compile
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local count, failed = 0, 0
local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif name:sub(-5) == ".luau" then
			local ok, err = pcall(luau.compile, fs.readFile(path))
			count += 1
			if not ok then
				failed += 1
				print("FAIL " .. path .. "\n  " .. tostring(err))
			end
		end
	end
end
walk("src")
walk("tests")
print(string.format("compiled %d files, %d failed", count, failed))
if failed > 0 then
	error("compile failures")
end
