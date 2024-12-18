HotLoad = HotLoad or {
    ---@type table<string, string>
    fileContent = {},
}

local function includeShared( filename )
    AddCSLuaFile( filename )
    include( filename )
end

includeShared( "hotloader/logging.lua" )
includeShared( "hotloader/wraps.lua" )
includeShared( "hotloader/luarunner.lua" )
includeShared( "hotloader/autoload.lua" )
includeShared( "hotloader/gma.lua")
includeShared( "hotloader/contentstripper.lua")
