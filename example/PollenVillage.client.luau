--!strict
--[[
	Pollen Village example: client side.

	Listens for NPC replies from the server and shows them in the default
	Roblox chat as system messages (no chat filtering concerns: the reply
	is only ever displayed to the single player who asked, on their own
	client, via DisplaySystemMessage).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local replyEvent = ReplicatedStorage:WaitForChild("NpcReply")

replyEvent.OnClientEvent:Connect(function(npcName: string, text: string)
	local general = TextChatService:FindFirstChild("TextChannels")
		and TextChatService.TextChannels:FindFirstChild("RBXGeneral")
	if general then
		(general :: any):DisplaySystemMessage(("%s: %s"):format(npcName, text))
	else
		print(("%s: %s"):format(npcName, text))
	end
end)
