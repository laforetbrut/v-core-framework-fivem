-- v-ui | shared config — THE design system
--
-- Every NUI page in the framework links `theme.css` (the primitives) and then
-- `theme-vars.css` (this file, resolved into CSS custom properties). Changing anything
-- here — or the matching setting in the admin panel — restyles **every** module at once,
-- because no module hardcodes a colour.
--
-- Adding a preset is the intended way to reskin the server: copy a block, change the
-- numbers, select it in Admin → Settings → Interface.
Config = {}

-- ── Presets ────────────────────────────────────────────────────
-- A preset only has to declare what it changes; anything omitted falls back to `ember`.
-- `accent` drives the whole highlight family (hover, glow, selection, gradients).
Config.Presets = {
    ember = {
        label   = 'Ember (default)',
        accent  = '#ff7a1a',   -- the brand orange
        accent2 = '#f04e00',   -- gradient partner / darker end
        bg      = '#0b0a08',   -- deepest background
        panel   = '#16130f',   -- panel fill
        text    = '#f4efe8',
        success = '#5aa06a', danger = '#d04a4a', warning = '#e0a05a', info = '#4a9fe0',
    },
    midnight = {
        label   = 'Midnight',
        accent  = '#4a9fe0', accent2 = '#2c6fb0',
        bg      = '#070a0f', panel   = '#101720',
        text    = '#e8eef4',
        success = '#4fae7a', danger = '#d05a6a', warning = '#dba24f', info = '#6ab6ea',
    },
    crimson = {
        label   = 'Crimson',
        accent  = '#e0323c', accent2 = '#9c1622',
        bg      = '#0c0708', panel   = '#191012',
        text    = '#f6ecec',
        success = '#5aa06a', danger = '#e0555f', warning = '#e0a05a', info = '#5a8fd0',
    },
    verdant = {
        label   = 'Verdant',
        accent  = '#57b364', accent2 = '#2f7a3c',
        bg      = '#070b08', panel   = '#101711',
        text    = '#ecf4ed',
        success = '#63bd70', danger = '#d05a5a', warning = '#dba24f', info = '#5a9fd0',
    },
    violet = {
        label   = 'Violet',
        accent  = '#a45ad8', accent2 = '#6d2ea0',
        bg      = '#0a070d', panel   = '#171021',
        text    = '#f1ecf6',
        success = '#5aa06a', danger = '#d04a5a', warning = '#dba24f', info = '#6a9fe0',
    },
    slate = {
        label   = 'Slate (neutral)',
        accent  = '#8a94a6', accent2 = '#5b6474',
        bg      = '#0a0b0d', panel   = '#15171b',
        text    = '#eceef2',
        success = '#5aa06a', danger = '#d05a5a', warning = '#dba24f', info = '#5a9fd0',
    },
}

Config.DefaultPreset = 'ember'

-- ── Shape ──────────────────────────────────────────────────────
-- `radius` scales every corner at once: 0 = square, 1 = as shipped, 2 = very round.
-- `density` scales padding and gaps, for operators who want a tighter or airier UI.
Config.Shape = {
    radius  = 1.0,
    density = 1.0,
    -- Corner brackets are the "Field Case" signature. Off = plain rounded panels.
    brackets = true,
    -- The orange light-streak along the top edge of every panel.
    topStreak = true,
}

-- ── Motion ─────────────────────────────────────────────────────
-- `speed` scales every transition/animation duration. 0 disables motion entirely, which
-- is both an accessibility option and a way to claw back frames on a weak client.
Config.Motion = {
    speed = 1.0,
    panelOpen = true,      -- the case-open animation on a panel appearing
}

-- ── Surfaces ───────────────────────────────────────────────────
Config.Surface = {
    -- Panel opacity. FiveM's CEF renders `backdrop-filter` as an opaque black box, so the
    -- glass look is done with near-opaque fills — this is how transparent they get.
    panelAlpha = 0.94,
    -- The dark vignette behind a full-screen panel.
    backdropAlpha = 0.82,
    -- Film grain over overlays.
    grain = true,
}

-- ── Rarity colours (inventory, shops, catalogues) ──────────────
Config.Rarity = {
    common    = '#9aa0a6',
    uncommon  = '#5aa06a',
    rare      = '#4a9fe0',
    epic      = '#a45ad8',
    legendary = '#e0a05a',
    mythic    = '#e0505a',
}

-- ── Typography ─────────────────────────────────────────────────
-- CEF has no network access for fonts, so these must be families the client already has.
Config.Font = {
    display = "'Bebas Neue', 'Oswald', 'Arial Narrow', sans-serif",
    body    = "'Inter', 'Segoe UI', Roboto, sans-serif",
    scale   = 1.0,
}
