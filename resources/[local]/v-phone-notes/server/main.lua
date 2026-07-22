-- v-phone-notes | server
--
-- The whole Lua side of a phone app. There is no more than this.
--
-- Notes keeps its data in `Phone.storage`, which v-phone persists per app and per
-- character, so this resource owns no table, no migration and no callback. An app that
-- needs its own server logic adds `V.Callback('notes:whatever', ...)` and calls it from
-- the page with `Phone.request('whatever', data)` - the name is composed from the app id
-- by the phone, so an app can only ever reach its own callbacks.

V.Ready(function()
    exports['v-phone']:RegisterApp('notes', {
        label = 'Notes',        -- a literal, or a locale key your resource ships
        icon  = 'note',         -- any key from PhoneUI.icons
        slot  = 20,
        desc  = 'Notes kept on your character through Phone.storage - the worked example for anyone writing an app.',
        page  = 'https://cfx-nui-v-phone-notes/html/index.html',
    })
end)
