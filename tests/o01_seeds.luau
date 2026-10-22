-- O01 robustness: the defending bot over one seed passed on the command line.
local process = require("@lune/process")
local Bot = require("./bot")
local seed = tonumber(process.args[1]) or 1
local out = Bot.run("W_ARC_RIFLE", 1, seed, false, nil, 1, nil, { op = "O01", orbit = 32, s01 = false })
local r = out.result
print(string.format("seed %d: %s (%s) at %s reactor %d%% kills %d s01best %d", seed, if r.victory then "VICTORY" else "DEFEAT", r.reason, Bot.fmt(r.time), math.floor((r.reactor or 0) * 100), r.kills, r.players[1].s01.best))
