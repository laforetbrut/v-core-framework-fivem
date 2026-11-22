#!/usr/bin/env python3
"""
Drive v-park's server scripts and v-vehicles' server script together, outside the game.

    python tools/vpark-selftest.py

Each resource gets its own Lua environment, as FiveM gives each its own state, on top of
tools/vehicles-selftest/stubs.lua (scheduler, entities, the in-memory `character_vehicles`).
tools/vpark-selftest/harness.lua adds the rest: v-core, v-garages, the player peds, statebags,
and a count of who called CreateVehicle or CreateVehicleServerSetter.

WHAT IT PROVES. On v-core, v-park keeps only cars `character_vehicles` knows, parks them in
v-vehicles, brings them back through `SpawnOwned` and never calls a vehicle-creating native
itself, follows a car v-garages stores, and `GetVehicleByPlate` answers for a car v-vehicles
parked. Off v-core (`upstream.lua`) v-park still creates its own, which is also what shows the
count can fail.

WHAT IT DOES NOT. The client, the real natives, the real SQL, timing under load. A pass here is
the logic, not the game.

Runs on lupa, or on tools/lupa-shim when lupa is not installed. Exit code 1 on any failure.
Author: vyrriox.
"""

import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.join(ROOT, 'tools', 'vpark-selftest')
STUBS = os.path.join(ROOT, 'tools', 'vehicles-selftest', 'stubs.lua')
VV = os.path.join(ROOT, 'resources', '[local]', 'v-vehicles')
VP = os.path.join(ROOT, 'resources', '[local]', 'v-park')

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
    src = ('STUBS, VV_DIR, VP_DIR = {st}, {vv}, {vp} '
           'dofile({h}) dofile({s})').format(
        st=lua_str(STUBS), vv=lua_str(VV), vp=lua_str(VP),
        h=lua_str(os.path.join(HERE, 'harness.lua')), s=lua_str(scenario))
    try:
        lua.execute(src)
        return True
    except LuaError as e:
        print('FAIL %s: %s' % (os.path.basename(scenario), e))
        return False


def main():
    # glob.escape: the resources live under `[local]`, which glob would read as a character class
    scenarios = sorted(p for p in glob.glob(os.path.join(glob.escape(HERE), '*.lua'))
                       if os.path.basename(p) != 'harness.lua')
    if not scenarios:
        print('vpark-selftest: no scenario found under', HERE)
        return 1
    failed = [s for s in scenarios if not run(s)]
    print('vpark-selftest: %d scenario(s), %d failed' % (len(scenarios), len(failed)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
