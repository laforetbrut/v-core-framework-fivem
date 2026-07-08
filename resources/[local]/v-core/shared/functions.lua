-- v-core | shared functions (loaded on both client and server)
VCore = VCore or {}
VCore.Version = '0.1.0'

--- Debug logger, printed only when Config.Debug is enabled.
function VCore.Debug(...)
    if Config and Config.Debug then
        print('^5[v-core]^7', ...)
    end
end

--- Round a number to the given number of decimals.
function VCore.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end
