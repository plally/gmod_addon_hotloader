_OldInclude = _OldInclude or include
_OldAddCSLuaFile = _OldAddCSLuaFile or AddCSLuaFile

local function normalizePath( path, root )
    local normalized = string.gsub( path, "\\", "/" )
    if not string.find( path, "../" ) then
        return normalized
    end

    normalized = root .. normalized

    local segments = string.Explode( "/", normalized )

    local normalizedSegments = {}

    for _, segment in ipairs( segments ) do
        if segment == ".." then
            table.remove( normalizedSegments )
        else
            table.insert( normalizedSegments, segment )
        end
    end

    return table.concat( normalizedSegments, "/" )
end

---@param addon LoadedAddon
function HotLoad.GetWraps( addon )
    local includeOverride = function( filename )
        local callSource = debug.getinfo( 2, "S" ).source
        local identifierData = HotLoad.parseIdentifier( callSource )
        local callSourceFilename
        if identifierData.isAddonLoader then
            callSourceFilename = identifierData.filename
        else
            callSourceFilename = callSource:sub( 2 )
        end

        filename = normalizePath( filename, string.GetPathFromFilename( callSourceFilename ) )

        local sourceDir = string.GetPathFromFilename( identifierData.filename )

        local relativePath = sourceDir .. filename
        if file.Exists( relativePath, "WORKSHOP" ) then
            HotLoad.logger:Debugf( "Including file '%s'", relativePath )
            addon:runLua( { relativePath } )
            return
        end

        if not string.StartsWith( filename, "lua/" ) then
            filename = "lua/" .. filename
        end

        HotLoad.logger:Debugf( "Including file '%s'", filename )
        addon:runLua( { filename } )
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
