# -*- coding: utf-8 -*-
"""The string table: sent only when the page lacks it, under real Lua.

    python tools/test-strings.py

bridge/shared/locale.lua, both locale files, config.lua and the whole of client/main.lua are
loaded into a real Lua 5.4 with faked natives, a faked NUI and a faked state bag. The bag
behaves the way FiveM's does in the one respect that matters here: **change handlers run
BEFORE the new value is stored**, so a handler that reads the bag sees the old language.

What is asserted, and why each one exists:

  * the table rides on a message only while the page is not known to hold the language, and a
    pocketed notification is a few hundred bytes once it does (it was 255 KB)
  * `boot` makes the client forget what an earlier page held, so a reloaded page is corrected
  * an acknowledgement naming a stale language does not count as holding the current one
  * the `lang` handler pushes the NEW language's table, not the one still in the bag
  * PhoneLang answers bag, then convar, then the fallback, and a bag that lands late wins
  * `L()` reads the state bag once, not twice per call inside per-frame loops
  * the control guard allocates nothing per frame, refuses the pause controls once per group,
    and a second close does not start a second pause-swallowing thread

Exit code 1 if anything fails.
"""
import io
import json
import os
import sys

# Lua 5.4, which is what FiveM runs. A bare `lupa.LuaRuntime` is whatever lupa's newest bundled
# version is, and that is 5.5 on a current install.
import lupa.lua54 as lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(rel):
    return io.open(os.path.join(ROOT, rel), encoding='utf-8').read()


MAIN = read('client/main.lua')

failures = []


def check(name, got, want):
    ok = got == want
    print('%-66s %s' % (name, 'ok' if ok else 'FAIL  got %r want %r' % (got, want)))
    if not ok:
        failures.append(name)


def thread_line(after):
    """The line of the first `CreateThread(function()` after a marker, 1-based like Lua's."""
    at = MAIN.index(after)
    at = MAIN.index('CreateThread(function()', at)
    return MAIN.count('\n', 0, at) + 1


GUARD_LINE = thread_line('local function startGuard()')
SWALLOW_LINE = thread_line('local function swallowPause(')

# ══════════════════════════════════════════════════════════════
# The world client/main.lua runs in
# ══════════════════════════════════════════════════════════════
ENV = r"""
NOW = 0
THREADS = {}
THREAD_COUNT = {}
function CreateThread(fn)
    local line = debug.getinfo(fn, 'S').linedefined
    THREADS[#THREADS + 1] = { co = coroutine.create(fn), line = line }
    THREAD_COUNT[line] = (THREAD_COUNT[line] or 0) + 1
end
function SetTimeout() end
function Wait(ms) coroutine.yield(tonumber(ms) or 0) end
function GetGameTimer() return NOW end

function IsDuplicityVersion() return false end
function PlayerId() return 0 end
function GetPlayerServerId() return 7 end
CONVARS = {}
function GetConvar(name, default)
    local v = CONVARS[name]
    if v == nil then return default end
    return v
end

-- ── the state bag, in FiveM's order: handlers first, then the store ──
BAG = {}
BAG_READS = 0
BAG_HANDLERS = {}
function AddStateBagChangeHandler(key, bagName, fn)
    BAG_HANDLERS[#BAG_HANDLERS + 1] = { key = key, bag = bagName, fn = fn }
end
local stateProxy = setmetatable({}, { __index = function(_, key) return BAG[key] end })
LocalPlayer = setmetatable({}, { __index = function(_, k)
    if k == 'state' then
        BAG_READS = BAG_READS + 1
        return stateProxy
    end
end })
function SET_BAG(key, value, only)
    for i, h in ipairs(BAG_HANDLERS) do
        if h.key == key and h.bag == 'player:7' and (only == nil or only == i) then
            h.fn('player:7', key, value, 0, false)
        end
    end
    BAG[key] = value
end

-- ── NUI ──
NUI = {}
function RegisterNUICallback(name, fn) NUI[name] = fn end
SENT = {}
function SendNUIMessage(m) SENT[#SENT + 1] = m end
function NUI_CALL(name, data)
    local answer
    NUI[name](data, function(r) answer = r end)
    return answer
end

NET = {}
function RegisterNetEvent(name, fn) if fn then NET[name] = fn end end
function AddEventHandler() end

-- ── what the open path and the guard touch ──
function HasModelLoaded() return true end
function HasAnimDictLoaded() return true end
function PlayerPedId() return 1 end
function IsPauseMenuActive() return false end
ANIM_CHECKS = 0
function IsEntityPlayingAnim() ANIM_CHECKS = ANIM_CHECKS + 1; return true end
DISABLED = {}
function DisableControlAction(group, control)
    local k = group * 1000 + control
    DISABLED[k] = (DISABLED[k] or 0) + 1
end

exports = setmetatable({}, {
    __call = function() end,
    __index = function()
        return setmetatable({}, { __index = function() return function() return false end end })
    end,
})
SUBS, REQUESTS = {}, {}
V = setmetatable({
    Sub = function(group, name, _, fn) SUBS[group .. ' ' .. name] = fn end,
    Request = function(name, cb) REQUESTS[#REQUESTS + 1] = { name = name, cb = cb } end,
}, { __index = function() return function() end end })

function vec3(x, y, z) return { x = x, y = y, z = z } end
vector3 = vec3
"""

AFTER_CONFIG = r"""
-- Anything else main.lua names is a native that answers nothing, which is what most of them
-- do in a world with no game in it. Installed after the locale and config files, which test
-- `X or default` on their own globals.
local NOOP = function() end
setmetatable(_G, { __index = function() return NOOP end })

--- Run one thread, found by the line its function starts on, for a number of frames.
function RUN_LINE(line, frames, step)
    local t
    for _, th in ipairs(THREADS) do
        if th.line == line and coroutine.status(th.co) ~= 'dead' then t = th break end
    end
    if not t then return 'none' end
    for _ = 1, frames do
        NOW = NOW + step
        local ok, err = coroutine.resume(t.co)
        if not ok then return 'error: ' .. tostring(err) end
        if coroutine.status(t.co) == 'dead' then return 'dead' end
    end
    return 'running'
end

function ALLOC_PER_FRAME(line, frames)
    RUN_LINE(line, 30, 16)
    collectgarbage('collect')
    collectgarbage('stop')
    local before = collectgarbage('count')
    local state = RUN_LINE(line, frames, 16)
    local after = collectgarbage('count')
    collectgarbage('restart')
    if state ~= 'running' then return state end
    return (after - before) * 1024 / frames
end

function OPEN()
    SUBS['phone open']()
    local req = REQUESTS[#REQUESTS]
    req.cb({ number = '555-0142', prefs = {}, apps = {} })
    return SENT[#SENT]
end
function CLOSE() SUBS['phone close']() end

function LAST(action)
    for i = #SENT, 1, -1 do if SENT[i].action == action then return SENT[i] end end
end

-- A key the two languages translate differently, so a table can be told apart by content.
for k, v in pairs(Locales.en) do
    if type(Locales.fr[k]) == 'string' and Locales.fr[k] ~= v then DIFF_KEY = k break end
end
"""


def world(bag=None, convar=None, block=None):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(ENV)
    if bag is not None:
        lua.execute('BAG.lang = %s' % json.dumps(bag))
    if convar is not None:
        lua.execute('CONVARS.phone_locale = %s' % json.dumps(convar))
    for rel in ('bridge/shared/locale.lua', 'locales/fr.lua', 'locales/en.lua', 'config.lua'):
        lua.execute(read(rel))
    if block is not None:
        lua.execute('Config.Hold.block = { %s }' % ', '.join(str(c) for c in block))
    lua.execute(AFTER_CONFIG)
    lua.execute(MAIN)
    return lua


def one(lua, expr):
    """One value out of Lua. The brackets truncate a multiple return to its first value."""
    return lua.execute('return (%s)' % expr)


def plain(v):
    if lupa.lua_type(v) == 'table':
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [plain(v[k]) for k in sorted(keys)]
        return {str(k): plain(x) for k, x in v.items()}
    return v


def size(lua, msg):
    return len(json.dumps(plain(msg), ensure_ascii=False, separators=(',', ':')).encode('utf-8'))


# ══════════════════════════════════════════════════════════════
# PhoneLang: precedence, a late bag, and what a call costs
# ══════════════════════════════════════════════════════════════
w = world()
check('empty bag, no convar: the fallback', one(w, 'PhoneLang()'), 'fr')
w.execute("SET_BAG('lang', 'en')")
check('a bag that lands after the first read replaces the fallback', one(w, 'PhoneLang()'), 'en')

w = world(convar='en')
check('empty bag, convar set: the convar', one(w, 'PhoneLang()'), 'en')
w.execute("SET_BAG('lang', 'fr')")
check('a bag that lands after the first read replaces the convar', one(w, 'PhoneLang()'), 'fr')
w.execute("SET_BAG('lang', '')")
check('a bag emptied again falls back to the convar', one(w, 'PhoneLang()'), 'en')

w = world(bag='en', convar='fr')
check('bag and convar both set: the bag', one(w, 'PhoneLang()'), 'en')

w = world(bag='en')
w.execute("L('ph.booth_use'); PhoneString('ph.cam_shoot_hint'); BAG_READS = 0")
w.execute("for i = 1, 600 do L('ph.booth_use'); PhoneString('ph.cam_shoot_hint'); "
          "PhoneWithStrings({}) end")
check('L() and the page helper: zero state bag reads after the first', one(w, 'BAG_READS'), 0)

# ══════════════════════════════════════════════════════════════
# The page's record: attach, boot, acknowledge
# ══════════════════════════════════════════════════════════════
w = world(bag='fr')
check('nothing known about the page: the table is attached',
      one(w, "PhoneWithStrings({}).strings ~= nil"), True)
check('and labelled with the current language', one(w, "PhoneWithStrings({}).locale"), 'fr')
w.execute("REPLY = NUI_CALL('strings', { boot = true })")
check('the strings callback answers with the full table',
      one(w, "REPLY.strings[DIFF_KEY] == Locales.fr[DIFF_KEY] and REPLY.locale == 'fr'"), True)
check('after answering it, the table is no longer attached',
      one(w, "PhoneWithStrings({}).strings == nil"), True)

w = world(bag='fr')
w.execute("NUI_CALL('stringsHeld', { locale = 'en' })")
check('an acknowledgement naming a stale language does not set the record',
      one(w, "PhoneWithStrings({}).strings ~= nil"), True)
w.execute("NUI_CALL('stringsHeld', { locale = 'fr' })")
check('one naming the current language does', one(w, "PhoneWithStrings({}).strings == nil"), True)
w.execute("NUI_CALL('stringsHeld', { locale = 'en' })")
check('a stale one after it makes the record unknown again',
      one(w, "PhoneWithStrings({}).strings ~= nil"), True)

# Boot: the page reloaded while this client kept running. Seen through a language whose table
# comes back empty, which the client must not record as held - so the only thing that can move
# the record is the reset itself.
w = world(bag='xx')
w.execute("NUI_CALL('stringsHeld', { locale = 'xx' }); Locales.fr = nil")
check('with a record in place, nothing is attached', one(w, "PhoneWithStrings({}).strings == nil"), True)
w.execute("NUI_CALL('strings', {})")
check('a request without boot leaves the record alone',
      one(w, "PhoneWithStrings({}).strings == nil"), True)
w.execute("NUI_CALL('strings', { boot = true })")
check('a boot request resets the record', one(w, "PhoneWithStrings({}).strings ~= nil"), True)

# ══════════════════════════════════════════════════════════════
# The lang handler pushes the language it was handed
# ══════════════════════════════════════════════════════════════
w = world(bag='fr')
w.execute("NUI_CALL('strings', { boot = true })")
# client/main.lua's handler alone, with the bag still holding French: exactly what FiveM hands a
# handler before the store. The locale file's own handler is registered first and is skipped
# here, so this cannot pass by reading a value somebody else already updated.
w.execute("MAIN_HANDLER = #BAG_HANDLERS; SET_BAG('lang', 'en', MAIN_HANDLER)")
check('the push is labelled with the new language', one(w, "LAST('strings').locale"), 'en')
check('and carries the NEW language table, not the one still in the bag',
      one(w, "LAST('strings').strings[DIFF_KEY] == Locales.en[DIFF_KEY]"), True)
w.execute("SENT = {}; SET_BAG('lang', 'fr')")
check('pushed every time, even to a page whose record said it held a table',
      one(w, "LAST('strings') ~= nil and LAST('strings').strings[DIFF_KEY] == Locales.fr[DIFF_KEY]"),
      True)

w = world(bag='fr')
w.execute("NUI_CALL('strings', { boot = true }); SET_BAG('lang', 'en')")
check('until the page acknowledges the push, messages carry the new table',
      one(w, "PhoneWithStrings({}).locale"), 'en')
w.execute("NUI_CALL('stringsHeld', { locale = 'en' })")
check('and once it has, they do not', one(w, "PhoneWithStrings({}).strings == nil"), True)

# ══════════════════════════════════════════════════════════════
# Real messages: open, a pocketed notification, the alerts
# ══════════════════════════════════════════════════════════════
w = world(bag='fr')
w.execute("OPEN_MSG = OPEN()")
check('the first open carries the table', one(w, "OPEN_MSG.strings ~= nil"), True)
check('and its locale is PhoneLang(), not a hard-coded default', one(w, "OPEN_MSG.locale"), 'fr')
w.execute("NUI_CALL('stringsHeld', { locale = 'fr' }); CLOSE(); SENT = {}; OPEN_MSG = OPEN()")
check('a second open, after the acknowledgement, does not', one(w, "OPEN_MSG.strings == nil"), True)
w.execute("CLOSE()")

w = world(bag='fr')
w.execute("SENT = {}; PhoneNotify({ app = 'messages', icon = 'messages', title = 'A', body = 'B' })")
check('pocketed, unknown page: the archive carries the table',
      one(w, "LAST('archive').strings ~= nil"), True)
check('and the peek right behind it does not', one(w, "LAST('peek').strings == nil"), True)
w.execute("NUI_CALL('stringsHeld', { locale = 'fr' }); SENT = {}; "
          "PhoneNotify({ app = 'messages', icon = 'messages', title = 'A', body = 'B' })")
pocketed = size(w, one(w, "LAST('archive')")) + size(w, one(w, "LAST('peek')"))
check('pocketed, page holds it: archive plus peek under 1 KB (was 255 KB)', pocketed < 1024, True)

w = world(bag='fr')
w.execute("SENT = {}; NET['v-phone:client:emergency']({ kind = 'Weather', title = 'Storm' })")
check('emergency, unknown page: the broadcast carries the table',
      one(w, "LAST('emergency').strings ~= nil"), True)
check('and its banner does not', one(w, "LAST('peek').strings == nil"), True)
w.execute("SENT = {}; NET['v-phone:client:911']({ alert = { id = 1, reason = 'ph.911_r_violence' } })")
check('911 alert, unknown page: the alert carries the table',
      one(w, "LAST('emergencyAlert').strings ~= nil"), True)
check('and its banner does not', one(w, "LAST('peek').strings == nil"), True)
w.execute("NUI_CALL('stringsHeld', { locale = 'fr' }); SENT = {}; "
          "NET['v-phone:client:zuber']({ restaurant = 'Burger Shot', status = 'ready' }); "
          "NET['v-phone:client:911status']({ state = 'taken', by = 'Unit 12' })")
check('page holds it: no Zuber, 911 status or banner message carries a table',
      one(w, "(function() for _, m in ipairs(SENT) do if m.strings then return m.action end end "
             "return 'none' end)()"), 'none')

# ══════════════════════════════════════════════════════════════
# The control guard and the pause swallow
# ══════════════════════════════════════════════════════════════
w = world(bag='fr')
w.execute("OPEN()")
per_frame = one(w, "ALLOC_PER_FRAME(%d, 600)" % GUARD_LINE)
check('the guard thread is running', isinstance(per_frame, (int, float)), True)
check('the guard allocates nothing per frame (was 104 B)',
      isinstance(per_frame, (int, float)) and per_frame < 8, True)
w.execute("for k in pairs(DISABLED) do DISABLED[k] = 0 end; ANIM_CHECKS = 0")
w.execute("RUN_LINE(%d, 100, 16)" % GUARD_LINE)
check('199 in group 0 refused once per frame, not twice', one(w, "DISABLED[199]"), 100)
check('199 still refused in group 1', one(w, "DISABLED[1199]"), 100)
check('200 still refused in group 2', one(w, "DISABLED[2200]"), 100)
anim = one(w, "ANIM_CHECKS")
check('the hold animation is checked about every 250 ms, not every frame (%d in 1.6 s)' % anim,
      5 <= anim <= 8, True)

w = world(bag='fr', block=[1, 2, 24, 25])
w.execute("OPEN(); RUN_LINE(%d, 5, 16); for k in pairs(DISABLED) do DISABLED[k] = 0 end" % GUARD_LINE)
w.execute("RUN_LINE(%d, 50, 16)" % GUARD_LINE)
check('a block list without 199: group 0 still refuses it, once', one(w, "DISABLED[199]"), 50)

w = world(bag='fr')
w.execute("OPEN(); CLOSE()")
check('closing ends the guard', one(w, "RUN_LINE(%d, 1, 16)" % GUARD_LINE), 'dead')
w.execute("OPEN(); CLOSE()")
w.execute("RUN_LINE(%d, 1, 16); SECOND_CLOSE = NOW" % GUARD_LINE)
check('two closes inside the window: one pause thread',
      one(w, "THREAD_COUNT[%d]" % SWALLOW_LINE), 1)
w.execute("RUN_LINE(%d, 200, 16)" % SWALLOW_LINE)
check('and it lasts until 500 ms after the second close',
      one(w, "NOW >= SECOND_CLOSE + 500"), True)

print('')
if failures:
    print('%d FAILED' % len(failures))
    sys.exit(1)
print('string table and guard: all ok')
