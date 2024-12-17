_OldInclude = _OldInclude or include
_OldAddCSLuaFile = _OldAddCSLuaFile or AddCSLuaFile

---@param addon LoadedAddon
function HotLoad.GetWraps( addon )
    local includeOverride = function( filename )
        local callSource = debug.getinfo( 2, "S" ).source
        local identifierData = HotLoad.parseIdentifier( callSource )
        if not identifierData.isAddonLoader then
            return _OldInclude( filename )
        end

        local sourceDir = string.GetPathFromFilename( identifierData.filename )

        local relativePath = sourceDir .. filename
        if file.Exists( relativePath, "WORKSHOP" ) then
            local code = file.Read( relativePath, "WORKSHOP" )

            HotLoad.logger:Debugf( "Including file '%s'", relativePath )
            addon:runLua( { relativePath } )
            return
        end

        local luaPath = "lua/" .. filename
        local code = file.Read( luaPath, "GAME" )

        HotLoad.logger:Debugf( "Including file '%s'", luaPath )
        addon:runLua( { luaPath } )
    end

    local AddCSLuaFileOverride = function( filename )
        local callSource = debug.getinfo( 2, "S" ).source
        local identifierData = HotLoad.parseIdentifier( callSource )
        if not identifierData.isAddonLoader then
            return _OldAddCSLuaFile( filename )
        end

        HotLoad.logger:Debugf( "Ignoring AddCSLuaFile for '%s'", filename )
    end

    local funcPrinter = function( ... )
        HotLoad.logger:Debug( "Ignoring function call with args", ... )
    end
    return {
        include = includeOverride,
        AddCSLuaFile = AddCSLuaFileOverride,
        resource = {
            AddFile = funcPrinter,
            AddSingleFile = funcPrinter,
            AddWorkshop = funcPrinter,
        }
    }
end
