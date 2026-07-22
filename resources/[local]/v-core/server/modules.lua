-- v-core | module registry & live settings
--
-- Two problems, one answer.
--
-- 1. "Everything must be configurable from the admin panel." Until now each module solved
--    that by inventing a v-world domain. That works for CONTENT (a list of shops, a table
--    of items) but it is far too heavy for TUNABLES — a drain rate, a threshold, a toggle.
-- 2. "Someone else's script should plug in without editing the framework."
--
-- A module DECLARES itself and its settings; v-core stores the values, serves them to the
-- admin panel, and pushes changes back. Nothing in v-admin knows what a module's settings
-- are — it renders whatever the module declared. That is what makes a third-party resource
-- a first-class citizen: it declares, and it appears.
--
--   -- in any resource, server side:
--   exports['v-core']:RegisterModule('my-script', {
--       label = 'My Script', category = 'gameplay',
--       settings = {
--           { key = 'payout',  label = 'Payout',    type = 'number', default = 250, min = 0, max = 10000 },
--           { key = 'enabled', label = 'Enabled',   type = 'bool',   default = true },
--           { key = 'mode',    label = 'Mode',      type = 'select', default = 'a', options = { 'a', 'b' } },
--       },
--   })
--   local payout = exports['v-core']:GetSetting('my-script', 'payout')
--   AddEventHandler('v-core:server:settingChanged', function(mod, key, value) ... end)
--
-- Auto-detection: a resource that declares `v_module 'yes'` in its fxmanifest is listed
-- even before it registers anything, so an operator can SEE that it is installed.
VCore = VCore or {}

local Modules  = {}     -- name -> { label, category, settings = { def, … }, resource }
local Values   = {}     -- name -> { key = value }
local declared = {}     -- name -> true (found via fxmanifest, may not have registered yet)

local TYPES = { number = true, bool = true, string = true, select = true, color = true }

-- ── Storage ────────────────────────────────────────────────────
local function ensureTable()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `module_settings` (
        `module` VARCHAR(64) NOT NULL,
        `key`    VARCHAR(64) NOT NULL,
        `value`  TEXT NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        `updated_by` VARCHAR(24) DEFAULT NULL,
        PRIMARY KEY (`module`, `key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

--- Values are stored as JSON so a bool stays a bool and a number stays a number:
--- a TEXT column that round-trips "true" into the string "true" is a bug generator.
local function encode(v) return json.encode({ v = v }) end
local function decode(s)
    if type(s) ~= 'string' then return nil end
    local ok, t = pcall(json.decode, s)
    return (ok and type(t) == 'table') and t.v or nil
end

local function loadValues(name)
    Values[name] = {}
    for _, r in ipairs(MySQL.query.await(
        'SELECT `key`, `value` FROM module_settings WHERE `module` = ?', { name }) or {}) do
        Values[name][r.key] = decode(r.value)
    end
end

-- ── Validation ─────────────────────────────────────────────────
--- Coerce a submitted value to the declared type and range. A setting that cannot be
--- coerced is REJECTED rather than silently stored as something else.
local function coerce(def, value)
    if def.type == 'number' then
        local n = tonumber(value)
        if not n then return nil, 'type' end
        if def.min and n < def.min then n = def.min end
        if def.max and n > def.max then n = def.max end
        if def.step == 1 then n = math.floor(n + 0.5) end
        return n
    elseif def.type == 'bool' then
        return (value == true or value == 1 or value == 'true') and true or false
    elseif def.type == 'select' then
        for _, o in ipairs(def.options or {}) do
            if o == value then return value end
        end
        return nil, 'option'
    elseif def.type == 'color' then
        local s = tostring(value or '')
        if not s:match('^#%x%x%x%x%x%x$') then return nil, 'type' end
        return s
    end
    local s = tostring(value or '')
    if def.maxLength and #s > def.maxLength then s = s:sub(1, def.maxLength) end
    return s
end

local function defOf(name, key)
    local m = Modules[name]
    if not m then return nil end
    for _, d in ipairs(m.settings or {}) do
        if d.key == key then return d end
    end
end

-- ── Public API ─────────────────────────────────────────────────
--- Declare a module and its settings. Safe to call again (a resource restart re-registers);
--- stored values survive because they live in the DB, not in this table.
--- @return boolean
function VCore.RegisterModule(name, info)
    name = tostring(name or '')
    if name == '' or type(info) ~= 'table' then return false end

    local clean = {}
    for _, d in ipairs(info.settings or {}) do
        if type(d) == 'table' and d.key and TYPES[d.type or 'string'] then
            clean[#clean + 1] = {
                key = tostring(d.key), label = d.label or d.key,
                type = d.type or 'string', default = d.default,
                min = d.min, max = d.max, step = d.step,
                options = d.options, maxLength = d.maxLength,
                hint = d.hint,
            }
        end
    end

    Modules[name] = {
        label = info.label or name,
        category = info.category or 'other',
        resource = info.resource or name,
        settings = clean,
    }
    if not Values[name] then loadValues(name) end
    VCore.Debug(('module registered: %s (%d setting(s))'):format(name, #clean))
    return true
end

--- Read a setting. Falls back to the declared default, so a module never has to care
--- whether an operator has touched it.
function VCore.GetSetting(name, key, fallback)
    local v = Values[name] and Values[name][key]
    if v ~= nil then return v end
    local d = defOf(name, key)
    if d and d.default ~= nil then return d.default end
    return fallback
end

--- Every setting of a module as a plain table, defaults filled in.
function VCore.GetSettings(name)
    local out = {}
    for _, d in ipairs((Modules[name] or {}).settings or {}) do
        out[d.key] = VCore.GetSetting(name, d.key)
    end
    return out
end

--- Write a setting. Returns ok, error.
function VCore.SetSetting(name, key, value, byCitizenId)
    local d = defOf(name, key)
    if not d then return false, 'unknown' end
    local v, err = coerce(d, value)
    if v == nil and err then return false, err end

    Values[name] = Values[name] or {}
    Values[name][key] = v
    MySQL.query.await([[INSERT INTO module_settings (`module`, `key`, `value`, `updated_by`) VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `updated_by` = VALUES(`updated_by`)]],
        { name, key, encode(v), byCitizenId })

    -- tell the module (and everyone else) so nothing has to poll
    TriggerEvent('v-core:server:settingChanged', name, key, v)
    TriggerClientEvent('v-core:client:settingChanged', -1, name, key, v)
    return true
end

--- Put a setting back to what the module declared.
function VCore.ResetSetting(name, key, byCitizenId)
    local d = defOf(name, key)
    if not d then return false, 'unknown' end
    Values[name] = Values[name] or {}
    Values[name][key] = nil
    MySQL.query.await('DELETE FROM module_settings WHERE `module` = ? AND `key` = ?', { name, key })
    TriggerEvent('v-core:server:settingChanged', name, key, d.default)
    TriggerClientEvent('v-core:client:settingChanged', -1, name, key, d.default)
    return true
end

function VCore.GetModules() return Modules end

-- ── Auto-detection ─────────────────────────────────────────────
--- Walk the running resources and note every one that declares `v_module 'yes'`. This is
--- what lets a script somebody else wrote show up in the panel: it declares in its
--- manifest, and it is listed — even before (or without) registering any settings.
local function detect()
    local found = 0
    for i = 0, GetNumResources() - 1 do
        local res = GetResourceByFindIndex(i)
        if res and GetResourceState(res) == 'started' then
            local flag = GetResourceMetadata(res, 'v_module', 0)
            if flag == 'yes' or flag == 'true' then
                declared[res] = true
                found = found + 1
                if not Modules[res] then
                    -- listed but silent: it has declared nothing yet
                    Modules[res] = {
                        label = GetResourceMetadata(res, 'v_module_label', 0) or res,
                        category = GetResourceMetadata(res, 'v_module_category', 0) or 'other',
                        resource = res, settings = {}, silent = true,
                    }
                end
            end
        end
    end
    VCore.Debug(('module scan: %d resource(s) declare v_module'):format(found))
end

VCore.DetectModules = detect

-- A resource that starts later must still be picked up.
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then return end
    local flag = GetResourceMetadata(res, 'v_module', 0)
    if flag == 'yes' or flag == 'true' then
        declared[res] = true
        if not Modules[res] then
            Modules[res] = {
                label = GetResourceMetadata(res, 'v_module_label', 0) or res,
                category = GetResourceMetadata(res, 'v_module_category', 0) or 'other',
                resource = res, settings = {}, silent = true,
            }
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    -- keep the settings (they are in the DB) but stop advertising a stopped module
    if Modules[res] and res ~= GetCurrentResourceName() then Modules[res] = nil end
end)

-- ── Admin surface ──────────────────────────────────────────────
-- The panel asks for "every module and its settings" and gets a self-describing payload;
-- it renders whatever it is given, so a new module needs no v-admin change at all.
VCore.RegisterCallback('v-core:settings:list', function(source, resolve)
    if not VCore.HasPermission(source, 'admin') then resolve(false); return end
    local out = {}
    for name, m in pairs(Modules) do
        local settings = {}
        for _, d in ipairs(m.settings) do
            settings[#settings + 1] = {
                key = d.key, label = d.label, type = d.type, hint = d.hint,
                min = d.min, max = d.max, step = d.step, options = d.options,
                default = d.default,
                value = VCore.GetSetting(name, d.key),
                overridden = (Values[name] or {})[d.key] ~= nil,
            }
        end
        table.sort(settings, function(a, b) return a.key < b.key end)
        out[#out + 1] = {
            name = name, label = m.label, category = m.category,
            running = GetResourceState(m.resource) == 'started',
            settings = settings, silent = m.silent and #settings == 0 or nil,
        }
    end
    table.sort(out, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.label < b.label
    end)
    resolve({ modules = out })
end)

VCore.RegisterCallback('v-core:settings:set', function(source, resolve, data)
    if not VCore.HasPermission(source, 'admin') or type(data) ~= 'table' then resolve(false); return end
    local p = VCore.GetPlayer(source)
    local cid = p and p.citizenid or 'console'
    local ok, err
    if data.reset then
        ok, err = VCore.ResetSetting(tostring(data.module or ''), tostring(data.key or ''), cid)
    else
        ok, err = VCore.SetSetting(tostring(data.module or ''), tostring(data.key or ''), data.value, cid)
    end
    if not ok then resolve({ error = err or 'unknown' }); return end
    VCore.Log('admin', ('%s set %s.%s'):format(cid, data.module, data.key),
        { value = data.value, reset = data.reset }, cid)
    resolve({ ok = true, value = VCore.GetSetting(data.module, data.key) })
end)

-- ── Boot ───────────────────────────────────────────────────────
CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    ensureTable()
    -- give the other modules a moment to start and register themselves
    Wait(3000)
    detect()
    -- warm every declared module's stored values
    for name in pairs(Modules) do
        if not Values[name] then loadValues(name) end
    end
    TriggerEvent('v-core:server:modulesReady')
end)

-- ── Direct exports ─────────────────────────────────────────────
-- A third-party script should not have to know about GetCore() to plug in. These are the
-- whole integration surface: declare, read, react.
exports('RegisterModule', function(name, info) return VCore.RegisterModule(name, info) end)
exports('GetSetting',     function(name, key, fallback) return VCore.GetSetting(name, key, fallback) end)
exports('GetSettings',    function(name) return VCore.GetSettings(name) end)
exports('SetSetting',     function(name, key, value) return VCore.SetSetting(name, key, value, 'script') end)
exports('GetModules',     function() return VCore.GetModules() end)
exports('IsModule',       function(name) return VCore.GetModules()[name] ~= nil end)
