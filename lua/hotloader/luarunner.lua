local function constructIdentifier( filename )
    return string.format( "AddonLoader: filename='%s' .lua", filename )
end

local function parseIdentifier( identifier )
    local filename = string.match( identifier, "@?AddonLoader: filename='(.*)' .lua" )
    return {
        isAddonLoader = string.StartsWith( identifier, "@AddonLoader: " ) or string.StartsWith( identifier, "AddonLoader: " ),
        filename = filename,
    }
end

HotLoad.parseIdentifier = parseIdentifier
HotLoad.constructIdentifier = constructIdentifier

---@class LoadedAddon
---@field id string
---@field files string[]
---@field filename string
---@field swepNames string[]
---@field effectNames string[]
---@field entityNames string[]
---@field autorun {shared: string[], client: string[], server: string[]}
---@field fileLookup table<string, boolean>
---@field wraps table<string, function>
local loadedAddon = {}

---@params id number
---@return LoadedAddon
function loadedAddon.New( id )
    local o = {
        id = id,
        swepNames = {},
        files = {},
        effectNames = {},
        entityNames = {},
        autorun = {
            shared = {},
            client = {},
            server = {},
        },

        fileLookup = {},
    }

    setmetatable( o, {
        __index = loadedAddon
    } )
    return o
end

local noop = function() end

---@param done? fun(loadedAddon)
function loadedAddon:Mount( done )
    done = done or noop

    if CLIENT then
        steamworks.DownloadUGC( self.id, function( name )
            self.filename = name
            local files = self:mountGMA()
            self:SetFiles( files )
            self:load()
            done( self )
        end )
    else
        local filename = "workshop_addons/" .. self.id .. ".gma"
        local data = GMA.Read( filename )
        if not data then
            HotLoad.logger:Errorf( "Failed to read GMA '%s'", filename )
            return
        end

        local files = {}
        local tmpDir = string.format( "hotload_tmp/%s", self.id )
        file.CreateDir( tmpDir )
        for _, v in pairs( data.Files ) do
            local name = v.Name
            local content = v.Content
            if string.EndsWith( name, ".lua" ) then
                table.insert( files, name )
                HotLoad.fileContent[name] = content
            else
                local dirPath = string.GetPathFromFilename( name )
                file.CreateDir( tmpDir .. "/" .. dirPath )
                file.Write( tmpDir .. "/" .. name, content )
            end
        end
        file.Write( tmpDir .. "/addon.json", util.TableToJSON( {
            ignore = {},
            title = string.format( "Hotloaded addon %s", self.id )
        } ) )

        GMA.Create( string.format( "hotload_tmp/%s_ws_content.txt", self.id ), "data/" .. tmpDir, false, false, function( path )
            -- TODO fix async
        end )
        local path = string.format( "data/hotload_tmp/%s_ws_content.txt", self.id )
        if not file.Exists( path, "GAME" ) then
            HotLoad.logger:Errorf( "Failed to create GMA at '%s'", path )
            return
        end

        HotLoad.logger:Debugf( "GMA created at '%s'", path )
        self.filename = path
        self:SetFiles( files )
        self:mountGMA()
        self:load()
        done( self )
    end
end

function loadedAddon:load()
    self:analyzeFiles()
    self:loadWraps()

    self:loadAutorun()

    if CLIENT then self:loadEffects() end
    self:loadEntities()
    self:loadSweps()
end

function loadedAddon:GetFiles()
    return self.files
end

function loadedAddon:FileExists( filename )
    return self.fileLookup[filename] or false
end

function loadedAddon:loadWraps()
    self.wraps = HotLoad.GetWraps( self )
end

function loadedAddon:applyWraps()
    include = self.wraps.include
    AddCSLuaFile = self.wraps.AddCSLuaFile
end

function loadedAddon:revertWraps()
    include = _OldInclude
    AddCSLuaFile = _OldAddCSLuaFile
end

function loadedAddon:SetFiles( files )
    self.files = files
    self.fileLookup = {}
    for _, filename in pairs( files ) do
        self.fileLookup[filename] = true
    end
end

local luaFenvMeta = {
    __index = _G,
    __newindex = function( t, k, v )
        _G[k] = v
    end
}
function loadedAddon:runLua( files )
    for _, filename in pairs( files ) do
        if not self:FileExists( filename ) then
            HotLoad.logger:Warnf( "Attempted to load file '%s' that was not mounted", filename )
            return
        end

        HotLoad.logger:Debugf( "Running file '%s'", filename )
        local code = HotLoad.fileContent[filename]
        if not code then
            code = file.Read( filename, "GAME" )
        end

        local func = CompileString( code, constructIdentifier( filename ) )

        local newEnv = self.wraps
        setmetatable( newEnv, luaFenvMeta )
        setfenv( func, newEnv )

        local startTime = SysTime()
        func()
        local elapsed = SysTime() - startTime
        HotLoad.logger:Debugf( "File '%s' took %s seconds to run", filename, elapsed )
    end
end

function loadedAddon:mountGMA()
    local success, files = game.MountGMA( self.filename )
    if not success then
        HotLoad.logger:Errorf( "Failed to mount GMA '%s'", self.filename )
        return
    end

    return files
end

function loadedAddon:analyzeFiles()
    for _, filename in ipairs( self.files ) do
        if string.StartsWith( filename, "lua/autorun/server/" ) then
            table.insert( self.autorun.server, filename )
        elseif string.StartsWith( filename, "lua/autorun/client/" ) then
            table.insert( self.autorun.client, filename )
        elseif string.StartsWith( filename, "lua/autorun/" ) then
            table.insert( self.autorun.shared, filename )
        elseif string.StartsWith( filename, "lua/effects" ) then
            local exploded = string.Explode( "/", filename )
            local effectName = exploded[3]
            table.insert( self.effectNames, effectName )
        elseif string.StartsWith( filename, "lua/entities/" ) then
            local exploded = string.Explode( "/", filename )
            local entityName = exploded[3]
            table.insert( self.entityNames, entityName )
        elseif string.StartsWith( filename, "lua/weapons/" ) then
            local exploded = string.Explode( "/", filename )
            local weaponName = exploded[3]
            table.insert( self.swepNames, weaponName )
        end
    end
    local totalAutorun = #self.autorun.shared + #self.autorun.client + #self.autorun.server
    HotLoad.logger:Debugf( "Found %s effects, %s entities, %s weapons, %s autorun files", #self.effectNames, #self.entityNames, #self.swepNames, totalAutorun )
end

function loadedAddon:loadEffects()
    for _, effectName in pairs( self.effectNames ) do
        EFFECT = {}
        self:runLua( { "lua/effects/" .. effectName .. "/init.lua" } )
        effects.Register( EFFECT, effectName )
    end
end

function loadedAddon:loadEntities()
    for _, entityName in pairs( self.entityNames ) do
        ENT = {}
        self:runLua( { "lua/entities/" .. entityName .. "/shared.lua" } )
        if CLIENT then self:runLua( { "lua/entities/" .. entityName .. "/cl_init.lua" } ) end
        if SERVER then self:runLua( { "lua/entities/" .. entityName .. "/init.lua" } ) end
        scripted_ents.Register( ENT, entityName )
    end
end

function loadedAddon:loadSweps()
    for _, swepName in pairs( self.swepNames ) do
        SWEP = {
            Spawnable = false,
            Category = "Other",
            AdminOnly = false,
            PrintName = "Scripted Weapon",
            Base = "weapon_base",
            m_WeaponDeploySpeed = 1,
            Author = "",
            Contact = "",
            Purpose = "",
            Instructions = "",
            ViewModel = "models/weapons/v_pistol.mdl",

            -- TODO all defaults from  https://wiki.facepunch.com/gmod/Structures/SWEP
            Primary = {},
            Secondary = {},
        }
        self:runLua( { "lua/weapons/" .. swepName .. "/shared.lua" } )
        if CLIENT then self:runLua( { "lua/weapons/" .. swepName .. "/cl_init.lua" } ) end
        if SERVER then self:runLua( { "lua/weapons/" .. swepName .. "/init.lua" } ) end
        weapons.Register( SWEP, swepName )
    end
end

function loadedAddon:loadAutorun()
    for _, filename in pairs( self.autorun.shared ) do
        self:runLua( { filename } )
    end
    if CLIENT then
        for _, filename in pairs( self.autorun.client ) do
            self:runLua( { filename } )
        end
    end
    if SERVER then
        for _, filename in pairs( self.autorun.server ) do
            self:runLua( { filename } )
        end
    end
end

HotLoad.LoadedAddon = loadedAddon
