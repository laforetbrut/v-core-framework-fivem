-- v-target | shared config
-- The interaction eye. Hold the key, look at something, pick an action.
Config = {}

-- Draws every registered zone as a wireframe box/sphere/polygon while true.
Config.Debug = false

-- Hold this key to open the eye (default LEFT ALT).
Config.Key = 'LMENU'

-- Reach of the eye, in metres. An option may shorten this for itself with `distance`,
-- never lengthen it past this value.
Config.MaxDistance = 7.0

-- Shape-test mask. The old code used -1 ("everything"), which also means WATER (32) and
-- FOLIAGE (512): a bush or a puddle in front of a car swallowed the ray and the car
-- became untargetable. This is world + vehicles + peds + objects, and nothing else.
--   1 world  |  2 vehicles  |  4 peds (simple)  |  8 peds  |  16 objects
Config.RayFlags = 31

-- How often the option list is rebuilt while the eye is open, in milliseconds. The ray
-- itself runs every frame; only the (much cheaper, but not free) predicate pass is
-- throttled. A change of target rebuilds immediately regardless.
Config.RefreshMs = 100

-- Show a self-interaction menu when the eye is pointed at nothing targetable. This is
-- what makes the eye the player's main interaction surface rather than a context menu:
-- there is always something to do with it.
Config.SelfMenu = true

-- Options blocked by a `canInteract` that returned a reason are drawn greyed out with
-- that reason. Options blocked by JOB or PERMISSION are always hidden outright, never
-- greyed: advertising police actions to a civilian tells them what the police can do.
Config.ShowBlocked = true

-- Longest list drawn at once. Beyond this the list scrolls.
Config.MaxOptions = 12

-- ── Bones ──────────────────────────────────────────────────────
-- Which part of a vehicle you are pointing at, so "open the boot" comes from the boot and
-- "check the engine" from the bonnet. The closest bone within `BoneDistance` wins.
Config.VehicleBones = {
    'boot', 'bonnet', 'engine', 'petroltank', 'windscreen', 'exhaust',
    'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r',
    'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr',
    'seat_dside_f', 'seat_pside_f',
}

Config.PedBones = {
    'SKEL_Head', 'SKEL_L_Hand', 'SKEL_R_Hand', 'SKEL_Spine3',
}

-- A bone must be within this many metres of the impact point to count. Too generous and
-- every hit resolves to the nearest bone on the far side of the car.
Config.BoneDistance = 1.1

-- ── Outline ────────────────────────────────────────────────────
Config.Outline = { r = 255, g = 106, b = 26, a = 200 }
