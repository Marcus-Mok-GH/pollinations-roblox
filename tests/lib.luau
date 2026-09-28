--!strict
-- Shared test helpers. Require this module from every spec file; it is a
-- singleton in the lune require cache, so results aggregate across specs.

local results = { pass = 0, fail = 0, failures = {} }

local lib = {}

function lib.check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.pass += 1
		print(("  ok  %s"):format(name))
	else
		results.fail += 1
		table.insert(results.failures, { name = name, err = err })
		print(("  FAIL %s: %s"):format(name, tostring(err)))
	end
end

function lib.assertEq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(
			("%s: expected %s, got %s"):format(
				label or "assertEq",
				tostring(expected),
				tostring(actual)
			)
		)
	end
end

function lib.assertTrue(cond: any, label: string)
	if not cond then
		error(("assertTrue failed: %s"):format(label))
	end
end

function lib.summary()
	return results
end

return lib
