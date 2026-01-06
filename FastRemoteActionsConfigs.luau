-- ReplicatedStorage/Shared/FastRemoteActionsConfigs.luau
--[[
	FastRemoteActionsConfigs - Configurations for RemoteFramework actions.

	Overview:
	This module exports a table mapping action names to their configurations,
	including cooldowns, validation schemas, and priorities.

	Example:
		[Actions.WalletAdd] = {
			cooldown = 0.5,
			schema = { types = {"number"}, min = 0, max = 1000 },
		}
--]]

local Actions = require(script.Parent.FastRemoteActions)  -- Adjust path if needed

local ActionsConfigs = {
    -- Wallet:Add - Pas de validation (pour test Fire basique)
    [Actions.WalletAdd] = {
        cooldown = 0.2,
    },

    -- Wallet:Get - Pas de validation (pour test Request simple)
    [Actions.WalletGet] = {
        cooldown = 0.1,
    },

    -- Shop:Buy - Pas de validation stricte (pour test Request multi-valeurs)
    [Actions.ShopBuy] = {
        cooldown = 1,
    },

    -- Wallet:AddValidated - AVEC validation (pour test validation)
    [Actions.WalletAddValidated] = {
        cooldown = 0.1,
        schema = {
            types = {"number"},
            min = 1,
            max = 1000,
        }
    },
}

return ActionsConfigs
