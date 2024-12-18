-- Copied from https://github.com/RaphaelIT7/gmod-lua-gma-writer

GMA = GMA or {}
GMA.Addon = {
    Indent = "GMAD",
    Version = 3,
    AppID = 4000,
    CompressionSignature = 0xBEEFCACE,
    Header = { -- 5 chars
        Ident = "    ", -- 4 chars
        Version = " ", -- 1 char
    },
    TimestampOffset = 5 + 8 -- Header Size + uint64_t
}

local str_b0 = string.char( 0 )
function GMA.Build( output, name, description, path, files, crc, prepared )
    prepared = prepared or {}

    local f = file.Open( output, "wb", "DATA" ) --[[@as File]]
    assert( f, "Failed to open " .. output )

    --[[
		Header
	]]
    f:Write( GMA.Addon.Indent ) -- Ident (4)
    f:WriteByte( GMA.Addon.Version ) -- Version (1)
    f:WriteUInt64( 0 ) -- SteamID (8) [unused]
    f:WriteUInt64( system.SteamTime() or os.time() ) -- TimeStamp (8)
    f:WriteByte( 0 ) -- Required content (list of strings) [seems unused]
    f:Write( name .. str_b0 ) -- Addon Name (n)
    f:Write( description .. str_b0 ) -- Addon Description (n)
    f:Write( "Author Name" .. str_b0 ) -- Addon Author (n) [unused]
    f:WriteLong( 1 ) -- Addon Version (4) [unused]

    --[[
		File list
	]]
    for id, ffile in ipairs( files ) do
        local data = prepared[ffile]

        f:WriteLong( id ) -- File number (4)

        f:Write( string.lower( string.sub( ffile, #path + 1 ) ) .. str_b0 ) -- File name (all lower case!) (n)

        f:WriteUInt64( data.size ) -- File size (8). We don't have WriteInt64 :<

        -- crc
        if crc then
            f:WriteULong( util.CRC( data.content ) ) -- File CRC (4)
        else
            f:WriteULong( 0 )
        end
    end

    f:WriteULong( 0 )

    --[[
		File content
	]]
    for id, ffile in ipairs( files ) do
        f:Write( prepared[ffile].content )
    end

    --[[
		.gma CRC
	]]
    if crc then
        local origin = f:Tell()
        f:Seek( 0 )
        local CRC = util.CRC( f:Read( f:Size() ) )
        f:Seek( origin )

        f:WriteULong( CRC )
    else
        f:WriteULong( 0 )
    end

    f:Close()
end

function GMA.PrePareFiles( tbl, path, files, async )
    async = async or false

    assert( tbl, "Missing table!" )

    local maxActiveReads = 500

    tbl.files = {}
    tbl.queue = {}
    tbl.async = async
    tbl.activeReads = 0
    tbl.checkfile = function( file, status, content, id )
        if status ~= FSASYNC_OK then
            -- return the error, we still need to call OnFinish if the last file failed
            return "Failed to read " .. file .. " (Code: " .. tostring( status ) .. ")"
        end

        tbl.files[file] = {
            content = content, -- file.Read is slow
            size = string.len( content ) -- file.Size is slow.
        }
    end

    local identifier = "GMA.PrePareFiles." .. path .. "-" .. CurTime()
    timer.Create( identifier, 0, 0, function()
        if tbl.activeReads >= maxActiveReads then return end

        for _ = 1, maxActiveReads - tbl.activeReads do
            local nextFile = table.remove( tbl.queue, 1 )
            if not nextFile then
                timer.Remove( identifier )
                return
            end
            tbl.activeReads = tbl.activeReads + 1
            file.AsyncRead( nextFile, "GAME", function( _, _, status, content )
                tbl.activeReads = tbl.activeReads - 1

                local err = tbl.checkfile( nextFile, status, content )
                if #tbl.queue == 0 and tbl.activeReads == 0 then
                    tbl.OnFinish( tbl.files )
                end
                if err then
                    error( err )
                end
            end )
        end
    end )

    for _, ffile in ipairs( files ) do
        if async then
            table.insert( tbl.queue, ffile )
        else
            -- TODO we should log file read errors, maybe by mapping to the correct FSASYNC enum
            local err = tbl.checkfile( ffile, FSASYNC_OK, file.Read( ffile, "GAME" ) )
            if err then
                error( err )
            end
        end
    end
    if not async then
        tbl.OnFinish( tbl.files )
    end
end

function GMA.FindFiles( tbl, path, ignore )
    path = string.EndsWith( path, "/" ) and path or (path .. "/")

    local files, folders = file.Find( path .. "*", "GAME" )
    for _, file in ipairs( files ) do
        --[[
			Ignore addon.json and everything in the ignore table.
		]]
        if file == "addon.json" then continue end
        local skip = false
        for _, str in ipairs( ignore ) do
            if string.EndsWith( file, str ) then
                skip = true
                break
            end
        end
        if skip then continue end

        table.insert( tbl, path .. file )
    end

    for _, folder in ipairs( folders ) do
        GMA.FindFiles( tbl, path .. folder, ignore )
    end
end

function GMA.Create( output, input, async, crc, callback )
    async = async or false
    crc = crc or false

    input = string.EndsWith( input, "/" ) and input or (input .. "/")

    local addon = file.Read( input .. "addon.json", "GAME" )
    local addon_tbl = util.JSONToTable( addon )
    local description = util.JSONToTable( addon )
    description.title = nil
    description.description = description.description or "Description"
    description.type = string.lower( description.type or "" )
    description.ignore = nil

    local files = {}
    GMA.FindFiles( files, input, addon_tbl.ignore )

    local prepare = {}
    prepare.OnFinish = function( prepared )
        GMA.Build( output, addon_tbl.title, "\n" .. string.Replace( util.TableToJSON( description, true ), '"tags": ', '"tags": \n	' ), input, files, crc, prepared )
        callback( "data/" .. output )
    end

    GMA.PrePareFiles( prepare, input, files, async )
end

local function ReadUntilNull( file, steps )
    local pos = file:Tell()

    local file_str = ""
    local finished = false
    while not finished do
        local str = file:Read( steps )
        local found = string.find( str, str_b0 )
        if found then
            str = string.sub( str, 0, found - 1 )
            finished = true
        end

        file_str = file_str .. str
    end

    file:Seek( pos + string.len( file_str ) + 1 ) -- + 1 for the Null byte we remove from the String.

    return file_str
end

function GMA.Read( file_path, no_content, path )
    no_content = no_content or false
    path = path or "DATA"

    local f = file.Open( file_path, "rb", path )

    local tbl = {}

    --[[
		Header
	]]
    tbl.Indent = f:Read( string.len( GMA.Addon.Indent ) )
    tbl.Version = f:ReadByte()
    tbl.SteamID = f:ReadUInt64()
    tbl.TimeStamp = f:ReadUInt64()
    tbl.Required_Content = f:ReadByte()
    tbl.Name = ReadUntilNull( f, 20 )
    tbl.Description = ReadUntilNull( f, 50 )
    tbl.Author = ReadUntilNull( f, 15 )

    tbl.Addon_Version = f:ReadLong()

    --[[
		File list
	]]
    tbl.Files = {}
    local search = true
    while search do
        local file_id = f:ReadLong()
        if file_id == 0 then
            search = false
            continue
        end

        tbl.Files[file_id] = {
            Name = ReadUntilNull( f, 50 ),
            Size = f:ReadUInt64(),
            CRC = f:ReadULong(),
        }
    end

    --[[
		File content
	]]
    if not no_content then
        for k = 1, #tbl.Files do
            local file_tbl = tbl.Files[k]
            file_tbl.Content = f:Read( file_tbl.Size )
        end
    else
        local skip = 0
        for k = 1, #tbl.Files do
            local file_tbl = tbl.Files[k]
            skip = skip + file_tbl.Size
        end

        f:Seek( f:Tell() + skip )
    end

    --[[
		.gma CRC
	]]
    tbl.CRC = f:ReadULong()
    f:Close()

    return tbl
end
