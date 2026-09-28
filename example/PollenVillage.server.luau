--!strict
--[[
	Pollen Village example: one talking NPC, powered by Pollinations.

	Server side: builds the NPC at runtime, starts conversations with a
	ProximityPrompt, and forwards what the player types in chat while the
	conversation is open. The reply is sent to the player's client, which
	displays it in the Roblox chat.

	Requires:
	  * HttpService enabled (Game Settings -> Security -> Allow HTTP Requests)
	  * A secret named POLLINATIONS_API_KEY in the secrets store
	    (Creator Hub -> your experience -> Secrets), or Pollinations.new({ apiKey = "..." })
	    for local testing only.

	Any model from the live list works: https://gen.pollinations.ai/text/models
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Pollinations = require(ReplicatedStorage.PollinationsRoblox.Pollinations)
local NpcDialogue = require(ReplicatedStorage.PollinationsRoblox.NpcDialogue)

-- Any text model from the live model list.
local MODEL = "openai/gpt-5.4-nano"

-- Remote event the client listens on for NPC replies.
local replyEvent = Instance.new("RemoteEvent")
replyEvent.Name = "NpcReply"
replyEvent.Parent = ReplicatedStorage

--------------------------------------------------------------------
-- Build the NPC at runtime: a simple rig standing in the village.
--------------------------------------------------------------------
local function buildNpc(): Model
	local npc = Instance.new("Model")
	npc.Name = "Mira"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 3, 1)
	body.Color = Color3.fromRGB(255, 205, 66)
	body.Material = Enum.Material.SmoothPlastic
	body.CFrame = CFrame.new(0, 3.5, -15)
	body.Anchored = true
	body.Parent = npc

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Shape = Enum.PartType.Ball
	head.Color = Color3.fromRGB(255, 235, 160)
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = CFrame.new(0, 6.2, -15)
	head.Anchored = true
	head.Parent = npc

	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk to Mira"
	prompt.ObjectText = "Mira the Beekeeper"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.fromOffset(200, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "Mira the Beekeeper"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	npc.Parent = workspace
	return npc
end

--------------------------------------------------------------------
-- Wire the conversation
--------------------------------------------------------------------
local client = Pollinations.fromSecretsStore() -- from the secrets store
local mira = NpcDialogue.new(client, {
	Name = "Mira",
	Persona = "A cheerful beekeeper in Pollen Village who explains how flowers become honey. You love questions about bees, honey and the village.",
	Model = MODEL,
	MaxHistory = 12,
})

-- Which players currently have the conversation open, by UserId.
local openConversations: { [number]: boolean } = {}

local npcModel = buildNpc()
local prompt = npcModel.Body:FindFirstChildOfClass("ProximityPrompt")

prompt.Triggered:Connect(function(player)
	if openConversations[player.UserId] then
		openConversations[player.UserId] = nil
		replyEvent:FireClient(player, "Mira", "See you around, friend!")
	else
		openConversations[player.UserId] = true
		replyEvent:FireClient(
			player,
			"Mira",
			"Hello! I'm Mira the beekeeper. Type your questions in chat, and press the prompt again when you're done."
		)
	end
end)

-- Forward chat messages from players with an open conversation to the NPC.
TextChatService.MessageReceived:Connect(function(message)
	local source = message.TextSource
	if source == nil then
		return
	end
	local player = game:GetService("Players"):GetPlayerByUserId(source.UserId)
	if player == nil or not openConversations[player.UserId] then
		return
	end

	local reply, err = mira:chat(tostring(source.UserId), message.Text)
	if reply then
		replyEvent:FireClient(player, "Mira", reply)
	else
		-- The NPC stays silent, the game keeps running: see README on error kinds.
		warn(("[Pollinations] NPC reply failed: %s"):format(err and err.message or "unknown"))
		replyEvent:FireClient(player, "Mira", "*Mira hums to herself and doesn't hear you. Try again in a moment.*")
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	openConversations[player.UserId] = nil
	mira:reset(tostring(player.UserId))
end)
