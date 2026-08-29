#!/usr/bin/env python3
"""
Ask the database whether every SQL statement in the framework is one it would accept.

    database\\start-db.bat                     the database is on-demand here
    set VCORE_DB=mysql://user:pass@host:port/db
    python tools/sql-check.py --client "C:/Program Files/MariaDB 12.3/bin/mariadb.exe"

WHY THIS IS NOT ONE OF THE OTHER FOUR. lua-syntax, privacy-sweep, locale-check and
manifest-check read the repository and need nothing else, so they run anywhere. This one needs
a running database and a client binary, and it is worth that: a boot test only ever exercises
the queries that run AT BOOT. A `SELECT` behind a shop, a garage or a phone app is never seen
until a player walks into it, and a column renamed out from under it fails there, in front of
them, months later.

HOW. `PREPARE s FROM '...'` runs the parser and the name resolver and then stops. Nothing is
read, nothing is written, nothing is deleted. A statement the database would refuse in
production is refused here instead, in about a second, against your own schema.

WHAT IT DOES NOT JUDGE, said out loud rather than counted as passing:

  * A query assembled at runtime - `'SELECT ' .. cols .. ' FROM x'`, or anything with `%s` -
    is not a complete statement in the file, so it is reported as skipped. A checker that
    quietly covers two thirds of its subject and prints a pass is worse than no checker.

  * A statement inside a `Bridge.framework == 'qb'` branch is written in another framework's
    schema on purpose. qb-core's `players` and ox_core's `characters` columns do not exist
    here and never will; those never run on this framework. They are listed apart, because a
    check that reports eight permanent failures every run teaches everybody to ignore it.

Exit code is 1 only when a statement that WOULD run here is refused.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.join('resources', '[local]')

CALL = re.compile(r"MySQL\.(?:query|scalar|insert|update|prepare|single|rawExecute)"
                  r"(?:\.await)?\s*\(\s*")
SQL_START = re.compile(
    r"^(SELECT|INSERT|UPDATE|DELETE|REPLACE|CREATE|ALTER|DROP|TRUNCATE|SET|SHOW)\b", re.I)
# The branch that makes a foreign schema legitimate.
FOREIGN = re.compile(r"Bridge\.framework\s*==\s*'([a-z_]+)'")


def literal_at(src, i):
    """The string literal starting at i, or None. Returns (text, index just past it)."""
    if i >= len(src):
        return None
    q = src[i]
    if q in "'\"":
        j, buf = i + 1, []
        while j < len(src):
            if src[j] == '\\':
                buf.append(src[j:j + 2])
                j += 2
                continue
            if src[j] == q:
                break
            buf.append(src[j])
            j += 1
        return ''.join(buf), j + 1
    if src.startswith('[[', i):
        j = src.find(']]', i + 2)
        if j < 0:
            return None
        return src[i + 2:j], j + 2
    return None


def strip_sql_comments(sql):
    """Drop `-- ...` comments before the statement is flattened onto one line.

    A comment ends at its own newline in the file. Flattening first lets it swallow everything
    after it: v-factions' `-- job | gang` turned a valid CREATE TABLE into a syntax error the
    database had never objected to.
    """
    out = []
    for line in sql.splitlines():
        cut = line.find(' --')
        out.append(line if cut < 0 else line[:cut])
    return ' '.join(out)


def framework_branch(src, at):
    """The framework named by the nearest enclosing branch above `at`, or None."""
    head = src.rfind('\nlocal function', 0, at)
    head = max(head, src.rfind('\nfunction', 0, at))
    window = src[head if head > 0 else max(0, at - 2000):at]
    found = FOREIGN.findall(window)
    return found[-1] if found else None


def collect():
    complete, assembled = [], 0
    for mod in sorted(os.listdir(ROOT)):
        base = os.path.join(ROOT, mod)
        if not os.path.isdir(base):
            continue
        for dirpath, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs
                       if d not in ('preview', 'tools', 'node_modules', '__pycache__')]
            for f in sorted(files):
                if not f.endswith('.lua'):
                    continue
                path = os.path.join(dirpath, f)
                try:
                    src = open(path, encoding='utf-8', errors='replace').read()
                except OSError:
                    continue
                for m in CALL.finditer(src):
                    got = literal_at(src, m.end())
                    if not got:
                        assembled += 1
                        continue
                    sql, end = got
                    tail = src[end:end + 40].lstrip()
                    if tail.startswith('..') or '..' in sql or '%s' in sql or '%d' in sql:
                        assembled += 1
                        continue
                    sql = ' '.join(strip_sql_comments(sql).split())
                    if not SQL_START.match(sql):
                        continue
                    complete.append({
                        'module': mod,
                        'path': path.replace(os.sep, '/'),
                        'line': src[:m.start()].count('\n') + 1,
                        'sql': sql,
                        'foreign': framework_branch(src, m.start()),
                    })
    return complete, assembled


def connection():
    url = (os.environ.get('VCORE_DB') or '').strip()
    for i, arg in enumerate(sys.argv):
        if arg == '--url' and i + 1 < len(sys.argv):
            url = sys.argv[i + 1].strip()
    m = re.match(r'mysql://([^:@/]+)(?::([^@]*))?@([^:/]+):(\d+)/([^?\s]+)(?:\?\S*)?$', url)
    if not m:
        sys.exit('set VCORE_DB (or pass --url) to  mysql://user:password@host:port/database\n'
                 'A read-only copy of your schema is enough - nothing is executed.')
    return m.groups()


def client():
    for i, arg in enumerate(sys.argv):
        if arg == '--client' and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    import shutil
    found = shutil.which('mariadb') or shutil.which('mysql')
    if not found:
        sys.exit('no mariadb/mysql client on PATH. Pass --client "C:/path/to/mariadb.exe".')
    return found


def main():
    statements, assembled = collect()
    print('sql-check: %d complete statement(s), %d assembled at runtime and not judged'
          % (len(statements), assembled))
    if not statements:
        return 0

    user, pw, host, port, db = connection()
    lines = ["PREPARE s FROM '%s'; DEALLOCATE PREPARE s;"
             % s['sql'].replace('\\', '\\\\').replace("'", "''") for s in statements]

    env = dict(os.environ)
    if pw:
        env['MYSQL_PWD'] = pw
    cmd = [client(), '-h', host, '-P', port, '-u', user, '-D', db, '--batch', '--silent']
    run = subprocess.run(cmd, input='\n'.join(lines) + '\n',
                         capture_output=True, text=True, env=env)

    failures = {}
    for line in (run.stderr or '').splitlines():
        m = re.search(r'ERROR\s+(\d+)\s+\([^)]*\)\s+at line (\d+):\s*(.*)', line)
        if m:
            # The FIRST error on a line: PREPARE and DEALLOCATE share one, so a failed PREPARE
            # is always followed by "unknown prepared statement handler", which would otherwise
            # replace every real message with that noise.
            n = int(m.group(2))
            if n not in failures:
                failures[n] = m.group(3).strip()

    real, foreign = [], []
    for n, msg in sorted(failures.items()):
        if n - 1 >= len(statements):
            continue
        s = dict(statements[n - 1])
        s['why'] = msg
        (foreign if s['foreign'] else real).append(s)

    if foreign:
        seen = sorted({s['foreign'] for s in foreign})
        print('   %d written for another framework (%s), never reached here'
              % (len(foreign), ', '.join(seen)))

    if not real:
        print('\nevery statement that runs on this framework prepares against the live schema.')
        return 0

    print()
    for s in real:
        print('  %s:%d' % (s['path'], s['line']))
        print('      %s' % s['why'])
        print('      %s' % s['sql'][:160])
    print('\n%d statement(s) the database refuses.' % len(real))
    return 1


if __name__ == '__main__':
    sys.exit(main())
