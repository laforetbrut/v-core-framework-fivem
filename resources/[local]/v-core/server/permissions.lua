-- v-core | permission system
-- Gates in-game management (jobs, prices, shops, items, ...) by tier.
VCore = VCore or {}

--- Numeric rank for a permission level string.
function VCore.PermRank(level)
    return Config.PermissionLevels[level or 'user'] or 0
end

--- Resolve a source's current permission level string.
function VCore.GetPermission(source)
    local player = VCore.GetPlayer(source)
    if player and player.permission then
        return player.permission
    end
    local license = VCore.GetLicense(source)
    if license and Config.Admins[license] then
        return Config.Admins[license]
    end
    return 'user'
end

--- True when the source has at least the required level.
function VCore.HasPermission(source, needed)
    return VCore.PermRank(VCore.GetPermission(source)) >= VCore.PermRank(needed or 'admin')
end

--- Change a player's permission (persisted). Requires an already-loaded player.
function VCore.SetPermission(source, level)
    local player = VCore.GetPlayer(source)
    if not player or not Config.PermissionLevels[level] then return false end
    player.permission = level
    VCore.DB.SetUserPermission(player.license, level)
    -- Permission-gated content (admin tools, restricted map blips, …) must re-evaluate.
    TriggerEvent('v-core:server:permissionChanged', source, level)
    return true
end

-- Let clients check their own permission for UI gating.
VCore.RegisterCallback('v-core:hasPermission', function(source, resolve, needed)
    resolve(VCore.HasPermission(source, needed or 'admin'))
end)
