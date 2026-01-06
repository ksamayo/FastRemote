local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ReplicatedStorage/Shared/SignalMappings.luau
--[[
	SignalMappings - Manages GoodSignal instances and action-to-signal mappings.

	Overview:
	This module separates signal logic for cleaner maintenance. It defines:
	- Signals: A table of GoodSignal instances.
	- Mappings: A table mapping action names to signal names.

	Add new signals and mappings here to associate server actions with local signals.

	Example:
		To add a new signal for "Player:LevelUp":
			Signals.PlayerLevelChanged = GoodSignal.new()
			Mappings["Player:LevelUp"] = "PlayerLevelChanged"
--]]

local GoodSignal = require(ReplicatedStorage.Frameworks.GoodSignal)  -- Adjust path if needed
local Actions = require(script.Parent.FastRemoteActions)  -- Adjust path if needed

local Signals = {
    WalletChanged = GoodSignal.new(),
    InventoryChanged = GoodSignal.new(),
    ShopUpdated = GoodSignal.new(),
}

local Mappings = {
    -- Wallet actions → WalletChanged signal
    [Actions.WalletUpdate] = Signals.WalletChanged,

    -- Inventory actions → InventoryChanged signal
    [Actions.InventoryUpdate] = Signals.InventoryChanged,

    -- Shop actions → ShopUpdated signal (optionnel)
    -- [Actions.ShopBuy] = Signals.ShopUpdated, -- Décommente si besoin
}
return {
	Signals = Signals,
	Mappings = Mappings,
}
