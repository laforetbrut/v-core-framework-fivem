-- v-core | i18n helper (shared)
-- Included by every resource:  shared_script '@v-core/locale/shared.lua'
-- Each resource defines its own `Locales = { en = {...}, fr = {...} }` and calls L('key', ...).
Locales = Locales or { en = {}, fr = {} }

local function currentLang()
    if IsDuplicityVersion() then
        return GetConvar('vcore_lang', 'fr')
    end
    return (LocalPlayer and LocalPlayer.state and LocalPlayer.state.lang) or GetConvar('vcore_lang', 'fr')
end

--- Translate a key in the local player's language (client) / server default.
function L(key, ...)
    local lang = currentLang()
    local tbl = Locales[lang] or Locales.en or {}
    local str = tbl[key]
    if str == nil then str = (Locales.en and Locales.en[key]) or key end
    if select('#', ...) > 0 then
        local ok, res = pcall(string.format, str, ...)
        return ok and res or str
    end
    return str
end

-- Server-only: translate for a specific player's language.
if IsDuplicityVersion() then
    function LP(source, key, ...)
        local lang = (Player(source).state and Player(source).state.lang) or GetConvar('vcore_lang', 'fr')
        local tbl = Locales[lang] or Locales.en or {}
        local str = tbl[key]
        if str == nil then str = (Locales.en and Locales.en[key]) or key end
        if select('#', ...) > 0 then
            local ok, res = pcall(string.format, str, ...)
            return ok and res or str
        end
        return str
    end
end
