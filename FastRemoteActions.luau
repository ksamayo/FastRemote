-- ReplicatedStorage/Shared/FastRemoteActions.luau
--[[
	FastRemoteActions - Defines all available actions for the RemoteFramework.

	Overview:
	This module exports a table of action strings using a "Service:Action" convention
	for organization. Add new actions here as needed.

	Example Usage:
		local Actions = require(script)
		RemoteFramework.Fire(Actions.WalletAdd, 100)
--]]

local Actions = {
    -- Wallet
    WalletAdd = "Wallet:Add",
    WalletRem = "Wallet:Rem",
    WalletGet = "Wallet:Get",
    WalletUpdate = "Wallet:Update",
    WalletAddValidated = "Wallet:AddValidated",

    -- Shop
    ShopBuy = "Shop:Buy",
    ShopSell = "Shop:Sell",

    -- Inventory (optionnel pour tests futurs)
    InventoryEquip = "Inventory:Equip",
    InventoryDrop = "Inventory:Drop",
    InventoryUpdate = "Inventory:Update",
}

return Actions
