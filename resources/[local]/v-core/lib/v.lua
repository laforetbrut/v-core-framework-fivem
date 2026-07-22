-- v-core | lib/v.lua — the helper every v-core script (and every third-party script)
-- loads first. Add ONE line to your manifest and the boilerplate below disappears:
--
--     shared_script '@v-core/lib/v.lua'
--
-- What it replaces, measured on this framework before it existed: 28 hand-tuned
-- `Wait(2600)` sleeps racing v-core's boot, 7 copies of the same lazy core-handle
-- block, and 11 defensive `pcall`s around optional cross-resource calls.
--
-- Everything here is safe to call at file scope, from either side, at any time.

V = V or {}
V.name = GetCurrentResourceName()

local isServer = IsDuplicityVersion()
local core, readyCbs, isReady = nil, {}, false

-- ── The core handle ───────────────────────────────────────────────────────────
-- Resolved on demand and cached. Returns nil rather than throwing while v-core is
-- still starting, so a call at file scope is harmless.
function V.Core()
    if core then return core end
    if GetResourceState('v-core') ~= 'started' then return nil end
    local ok, c = pcall(function() return exports['v-core']:GetCore() end)
    if ok and type(c) == 'table' then core = c end
    return core
end

-- ── V.Ready(fn) ───────────────────────────────────────────────────────────────
-- Runs fn(Core) as soon as v-core is actually up — not after a guessed delay. If the
-- core is already up, fn runs on the next tick, so ordering is the same either way.
function V.Ready(fn)
    if type(fn) ~= 'function' then return end
    if isReady then CreateThread(function() fn(core) end) return end
    readyCbs[#readyCbs + 1] = fn
end

CreateThread(function()
    while not V.Core() do Wait(50) end
    isReady = true
    local cbs = readyCbs
    readyCbs = {}
    for _, fn in ipairs(cbs) do
        local ok, err = pcall(fn, core)
        if not ok then print(('[v] %s: V.Ready handler failed: %s'):format(V.name, err)) end
    end
end)

-- ── V.Module(info) ────────────────────────────────────────────────────────────
-- Declares this resource in the registry so it appears in the admin panel, with its
-- settings. The resource name is filled in for you — one less thing to keep in sync.
-- The registry is server-owned, so this is a no-op on the client (call it from your
-- server side; the values are mirrored to clients automatically).
function V.Module(info)
    if not isServer then return end
    V.Ready(function()
        local ok, err = pcall(function()
            exports['v-core']:RegisterModule(V.name, info)
        end)
        if not ok then print(('[v] %s: RegisterModule failed: %s'):format(V.name, err)) end
    end)
end

-- ── V.Setting(key, default) ───────────────────────────────────────────────────
-- This module's setting. No module name to repeat, and never nil: a value the admin
-- has not touched falls back to what you passed, so callers need no guard.
function V.Setting(key, default)
    local c = V.Core()
    if not c or not c.GetSetting then return default end
    local ok, val = pcall(c.GetSetting, V.name, key, default)
    if ok and val ~= nil then return val end
    return default
end

function V.SettingNumber(key, default)
    return tonumber(V.Setting(key, default)) or default
end

function V.SettingBool(key, default)
    local v = V.Setting(key, default)
    if v == nil then return default end
    return v == true or v == 1 or v == '1' or v == 'true'
end

-- ── V.OnSetting(fn) ───────────────────────────────────────────────────────────
-- Fires when an admin changes one of THIS module's settings. The single most common
-- reason a setting appears to do nothing is that the module cached it at boot.
function V.OnSetting(fn)
    local ev = isServer and 'v-core:server:settingChanged' or 'v-core:client:onSettingChanged'
    AddEventHandler(ev, function(mod, key, value)
        if mod == V.name then fn(key, value) end
    end)
end

-- ── V.Use(resource) ───────────────────────────────────────────────────────────
-- An optional dependency, without the pcall. Returns a table whose every field is a
-- function: if the resource is missing, stopped, or does not define that export, the
-- call returns nil instead of throwing.
--
--     local fuel = V.Use('v-fuel')
--     if fuel.IsElectric(veh) then ... end        -- false-y and safe when v-fuel is gone
--
-- Unlike a bare pcall this SAYS something when the call fails, which is how a whole
-- class of silent bugs (calling a server export from the client) stops being silent.
local proxies = {}

function V.Use(resource)
    if proxies[resource] then return proxies[resource] end
    local p = setmetatable({}, {
        __index = function(_, method)
            return function(...)
                if GetResourceState(resource) ~= 'started' then return nil end
                -- table.pack, not `local ok, res`: several exports in this framework
                -- return (value, reason) and a two-name capture silently drops the
                -- reason, leaving the caller to report "unknown error" forever.
                local r = table.pack(pcall(function(...)
                    return exports[resource][method](exports[resource], ...)
                end, ...))
                local ok, res = r[1], r[2]
                if ok then return table.unpack(r, 2, r.n) end
                print(('[v] %s: exports[\'%s\']:%s() failed on the %s side — %s')
                    :format(V.name, resource, method, isServer and 'server' or 'client', res))
                return nil
            end
        end,
    })
    proxies[resource] = p
    return p
end

function V.Has(resource)
    return GetResourceState(resource) == 'started'
end

-- ── Shortcuts for the three things every script does ──────────────────────────
function V.Notify(target, message, kind)
    -- Server: V.Notify(source, msg, kind). Client: V.Notify(msg, kind).
    local c = V.Core()
    if not c or not c.Notify then return end
    if isServer then c.Notify(target, message, kind or 'info')
    else c.Notify(target, message or 'info') end
end

function V.Player(src)
    local c = V.Core()
    if not c then return nil end
    if isServer then return c.GetPlayer(src) end
    return c.PlayerData
end

-- ── Callbacks, with the side picked for you ───────────────────────────────────
-- Core.RegisterCallback is server-side and Core.TriggerCallback is client-side; mixing
-- them up is a hang with no error. These two only exist on the side that can use them.
if isServer then
    function V.Callback(name, fn)
        V.Ready(function(c) c.RegisterCallback(name, fn) end)
    end
else
    function V.Request(name, cb, ...)
        local c = V.Core()
        if not c then return end
        c.TriggerCallback(name, cb, ...)
    end
end

function V.Log(...)
    print(('[%s]'):format(V.name), ...)
end
