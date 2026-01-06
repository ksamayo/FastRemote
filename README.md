# FastRemote

FastRemote is a lightweight and performant framework to handle client ↔ server interactions in Roblox using a single `RemoteEvent`.

It is designed to stay simple, fast and secure, while giving enough flexibility for complex systems
(rate limiting, validation, middleware, request/response, optional signals).

> If `USE_SIGNALS` is enabled, FastRemote depends on **GoodSignal**.
> You can change the GoodSignal path in `SignalsMappings.luau` (around line 19):

```lua
local GoodSignal = require(ReplicatedStorage.Frameworks.GoodSignal)
```
## Configuration

Configuration is located in `init.luau`.

```lua
local Config = {
	-- Rate limiting
	DEFAULT_RATE_LIMIT = 0.1, -- default per-action cooldown (10 calls/sec)
	GLOBAL_RATE_LIMIT  = 0.05, -- global anti-spam protection

	-- Remote
	REMOTE_NAME = "GameRemote",

	-- Logging & analytics
	ENABLE_LOGGING   = false,
	ENABLE_ANALYTICS = false,
	LOG_ERRORS       = true,

	-- Request / response
	REQUEST_TIMEOUT = 10, -- seconds

	-- Signals
	USE_SIGNALS = true, -- enable GoodSignal integration
}
```

Edit this table to match your needs.

## Actions

Actions are defined in `FastRemoteActions.luau`.

Naming convention: `Category:Action`.

```lua
local Actions = {
	-- Wallet
	WalletAdd          = "Wallet:Add",
	WalletRem          = "Wallet:Rem",
	WalletGet          = "Wallet:Get",
	WalletUpdate       = "Wallet:Update",
	WalletAddValidated = "Wallet:AddValidated",

	-- Shop
	ShopBuy  = "Shop:Buy",
	ShopSell = "Shop:Sell",

	-- Inventory (optional)
	InventoryEquip  = "Inventory:Equip",
	InventoryDrop   = "Inventory:Drop",
	InventoryUpdate = "Inventory:Update",
}
```

## Action Configuration

Per-action cooldowns and validation are defined in `FastRemoteActionsConfigs.luau`.

```lua
local ActionsConfigs = {
	[Actions.WalletAdd] = {
		cooldown = 0.2,
	},

	[Actions.WalletGet] = {
		cooldown = 0.1,
	},

	[Actions.ShopBuy] = {
		cooldown = 1,
	},

	[Actions.WalletAddValidated] = {
		cooldown = 0.1,
		schema = {
			types = { "number" },
			min = 1,
			max = 1000,
		},
	},
}
```

Validation is always executed server-side before the handler.

## Signals Mapping

Signals are optional and defined in `SignalsMappings.luau`.

```lua
local Signals = {
	WalletChanged    = GoodSignal.new(),
	InventoryChanged = GoodSignal.new(),
	ShopUpdated      = GoodSignal.new(),
}

local Mappings = {
	[Actions.WalletUpdate]     = Signals.WalletChanged,
	[Actions.InventoryUpdate] = Signals.InventoryChanged,
	-- [Actions.ShopBuy] = Signals.ShopUpdated
}
```

If `USE_SIGNALS` is enabled, the mapped signal will be fired automatically when the action is received.

## API

### Server

```lua
RemoteFramework.Use(middleware)
RemoteFramework.RegisterHandler(action, handler)
RemoteFramework.FireClient(playerOrNil, action, ...)
RemoteFramework.GetAnalytics()
```
### Client

```lua
RemoteFramework.Fire(action, ...)
RemoteFramework.Request(action, ...)
RemoteFarmework.OnEvent
```
