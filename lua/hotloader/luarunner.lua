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
---@field wraps table<string, any>
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
        steamworks.DownloadUGC( self.id, function( path, fileHandle )
            self.filename = path
            local files = self:mountGMA()

            -- try stripping linux prefix and mounting
            if files == false then
                HotLoad.logger:Infof( "Failed to mount GMA '%s', trying to strip S:/workshop/ prefix", path )
                local prefix = "S:/workshop/"
                if string.StartsWith( path, prefix ) then
                    path = string.sub( path, #prefix + 1 )
                end
                self.filename = path
                files = self:mountGMA()
            end

            -- if it is still failing use the file handle to copy to data  directory
            if files == false then
                HotLoad.logger:Infof( "File outside of game directory, copying to data directory: %s", path )
                local newFilename = "workshop_addons/" .. self.id .. ".gma.txt"
                local dir = string.GetPathFromFilename( newFilename )
                file.CreateDir( dir )
                local didDelete = file.Delete( newFilename, "DATA" )
                if didDelete then
                    local newFile = file.Open( newFilename, "wb", "DATA" ) --[[@as File]]

                    local f = fileHandle --[[@as File]]

                    while not f:EndOfFile() do
                        local data = f:Read( 1024 * 1024 )
                        newFile:Write( data )
                    end

                    newFile:Close()
                    path = "data/" .. newFilename
                    self.filename = path
                elseif file.Exists( newFilename, "DATA" ) then
                    -- TODO we could maybe just  read the already mounted addon here

                    -- its posible we couldnt delete the addon because it was already mounted
                    -- so just use it I guess
                    path = "data/" .. newFilename
                    self.filename = path
                end

                files = self:mountGMA()
            end

            if files == false then
                HotLoad.logger:Errorf( "Failed to mount GMA, exhausted all methods" )
                done( nil )
                return
            end


            self:SetFiles( files )
            self:load()
            done( self )
        end )
    else
        local filename = "workshop_addons/" .. self.id .. ".gma"
        if not file.Exists( filename, "DATA" ) then
            HotLoad.logger:Errorf( "Failed to find GMA '%s'", filename )
            done( nil )
            return
        end

        self.filename = filename
        HotLoad.StripGMALua( self.id, filename, function( result )
            if not result then
                HotLoad.logger:Errorf( "Failed to strip GMA '%s'", filename )
                done( nil )
                return
            end

            self.filename = result.contentGMAPath
            self:mountGMA()
            self:SetFiles( result.luaFileNames )
            self:load()
            done( self )
        end )
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
    __newindex = function( _, k, v )
        _G[k] = v
    end
}
function loadedAddon:runLua( files )
    for _, filename in pairs( files ) do
        if not self:FileExists( filename ) then
            HotLoad.logger:Warnf( "Attempted to load file '%s' that was not mounted by the addon loader. Called from %s", filename, callSource )
            return
        end

        HotLoad.logger:Debugf( "Running file '%s'", filename )
        local code = HotLoad.fileContent[filename]
        if not code then
            code = file.Read( filename, "WORKSHOP" )
        end

        local func = CompileString( code, constructIdentifier( filename ) )

        local env = self.wraps
        setmetatable( env, luaFenvMeta )
        setfenv( func, env )


        -- TODO maybe this could be stored in the fenv somehow?
        local oldPath = HotLoad._hotLoadIncludeLocalPath
        HotLoad._hotLoadIncludeLocalPath = string.GetPathFromFilename( filename )

        local startTime = SysTime()
        func()

        local elapsed = SysTime() - startTime
        HotLoad.logger:Debugf( "File '%s' took %s seconds to run", filename, elapsed )

        HotLoad._hotLoadIncludeLocalPath = oldPath
    end
end

function loadedAddon:mountGMA()
    local success, files = game.MountGMA( self.filename )
    if not success or not files then
        HotLoad.logger:Warnf( "Failed to mount GMA '%s'", self.filename )
        return false
    end

    return files
end

function loadedAddon:analyzeFiles()
    for _, filename in ipairs( self.files ) do
        if string.match( filename, "lua/autorun/server/[^/]+%.lua" ) then
            table.insert( self.autorun.server, filename )
        elseif string.match( filename, "lua/autorun/client/[^/]+%.lua" ) then
            table.insert( self.autorun.client, filename )
        elseif string.match( filename, "lua/autorun/[^/]+%.lua" ) then
            table.insert( self.autorun.shared, filename )
        elseif string.StartsWith( filename, "lua/effects" ) then
            local exploded = string.Explode( "/", filename )
            local effectName = exploded[3]
            table.insert( self.effectNames, effectName )
        elseif string.StartsWith( filename, "lua/entities/" ) then
            local exploded = string.Explode( "/", filename )
            local entityName = exploded[3]
            if string.EndsWith( exploded[3], ".lua" ) then
                entityName = string.sub( entityName, 1, -5 ) -- remove .lua at the end
            end
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
        self:runLua( { "lua/entities/" .. entityName .. ".lua" } )
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
