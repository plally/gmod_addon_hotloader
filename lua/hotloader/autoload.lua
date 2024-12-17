local convarName = "_hotload_autoload_client_addon_ids"

HotLoad.loadedAddons = HotLoad.loadedAddons or {}

---@param id string
---@param done? function
function HotLoad.LoadAddon( id, done )
    if HotLoad.loadedAddons[id] then
        HotLoad.logger:Warnf( "Addon %s is already loaded", id )
        done()
        return
    end

    local addon = HotLoad.LoadedAddon.New( id )
    addon:Mount( done )

    HotLoad.loadedAddons[id] = addon
end

CreateConVar( convarName, "", FCVAR_REPLICATED, "List of addon IDs to autoload on client" )

if SERVER then
    function HotLoad.EnableClientAutoload( addonId )
        HotLoad.logger:Debugf( "Enabling client autoload for addon %s", addonId )
        local ids = GetConVar( convarName ):GetString()
        local idsList = string.Explode( ",", ids )

        if table.HasValue( idsList, addonId ) then
            HotLoad.logger:Debugf( "Client autoload for addon %s is already enabled", addonId )
            return
        end

        table.insert( idsList, addonId )

        local newIds = table.concat( idsList, "," )
        GetConVar( convarName ):SetString( newIds )
    end

    function HotLoad.DisableClientAutoload( addonId )
        HotLoad.logger:Debugf( "Disabling client autoload for addon %s", addonId )
        local ids = GetConVar( convarName ):GetString()
        local idsList = string.Explode( ",", ids )
        table.RemoveByValue( idsList, addonId )

        local newIds = table.concat( idsList, "," )
        GetConVar( convarName ):SetString( newIds )
    end
end

if CLIENT then
    local function LoadAddons()
        local cvar = GetConVar( convarName )
        if not cvar then
            HotLoad.logger:Error( "Failed to get cvar" )
            return
        end
        local ids = cvar:GetString()
        local idsList = string.Explode( ",", ids )
        for _, id in ipairs( idsList ) do
            if id ~= "" then
                HotLoad.logger:Debugf( "Autoloading addon %s", id )
                HotLoad.LoadAddon( id )
            end
        end
    end

    hook.Add( "InitPostEntity", "HotLoad_Autoload", LoadAddons )
end
