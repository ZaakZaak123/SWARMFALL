-- Exports icon specs as JSON for offline preview rendering: lune run tools/export_icons > out.json
local serde = require("@lune/serde")
local H = require("../tests/harness")
local Icons = H.require("src/client/Icons")
print(serde.encode("json", Icons.Specs))
