-- v-voice | shared config
-- FiveM already ships a Mumble voice server. This module does not implement audio: it
-- decides **who hears whom, and how loudly**. That framing is what keeps it small.
--
-- SEED DATA ONLY for the channels: they live in `world_radio` (owned by v-world) and are
-- edited from the admin panel -> Editor -> Radio channels.
Config = {}

-- Three proximity steps, cycled on a key. Ranges are settings rather than constants
-- because a server's idea of "normal" depends on how big its scenes are.
Config.Proximity = {
    { key = 'whisper', label = 'Whisper', range = 3.0 },
    { key = 'normal',  label = 'Normal',  range = 8.0 },
    { key = 'shout',   label = 'Shout',   range = 20.0 },
}
Config.DefaultStep = 2      -- index into the list above

-- Keys. Push-to-talk on the radio is the convention; cycling proximity is a tap.
Config.Keys = {
    cycle = 'Z',
    radio = 'CAPITAL',      -- Caps Lock, the usual radio PTT
}

-- Transmitting needs a radio in your pocket, so being disarmed of it is a real event.
-- Set to false to drop the requirement.
Config.RadioItem = 'radio'

-- Being hurt narrows your range: a bleeding player should not be shouting across a street.
Config.Injured = {
    bleedThreshold = 2,     -- v-status bleed level at or above which the penalty applies
    rangeMult      = 0.5,
}

-- The phone gets its own Mumble channel rather than sharing proximity, so a call is
-- audible across the map and inaudible to somebody standing next to you.
Config.PhoneChannel = 900

-- Channel numbers are Mumble channels. Anything without a job or gang is open to anyone
-- carrying a radio, which is what a citizens' band should be.
Config.Channels = {
    { id = 1,  label = 'Citizens Band' },
    { id = 2,  label = 'Taxi Dispatch',       job = 'taxi' },
    { id = 3,  label = 'Mechanic Dispatch',   job = 'mechanic' },
    { id = 10, label = 'LSPD Dispatch',       job = 'police' },
    { id = 11, label = 'LSPD Command',        job = 'police', grade = 3 },
    { id = 20, label = 'EMS Dispatch',        job = 'ambulance' },
    { id = 30, label = 'Ballas',              gang = 'ballas' },
    { id = 31, label = 'Vagos',               gang = 'vagos' },
    { id = 32, label = 'Families',            gang = 'families' },
    { id = 33, label = 'Marabunta Grande',    gang = 'marabunta' },
    { id = 34, label = 'The Lost MC',         gang = 'lostmc' },
}
