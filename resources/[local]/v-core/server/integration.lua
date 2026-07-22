-- v-core | server/integration.lua
-- The registry a third-party script plugs into, and the three things a framework needs to
-- be extensible rather than merely large:
--
--   * **Services** - "who provides banking?" so an implementation can be swapped without
--     every consumer knowing the resource name.
--   * **Hooks** - a synchronous interception point another resource can veto or rewrite.
--     FiveM events cannot do this: arguments are serialised across resources, so a handler
--     mutating a table changes nothing. Hooks go through exports, which do return values.
--   * **Discovery** - a live list of every module, service, hook, event and command, so a
--     developer can find out what exists instead of reading twenty files.

VCore = VCore or {}

local Services = {}     -- [service] = { resource, provider (export name), since }
local Hooks    = {}     -- [hook]    = { { resource, fn (export name), priority } }
local Events   = {}     -- [event]   = { emitters = {res}, handlers = {res} }
local Commands = {}     -- [name]    = { resource, perm, help }

local function note(tbl, key, resource)
    tbl[key] = tbl[key] or {}
    for _, r in ipairs(tbl[key]) do if r == resource then return end end
    tbl[key][#tbl[key] + 1] = resource
end

-- ── Services ──────────────────────────────────────────────────
--- A resource declares that it provides a named capability. The point is indirection: a
--- server that replaces v-banking with its own banking keeps every consumer working,
--- because consumers ask for the *service*, not the resource.
function VCore.ProvideService(service, resource, providerExport)
    service = tostring(service or '')
    if service == '' or not resource then return false end

    local prev = Services[service]
    if prev and prev.resource ~= resource then
        -- Two providers is a configuration mistake worth shouting about: silently picking
        -- one means half the server talks to a module the operator thinks is disabled.
        VCore.Debug(('service "%s" claimed by %s is already provided by %s - keeping %s')
            :format(service, resource, prev.resource, prev.resource))
        return false
    end

    Services[service] = { resource = resource, provider = providerExport, since = os.time() }
    VCore.Debug(('service registered: %s -> %s'):format(service, resource))
    TriggerEvent('v-core:server:serviceRegistered', service, resource)
    return true
end

function VCore.GetService(service)
    local s = Services[tostring(service or '')]
    if not s then return nil end
    if GetResourceState(s.resource) ~= 'started' then return nil end
    return s.resource, s.provider
end

function VCore.ListServices()
    local out = {}
    for name, s in pairs(Services) do
        out[#out + 1] = { service = name, resource = s.resource,
                          up = GetResourceState(s.resource) == 'started' }
    end
    table.sort(out, function(a, b) return a.service < b.service end)
    return out
end

-- ── Hooks ─────────────────────────────────────────────────────
--- Register an interception point. `fnExport` is an export name in `resource`, called with
--- the payload table and expected to return either a table (the payload, possibly changed)
--- or `false` to veto.
function VCore.RegisterHook(hook, resource, fnExport, priority)
    hook = tostring(hook or '')
    if hook == '' or not resource or not fnExport then return false end
    Hooks[hook] = Hooks[hook] or {}
    for _, h in ipairs(Hooks[hook]) do
        if h.resource == resource and h.fn == fnExport then return true end
    end
    Hooks[hook][#Hooks[hook] + 1] = { resource = resource, fn = fnExport,
                                      priority = tonumber(priority) or 100 }
    -- Lower priority runs first, so a validator can reject before a mutator bothers.
    table.sort(Hooks[hook], function(a, b) return a.priority < b.priority end)
    return true
end

--- Run every handler in turn. Returns the final payload, or nil when one vetoed.
--- A handler that errors is skipped rather than allowed to abort the chain: one broken
--- third-party script must not be able to stop money from moving.
function VCore.RunHook(hook, payload)
    local list = Hooks[tostring(hook or '')]
    if not list or #list == 0 then return payload end
    payload = payload or {}

    for _, h in ipairs(list) do
        if GetResourceState(h.resource) == 'started' then
            local ok, res = pcall(function()
                return exports[h.resource][h.fn](exports[h.resource], payload)
            end)
            if not ok then
                VCore.Debug(('hook %s: %s errored (%s)'):format(hook, h.resource, tostring(res)))
            elseif res == false then
                VCore.Debug(('hook %s: vetoed by %s'):format(hook, h.resource))
                return nil, h.resource
            elseif type(res) == 'table' then
                payload = res
            end
        end
    end
    return payload
end

function VCore.ListHooks()
    local out = {}
    for name, list in pairs(Hooks) do
        local res = {}
        for _, h in ipairs(list) do res[#res + 1] = h.resource end
        out[#out + 1] = { hook = name, handlers = res }
    end
    table.sort(out, function(a, b) return a.hook < b.hook end)
    return out
end

-- ── Discovery ─────────────────────────────────────────────────
function VCore.NoteEvent(event, resource, kind)
    event = tostring(event or '')
    if event == '' then return end
    Events[event] = Events[event] or { emitters = {}, handlers = {} }
    note(Events[event], kind == 'emit' and 'emitters' or 'handlers', resource)
end

function VCore.NoteCommand(name, resource, perm, help)
    Commands[tostring(name or '')] = { resource = resource, perm = perm, help = help }
end

--- Everything a developer needs to answer "what already exists here" in one call.
function VCore.GetRegistry()
    local events = {}
    for name, e in pairs(Events) do
        events[#events + 1] = { event = name, emitters = e.emitters, handlers = e.handlers }
    end
    table.sort(events, function(a, b) return a.event < b.event end)

    local commands = {}
    for name, c in pairs(Commands) do
        commands[#commands + 1] = { name = name, resource = c.resource, perm = c.perm, help = c.help }
    end
    table.sort(commands, function(a, b) return a.name < b.name end)

    return {
        modules  = VCore.GetModules and VCore.GetModules() or {},
        services = VCore.ListServices(),
        hooks    = VCore.ListHooks(),
        events   = events,
        commands = commands,
    }
end

-- ── Exports ───────────────────────────────────────────────────
-- `GetInvokingResource` is what makes these safe to call from anywhere: a resource cannot
-- register a service or a hook in somebody else's name.
exports('ProvideService', function(service, providerExport)
    return VCore.ProvideService(service, GetInvokingResource(), providerExport)
end)
exports('GetService',   function(service) return VCore.GetService(service) end)
exports('ListServices', function() return VCore.ListServices() end)

exports('RegisterHook', function(hook, fnExport, priority)
    return VCore.RegisterHook(hook, GetInvokingResource(), fnExport, priority)
end)
exports('RunHook',   function(hook, payload) return VCore.RunHook(hook, payload) end)
exports('ListHooks', function() return VCore.ListHooks() end)

exports('NoteEvent',   function(event, kind) VCore.NoteEvent(event, GetInvokingResource(), kind) end)
exports('NoteCommand', function(name, perm, help) VCore.NoteCommand(name, GetInvokingResource(), perm, help) end)
exports('GetRegistry', function() return VCore.GetRegistry() end)

--- Turn a module on or off at runtime. The admin panel and `V.SetEnabled` both land here,
--- and it is a real resource stop rather than a flag a module has to remember to check.
exports('SetModuleEnabled', function(name, on)
    name = tostring(name or '')
    if name == '' or name == 'v-core' then return false end   -- the core cannot stop itself
    if on then
        if GetResourceState(name) ~= 'started' then StartResource(name) end
    else
        if GetResourceState(name) == 'started' then StopResource(name) end
    end
    VCore.Log('admin', ('module %s %s'):format(name, on and 'started' or 'stopped'))
    return true
end)

-- A console line that answers "what is in this framework" without opening a file.
RegisterCommand('vdev', function(source)
    if source ~= 0 and not VCore.HasPermission(source, 'admin') then return end
    local r = VCore.GetRegistry()
    local function line(...) print(('[vdev]'):format(), ...) end
    line(('%d modules, %d services, %d hooks, %d events, %d commands')
        :format(#(r.modules or {}), #r.services, #r.hooks, #r.events, #r.commands))
    for _, s in ipairs(r.services) do
        line((' service %-18s %s%s'):format(s.service, s.resource, s.up and '' or ' (down)'))
    end
    for _, h in ipairs(r.hooks) do
        line((' hook    %-18s %s'):format(h.hook, table.concat(h.handlers, ', ')))
    end
end, false)
