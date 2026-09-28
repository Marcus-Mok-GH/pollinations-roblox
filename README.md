# Pollinations for Roblox

Give your Roblox NPCs conversations powered by [Pollinations](https://pollinations.ai) text models, with a few lines of Luau.

- **`Pollinations` module** — `POST https://gen.pollinations.ai/v1/chat/completions` via `HttpService`, **any model from the live model list** (default `openai/gpt-5.4-nano`), automatic retries with exponential backoff on `429`/`5xx`, and stable error kinds (`auth` / `rate_limit` / `server` / `network` / `parse` / `bad_request`) so your game never crashes on an API failure. Also `ask()` (one-shot `GET /text/{prompt}`) and `listModels()` (the live list).
- **`NpcDialogue` module** — `NpcDialogue.new(client, { Name, Persona })` gives an NPC a persona and rolling per-player conversation memory in ~5 lines.
- **Example place** — `PollenVillage.rbxlx`: a playable village with Mira the beekeeper, built at runtime (rig, ProximityPrompt, name tag), who answers what players type in the Roblox chat.
- **Headless test suite** — the same module source runs under [lune](https://lune-org.github.io) so all of it is tested against the **live** API, with your key, before it ships.

The API key lives in [Roblox's secrets store](https://create.roblox.com/docs/cloud-services/secrets) — it is never written into the place, a script, or any serialized data.

## Install

Option A — example place (fastest):

1. Download [`PollenVillage.rbxlx`](PollenVillage.rbxlx) and open it in Roblox Studio.
2. Enable HTTP requests: **Game Settings → Security → Allow HTTP Requests** (the place ships with it on, Studio may re-ask).
3. Publish the place to an experience (or use File → Save to keep testing locally).
4. Add your API key as a secret (next section). Press Play, walk up to Mira, press `E`, type in chat.

Option B — drop the modules into your own game:

1. Open `PollenVillage.rbxlx` in Studio and copy the `ReplicatedStorage/PollinationsRoblox` folder into your game, **or** clone this repo and use [Rojo](https://rojo.space) (`rojo build pollinations-roblox.project.json -o pollinations-roblox.rbxmx`).
2. Enable HTTP requests (**Game Settings → Security → Allow HTTP Requests**).
3. Add the example scripts from `example/` if you want the full chat + ProximityPrompt wiring.

## API key

1. Get a key at [enter.pollinations.ai/keys](https://enter.pollinations.ai/keys).
2. In [Creator Hub](https://create.roblox.com/creator-hub), open your experience → **Secrets** → create a secret named `POLLINATIONS_API_KEY` with the key as its value.
3. In Studio the secret syncs automatically (restart Studio if you just added it).

The default constructor `Pollinations.new()` (no arguments) picks the key up from the secrets store. For local testing only, you can pass a plain string:

```luau
local Pollinations = require(ReplicatedStorage.PollinationsRoblox.Pollinations)
local client = Pollinations.new({ apiKey = "sk-..." }) -- local testing only
```

Never hardcode the key in a published game — keep it in the secrets store.

## Quickstart: a talking NPC

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pollinations = require(ReplicatedStorage.PollinationsRoblox.Pollinations)
local NpcDialogue = require(ReplicatedStorage.PollinationsRoblox.NpcDialogue)

local client = Pollinations.new() -- key from the secrets store

local npc = NpcDialogue.new(client, {
    Name = "Mira",
    Persona = "A cheerful beekeeper in Pollen Village who explains how flowers become honey.",
})

local reply = npc:chat(tostring(player.UserId), "What do you do here?")
print(reply)
```

Any model from the live list works — set it per client or per NPC:

```luau
local client = Pollinations.new({ model = "anthropic/claude-opus-5.5" }) -- from https://gen.pollinations.ai/text/models
local npc = NpcDialogue.new(client, { Name = "Mira", Persona = "...", Model = "openai/gpt-6-luna" })
```

Raw access, if you don't want the NPC helper:

```luau
local reply, err = client:chat({
    { role = "system", content = "You are a grumpy blacksmith." },
    { role = "user", content = "Got any swords?" },
}, { maxTokens = 100 })
if not reply then
    print(err.kind) -- "auth" | "rate_limit" | "server" | "network" | "parse" | "bad_request"
end
```

## How the example place works

- The NPC rig, name tag and ProximityPrompt are **built at runtime** by `example/PollenVillage.server.luau` — no assets beyond the baseplate.
- Press `E` near Mira to open the conversation; whatever you then type in chat is sent to the model with Mira's persona and her memory of this conversation; press `E` again to end it.
- The reply comes back through a `RemoteEvent` and the client shows it in the default Roblox chat via `TextChatService:DisplaySystemMessage`.
- Each player gets their own conversation memory (`MaxHistory` turns back), cleaned up on leave.
- When the API fails (bad key, rate limit, outage) the NPC stays silent with a friendly in-character line and the **game keeps running** — no error thrown to the player.

## Run the tests yourself

The suite runs the same module source under [lune](https://lune-org.github.io/docs) and hits the **live** API:

```bash
# install lune (https://github.com/lune-org/lune/releases) then:
export POLLINATIONS_API_KEY=sk-your-key
lune run tests/run.luau
```

What it covers — 15 checks, all run against the real service:

- live model list fetched and default model present
- chat with a real key returns a reply; system prompts (personas) honored
- wrong key → `auth` error, unknown model → `bad_request` — returned, never thrown
- `NpcDialogue`: persona and rules reach the system prompt, memory rolls forward and is isolated per player, history trimming never starts on an assistant turn, failed exchanges don't corrupt memory, bad config throws early
- end-to-end: an NPC with a persona stays in character over the live API

Note: the live API rate-limits bursts (it answers `401` for rapid back-to-back calls), so live tests are spaced a few seconds apart.

## Repo layout

```
src/Pollinations/init.luau     the API client (Roblox + lune, same source)
src/NpcDialogue/init.luau      persona + rolling conversation memory
example/PollenVillage.server.luau  example place, server side
example/PollenVillage.client.luau  example place, client side
place.project.json             Rojo project that builds the example place
pollinations-roblox.project.json   Rojo project for the module folder
PollenVillage.rbxlx            the built, playable example place
tests/                         lune test suite (live API + unit tests)
```

## License

MIT — see [LICENSE](LICENSE).

## Links

- Pollinations API docs: <https://gen.pollinations.ai/docs>
- Live text model list: <https://gen.pollinations.ai/text/models>
- Get an API key: <https://enter.pollinations.ai/keys>
- Roblox secrets store: <https://create.roblox.com/docs/cloud-services/secrets>
