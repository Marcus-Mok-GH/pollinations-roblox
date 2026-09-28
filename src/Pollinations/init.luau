--!strict
--[[
	Pollinations client for Roblox.

	One module, two runtimes:
	  * Inside Roblox it uses HttpService for requests and Roblox's Secrets
	    store for the API key (server scripts only).
	  * Under lune (headless Luau) it uses the lune net library, which is
	    how the test suite in this repository runs against the live API.

	Error handling: every request method returns (result, err). On failure
	result is nil and err is a table { kind = ..., status = ..., message = ... }
	with kind one of "config" | "network" | "auth" | "rate_limit" |
	"server" | "bad_request" | "parse". API failures never throw; only
	misconfiguration throws (missing key, HttpService disabled).
]]

local DEFAULT_BASE_URL = "https://gen.pollinations.ai"
local DEFAULT_MODEL = "openai/gpt-5.4-nano"
local BEARER_PREFIX = "Bearer "

local IS_ROBLOX = typeof(game) ~= "nil"
	and pcall(function()
		return game:GetService("HttpService") and true
	end)

local HttpService, SecretsService
if IS_ROBLOX then
	HttpService = game:GetService("HttpService")
	pcall(function()
		SecretsService = game:GetService("Secrets")
	end)
end

local net, luneJson
if not IS_ROBLOX then
	net = require("@lune/net")
	local serde = require("@lune/serde")
	luneJson = {
		encode = function(v)
			return serde.encode("json", v)
		end,
		decode = function(s)
			return serde.decode("json", s)
		end,
	}
end

export type ErrorKind = "config" | "network" | "auth" | "rate_limit" | "server" | "bad_request" | "parse"
export type ApiError = { kind: ErrorKind, status: number?, message: string }

export type Options = {
	apiKey: (Secret | string)?,
	baseUrl: string?,
	model: string?,
	maxRetries: number?,
	timeoutSeconds: number?,
}

local function err(kind: ErrorKind, message: string, status: number?): ApiError
	return { kind = kind, status = status, message = message }
end

local function authorizationHeader(apiKey: any): (any, ApiError?)
	-- Roblox Secret from the Secrets store, or a plain string for local testing.
	if typeof(apiKey) == "string" then
		return BEARER_PREFIX .. apiKey, nil
	end
	if typeof(apiKey) == "userdata" or typeof(apiKey) == "Secret" then
		local okPrefix, secret = pcall(function()
			return (apiKey :: any):AddPrefix(BEARER_PREFIX)
		end)
		if okPrefix then
			return secret, nil
		end
		return nil, err("config", "apiKey is not a string or a Roblox Secret")
	end
	return nil, err("config", "apiKey is not a string or a Roblox Secret")
end

local Pollinations = {}
Pollinations.__index = Pollinations

export type ChatMessage = { role: string, content: string }

export type ChatOptions = {
	model: string?,
	maxTokens: number?,
	temperature: number?,
	extraBody: { [string]: any }?,
}

function Pollinations.new(options: Options?)
	options = options or {}

	local authValue, authErr
	if options.apiKey ~= nil then
		authValue, authErr = authorizationHeader(options.apiKey)
		if authErr then
			error("[Pollinations] " .. authErr.message, 2)
		end
	elseif IS_ROBLOX then
		if SecretsService == nil then
			error("[Pollinations] no apiKey given and the Secrets service is unavailable", 2)
		end
		local ok, secret = pcall(function()
			return SecretsService:GetSecret("POLLINATIONS_API_KEY")
		end)
		if not ok then
			error(
				[[No API key configured.
Get a key at https://enter.pollinations.ai/keys, then add it to the secrets
store as POLLINATIONS_API_KEY (Creator Hub -> your experience -> Secrets),
or pass it as Pollinations.new({ apiKey = "<key>" }) for local testing only.]],
				2
			)
		end
		authValue, authErr = authorizationHeader(secret)
		if authErr then
			error("[Pollinations] " .. authErr.message, 2)
		end
	else
		error("[Pollinations] an apiKey is required when running outside Roblox", 2)
	end

	if IS_ROBLOX and not HttpService.HttpEnabled then
		error("[Pollinations] HttpService must be enabled (Game Settings -> Security -> Allow HTTP Requests)", 2)
	end

	return setmetatable({
		_auth = authValue,
		_baseUrl = (options.baseUrl or DEFAULT_BASE_URL):gsub("/+$", ""),
		_model = options.model or DEFAULT_MODEL,
		_maxRetries = options.maxRetries or 2,
		_timeout = options.timeoutSeconds or 30,
	}, Pollinations)
end

-- Convenience constructor: key straight from Roblox's secrets store.
function Pollinations.fromSecretsStore(secretName: string?, options: Options?)
	local IS_ROBLOX_ = typeof(game) ~= "nil"
	assert(IS_ROBLOX_, "fromSecretsStore only works inside Roblox")
	local svc = game:GetService("Secrets")
	local ok, secret = pcall(function()
		return svc:GetSecret(secretName or "POLLINATIONS_API_KEY")
	end)
	if not ok then
		error(
			('Secret "%s" is not configured. Add it under Creator Hub -> your experience -> Secrets, or pass Pollinations.new({ apiKey = ... }).'):format(
				secretName or "POLLINATIONS_API_KEY"
			),
			2
		)
	end
	local opts = table.clone(options or {})
	opts.apiKey = secret
	return Pollinations.new(opts)
end

function Pollinations:_request(method: string, path: string, body: string?): (string, ApiError?)
	local headers = { ["Content-Type"] = "application/json", Authorization = self._auth }
	local delaySeconds = 1
	local lastErr: ApiError? = nil

	for attempt = 0, self._maxRetries do
		local code, responseBody
		if IS_ROBLOX then
			local ok, response = pcall(function()
				return HttpService:RequestAsync({
					Method = method,
					Url = self._baseUrl .. path,
					Headers = headers,
					Body = body,
					Timeout = self._timeout,
				})
			end)
			if not ok then
				code, responseBody = nil, tostring(response)
			elseif not response.Success then
				code, responseBody = nil, ("HTTP request failed: %s"):format(tostring(response.HttpError or ""))
			else
				code, responseBody = response.StatusCode, response.Body
			end
		else
			local ok, response = pcall(function()
				return net.request({
					method = method,
					url = self._baseUrl .. path,
					headers = headers,
					body = body,
				})
			end)
			if not ok then
				code, responseBody = nil, tostring(response)
			else
				code, responseBody = response.statusCode, response.body
			end
		end

		if code == nil then
			lastErr = err("network", ("request failed: %s"):format(tostring(responseBody)))
		elseif code >= 200 and code < 300 then
			return responseBody, nil
		else
			local kind
			if code == 401 or code == 403 then
				kind = "auth"
			elseif code == 429 then
				kind = "rate_limit"
			elseif code >= 500 then
				kind = "server"
			else
				kind = "bad_request"
			end
			lastErr = err(kind, ("HTTP %d: %s"):format(code, tostring(responseBody)), code)
			-- Only rate limiting and transient server errors are retried.
			if kind ~= "rate_limit" and kind ~= "server" then
				return nil, lastErr
			end
		end

		if attempt < self._maxRetries then
			if IS_ROBLOX then
				task.wait(delaySeconds)
			else
				-- lune has no task library; short busy-wait keeps retries testable
				local until_ = os.clock() + delaySeconds
				while os.clock() < until_ do end
			end
			delaySeconds *= 2
		end
	end

	return nil, lastErr
end

local function decodeJson(text: string): (any, ApiError?)
	if IS_ROBLOX then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(text)
		end)
		if ok then
			return data, nil
		end
		return nil, err("parse", "invalid JSON in response")
	end
	local ok, data = pcall(function()
		return luneJson.decode(text)
	end)
	if ok then
		return data, nil
	end
	return nil, err("parse", "invalid JSON in response")
end

-- POST /v1/chat/completions. messages is an array of { role, content }.
-- Returns (reply: string, err: ApiError?).
function Pollinations:chat(messages: { ChatMessage }, options: ChatOptions?)
	options = options or {}
	local body: { [string]: any } = {
		model = options.model or self._model,
		messages = messages,
	}
	if options.maxTokens then
		body.max_tokens = options.maxTokens
	end
	if options.temperature then
		body.temperature = options.temperature
	end
	for k, v in options.extraBody or {} do
		body[k] = v
	end

	local encoded
	if IS_ROBLOX then
		encoded = HttpService:JSONEncode(body)
	else
		encoded = luneJson.encode(body)
	end

	local responseBody, reqErr = self:_request("POST", "/v1/chat/completions", encoded)
	if reqErr then
		return nil, reqErr
	end

	local data, parseErr = decodeJson(responseBody)
	if parseErr then
		return nil, parseErr
	end
	local choices = (data :: any).choices
	if typeof(choices) ~= "table" or #choices == 0 or typeof(choices[1].message) ~= "table" then
		return nil, err("parse", "response had no choices[1].message")
	end
	local content = choices[1].message.content
	if typeof(content) ~= "string" then
		-- some models return content as an array of parts
		if typeof(content) == "table" then
			local parts = {}
			for _, part in content do
				if typeof(part) == "table" and typeof(part.text) == "string" then
					table.insert(parts, part.text)
				end
			end
			if #parts > 0 then
				return table.concat(parts), nil
			end
		end
		return nil, err("parse", "response content was not text")
	end
	return content, nil
end

-- One-shot text: GET /text/{prompt}. Returns (text, err).
function Pollinations:ask(prompt: string, options: { model: string? }?)
	local model = (options and options.model) or self._model
	local escaped = (prompt:gsub("[^%w _%-%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
	local responseBody, reqErr = self:_request("GET", "/text/" .. escaped .. "?model=" .. model, nil)
	if reqErr then
		return nil, reqErr
	end
	return responseBody, nil
end

-- Live text model list. Returns (models, err).
function Pollinations:listModels()
	local responseBody, reqErr = self:_request("GET", "/text/models", nil)
	if reqErr then
		return nil, reqErr
	end
	local data, parseErr = decodeJson(responseBody)
	if parseErr then
		return nil, parseErr
	end
	if typeof(data) ~= "table" then
		return nil, err("parse", "model list was not an array")
	end
	return data, nil
end

-- The default model this client will use.
function Pollinations:defaultModel(): string
	return self._model
end

return Pollinations
