--!strict
-- Unit tests for NpcDialogue: persona wiring, memory handling and error
-- paths, using a fake Pollinations client (no network).

local lib = require("./lib")
local NpcDialogue = require("../src/NpcDialogue")

-- A fake Pollinations client that records the messages it receives and
-- can be told to fail.
local function fakeClient(config)
	config = config or {}
	local fake = {
		received = {},
		replies = config.replies or { "I am fine, thank you!" },
		failWith = config.failWith,
		call = 0,
	}
	function fake:chat(messages, _opts)
		self.call += 1
		table.insert(self.received, messages)
		if self.failWith then
			return nil, self.failWith
		end
		return self.replies[math.min(self.call, #self.replies)], nil
	end
	return fake
end

print("NpcDialogue (fake client, no network):")

lib.check("persona and rules reach the system prompt", function()
	local fake = fakeClient()
	local npc = NpcDialogue.new(fake, {
		Name = "Mira",
		Persona = "A beekeeper who loves honey.",
	})
	local reply = npc:chat("1", "hello?")
	lib.assertEq(reply, "I am fine, thank you!", "reply")
	local messages = fake.received[1]
	lib.assertEq(messages[1].role, "system", "system role")
	local system = messages[1].content
	lib.assertTrue(system:find("Mira", 1, true) ~= nil, "system prompt contains NPC name")
	lib.assertTrue(system:find("beekeeper", 1, true) ~= nil, "system prompt contains persona")
	lib.assertTrue(system:find("200 characters", 1, true) ~= nil, "system prompt contains chat length rule")
	lib.assertEq(messages[2].role, "user", "user role")
	lib.assertEq(messages[2].content, "hello?", "user content")
end)

lib.check("conversation memory rolls forward", function()
	local fake = fakeClient({ replies = { "first reply", "second reply" } })
	local npc = NpcDialogue.new(fake, { Name = "Mira", Persona = "A beekeeper." })
	npc:chat("1", "question one")
	npc:chat("1", "question two")
	local messages = fake.received[2]
	-- system, user, assistant, user
	lib.assertEq(#messages, 4, "second call carries history")
	lib.assertEq(messages[3].content, "first reply", "history contains first reply")
	lib.assertEq(messages[4].content, "question two", "history contains second question")
end)

lib.check("histories are isolated per player key", function()
	local fake = fakeClient()
	local npc = NpcDialogue.new(fake, { Name = "Mira", Persona = "A beekeeper." })
	npc:chat("player-a", "hi from a")
	npc:chat("player-b", "hi from b")
	local b = fake.received[2]
	lib.assertEq(#b, 2, "player-b's prompt has no player-a history")
	lib.assertEq(b[2].content, "hi from b", "player-b's message")
end)

lib.check("history is trimmed to MaxHistory and never starts on an assistant turn", function()
	local replies = {}
	for i = 1, 20 do
		table.insert(replies, ("reply %d"):format(i))
	end
	local fake = fakeClient({ replies = replies })
	local npc = NpcDialogue.new(fake, { Name = "Mira", Persona = "A beekeeper.", MaxHistory = 4 })
	for i = 1, 10 do
		npc:chat("1", ("message %d"):format(i))
	end
	local messages = fake.received[10]
	-- system + at most MaxHistory history messages, newest first in, oldest out
	lib.assertTrue(#messages <= 5, "history never exceeds MaxHistory (got " .. #messages .. ")")
	lib.assertTrue(#messages >= 3, "history keeps the newest exchanges (got " .. #messages .. ")")
	lib.assertEq(messages[2].role, "user", "trimmed history starts with a user turn")
	lib.assertEq(messages[#messages].content, "message 10", "trimmed history keeps the newest question")
end)

lib.check("failed exchanges do not corrupt history", function()
	local fake = fakeClient()
	local npc = NpcDialogue.new(fake, { Name = "Mira", Persona = "A beekeeper." })
	npc:chat("1", "good question")
	fake.failWith = { kind = "auth", message = "HTTP 401" }
	local reply, err = npc:chat("1", "will fail")
	lib.assertEq(reply, nil, "failed reply is nil")
	lib.assertEq(err.kind, "auth", "error kind surfaces")
	fake.failWith = nil
	npc:chat("1", "back again")
	local messages = fake.received[3]
	-- The failed user turn is dropped: system, user, assistant, user
	lib.assertEq(#messages, 4, "no dangling user turn after failure")
	lib.assertEq(messages[4].content, "back again", "latest message present")
end)

lib.check("reset clears one player or everyone", function()
	local fake = fakeClient()
	local npc = NpcDialogue.new(fake, { Name = "Mira", Persona = "A beekeeper." })
	npc:chat("1", "a")
	npc:chat("2", "b")
	npc:reset("1")
	local second = fake.received[2]
	lib.assertEq(#second, 2, "sanity: player-2 prompt before re-chat")
	npc:chat("1", "a again")
	local fresh = fake.received[3]
	lib.assertEq(#fresh, 2, "player-1 history was reset")
	npc:reset()
	local afterAll = NpcDialogue.new(fake, { Name = "Mira", Persona = "A beekeeper." })
	lib.assertTrue(next(afterAll._histories) == nil, "reset(nil) clears all")
end)

lib.check("misconfiguration throws early", function()
	local ok1 = pcall(function()
		NpcDialogue.new(nil, { Name = "Mira", Persona = "x" })
	end)
	lib.assertTrue(not ok1, "nil client throws")
	local ok2 = pcall(function()
		NpcDialogue.new(fakeClient(), { Name = "Mira" })
	end)
	lib.assertTrue(not ok2, "missing persona throws")
end)
