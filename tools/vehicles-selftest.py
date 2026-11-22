#!/usr/bin/env python3
"""
Drive v-vehicles' server script outside the game.

    python tools/vehicles-selftest.py

FiveM's server natives, oxmysql and v-core are stubbed in tools/vehicles-selftest/stubs.lua.
The database is an in-memory `character_vehicles` that refuses a column it does not have, so a
statement that needs a column the migration has not added yet fails here as it would in
production. Time is virtual: the 30 s cleanup tick runs in a millisecond.

WHAT IT PROVES. The rules a car parked in the street lives by: no impound when its entity
vanishes, no delete and no garage at a resource stop, the restore with no player through the
server setter, the adoption of parked cars after a restart of v-vehicles alone (no second copy),
and that leaving the street forgets the position. It also proves that a car that is not parked
goes through statements that need none of the new columns. Each scenario was seen failing on the
code before the change, and on a copy with the PARKED guard removed, before it was believed.

WHAT IT DOES NOT. The real natives, the real SQL dialect (tools/sql-check.py does that, against
a database), and the client. A pass here is the logic, not the game.

Runs on lupa, or on tools/lupa-shim when lupa is not installed. Exit code 1 on any failure.
Author: vyrriox.
"""

import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.join(ROOT, 'tools', 'vehicles-selftest')
MOD = os.path.join(ROOT, 'resources', '[local]', 'v-vehicles')

try:
    from lupa.lua54 import LuaRuntime, LuaError
except ImportError:
    try:
        from lupa import LuaRuntime, LuaError
    except ImportError:
        sys.path.insert(0, os.path.join(ROOT, 'tools', 'lupa-shim'))
        from lupa import LuaRuntime, LuaError


def lua_str(s):
    return '[==[' + s + ']==]'


def run(scenario):
    lua = LuaRuntime(unpack_returned_tuples=True)
    src = ('local HERE, MOD = {h}, {m} '
           "dofile(HERE .. '/stubs.lua') dofile(MOD .. '/config.lua') "
           "H.load = function(path) dofile(path or (MOD .. '/server/main.lua')) end "
           'dofile({s})').format(h=lua_str(HERE), m=lua_str(MOD), s=lua_str(scenario))
    try:
        lua.execute(src)
        return True
    except LuaError as e:
        print('FAIL %s: %s' % (os.path.basename(scenario), e))
        return False


def main():
    # glob.escape: the module lives under `[local]`, which glob would read as a character class
    scenarios = sorted(p for p in glob.glob(os.path.join(glob.escape(HERE), '*.lua'))
                       if os.path.basename(p) != 'stubs.lua')
    if not scenarios:
        print('vehicles-selftest: no scenario found under', HERE)
        return 1
    failed = [s for s in scenarios if not run(s)]
    print('vehicles-selftest: %d scenario(s), %d failed' % (len(scenarios), len(failed)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
