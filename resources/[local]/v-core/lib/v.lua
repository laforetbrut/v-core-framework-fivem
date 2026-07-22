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

-- ═══════════════════════════════════════════════════════════════════════════════
--  Integration toolkit
--  Everything below exists so a script somebody else wrote can plug into this
--  framework without reading its source.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Events, with discovery ────────────────────────────────────────────────────
-- Thin wrappers over FiveM's own events, plus one thing FiveM does not give you: a
-- registry, so `GetRegistry()` can answer "what events exist and who listens".

function V.On(event, fn)
    AddEventHandler(event, fn)
    if isServer then
        pcall(function() exports['v-core']:NoteEvent(event, 'handle') end)
    end
    return true
end

--- A net event this resource is willing to receive from the other side.
function V.OnNet(event, fn)
    RegisterNetEvent(event, fn)
    if isServer then
        pcall(function() exports['v-core']:NoteEvent(event, 'handle') end)
    end
    return true
end

function V.Emit(event, ...)
    TriggerEvent(event, ...)
    if isServer then
        pcall(function() exports['v-core']:NoteEvent(event, 'emit') end)
    end
end

if isServer then
    --- To one player, or to everyone when `target` is nil.
    function V.EmitClient(event, target, ...)
        TriggerClientEvent(event, target or -1, ...)
        pcall(function() exports['v-core']:NoteEvent(event, 'emit') end)
    end
else
    function V.EmitServer(event, ...)
        TriggerServerEvent(event, ...)
    end
end

-- ── Services ──────────────────────────────────────────────────────────────────
-- Ask for a capability, not a resource. A server that swaps `v-banking` for its own
-- banking keeps every consumer working, because consumers never named the resource.
--
--     V.Provide('banking')                    -- in v-banking
--     local bank = V.Service('banking')        -- in anything else
--     bank.GetBalance(src)
--
-- `V.Service` returns the same forgiving proxy as `V.Use`, so a missing provider is a nil
-- return rather than a crash.

function V.Provide(service)
    if not isServer then return false end
    local ok = false
    V.Ready(function()
        ok = select(1, pcall(function()
            return exports['v-core']:ProvideService(service)
        end))
    end)
    return ok
end

function V.Service(service)
    local c = V.Core()
    if not c then return V.Use('__missing__') end
    local ok, resource = pcall(function() return exports['v-core']:GetService(service) end)
    if not ok or not resource then return V.Use('__missing__') end
    return V.Use(resource)
end

function V.HasService(service)
    local ok, resource = pcall(function() return exports['v-core']:GetService(service) end)
    return ok and resource ~= nil
end

-- ── Hooks ─────────────────────────────────────────────────────────────────────
-- A synchronous interception point another resource can veto or rewrite. This is the one
-- thing FiveM events cannot do: event arguments are serialised across resources, so a
-- handler that mutates a table changes nothing on the other side. Hooks go through
-- exports, which do return values.
--
--     V.Hook('banking:beforeTransfer', function(p)
--         if p.amount > 100000 then return false end   -- veto
--         p.fee = p.fee + 50                            -- or rewrite
--         return p
--     end)
--
-- Lower priority runs first, so a validator can reject before a mutator bothers.

local hookSeq = 0

function V.Hook(hook, fn, priority)
    if not isServer or type(fn) ~= 'function' then return false end
    hookSeq = hookSeq + 1
    local name = ('__vhook_%d'):format(hookSeq)
    -- The handler is exposed as an export so v-core can call it and read what it returns.
    exports(name, fn)
    V.Ready(function()
        pcall(function() exports['v-core']:RegisterHook(hook, name, priority) end)
    end)
    return true
end

--- Run a hook from the module that owns the decision. Returns the payload (possibly
--- rewritten) or nil when a handler vetoed - so the caller checks for nil, not for true.
function V.RunHook(hook, payload)
    if not isServer then return payload end
    local ok, res, by = pcall(function()
        return exports['v-core']:RunHook(hook, payload)
    end)
    if not ok then return payload end
    return res, by
end

-- ── Modules: state and control ────────────────────────────────────────────────
function V.Enabled(module)
    return GetResourceState(tostring(module or '')) == 'started'
end

--- Start or stop another module at runtime. A real resource stop, not a flag every module
--- has to remember to honour.
function V.SetEnabled(module, on)
    if not isServer then return false end
    local ok = pcall(function() return exports['v-core']:SetModuleEnabled(module, on) end)
    return ok
end

--- Refuse to run against a version you were not written for, loudly and once, rather than
--- failing in some unrelated place an hour later.
function V.Require(resource, minVersion)
    if GetResourceState(resource) ~= 'started' then
        print(('[v] %s requires %s, which is not started.'):format(V.name, resource))
        return false
    end
    if not minVersion then return true end
    local have = GetResourceMetadata(resource, 'version', 0) or '0.0.0'
    local function parts(v)
        local a, b, c = tostring(v):match('(%d+)%.(%d+)%.(%d+)')
        return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    end
    local h1, h2, h3 = parts(have)
    local w1, w2, w3 = parts(minVersion)
    local okv = h1 > w1 or (h1 == w1 and (h2 > w2 or (h2 == w2 and h3 >= w3)))
    if not okv then
        print(('[v] %s requires %s >= %s, found %s.'):format(V.name, resource, minVersion, have))
    end
    return okv
end

function V.Version(resource)
    return GetResourceMetadata(resource or V.name, 'version', 0) or '0.0.0'
end

-- ── Commands, gated and discoverable ──────────────────────────────────────────
-- Admin commands are fine; player commands are not (see DEVELOPERS.md). This registers
-- the permission check and the help text in one call, and puts the command in the registry
-- so `vdev` can list it.

function V.Command(name, opts, fn)
    if not isServer then return false end
    opts = opts or {}
    local perm = opts.perm or 'admin'
    RegisterCommand(name, function(source, args, raw)
        if source ~= 0 then
            local c = V.Core()
            if not c or not c.HasPermission(source, perm) then return end
        end
        fn(source, args, raw)
    end, false)
    V.Ready(function()
        pcall(function() exports['v-core']:NoteCommand(name, perm, opts.help) end)
    end)
    return true
end

-- ── Small things every script rewrites ────────────────────────────────────────
function V.Interval(ms, fn)
    local stop = false
    CreateThread(function()
        while not stop do
            Wait(ms)
            local ok, err = pcall(fn)
            if not ok then print(('[v] %s: interval failed: %s'):format(V.name, err)) end
        end
    end)
    return function() stop = true end
end

function V.Timeout(ms, fn)
    CreateThread(function() Wait(ms); pcall(fn) end)
end

--- A statebag on the player, readable by every resource on both sides. The shortest safe
--- way to share a fact without inventing an event for it.
function V.State(key, value, replicated)
    if isServer then
        return nil
    end
    local st = LocalPlayer.state
    if value == nil then return st[key] end
    st:set(key, value, replicated ~= false)
    return value
end

if isServer then
    function V.PlayerState(src, key, value, replicated)
        local st = Player(src).state
        if value == nil then return st[key] end
        st:set(key, value, replicated ~= false)
        return value
    end
end

--- The whole registry: modules, services, hooks, events and commands. What a developer
--- reads instead of twenty files.
function V.Registry()
    if not isServer then return nil end
    local ok, r = pcall(function() return exports['v-core']:GetRegistry() end)
    return ok and r or nil
end
