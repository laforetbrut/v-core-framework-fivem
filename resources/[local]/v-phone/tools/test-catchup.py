# -*- coding: utf-8 -*-
"""What the phone says about the time a character was offline.

`catchUp` in server/main.lua is lifted out by its own text and run under the Lua FiveM runs,
against a fake database that answers counts and a fake client that records banners. What is
checked is the decision, not the SQL engine: WHEN something is announced, WHAT it is announced
as, and that nothing already read is announced twice.

Pinned to Lua 5.4: a bare `import lupa` loads the newest bundled Lua (5.5), which FiveM does
not run.
"""
import io
import os
import re
import sys

import lupa.lua54 as lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

failures = []


def check(ok, label, detail=''):
    print(('  ok   ' if ok else '  FAIL ') + label + (('  (%s)' % detail) if not ok and detail else ''))
    if not ok:
        failures.append(label)


def lift(path, start, end):
    """One function out of a real file, by the text around it."""
    src = io.open(os.path.join(ROOT, path), encoding='utf-8').read()
    a = src.index(start)
    b = src.index(end, a)
    return src[a:b]


CATCHUP = lift('server/main.lua', 'local function catchUp(src, p)',
               '--- Scheduled rather than immediate')
# A file-local in main.lua; global here, so the test can call the real thing.
CATCHUP = CATCHUP.replace('local function catchUp', 'function catchUp', 1)

PRELUDE = r'''
BANNERS = {}
QUERIES = {}
COUNTS = { msgs = 0, calls = 0, mail = 0, social = 0 }
KV = {}
NOW = 1000000
os.time = function() return NOW end

Config = { CatchUp = { enabled = true, delaySeconds = 45, firstRunHours = 24 } }

Bridge = { KvGet = function(cid, key) return (KV[cid] or {})[key] end }

ASKED_ITEM = 0
-- Counted, so the test can see that nothing is even PREPARED when there is nothing to say.
function requireItem(src) ASKED_ITEM = ASKED_ITEM + 1 return true end
function L(src, key) return KEYS[key] or key end

KEYS = {
    ['ph.away_title']    = 'While you were away',
    ['ph.away_messages'] = '%d unread message(s)',
    ['ph.away_calls']    = '%d missed call(s)',
    ['ph.away_mail']     = '%d unread mail',
    ['ph.away_social']   = '%d new notification(s)',
}

function TriggerClientEvent(event, src, payload)
    BANNERS[#BANNERS + 1] = { event = event, src = src, app = payload.app,
                              title = payload.title, body = payload.body }
end

-- A database that answers whichever count the query asks for, and records the cut-off it was
-- given so the test can see WHICH window was used.
MySQL = { scalar = { await = function(sql, args)
    QUERIES[#QUERIES + 1] = { sql = sql, cid = args[1], since = args[2] }
    if sql:find('vphone_messages') then return COUNTS.msgs end
    if sql:find('vphone_calls') then return COUNTS.calls end
    if sql:find('vphone_mail_box') then return COUNTS.mail end
    if sql:find('vphone_social_notifs') then return COUNTS.social end
    return 0
end } }

function reset()
    BANNERS, QUERIES, ASKED_ITEM = {}, {}, 0
    COUNTS = { msgs = 0, calls = 0, mail = 0, social = 0 }
end

PLAYER = { citizenid = 'CID1' }

function apps()
    local out = {}
    for _, b in ipairs(BANNERS) do out[#out + 1] = b.app end
    table.sort(out)
    return table.concat(out, ',')
end

function bodies()
    local out = {}
    for _, b in ipairs(BANNERS) do out[#out + 1] = b.body end
    table.sort(out)
    return table.concat(out, ' | ')
end

function firstSince()
    return QUERIES[1] and QUERIES[1].since or -1
end
'''

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(PRELUDE)
lua.execute(CATCHUP)
run = lua.eval('function() catchUp(7, PLAYER) end')
ev = lua.eval
ex = lua.execute

print('catch-up: what arrived while the character was offline')
check(str(ev('_VERSION')) == 'Lua 5.4', 'the Lua that FiveM runs', str(ev('_VERSION')))

# 1. Nothing unread: nothing is said.
ex('reset()')
run()
check(ev('#BANNERS') == 0, 'nothing unread, nothing announced', '%d banner(s)' % ev('#BANNERS'))
check(ev('#QUERIES') == 4, 'one counting query per source', '%d quer(ies)' % ev('#QUERIES'))
check(ev('ASKED_ITEM') == 0, 'and it stops before preparing a card', 'asked %d time(s)' % ev('ASKED_ITEM'))

# 2. One card per app that has something, and none for the others.
ex('reset() COUNTS.msgs = 3 COUNTS.mail = 1')
run()
check(ev('apps()') == 'mail,messages', 'a card for each app that has something',
      ev('apps()'))
check('3 unread message(s)' in ev('bodies()') and '1 unread mail' in ev('bodies()'),
      'the counts are in the text', ev('bodies()'))
check(ev('BANNERS[1].title') == 'While you were away', 'the card is titled for the absence',
      str(ev('BANNERS[1].title')))

# 3. Missed calls open the phone, social notifications open the social app.
ex('reset() COUNTS.calls = 2 COUNTS.social = 5')
run()
check(ev('apps()') == 'bleeter,phone', 'calls open the phone, notifications the social app',
      ev('apps()'))

# 4. The window starts at the last disconnect.
ex('reset() COUNTS.msgs = 1 KV["CID1"] = { lastOut = NOW - 600 }')
run()
check(ev('firstSince()') == ev('NOW') - 600, 'counted from the last disconnect',
      str(ev('firstSince()')))

# 5. No recorded disconnect: a bounded window, not the whole history.
ex('reset() COUNTS.msgs = 1 KV["CID1"] = nil')
run()
check(ev('firstSince()') == ev('NOW') - 24 * 3600, 'without one, the configured window',
      str(ev('firstSince()')))
ex('reset() COUNTS.msgs = 1 Config.CatchUp.firstRunHours = 2')
run()
check(ev('firstSince()') == ev('NOW') - 2 * 3600, 'and that window is configurable',
      str(ev('firstSince()')))
ex('Config.CatchUp.firstRunHours = 24')

# 6. Switched off means silent, and asks the database nothing.
ex('reset() COUNTS.msgs = 9 Config.CatchUp.enabled = false')
run()
check(ev('#BANNERS') == 0 and ev('#QUERIES') == 0, 'switched off: no banner and no query',
      '%d banner(s), %d quer(ies)' % (ev('#BANNERS'), ev('#QUERIES')))
ex('Config.CatchUp.enabled = true')

# 7. A player without a character is not announced to.
ex('reset() COUNTS.msgs = 4')
lua.eval('function() catchUp(7, nil) end')()
check(ev('#BANNERS') == 0, 'no character, nothing announced', '%d banner(s)' % ev('#BANNERS'))

# 8. A query that raises costs the announcement, not the session.
ex('''reset() COUNTS.msgs = 2
      MySQL.scalar.await = function() error('database away') end''')
ok = True
try:
    run()
except Exception as exc:                                    # noqa: BLE001 - reported below
    ok = False
    print('    raised: %s' % str(exc)[:80])
check(ok and ev('#BANNERS') == 0, 'a database that is away raises nothing at the caller')

print('')
if failures:
    print('%d failure(s)' % len(failures))
    sys.exit(1)
print('0 failure(s)')
