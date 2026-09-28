--!strict
-- Test runner: lune run tests/run.luau
-- Requires POLLINATIONS_API_KEY for the live tests.

local process = require("@lune/process")

print("== pollinations-roblox test suite ==")
print("")

require("./npcdialogue_test")
print("")

require("./pollinations_live_test")

local lib = require("./lib")
local results = lib.summary()

print("")
print(("== done: %d passed, %d failed =="):format(results.pass, results.fail))
for _, f in results.failures do
	print(("  FAILED: %s -> %s"):format(f.name, tostring(f.err)))
end

if results.fail > 0 then
	process.exit(1)
end
