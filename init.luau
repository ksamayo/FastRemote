-- ReplicatedStorage/Shared/RemoteFramework.lua
--[[
	RemoteFramework v1.0 - Optimized Framework for Client-Server Interactions

	Overview:
	This module provides a comprehensive framework for managing remote communications in Roblox games.
	It utilizes a single RemoteEvent for all interactions to maximize performance, while incorporating
	features such as rate limiting, parameter validation, middleware support, request/response patterns,
	and optional integration with GoodSignal for local event dispatching.

	Key Features:
	- Single RemoteEvent for the entire project to ensure optimal performance.
	- Simple and intuitive API: Fire("Action", ...) for sending events; OnEvent for receiving.
	- Configurable rate limiting per action with cooldowns.
	- Automatic parameter validation using defined schemas.
	- Robust error handling with pcall and optional logging.
	- Middleware system for custom logic (e.g., authentication, permissions).
	- Asynchronous request/response pattern in addition to fire-and-forget.
	- Optional GoodSignal integration for local updates, configurable via settings.
	- Type-safe implementation using Luau's strict mode.
	- Optional debug logging and analytics.

	Client Usage Example:
		RemoteFramework.Fire("Wallet:Add", 100)
		local coins = RemoteFramework.Request("Wallet:Get"):await()
		RemoteFramework.Signals.WalletChanged:Connect(function(newValue) ... end)

	Server Usage Example:
		RemoteFramework.RegisterHandler("Wallet:Add", function(player, amount)
			-- Implement logic here
		end)
		RemoteFramework.FireClient(player, "Wallet:Update", newBalance)
--]]

--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local GoodSignal = require(ReplicatedStorage.Frameworks.GoodSignal)

-- ============================================================================
-- TYPES
-- ====================================j========================================

export type Middleware = (player: Player, action: string, ...any) -> boolean?
export type Handler = (player: Player, ...any) -> (...any)

export type ValidationSchema = {
	types: {string}?,
	min: number?,
	max: number?,
	pattern: string?,
	validator: ((...any) -> boolean)?,
}

export type ActionConfig = {
	cooldown: number?,
	schema: ValidationSchema?,
	priority: number?,
}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local Config = {
	-- Rate Limiting
	DEFAULT_RATE_LIMIT = 0.1, -- Default: 10 calls/sec per action
	GLOBAL_RATE_LIMIT = 0.05, -- Global anti-spam protection

	-- Remote Settings
	REMOTE_NAME = "GameRemote",

	-- Debug and Analytics
	ENABLE_LOGGING = false, -- Enables detailed logging
	ENABLE_ANALYTICS = false, -- Tracks metrics (calls, durations, etc.)
	LOG_ERRORS = true, -- Logs handler errors

	-- Request/Response
	REQUEST_TIMEOUT = 10, -- Timeout in seconds for requests

	-- Signals
	USE_SIGNALS = true, -- Toggle to enable/disable GoodSignal integration
}

-- ============================================================================
-- REMOTE FRAMEWORK
-- ============================================================================

local RemoteFramework = {}
RemoteFramework.__index = RemoteFramework

-- Actions: Available actions defined in a separate module for modularity.
RemoteFramework.Actions = require(script.FastRemoteActions) :: {[string]: string}

-- Action Configurations: Per-action settings (e.g., cooldowns, schemas) from a separate module.
RemoteFramework.ActionConfigs = require(script.FastRemoteActionsConfigs) :: {[string]: ActionConfig}

-- Signals: Local GoodSignal instances, defined in a separate mappings module.
RemoteFramework.Signals = require(script.SignalMappings).Signals :: { [string]: typeof(GoodSignal.new()) }

-- Signal Mappings: Mapping from actions to signals for cleaner dispatching.
local SignalMappings = require(script.SignalMappings).Mappings :: { [string]: string }

-- ============================================================================
-- SHARED UTILITIES
-- ============================================================================

--[[
	Validates if an action is registered.

	@param action string - The action name to check.
	@return boolean - True if the action exists in RemoteFramework.Actions.
]]
function RemoteFramework.IsValidAction(action: string): boolean
	for _, validAction in RemoteFramework.Actions do
		if validAction == action then
			return true
		end
	end
	return false
end

--[[
	Retrieves the configuration for a specific action.

	@param action string - The action name.
	@return ActionConfig - The action's configuration or default values.
]]
local function GetActionConfig(action: string): ActionConfig
	return RemoteFramework.ActionConfigs[action] or {
		cooldown = Config.DEFAULT_RATE_LIMIT,
	}
end

--[[
	Validates parameters against a defined schema.

	@param schema ValidationSchema? - The validation schema.
	@param ... any - Parameters to validate.
	@return boolean, string? - Success status and optional error message.
]]
local function ValidateParams(schema: ValidationSchema?, ...: any): (boolean, string?)
	if not schema then return true end

	local params = {...}

	-- Type Validation
	if schema.types then
		for i, expectedType in schema.types do
			local param = params[i]
			if param == nil then
				return false, `Parameter {i} is missing`
			end
			local actualType = typeof(param)
			if actualType ~= expectedType then
				return false, `Parameter {i}: expected {expectedType}, received {actualType}`
			end
		end
	end

	-- Min/Max Validation for Numbers
	if schema.min or schema.max then
		for _, param in params do
			if typeof(param) == "number" then
				if schema.min and param < schema.min then
					return false, `Value {param} < minimum {schema.min}`
				end
				if schema.max and param > schema.max then
					return false, `Value {param} > maximum {schema.max}`
				end
			end
		end
	end

	-- Pattern Validation for Strings
	if schema.pattern then
		for _, param in params do
			if typeof(param) == "string" then
				if not string.match(param, schema.pattern) then
					return false, `String does not match pattern {schema.pattern}`
				end
			end
		end
	end

	-- Custom Validator
	if schema.validator then
		local success, result = pcall(schema.validator, ...)
		if not success or not result then
			return false, "Custom validation failed"
		end
	end

	return true
end

--[[
	Logs a message if logging is enabled.

	@param level string - Log level ("INFO", "WARN", "ERROR").
	@param message string - The message to log.
	@param ... any - Additional arguments.
]]
local function Log(level: string, message: string, ...: any)
	if not Config.ENABLE_LOGGING and level ~= "ERROR" then return end
	if level == "ERROR" and not Config.LOG_ERRORS then return end

	local timestamp = os.date("%H:%M:%S")
	local prefix = `[RemoteFramework][{timestamp}][{level}]`

	if level == "ERROR" then
		warn(prefix, message, ...)
	else
		print(prefix, message, ...)
	end
end

-- ============================================================================
-- SERVER-SIDE IMPLEMENTATION
-- ============================================================================

if RunService:IsServer() then
	-- Internal Storage
	local handlers: { [string]: Handler } = {}
	local middlewares: { Middleware } = {}
	local playerCooldowns: { [Player]: { [string]: number } } = {}
	local playerGlobalCooldowns: { [Player]: number } = {}
	local analytics: { [string]: { calls: number, errors: number, totalTime: number } } = {}
	local pendingRequests: { [string]: { player: Player, action: string, startTime: number } } = {}

	-- Initialize RemoteEvent
	local RemotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	RemotesFolder.Name = "Remotes"
	RemotesFolder.Parent = ReplicatedStorage

	local remote = RemotesFolder:FindFirstChild(Config.REMOTE_NAME) or Instance.new("RemoteEvent")
	remote.Name = Config.REMOTE_NAME
	remote.Parent = RemotesFolder

	--[[
		Registers a middleware function executed before each handler.
		Middlewares can block execution by returning false.

		@param middleware Middleware - Function (player, action, ...) -> boolean?

		Example:
			RemoteFramework.Use(function(player, action, ...)
				if not PlayerHasPermission(player, action) then
					return false -- Blocks the action
				end
			end)
	]]
	function RemoteFramework.Use(middleware: Middleware)
		table.insert(middlewares, middleware)
		Log("INFO", "Middleware registered")
	end

	--[[
		Registers a handler for a specific action.
		The handler is invoked when a client triggers the action.

		@param action string - The action name (must be in RemoteFramework.Actions).
		@param handler Handler - Function (player, ...) -> (...any)?

		Example:
			RemoteFramework.RegisterHandler("Wallet:Add", function(player, amount)
				local wallet = GetPlayerWallet(player)
				wallet:Add(amount)
			end)
	]]
	function RemoteFramework.RegisterHandler(action: string, handler: Handler)
		assert(RemoteFramework.IsValidAction(action), `Invalid action: {action}`)
		assert(typeof(handler) == "function", "Handler must be a function")

		handlers[action] = handler

		-- Initialize Analytics
		if Config.ENABLE_ANALYTICS then
			analytics[action] = { calls = 0, errors = 0, totalTime = 0 }
		end

		Log("INFO", `Handler registered: {action}`)
	end

	--[[
		Sends an event to a specific client or all clients.

		@param playerOrNil Player? - Target player, or nil for broadcast.
		@param action string - The action name.
		@param ... any - Parameters to send.

		Examples:
			RemoteFramework.FireClient(player, "Wallet:Update", 1500)
			RemoteFramework.FireClient(nil, "Shop:NewItem", itemData) -- Broadcast
	]]
	function RemoteFramework.FireClient(playerOrNil: Player?, action: string, ...: any)
		assert(RemoteFramework.IsValidAction(action), `Invalid action: {action}`)

		if playerOrNil then
			remote:FireClient(playerOrNil, action, ...)
			Log("INFO", `FireClient → {playerOrNil.Name}: {action}`)
		else
			remote:FireAllClients(action, ...)
			Log("INFO", `FireAllClients: {action}`)
		end
	end

	--[[
		Responds to a client request (internal use for request/response).

		@param player Player - The requesting player.
		@param requestId string - Unique request ID.
		@param ... any - Response data.
	]]
	function RemoteFramework.RespondToRequest(player: Player, requestId: string, ...: any)
		remote:FireClient(player, "_Response", requestId, ...)
		pendingRequests[requestId] = nil
	end

	--[[
		Retrieves usage statistics if analytics are enabled.

		@return table - Stats per action { [action] = { calls, errors, avgTime } }
	]]
	function RemoteFramework.GetAnalytics(): { [string]: any }
		if not Config.ENABLE_ANALYTICS then
			return {}
		end

		local stats = {}
		for action, data in analytics do
			stats[action] = {
				calls = data.calls,
				errors = data.errors,
				avgTime = data.calls > 0 and (data.totalTime / data.calls) or 0,
			}
		end
		return stats
	end

	--[[
		Checks rate limits for a player and action.

		@param player Player
		@param action string
		@param config ActionConfig
		@return boolean - True if the action is allowed.
	]]
	local function CheckRateLimit(player: Player, action: string, config: ActionConfig): boolean
		local now = os.clock()

		-- Global Rate Limit (anti-spam)
		local lastGlobal = playerGlobalCooldowns[player] or 0
		if now - lastGlobal < Config.GLOBAL_RATE_LIMIT then
			Log("WARN", `Global rate limit exceeded for {player.Name}`)
			return false
		end

		-- Per-Action Rate Limit
		local actionCooldowns = playerCooldowns[player] or {}
		local lastAction = actionCooldowns[action] or 0
		local cooldown = config.cooldown or Config.DEFAULT_RATE_LIMIT

		if now - lastAction < cooldown then
			Log("WARN", `Rate limit exceeded for {player.Name} on {action}`)
			return false
		end

		-- Update Cooldowns
		actionCooldowns[action] = now
		playerCooldowns[player] = actionCooldowns
		playerGlobalCooldowns[player] = now

		return true
	end

	--[[
		Executes middlewares for an action.

		@param player Player
		@param action string
		@param ... any
		@return boolean - True if all middlewares pass.
	]]
	local function RunMiddlewares(player: Player, action: string, ...: any): boolean
		for _, middleware in middlewares do
			local success, result = pcall(middleware, player, action, ...)
			if not success then
				Log("ERROR", `Middleware error: {result}`)
				return false
			end
			if result == false then
				Log("INFO", `Middleware blocked action {action} for {player.Name}`)
				return false
			end
		end
		return true
	end

	-- Central Server Event Handler
	remote.OnServerEvent:Connect(function(player: Player, action: string, ...: any)
		local args = {...}
        local requestId
		-- Special Case: Request/Response
		if action == "_Request" then
			requestId = args[1]
			local actualAction = args[2]
			local actualArgs = {table.unpack(args, 3)}

			action = actualAction
			args = actualArgs

			-- Store Request for Timeout Monitoring
			pendingRequests[requestId] = {
				player = player,
				action = action,
				startTime = os.clock(),
			}
		end

		-- Action Validation
		if not RemoteFramework.IsValidAction(action) then
			Log("ERROR", `Invalid action from {player.Name}: {action}`)
			return
		end

		-- Rate Limit Check
		local config = GetActionConfig(action)
		if not CheckRateLimit(player, action, config) then
			return
		end

		-- Parameter Validation
		local validParams, validationError = ValidateParams(config.schema, table.unpack(args))
		if not validParams then
			Log("ERROR", `Validation failed for {action} ({player.Name}): {validationError}`)
			return
		end

		-- Middleware Execution
		if not RunMiddlewares(player, action, table.unpack(args)) then
			return
		end

		-- Handler Retrieval
		local handler = handlers[action]
		if not handler then
			Log("WARN", `No handler for {action} (from {player.Name})`)
			return
		end

		-- Analytics Tracking
		local startTime = os.clock()
		if Config.ENABLE_ANALYTICS then
			analytics[action].calls += 1
		end

        -- Execute Handler with Error Handling
        task.spawn(function()
            local results = table.pack(pcall(function()
                return handler(player, table.unpack(args))
            end))

            local success = results[1]

            if not success then
                local errorMsg = results[2]
                Log("ERROR", `Handler error for {action}: {errorMsg}`)
                if Config.ENABLE_ANALYTICS then
                    analytics[action].errors += 1
                end

                if requestId then
                    RemoteFramework.RespondToRequest(player, requestId, false, errorMsg)
                end
            else
                Log("INFO", `Handler executed successfully: {action} by {player.Name}`)

                if requestId then
                    local returnValues = {table.unpack(results, 2, results.n)}
                    RemoteFramework.RespondToRequest(player, requestId, table.unpack(returnValues))
                end
            end

            -- Track Duration
            if Config.ENABLE_ANALYTICS then
                local duration = os.clock() - startTime
                analytics[action].totalTime += duration
            end
        end)
	end)

	-- Player Cleanup
	Players.PlayerRemoving:Connect(function(player)
		playerCooldowns[player] = nil
		playerGlobalCooldowns[player] = nil
		Log("INFO", `Cleanup for {player.Name}`)
	end)

	-- Request Timeout Monitoring
	if Config.REQUEST_TIMEOUT > 0 then
		task.spawn(function()
			while true do
				task.wait(1)
				local now = os.clock()
				for requestId, data in pendingRequests do
					if now - data.startTime > Config.REQUEST_TIMEOUT then
						Log("WARN", `Request timeout: {data.action} by {data.player.Name}`)
						pendingRequests[requestId] = nil
					end
				end
			end
		end)
	end
end

-- ============================================================================
-- CLIENT-SIDE IMPLEMENTATION
-- ============================================================================

if RunService:IsClient() then
	local remote = ReplicatedStorage.Remotes:WaitForChild(Config.REMOTE_NAME) :: RemoteEvent
	local pendingRequests: { [string]: (boolean, ...any) -> () } = {}

	--[[
		Sends an action to the server (fire-and-forget).

		@param action string - The action name.
		@param ... any - Parameters to send.

		Example:
			RemoteFramework.Fire("Wallet:Add", 100)
	]]
	function RemoteFramework.Fire(action: string, ...: any)
		assert(RemoteFramework.IsValidAction(action), `Invalid action: {action}`)
		remote:FireServer(action, ...)
		Log("INFO", `Fire → Server: {action}`)
	end

	--[[
		Sends a request to the server and awaits the response asynchronously.
		Returns a promise-like object that can be awaited or chained with callbacks.

		@param action string - The action name.
		@param ... any - Parameters to send.
		@return table - Promise with :await() -> ...any and :andThen(callback).

		Example:
			local coins = RemoteFramework.Request("Wallet:Get"):await()

			-- With Callback:
			RemoteFramework.Request("Shop:Buy", "Sword"):andThen(function(success, item)
				if success then print("Purchased:", item) end
			end)
	]]
	function RemoteFramework.Request(action: string, ...: any): any
		assert(RemoteFramework.IsValidAction(action), `Invalid action: {action}`)

		local requestId = HttpService:GenerateGUID(false)

		-- Promise Implementation
		local promise = {
			_resolved = false,
			_result = nil,
		}

		function promise:await(): ...any
			while not self._resolved do
				task.wait()
			end
			return table.unpack(self._result)
		end

		function promise:andThen(callback: (...any) -> ())
			task.spawn(function()
				local result = {self:await()}
				callback(table.unpack(result))
			end)

			return self
		end

		-- Store Callback
		pendingRequests[requestId] = function(...)
			promise._result = {...}
			promise._resolved = true
		end

		-- Send Request
		remote:FireServer("_Request", requestId, action, ...)
		Log("INFO", `Request → Server: {action} (ID: {requestId})`)

		-- Timeout Handling
		task.delay(Config.REQUEST_TIMEOUT, function()
			if not promise._resolved then
				Log("WARN", `Request timeout: {action}`)
				promise._result = {false, "Timeout"}
				promise._resolved = true
			end
		end)

		return promise
	end

	-- Global Event Signal (Optional)
	RemoteFramework.OnEvent = GoodSignal.new()

	-- Client Event Handler
	remote.OnClientEvent:Connect(function(action: string, ...: any)
		Log("INFO", `Received from server: {action}`)

		-- Special Case: Response to Request
		if action == "_Response" then
			local requestId = (...)
			local responseData = {select(2, ...)}
			local callback = pendingRequests[requestId]
			if callback then
				callback(table.unpack(responseData))
				pendingRequests[requestId] = nil
			end
			return
		end

		-- Fire Mapped Signals if Enabled
        if Config.USE_SIGNALS then
            local signal = SignalMappings[action]

            if signal then
                signal:Fire(...)
            end
        end

		-- Fire Global Event
		RemoteFramework.OnEvent:Fire(action, ...)
	end)
end

return RemoteFramework
