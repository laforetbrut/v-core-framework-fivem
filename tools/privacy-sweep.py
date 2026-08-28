#!/usr/bin/env python3
"""
Look for anything that must never be committed: real addresses, account identifiers, keys,
tokens and live connection strings.

Run it from the repository root:

    python tools/privacy-sweep.py

It reads only files git already tracks, so an untracked local config - license.cfg and
anything like it - is never opened, which is the point of keeping those out of the index in
the first place.

VENDORED TREES ARE SKIPPED. `resources/[cfx-default]` and `resources/[standalone]` are
upstream code: they carry `root@cfx.re` in fifty-eight manifests and version numbers that
read like addresses, and reporting those buries the one line that actually matters. What is
skipped is listed at the end of a run, so the skip can never quietly grow into a blind spot.

Exit code is 1 when something matched, so a hook or a CI step can fail on it.
"""

import io
import re
import subprocess
import sys

PATTERNS = [
    ('e-mail address',      re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')),
    ('Discord snowflake',   re.compile(r'\b\d{17,19}\b')),
    ('Steam identifier',    re.compile(r'\bsteam:1100001[0-9a-f]{8}\b', re.I)),
    ('FiveM license',       re.compile(r'\blicense:[0-9a-f]{40}\b', re.I)),
    # An address only counts when something around it says it is one. A bare dotted quad
    # matches a version number and, worse, the coordinates inside an SVG path: the phone's
    # icon set alone produced six of those, which is exactly the noise that gets a checker
    # ignored. CONTEXT below is what makes the difference.
    ('routable IP',         re.compile(r'\b(?!127\.0\.0\.1|0\.0\.0\.0|255\.)(?:\d{1,3}\.){3}\d{1,3}\b')),
    ('Discord invite',      re.compile(r'discord\.(?:gg|com/invite)/[A-Za-z0-9]+')),
    ('key or secret',       re.compile(r'(api[_-]?key|secret|bearer|authorization)\s*[:=]\s*[\'"][^\'"]{12,}', re.I)),
    ('server license key',  re.compile(r'\bsv_licenseKey\s+[A-Za-z0-9]{10,}', re.I)),
    ('database URL',        re.compile(r'\b\w+://[^\s"\']*:[^\s"\'@]+@[^\s"\']+')),
]

# Upstream code we ship but do not write.
SKIP_DIRS = (
    'resources/[cfx-default]/',
    'resources/[standalone]/',
)
SKIP_EXT = ('.png', '.jpg', '.jpeg', '.webp', '.gif', '.ico', '.mp3', '.ogg', '.wav',
            '.webm', '.mp4', '.ytd', '.gfx', '.woff', '.woff2', '.ttf', '.otf', '.pyc',
            '.zip', '.dll', '.exe')

# A placeholder is the correct thing to find in documentation and in a shipped config: it is
# what an operator is meant to replace. Reporting them trains the reader to ignore the tool.
#
# `localhost` is deliberately NOT in this list. A connection string is a credential wherever
# it points, and the first version of this file filtered on the word - which hid the one real
# finding it had, in server.cfg, behind six SVG coordinates it had mistaken for addresses.
PLACEHOLDER = re.compile(
    r'(your|votre|ta_|example|placeholder|user:password|xxx+|0{8,}|1234567890|'
    r'root@cfx\.re)', re.I)

# Only report an address when its surroundings claim it is one.
IP_CONTEXT = re.compile(r'(://|host|\bip\b|addr|server|connect|endpoint|proxy)', re.I)


def tracked_files():
    out = subprocess.run(['git', 'ls-files'], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit('privacy-sweep: not a git repository, or git is unavailable')
    return out.stdout.splitlines()


def main():
    findings = []
    scanned = skipped = 0

    for path in tracked_files():
        low = path.lower()
        if low.startswith(SKIP_DIRS) or low.endswith(SKIP_EXT):
            skipped += 1
            continue
        try:
            text = io.open(path, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        scanned += 1

        for label, pattern in PATTERNS:
            for match in pattern.finditer(text):
                fragment = match.group(0)
                if PLACEHOLDER.search(fragment):
                    continue
                if label == 'routable IP':
                    around = text[max(0, match.start() - 40):match.end() + 40]
                    if not IP_CONTEXT.search(around):
                        continue
                line = text.count('\n', 0, match.start()) + 1
                findings.append((path, line, label, fragment[:90]))

    print('privacy-sweep: %d tracked file(s) read, %d skipped as vendored or binary'
          % (scanned, skipped))
    print('skipped trees: %s' % ', '.join(SKIP_DIRS))

    if not findings:
        print('\nnothing to report.')
        return 0

    print('\n%d thing(s) worth a look:\n' % len(findings))
    for path, line, label, fragment in findings:
        print('  %s:%d' % (path, line))
        print('      %-18s %s' % (label, fragment))
    print('\nA placeholder is fine and is filtered out. Anything above is a real value in a')
    print('tracked file: move it into a gitignored config the way license.cfg already is.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
