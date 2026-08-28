#!/usr/bin/env python3
"""
Parse every Lua file the framework ships.

    python tools/lua-syntax.py

WHY THIS EXISTS. Starting the server proves the SERVER scripts parse, and nothing else. A
client script with a syntax error is never read by the server: the resource reports "Started",
the boot log is clean, and the file simply does not run when a player connects. Half a HUD
quietly missing is not something a boot test can catch, which is the gap this fills.

It parses, it does not execute: a file is compiled and the result thrown away, so nothing in
the framework runs and no native is called.

FIVEM IS NOT STOCK LUA. `WEAPON_UNARMED` between backticks is a CitizenFX literal that the
compiler turns into a joaat hash; stock Lua has no such thing and rejects it outright. The
first version of this check reported v-hud's weapon test as a syntax error, which is valid
FiveM and would have been "fixed" into something worse. Those literals are replaced with a
number before parsing - they cannot span a line, so the substitution is safe.

Exit code is 1 when a file fails to parse.
"""

import io
import os
import re
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit('lua-syntax: needs lupa (pip install lupa)')

ROOT = os.path.join('resources', '[local]')
SKIP_DIRS = {'node_modules', '__pycache__', '.git', 'tools'}

# `HASH_LIKE_THIS` -> a number the parser accepts. Never spans a line.
BACKTICK = re.compile(r'`[^`\n]*`')


def lua_files():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in sorted(files):
            if name.endswith('.lua'):
                yield os.path.join(base, name)


def main():
    if not os.path.isdir(ROOT):
        sys.exit('lua-syntax: run me from the repository root')

    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_only = lua.eval(
        'function(src, chunk) local f, err = load(src, chunk); return (f ~= nil), err end')

    failed = 0
    total = 0
    for path in lua_files():
        total += 1
        source = BACKTICK.sub('0', io.open(path, encoding='utf-8', errors='replace').read())
        ok, err = compile_only(source, '@' + path)
        if not ok:
            failed += 1
            print('%s' % path)
            print('      %s' % err)

    print('lua-syntax: %d file(s) parsed' % total)
    if failed:
        print('\n%d file(s) will not load.' % failed)
        return 1
    print('all of them compile.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
