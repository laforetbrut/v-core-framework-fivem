-- v-core | shared functions (loaded on both client and server)
VCore = VCore or {}
VCore.Version = '0.1.1'

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

--- Format an integer as grouped money: 1234567 -> "1,234,567".
function VCore.FormatMoney(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign = ''
    if s:sub(1, 1) == '-' then sign = '-'; s = s:sub(2) end
    local grouped = s:reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^%s', '')
    return sign .. (grouped:gsub(' ', ','))
end
