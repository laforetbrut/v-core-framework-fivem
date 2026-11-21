# -*- coding: utf-8 -*-
"""Deleting a mail address, under real Lua 5.4, against a database that actually stores rows.

    python tools/test-mail-delete.py

The Mail section of server/main.lua and the mail exports of server/api.lua are lifted out by name
and run against SQLite standing in for MySQL. The only translation is `NOW()`; every statement is
the one the server really sends, so a WHERE clause that forgets retired rows fails here.

The design this checks has one rule that matters more than the rest:

**a deleted address is retired, not freed.** Its row stays with `deleted_at` set and the UNIQUE key
on `address` keeps it. If it were freed, the next player to take it would receive every reply still
meant for the previous owner. So: nobody else can create it, mail to it answers `noaddr`, and only
its own owner can bring it back, which counts against the cap like a new address.

The rest: ownership is decided on the server, the operator switch refuses, only the deleted
address's own mailbox rows go, `SendMail` never picks a retired row, a wipe and an export still
see every row, and the migration that adds the column is guarded so it runs once.
"""
import io
import os
import sqlite3

# Pinned: a bare `import lupa` loads the newest Lua bundled with lupa (5.5 with lupa 2.8), and
# FiveM runs 5.4.
import lupa.lua54 as lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = io.open(os.path.join(ROOT, 'server', 'main.lua'), encoding='utf-8').read()
API = io.open(os.path.join(ROOT, 'server', 'api.lua'), encoding='utf-8').read()
CFG = io.open(os.path.join(ROOT, 'config.lua'), encoding='utf-8').read()


def block(text, start_marker, end_marker='\nend)\n', search_from=None):
    """From `start_marker` up to and including the first `end_marker` after `search_from`."""
    start = text.index(start_marker)
    end = text.index(end_marker, text.index(search_from) if search_from else start) + len(end_marker)
    return text[start:end]


# ── The database ──────────────────────────────────────────────────────────
db = sqlite3.connect(':memory:')
db.executescript('''
CREATE TABLE vphone_mail_accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT, citizenid TEXT NOT NULL, address TEXT NOT NULL UNIQUE,
    at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, deleted_at TEXT NULL DEFAULT NULL);
CREATE TABLE vphone_mail_domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT, citizenid TEXT NOT NULL, domain TEXT NOT NULL UNIQUE,
    at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE vphone_mail (
    id INTEGER PRIMARY KEY AUTOINCREMENT, from_addr TEXT NOT NULL, to_addr TEXT NOT NULL DEFAULT '',
    subject TEXT NOT NULL DEFAULT '', body TEXT, image TEXT NOT NULL DEFAULT '',
    at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, reply_to INTEGER);
CREATE TABLE vphone_mail_box (
    id INTEGER PRIMARY KEY AUTOINCREMENT, mail_id INTEGER NOT NULL, address TEXT NOT NULL,
    folder TEXT NOT NULL, seen INTEGER NOT NULL DEFAULT 0, saved INTEGER NOT NULL DEFAULT 0);
''')

lua = lupa.LuaRuntime(unpack_returned_tuples=True)


def _run(sql, params):
    sql = str(sql).replace('NOW()', 'CURRENT_TIMESTAMP')
    # Positional, by the number of placeholders: a Lua table with a trailing nil is shorter
    # than the statement it was written for.
    args = [params[i + 1] if params is not None else None for i in range(sql.count('?'))]
    return db.execute(sql, args)


def _missing(e):
    # The wipe and the export walk tables this test never created. MySQL would have them.
    return 'no such table' in str(e)


def q_query(sql, params=None):
    try:
        cur = _run(sql, params)
    except sqlite3.OperationalError as e:
        if _missing(e):
            return lua.table_from([])
        raise
    if str(sql).lstrip().upper().startswith('SELECT'):
        names = [d[0] for d in cur.description]
        return lua.table_from([lua.table_from(dict(zip(names, r))) for r in cur.fetchall()])
    return cur.rowcount


def q_scalar(sql, params=None):
    cur = _run(sql, params)
    r = cur.fetchone()
    return r[0] if r else None


def q_insert(sql, params=None):
    try:
        return _run(sql, params).lastrowid
    except sqlite3.IntegrityError:
        return None


def q_update(sql, params=None):
    try:
        return _run(sql, params).rowcount
    except sqlite3.OperationalError as e:
        if _missing(e):
            return 0
        raise


lua.execute('''
Config = {}
Handlers, Exports, Players, LOGS, Online = {}, {}, {}, {}, {}
V = { Callback = function(name, fn) Handlers[name] = fn end }
Core = {
    GetPlayer = function(src) return Players[src] end,
    GetPlayerByCitizenId = function() return nil end,
    Log = function(kind, msg) LOGS[#LOGS + 1] = kind .. ': ' .. msg end,
}
Bridge = { KvSet = function() end }
function num(v, d) return tonumber(v) or d or 0 end
function L(src, k) return k end
function numberOfCid() return nil end
function requireItem() return false end
function wallpaperAllowed() return true end
function TriggerClientEvent() end
function GetCurrentResourceName() return 'v-phone' end
exports = setmetatable({}, { __call = function(_, name, fn) Exports[name] = fn end })
json = { decode = function() return nil end, encode = function() return '' end }

function makeMySQL(q, s, i, u)
    local function callable(f)
        return setmetatable({ await = function(...) return f(...) end },
                            { __call = function(_, ...) return f(...) end })
    end
    MySQL = { query = callable(q), scalar = callable(s), insert = callable(i), update = callable(u) }
end

function mailCall(src, data)
    local out
    Handlers['v-phone:mail'](src, function(r) out = r end, data)
    return out
end

-- Multiple returns come back through lupa as a tuple; one string is one value to assert on.
function sendMail(cid, from, subject, body)
    local ok, why = Exports.SendMail(cid, from, subject, body)
    return tostring(ok) .. '|' .. tostring(why)
end
function wipe(cid)
    local ok = Exports.WipePhone(cid)
    return ok == true
end
''')
g = lua.globals()
g.makeMySQL(q_query, q_scalar, q_insert, q_update)

lua.execute(block(CFG, 'Config.Mail = {', '\n}\n'))
mail_chunk = block(MAIN, 'function mailAccountsOf(cid)', search_from="V.Callback('v-phone:mail'")
# `cidOfAddress` is a local of the chunk; exported under a test name so it can be asked directly.
lua.execute(mail_chunk + '\nTEST_cidOfAddress = cidOfAddress\n')
lua.execute(block(API, "exports('SendMail'"))
lua.execute(block(API, "exports('WipePhone'"))
lua.execute(block(API, 'local EXPORT_TABLES', search_from="exports('ExportPhone'"))

fails = []


def check(ok, what, detail=''):
    print('  %s %s%s' % ('ok  ' if ok else 'FAIL', what, ('  (%s)' % detail) if detail else ''))
    if not ok:
        fails.append(what)


def call(src, **data):
    return g.mailCall(src, lua.table_from(data))


def accounts(cid):
    t = g.mailAccountsOf(cid)
    return [t[i] for i in range(1, len(t) + 1)]


def one(sql, *args):
    r = db.execute(sql, args).fetchone()
    return r[0] if r else None


lua.execute('''
Players[1] = { citizenid = 'ALICE' }
Players[2] = { citizenid = 'BOB' }
Players[3] = { citizenid = 'CAROL' }
Players[4] = { citizenid = 'DAVE' }
''')

print('the runtime')
check(lua.eval('_VERSION') == 'Lua 5.4', 'the Lua that FiveM runs', lua.eval('_VERSION'))

print('')
print('the configuration')
check(g.Config.Mail.deleteAccounts is True, 'config.lua ships deleteAccounts = true')
g.Config.Mail.maxAccounts = 2

print('')
print('setting up')
r1 = call(1, op='create', localpart='alice', domain='ls.com')
r2 = call(1, op='create', localpart='alice2', domain='ls.com')
r3 = call(2, op='create', localpart='bob', domain='ls.com')
check(bool(r1.ok and r2.ok and r3.ok), 'three addresses created')
me = call(1, op='me')
check(me.canDelete is True, 'op me says canDelete when the config allows it')
check(call(2, op='send', address='bob@ls.com', to='alice@ls.com', subject='hi', body='x').ok is True,
      'bob writes to alice')
check(call(1, op='send', address='alice@ls.com', to='bob@ls.com', subject='re', body='y').ok is True,
      'alice writes back to bob')
call(1, op='draft', address='alice@ls.com', subject='later', body='z')
check(one("SELECT COUNT(*) FROM vphone_mail_box WHERE address = 'alice@ls.com'") == 3,
      'alice@ls.com holds an inbox, a sent and a draft row')

print('')
print('who may delete')
r = call(2, op='deleteAccount', address='alice@ls.com')
check(r.error == 'noaccount', "deleting somebody else's address is refused", str(r.error))
check(one("SELECT deleted_at FROM vphone_mail_accounts WHERE address = 'alice@ls.com'") is None,
      'and it is still live')
check(one("SELECT COUNT(*) FROM vphone_mail_box WHERE address = 'alice@ls.com'") == 3,
      "and alice's mail was not touched by the refused request")
r = call(1, op='deleteAccount')
check(r.error == 'noaccount', 'no address named is refused, never a fallback to the first', str(r.error))

g.Config.Mail.deleteAccounts = False
r = call(1, op='deleteAccount', address='alice@ls.com')
check(r.error == 'disabled', 'config off refuses', str(r.error))
check(call(1, op='me').canDelete is False, 'and op me stops offering it')
g.Config.Mail.deleteAccounts = True

print('')
print('deleting')
r = call(1, op='deleteAccount', address='alice@ls.com')
check(r.ok is True, 'the owner deletes alice@ls.com')
check(one("SELECT COUNT(*) FROM vphone_mail_accounts WHERE address = 'alice@ls.com'") == 1
      and one("SELECT deleted_at FROM vphone_mail_accounts WHERE address = 'alice@ls.com'") is not None,
      'the row is kept and marked retired, not removed')
check(accounts('ALICE') == ['alice2@ls.com'], 'mailAccountsOf no longer lists it', repr(accounts('ALICE')))
check(g.TEST_cidOfAddress('alice@ls.com') is None, 'cidOfAddress answers nil for it')
check(g.TEST_cidOfAddress('alice2@ls.com') == 'ALICE', 'and still answers for a live one')
check(one("SELECT COUNT(*) FROM vphone_mail_box WHERE address = 'alice@ls.com'") == 0,
      "that address's mailbox rows are gone")
check(one("SELECT COUNT(*) FROM vphone_mail_box WHERE address = 'bob@ls.com'") == 2,
      "bob's copies of the same two mails are kept")
check(any('deleted the address alice@ls.com' in str(g.LOGS[i]) for i in range(1, len(g.LOGS) + 1)),
      'the deletion is logged')
me = call(1, op='me', address='alice@ls.com')
check(me.address == 'alice2@ls.com', 'op me falls back to the remaining address', str(me.address))

print('')
print('a request that names an address the caller does not hold')
# A mail in alice2's inbox, so a refused op has one of alice's own rows it could wrongly touch if
# it fell back to her first live address.
check(call(2, op='send', address='bob@ls.com', to='alice2@ls.com', subject='own', body='x').ok is True,
      'bob writes to alice2')
own_box = one("SELECT id FROM vphone_mail_box WHERE address = 'alice2@ls.com' AND folder = 'inbox'")


def snap():
    return (db.execute('SELECT * FROM vphone_mail ORDER BY id').fetchall(),
            db.execute('SELECT * FROM vphone_mail_box ORDER BY id').fetchall())


attempts = [
    ('list', {'folder': 'inbox'}),
    ('saved', {}),
    ('send', {'to': 'bob@ls.com', 'subject': 'from where?', 'body': 'x'}),
    ('draft', {'subject': 'draft', 'body': 'x'}),
    ('save', {'boxId': own_box, 'saved': True}),
    ('seen', {'boxId': own_box}),
    ('del', {'boxId': own_box}),
]
for named, whose in (('alice@ls.com', 'a retired address'), ('bob@ls.com', "somebody else's address")):
    for op, extra in attempts:
        before = snap()
        r = call(1, op=op, address=named, **extra)
        check(r.error == 'noaccount' and snap() == before,
              '%s naming %s is refused and touches nothing' % (op, whose), str(r.error))

r = call(1, op='list', folder='inbox')
check(r.ok is True and len(r.mail) == 1 and r.mail[1].from_addr == 'bob@ls.com',
      'naming no address still acts as the first live one', str(r.error))
check(call(1, op='send', to='bob@ls.com', subject='old page', body='x').ok is True,
      'an older page that names no address still sends')
check(one('SELECT from_addr FROM vphone_mail ORDER BY id DESC LIMIT 1') == 'alice2@ls.com',
      'from the first live address')
me = call(1, op='me', address='bob@ls.com')
check(me.ok is True and me.address == 'alice2@ls.com',
      'op me still falls back for a foreign address, so the page can recover', str(me.address))

lua.execute('function pickStrict(cid, w) return (mailPickStrict(cid, w)) end')
check(g.pickStrict('ALICE', 'alice@ls.com') is None, 'mailPickStrict refuses a retired address')
check(g.pickStrict('ALICE', 'bob@ls.com') is None, 'and a foreign one')
check(g.pickStrict('ALICE', 'alice2@ls.com') == 'alice2@ls.com', 'and answers for a live one')
check(g.pickStrict('ALICE', None) == 'alice2@ls.com', 'naming nothing is the first live address')
check('local chosen = mailPickStrict(me.citizenid, data and data.address)' in MAIN
      and 'local chosen = mailPick(me.citizenid' not in MAIN,
      'the FruitDrop email share uses the strict pick')

print('')
print('a retired address is nobody else\'s')
r = call(2, op='send', address='bob@ls.com', to='alice@ls.com', subject='hello?', body='x')
check(r.error == 'noaddr', 'mail sent to it answers noaddr', str(r.error))
r = call(3, op='create', localpart='alice', domain='ls.com')
check(r.error == 'taken', 'another character cannot create it', str(r.error))
check(one("SELECT citizenid FROM vphone_mail_accounts WHERE address = 'alice@ls.com'") == 'ALICE',
      'the row still belongs to its owner')
r = call(2, op='create', localpart='bob', domain='ls.com')
check(r.error == 'taken', 'a live address is still taken, even for its own owner', str(r.error))

print('')
print('the cap, and taking it back')
r = call(1, op='create', localpart='alice3', domain='ls.com')
check(r.ok is True, 'the cap counts live rows only: a second live address fits beside a retired one',
      str(r.error))
r = call(1, op='create', localpart='alice', domain='ls.com')
check(r.error == 'maxaccounts', 'restoring counts against the cap like a new address', str(r.error))
check(call(1, op='deleteAccount', address='alice3@ls.com').ok is True, 'alice deletes alice3')
r = call(1, op='create', localpart='alice', domain='ls.com')
check(r.ok is True and r.address == 'alice@ls.com', 'the owner takes alice@ls.com back', str(r.error))
check(one("SELECT deleted_at FROM vphone_mail_accounts WHERE address = 'alice@ls.com'") is None
      and one("SELECT COUNT(*) FROM vphone_mail_accounts WHERE address = 'alice@ls.com'") == 1,
      'restored in place: the same row, live again')
check(g.TEST_cidOfAddress('alice@ls.com') == 'ALICE', 'and mail reaches it again')
check(sorted(accounts('ALICE')) == ['alice2@ls.com', 'alice@ls.com'], 'listed again', repr(accounts('ALICE')))

print('')
print('SendMail')
call(4, op='create', localpart='dave1', domain='ls.com')
call(4, op='create', localpart='dave2', domain='ls.com')
call(4, op='deleteAccount', address='dave1@ls.com')
check(g.sendMail('DAVE', 'hr@ls.com', 'payslip', 'x') == 'true|nil', 'delivers to a character with a live address')
check(one("SELECT address FROM vphone_mail_box ORDER BY id DESC LIMIT 1") == 'dave2@ls.com',
      'to the live address, never the older retired one')
call(3, op='create', localpart='carol', domain='ls.com')
call(3, op='deleteAccount', address='carol@ls.com')
check(g.sendMail('CAROL', 'hr@ls.com', 'payslip', 'x') == 'false|nomailbox',
      'only a retired address is no mailbox at all', g.sendMail('CAROL', 'hr@ls.com', 's', 'b'))

print('')
print('export and wipe see every row')
exported = g.Exports.ExportPhone('ALICE')
check(len(exported.mailbox) == 3, 'an export carries live and retired addresses', str(len(exported.mailbox)))
check(g.wipe('DAVE') is True, 'the wipe runs')
check(one("SELECT COUNT(*) FROM vphone_mail_accounts WHERE citizenid = 'DAVE'") == 0,
      'and removes the retired row with the live one')

print('')
print('the migration')
create_start = MAIN.index('CREATE TABLE IF NOT EXISTS `vphone_mail_accounts`')
create = MAIN[create_start:MAIN.index(']])', create_start)]
check('`deleted_at` TIMESTAMP NULL DEFAULT NULL' in create, 'a fresh install gets the column')
check('UNIQUE KEY `address` (`address`)' in create, 'the UNIQUE key on address stays')

guard_at = MAIN.index("COLUMN_NAME = 'deleted_at'")
id_guard_at = MAIN.index("COLUMN_NAME = 'id' LIMIT 1]]) then")
check(guard_at > id_guard_at, 'the new migration runs after the id migration')
mig_start = MAIN.rindex('    if not MySQL.scalar.await(', 0, guard_at)
mig = MAIN[mig_start:MAIN.index('\n    end\n', guard_at) + len('\n    end\n')]
check("TABLE_NAME = 'vphone_mail_accounts'" in mig and 'information_schema.COLUMNS' in mig,
      'it is guarded by information_schema')

m = lupa.LuaRuntime(unpack_returned_tuples=True)
m.execute('''
RAN, HAS, FAIL, OUT = {}, nil, false, {}
print = function(s) OUT[#OUT + 1] = tostring(s) end
MySQL = {
    scalar = { await = function(sql) return HAS end },
    query = { await = function(sql)
        RAN[#RAN + 1] = sql
        if FAIL then error('simulated: ALTER denied') end
        return true
    end },
}
''')
run_mig = m.eval('function(code) return load(code)() end')
mg = m.globals()


def migrate(has, fail=False):
    m.execute('RAN, OUT = {}, {}')
    mg.HAS = has
    mg.FAIL = fail
    run_mig(mig)
    return ([str(mg.RAN[i]) for i in range(1, len(mg.RAN) + 1)],
            [str(mg.OUT[i]) for i in range(1, len(mg.OUT) + 1)])


ran, out = migrate(1)
check(not ran, 'a table that already has the column runs no ALTER', '%d statement(s)' % len(ran))
ran, out = migrate(None)
check(len(ran) == 1 and 'ADD COLUMN `deleted_at` TIMESTAMP NULL DEFAULT NULL' in ran[0],
      'a table without it gets exactly one ALTER', ran[0][:80] if ran else '')
check(all('DROP' not in s.upper() for s in ran), 'nothing is dropped')
ran, out = migrate(None, fail=True)
check(any('Run this once by hand' in s and 'deleted_at' in s for s in out),
      'a failed ALTER prints the statement to run by hand, and does not stop the boot')

print('')
print('%d failure(s)' % len(fails))
raise SystemExit(1 if fails else 0)
