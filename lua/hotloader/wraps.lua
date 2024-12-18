_OldInclude = _OldInclude or include
_OldAddCSLuaFile = _OldAddCSLuaFile or AddCSLuaFile

HotLoad._hotLoadincludeLocalPath = nil

local function normalizePath( path )
    local normalized = string.gsub( path, "\\", "/" )
    return normalized
end

---@param addon LoadedAddon
---@return table<string, any>
function HotLoad.GetWraps( addon )
    local includeOverride = function( filename )
        local localPath = HotLoad._hotLoadIncludeLocalPath

        local luaFilename = filename
        if not string.StartsWith( luaFilename, "lua/" ) then
            luaFilename = "lua/" .. luaFilename
        end
        if file.Exists( luaFilename, "WORKSHOP" ) then
            HotLoad.logger:Debugf( "Including file '%s'", filename )
            addon:runLua( { luaFilename } )
            return
        end

        if not localPath then
            HotLoad.logger:Errorf( "Could not find file to include %s", filename )
            return _OldInclude( filename )
        end

        print(localPath, filename)
        local relativePath = localPath .. filename

        HotLoad.logger:Debugf( "Including file '%s'", relativePath )
        addon:runLua( { relativePath } )
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
        -- HotLoad.logger:Debug( "Ignoring function call with args", ... )
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
