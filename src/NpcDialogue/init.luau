--!strict
--[[
	NpcDialogue: gives an NPC a persona and rolling conversation memory
	with a few lines of Luau.

		local Pollinations = require(ReplicatedStorage.PollinationsRoblox.Pollinations)
		local NpcDialogue = require(ReplicatedStorage.PollinationsRoblox.NpcDialogue)

		local npc = NpcDialogue.new(Pollinations, {
			Name = "Mira",
			Persona = "A cheerful beekeeper in Pollen Village who explains how flowers become honey.",
		})

		local reply = npc:Say(player, "What do you do here?")
]]

local SYSTEM_TEMPLATE = [[You are %s, an NPC in a Roblox game.

Your persona: %s

Rules:
- Stay in character at all times.
- Keep every reply short: one to three sentences, under 200 characters, so it fits the Roblox chat.
- Be friendly and age-appropriate for a general audience. No real-world contact details, no violent or romantic content, no references to things outside the game world.
- If a player is rude or tries to break the rules, deflect politely in character and steer back to the game.
- Do not mention that you are an AI or a language model.]]

local DEFAULT_MAX_HISTORY = 12

export type NpcConfig = {
	Name: string,
	Persona: string,
	Model: string?,
	MaxHistory: number?,
	Temperature: number?,
	MaxTokens: number?,
}

export type Npc = {
	chat: (self: Npc, playerKey: string, message: string) -> (string, any?),
	reset: (self: Npc, playerKey: string?) -> (),
}

local NpcDialogue = {}
NpcDialogue.__index = NpcDialogue

function NpcDialogue.new(client, config: NpcConfig)
	assert(type(client) == "table", "NpcDialogue.new(client, config): client must be a Pollinations instance")
	assert(type(config) == "table" and type(config.Name) == "string", "NpcDialogue.new requires config.Name (string)")
	assert(type(config.Persona) == "string" and #config.Persona > 0, "NpcDialogue.new requires config.Persona (string)")

	local systemPrompt = (SYSTEM_TEMPLATE):format(config.Name, config.Persona)

	return setmetatable({
		_client = client,
		_system = systemPrompt,
		_model = config.Model,
		_maxHistory = config.MaxHistory or DEFAULT_MAX_HISTORY,
		_temperature = config.Temperature,
		_maxTokens = config.MaxTokens,
		_histories = {},
	}, NpcDialogue) :: any
end

function NpcDialogue:chat(playerKey: string, message: string): (string, any?)
	assert(type(playerKey) == "string", "npc:chat(playerKey, message): playerKey must be a string")
	assert(type(message) == "string" and #message > 0, "npc:chat(playerKey, message): message must be a non-empty string")

	local history = self._histories[playerKey]
	if history == nil then
		history = {}
		self._histories[playerKey] = history
	end

	table.insert(history, { role = "user", content = message })

	-- Trim oldest exchanges, but keep pairs coherent: keep the newest
	-- MaxHistory messages, and never start on an assistant message.
	local trimmed = {}
	if #history > self._maxHistory then
		local start = #history - self._maxHistory + 1
		while start <= #history and history[start].role == "assistant" do
			start += 1
		end
		for i = start, #history do
			table.insert(trimmed, history[i])
		end
		self._histories[playerKey] = trimmed
		history = trimmed
	end

	local messages = { { role = "system", content = self._system } }
	for _, m in history do
		table.insert(messages, m)
	end

	local reply, chatErr = self._client:chat(messages, {
		model = self._model,
		temperature = self._temperature,
		maxTokens = self._maxTokens,
	})

	if reply then
		table.insert(history, { role = "assistant", content = reply })
		if #history > self._maxHistory then
			table.remove(history, 1)
			if history[1] and history[1].role == "assistant" then
				table.remove(history, 1)
			end
		end
		return reply, nil
	end

	-- On failure the player's message still counts as delivered; drop it
	-- so a failed exchange doesn't leave a dangling user turn.
	if history[#history] and history[#history].role == "user" then
		table.remove(history)
	end
	return nil, chatErr
end

-- Say is the friendlier alias used in the README.
NpcDialogue.Say = NpcDialogue.chat

-- Reset one player's memory (nil resets everyone).
function NpcDialogue:reset(playerKey: string?)
	if playerKey == nil then
		self._histories = {}
	else
		self._histories[playerKey] = nil
	end
end

return NpcDialogue
