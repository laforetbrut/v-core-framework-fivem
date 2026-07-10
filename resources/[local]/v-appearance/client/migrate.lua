-- v-appearance | one-time appearance migration (schema v1 -> v2)
--
-- v1 stored each component/prop as a raw global drawable id; v2 stores a stable
-- (collection, local index, texture) ref. Conversion needs a live freemode ped
-- (the collection natives are client-only), so it runs once on player load.
--
-- Honest caveat: the conversion is only correct if the load order now equals the
-- one that produced the stored global id. On a base-game-only server that holds
-- for every existing character. Run the migration BEFORE installing the first
-- addon clothing pack — see memory/appearance-suite-plan.md.

local function migrate(app)
    local ped = PlayerPedId()
    -- Convert a table of slots. Entries that fail to decode are LEFT as legacy
    -- ({drawable,texture}) so the engine renders the cache and a later load can
    -- retry them; only clean conversions become refs.
    local function conv(kind, tbl)
        local allOk = true
        for id, e in pairs(tbl or {}) do
            if e and e.idx == nil and e.col == nil then
                local ref = Refs.FromGlobal(ped, kind, tonumber(id), e.drawable, e.texture)
                if ref.idx == nil then
                    allOk = false                              -- keep legacy, retry next load
                else
                    e.col, e.idx, e.tex = ref.col, ref.idx, ref.tex   -- keep e.drawable as cache
                end
            end
        end
        return allOk
    end
    local ok = conv('comp', app.components)
    ok = conv('prop', app.props) and ok
    if ok then app.schema = Config.Schema end   -- only stamp when fully converted
    return app, ok
end

AddEventHandler('v-core:client:onPlayerLoaded', function(data)
    local app = data and data.appearance
    if not app or app.schema == Config.Schema then return end
    if not app.components and not app.props then
        app.schema = Config.Schema
        TriggerServerEvent('v-core:server:saveAppearance', app)
        return
    end
    CreateThread(function()
        -- Collections enumerate off the ped, and drawable sets differ per sex, so
        -- convert only once the ped model matches the stored sex (v-spawn sets it
        -- on load in a separate thread — wait it out).
        local want = joaat(Config.Models[app.sex or 0] or Config.Models[0])
        local tries = 0
        while GetEntityModel(PlayerPedId()) ~= want and tries < 200 do Wait(50); tries = tries + 1 end
        if GetEntityModel(PlayerPedId()) ~= want then return end   -- wrong/late model: retry next load
        Wait(250)   -- let variations settle
        local migrated, ok = migrate(app)
        TriggerServerEvent('v-core:server:saveAppearance', migrated)
        if Config.Debug then print(('[v-appearance] migration %s (schema v%d)'):format(ok and 'complete' or 'partial', migrated.schema or 1)) end
    end)
end)
