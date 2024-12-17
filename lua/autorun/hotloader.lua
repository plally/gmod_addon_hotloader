HotLoad = HotLoad or {}
local function includeShared( filename )
    AddCSLuaFile( filename )
    include( filename )
end

includeShared( "hotloader/logging.lua" )
includeShared( "hotloader/wraps.lua" )
includeShared( "hotloader/luarunner.lua" )
includeShared( "hotloader/autoload.lua" )
