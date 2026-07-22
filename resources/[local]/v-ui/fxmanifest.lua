fx_version 'cerulean'
game 'gta5'

name 'v-ui'
author 'vyrriox'
description 'v-ui — Projet R shared NUI design system (theme tokens + components)'
version '0.1.0'

-- Detected by v-core's module registry (admin panel -> Settings). See INTEGRATION.md.
v_module 'yes'
v_module_label 'Ui'
v_module_category 'other'
-- Exposed so any NUI page can load it via:
--   <link rel="stylesheet" href="https://cfx-nui-v-ui/theme.css">
files {
    'theme.css',
}
