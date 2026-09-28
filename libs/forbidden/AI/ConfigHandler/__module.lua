--[[ Development Notes:
Purpose of file:
    This file contains the configuration handler for the Forbidden AI system.
    This is like GL11's ConfigHandler, where you edit everything line by line.
    Serves to enforce good practice & documentation

Developer History
    > @crit-dev (@rman501), initial commit
        o7 to future devs

]]--

-- [Libraries] --
local AIT = remoteRequire("libs/forbidden/AI/Types")
local TablesLibrary = remoteRequire("libs/forbidden/Libraries/Tables")
local Defaults = remoteRequire("libs/forbidden/AI/ConfigHandler/Defaults")

local ConfigHandler = {}
local ActiveConfigInstances: {[Instance]: AIT.Config} = {} -- Configs that the AI system reads
local LocalConfigInstances: {[Instance]: AIT.Config} = {} -- Modified configs not yet seen by AI sys (these are copied over with a new call to the active config)
local GlobalPresets: {[string]: AIT.Config} = {} -- Presets that are available globally, not just for the NPC
local LocalPresets: {[Instance]: {[string]: AIT.Config}} = {} -- Presets that are available locally, for a singular NPC


-- [Internal Functions] --


-- Removes the key lock (for saving presets.)
local function RemoveMetatable(tbl)
    -- Remove the metatable from the table, this is used to allow the NPC field to be set again without causing an error
    TablesLibrary.RemoveMetatable(tbl)
end


-- Locks the NPC key, which is used internally.
local function AddMetatable(tbl)
    TablesLibrary.LockKeyInTable(tbl, "NPC") -- Lock the NPC field so it cannot be modified
end


-- for organization, the declaration was made up here.
local createConfig: (NPC: Instance) -> AIT.Config = nil -- defined down more.


-- Initializes the ConfigHandler for a given NPC.
local function InitializeConfig(NPC: Instance)
    -- If there is already a config for this NPC, do not initialize again
    if LocalConfigInstances[NPC] then return end
    
    -- Create a new config instance for the NPC
    local config = createConfig(NPC)
    LocalConfigInstances[NPC] = config
    ActiveConfigInstances[NPC] = TablesLibrary.DeepCopy(config)
    LocalPresets[NPC] = {}
end


-- Creates a config that can be saved to the presets.
local function CreateCleanConfig(tbl: AIT.Config): AIT.Config
    -- Create a clean preset from the config, this will remove the NPC field and return a new table
    local newCfg = TablesLibrary.DeepCopy(tbl) :: AIT.Config
    RemoveMetatable(newCfg) -- this will allow the NPC field to be set again without causing an error
    newCfg.NPC = nil
    return newCfg
end
    

-- [Config Functions] --

-- THIS SHOULD ONLY EFFECT LOCAL CONFIG (which should be self call)
--[=[
    Reset the current config.
    
    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    config.Tracking.CollinearTargetPositionOffset = 3 -- the NPC will now stay 3 studs away.
    config:RestoreDefaults()
    ```
]=]
function RestoreDefaults(self: AIT.Config)
    -- Restore the config to the default values
    local npc = self.NPC
    RemoveMetatable(self)
    TablesLibrary.DeepCopyPaste(Defaults, self) -- ? maybe consider 
    self.NPC = npc
    AddMetatable(self)
end


--[=[
    Reset the local config with the values of the current active config.
    
    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent
    local someTarget = ...

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    config.Tracking.CollinearTargetPositionOffset = 1 -- the NPC will now stay 3 studs away.
    AI.SmartPathfind(myNPC, someTarget)
    config.Tracking.CollinearTargetPositionOffset = 3 -- the NPC will now stay 3 studs away.
    config:RestoreActiveConfig() -- resets to the current op.
    -- effectively resets the setting back to 1 from 3. (what it is when it was activated)
    ```
]=]
function RestoreActiveConfig(self: AIT.Config)
    -- Restore the local config to the values of the active config.
    -- local npc = self.NPC
    RemoveMetatable(LocalConfigInstances[self.NPC])
    TablesLibrary.DeepCopyPaste(ActiveConfigInstances[self.NPC], LocalConfigInstances[self.NPC])
    -- LocalConfigInstances[self.NPC] = npc -- redundant tbf
    AddMetatable(LocalConfigInstances[self.NPC])
end


--[=[
    Saves a preset that can be loaded at a later date.
    
    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    config:SavePreset("Chasing")
    config.Tracking.Enabled = false
    config:LoadPreset("Chasing")
    print(config.Tracking.Enabled) -- true
    ```

    @param PresetName <strong>string</strong> Name of the preset.
    @param SaveGlobally <strong>boolean?</strong> Whether or not to store this preset for all NPCs.
]=]
function SavePreset(self: AIT.Config, PresetName: string, SaveGlobally: boolean?)
    
    -- Quick validation
    if PresetName == "" or PresetName == nil then
        warn("Preset name cannot be nil or empty.")
        return
    end
    
    -- Global Save
    if SaveGlobally then
        ConfigHandler.SaveGlobalPreset(PresetName, self)
        return
    end
    
    -- Create a clean preset to save
    local preset = CreateCleanConfig(self)
    
    -- Local Save
    if not SaveGlobally then
        LocalPresets[self.NPC][PresetName] = preset
    end
end


--[=[
    Loads a saved preset, <strong>does not automatically apply it</strong>
    
    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    config:SavePreset("Chasing")
    config.Tracking.Enabled = false
    config:LoadPreset("Chasing")
    print(config.Tracking.Enabled) -- true
    ```

    @param PresetName <strong>string</strong> Name of the preset.
    @param UseGlobalIfBothFound <strong>boolean?</strong> If true and a preset of the same name is found globally, the system will prefer the global preset.
]=]
function LoadPreset(self: AIT.Config, PresetName: string, UseGlobalIfBothFound: boolean?)
    -- Load a preset if it exists
    if PresetName == nil or PresetName == "" then
        warn("Preset name cannot be nil or empty.")
        return
    end
    
    -- Check if the preset exists locally
    local localPreset = LocalPresets[self.NPC][PresetName]
    local globalPreset = GlobalPresets[PresetName]
    
    local presetToUse = localPreset
    
    -- Swap to global if available and we should
    if UseGlobalIfBothFound and globalPreset then presetToUse = globalPreset end
    
    -- Swap to global if no local preset (see check below as to why we don't care if we shou)
    if not localPreset then presetToUse = globalPreset end
    
    -- If no preset was found, warn and return
    if not presetToUse then
        warn(`Preset '{PresetName}' does not exist locally or globally.`)
        return
    end
    
    -- Setup the preset
    local newCfg = TablesLibrary.DeepCopy(presetToUse) :: AIT.Config
    newCfg.NPC = self.NPC -- keep the NPC reference (technically this is not needed, but it is good to have)
    
    -- Allow configs to be updated
    RemoveMetatable(LocalConfigInstances[self.NPC])

    -- Update configs with preset
    TablesLibrary.DeepCopyPaste(newCfg, self)
    
    -- Do this down here so that it doesn't cause an error as the NPC field is not editable.
    AddMetatable(self)
end


--[=[
    Make the current config (presumably altered config) visible to the system, this is done 
    automatically when a new pathfind is requested, but can be used to apply the config immediately.

    This may matter if you would like to alter a pathfind (more than likely a Tracking one)
    mid cycle.
    
    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent
    local someTarget = nil -- your target here.

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    AI.SmartPathfind(myNPC, someTarget) -- the change above is applied as a new call was made.
    config.Tracking.CollinearTargetPositionOffset = 3 -- the NPC will now stay 3 studs away.
    config:ApplyNow() -- makes this change appear even though a new call was not made.
    ```
]=]
function ApplyNow(self: AIT.Config)
    if not self.NPC then
        error("Cannot apply config to NPC, NPC field is nil.")
    end

    -- Load the local config to the active config
    TablesLibrary.DeepCopyPaste(LocalConfigInstances[self.NPC], ActiveConfigInstances[self.NPC])
end


-- Initialized the function above already.
createConfig = function (NPC: Instance): AIT.Config
    local newCfg = TablesLibrary.DeepCopy(Defaults)
    
    -- Attach the NPC to the config
    newCfg.NPC = NPC

    -- Functions
    function newCfg:SavePreset(PresetName: string, SaveGlobally: boolean?) SavePreset(self, PresetName, SaveGlobally) end
    function newCfg:LoadPreset(PresetName: string, UseGlobalIfBothFound: boolean?) LoadPreset(self, PresetName, UseGlobalIfBothFound) end
    function newCfg:RestoreDefaults() RestoreDefaults(self) end
    function newCfg:RestoreActiveConfig() RestoreActiveConfig(self) end
    function newCfg:ApplyNow() ApplyNow(self) end

    AddMetatable(newCfg)
    return newCfg
end


-- [Global Functions] --


--[=[
    Saves a preset that can be loaded at a later date.
    
    ```lua
    -- Usage Example
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    config:SavePreset("Chasing", true) -- see second param
    -- you also could call the func directly, although that is frowned upon.
    config.Tracking.Enabled = false
    config:LoadPreset("Chasing", true) -- prefer global, not necessary if local does not exist.
    print(config.Tracking.Enabled) -- true
    ```

    @param PresetName <strong>string</strong> Name of the preset.
    @param Config <strong>AIConfig</strong> The config to save globally.
]=]
ConfigHandler.SaveGlobalPreset = function(PresetName: string, Config: AIT.Config)
   -- Quick validation
    if PresetName == "" or PresetName == nil then
        warn("Preset name cannot be nil or empty.")
        return
    end
    
    -- Create a clean preset to save
    local preset = CreateCleanConfig(Config)

    -- Save the preset globally
    GlobalPresets[PresetName] = preset
end


--[=[
    Gets the current config of the NPC. All changes made to the config will not take effect
    until the next time a pathfind is called. 
    
    To make changes take effect immediately do:
    ```lua
    config:ApplyNow()
    ```
    
    Usage Example
    ```lua
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)

    -- == Settings == --
    local myNPC = script.Parent

    -- == Usage == --
    local config = AI.GetConfig(myNPC)
    config.Tracking.Enabled = true
    config:SavePreset("Chasing")
    config.Tracking.Enabled = false
    config:LoadPreset("Chasing")
    print(config.Tracking.Enabled) -- true
    ```

    @param NPC <strong>Instance</strong> NPC to get the config of.
    @return <strong>AIConfig</strong> Returns the config of the specified NPC
]=]
ConfigHandler.GetConfig = function(NPC: Instance): AIT.Config
    if not LocalConfigInstances[NPC] then
        InitializeConfig(NPC)
    end
    
    return LocalConfigInstances[NPC]
end


--[=[
    FOR USE WITH FORBIDDEN ARCHITECTURE ONLY
    
    Gets the <strong>active</strong> config of the NPC. i.e. what is being read in the system.
    
    Usage Example
    ```lua
    -- == Services == --
    local rs = game:GetService("ReplicatedStorage")

    -- == Libraries == --
    local AI = require(rs.Forbidden.AI)
    local ConfigHandler = require(rs.Forbidden.AI.ConfigHandler)

    -- == Settings == --
    local myNPC = script.Parent

    if ConfigHandler.GetActiveConfig(myNPC).Tracking.Enabled then
        print("Current call has tracking enabled!")
    end
    
    ```

    @param NPC <strong>Instance</strong> NPC to get the config of.
    @return <strong>AIConfig</strong> Returns the active config of the specified NPC
]=]
ConfigHandler.GetActiveConfig = function(NPC: Instance): AIT.Config
    if not ActiveConfigInstances[NPC] then
        InitializeConfig(NPC)
    end
    
    return ActiveConfigInstances[NPC]
end


ConfigHandler.TriggerCleanup = function(NPC: Instance)
    ActiveConfigInstances[NPC]  = nil
    LocalConfigInstances[NPC]   = nil
    LocalPresets[NPC]           = nil
end

return ConfigHandler