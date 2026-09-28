--!strict
-- Live tests: the real Pollinations API over HTTPS, from headless Luau.
--
-- Requires the API key in the environment:
--   POLLINATIONS_API_KEY=... lune run tests/run.luau

local process = require("@lune/process")
local task = require("@lune/task")
local lib = require("./lib")
local Pollinations = require("../src/Pollinations")

-- The live API rate-limits bursts (answering 401), so live calls are spaced.
local function breathe()
	task.wait(2)
end

local apiKey = process.env.POLLINATIONS_API_KEY
if apiKey == nil then
	error("Set POLLINATIONS_API_KEY in the environment before running the live tests")
end

print("Pollinations client (live https, real key):")

local client = Pollinations.new({ apiKey = apiKey })

lib.check("listModels returns the live list with the default model", function()
	local models, err = client:listModels()
	lib.assertEq(err, nil, "listModels error")
	lib.assertTrue(#models > 100, "model list is large (got " .. #models .. ")")
	local names = {}
	for _, m in models do
		table.insert(names, m.name)
	end
	local found = table.find(names, "openai/gpt-5.4-nano") ~= nil
	lib.assertTrue(found, "default model present in live list")
end)

breathe()
lib.check("chat with a real key returns a reply", function()
	local reply, err = client:chat({
		{ role = "user", content = "Reply with exactly the word: pollen" },
	}, { maxTokens = 20 })
	lib.assertEq(err, nil, "chat error")
	lib.assertTrue(typeof(reply) == "string" and #reply > 0, "reply is a non-empty string")
	print(("       reply: %s"):format(reply))
end)

breathe()
lib.check("system prompts work (persona answered)", function()
	local reply, err = client:chat({
		{ role = "system", content = "You are Mira, a beekeeper. Reply with at most one short sentence." },
		{ role = "user", content = "Who are you?" },
	}, { maxTokens = 60 })
	lib.assertEq(err, nil, "chat error")
	lib.assertTrue(typeof(reply) == "string" and #reply > 0, "reply present")
	print(("       reply: %s"):format(reply))
end)

breathe()
lib.check("a bad model is a bad_request error", function()
	local _, err = client:chat({ { role = "user", content = "hi" } }, { model = "not-a-real-model" })
	lib.assertEq(err.kind, "bad_request", "error kind")
end)

breathe()
lib.check("a wrong key is an auth error (not a thrown error)", function()
	local bad = Pollinations.new({ apiKey = "sk-this-key-does-not-work" })
	-- a nonce keeps the prompt out of the anonymous cache, so the key is actually checked
	local nonce = ("auth-check %d"):format(math.floor(os.clock() * 1000))
	local _, err = bad:chat({ { role = "user", content = "Reply with: " .. nonce } })
	lib.assertEq(err.kind, "auth", "error kind")
end)

breathe()
lib.check("ask() does a one-shot GET text completion", function()
	local text, err = client:ask("Say the word: honey")
	lib.assertEq(err, nil, "ask error")
	lib.assertTrue(typeof(text) == "string" and #text > 0, "ask returns text")
	print(("       ask: %s"):format(text:sub(1, 60)))
end)

breathe()
lib.check("default model accessor", function()
	lib.assertEq(client:defaultModel(), "openai/gpt-5.4-nano", "default model")
end)

-- End-to-end: NpcDialogue over the real client.
print("NpcDialogue (live https, real key):")

local NpcDialogue = require("../src/NpcDialogue")

breathe()
lib.check("an NPC with a persona stays in character over the live API", function()
	local mira = NpcDialogue.new(client, {
		Name = "Mira",
		Persona = "A cheerful beekeeper in Pollen Village who only ever talks about bees, honey and flowers.",
	})
	local reply, err = mira:chat("test-player", "What is your favourite thing in the whole village?")
	lib.assertEq(err, nil, "npc chat error")
	lib.assertTrue(typeof(reply) == "string" and #reply > 0, "npc reply present")
	print(("       reply: %s"):format(reply))
end)
