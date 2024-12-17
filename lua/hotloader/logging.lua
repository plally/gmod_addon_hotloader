HotLoad           = HotLoad or {}

local cvar        = CreateConVar( "hotload_logging_level", "1", FCVAR_ARCHIVE, "Logging level for HotLoad", 0, 3 )

local LEVEL_DEBUG = 0
local LEVEL_INFO  = 1
local LEVEL_WARN  = 2
local LEVEL_ERROR = 3


local logger = {
    prefix = "[HotLoad]",
    level = cvar:GetInt()
}

cvars.AddChangeCallback( "hotload_logging_level", function( _, _, new )
    logger.level = tonumber( new )
end )

function logger:Debug( ... )
    if self.level <= LEVEL_DEBUG then
        print( self.prefix, "[DEBUG]", ... )
    end
end

function logger:Debugf( fmt, ... )
    if self.level <= LEVEL_DEBUG then
        self:Debug( string.format( fmt, ... ) )
    end
end

function logger:Info( ... )
    if self.level <= LEVEL_INFO then
        print( self.prefix, "[INFO]", ... )
    end
end

function logger:Infof( fmt, ... )
    if self.level <= LEVEL_INFO then
        self:Info( string.format( fmt, ... ) )
    end
end

function logger:Warn( ... )
    if self.level <= LEVEL_WARN then
        print( self.prefix, "[WARN]", ... )
    end
end

function logger:Warnf( fmt, ... )
    if self.level <= LEVEL_WARN then
        self:Warn( string.format( fmt, ... ) )
    end
end

function logger:Error( ... )
    if self.level <= LEVEL_ERROR then
        print( self.prefix, "[ERROR]", ... )
    end
end

function logger:Errorf( fmt, ... )
    if self.level <= LEVEL_ERROR then
        self:Error( string.format( fmt, ... ) )
    end
end

HotLoad.logger = logger
