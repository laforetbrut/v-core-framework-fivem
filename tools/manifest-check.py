#!/usr/bin/env python3
"""
Check that every asset a NUI page loads is one the resource actually serves.

    python tools/manifest-check.py

A page can only fetch a file the manifest lists in `files{}`. A stylesheet or a script
referenced by the HTML and missing from that list is fetched, 404s, and the page carries on
without it - so the symptom is a feature that quietly does nothing, with no error anywhere
except the client console nobody has open. The HUD shipped exactly that: its preview loaded
nine of its ten scripts, and the tenth was missing for weeks.

WHAT IS AND IS NOT REPORTED. A glob in `files{}` that matches nothing today is deliberate and
is left alone: the loading screen lists `assets/backgrounds/*.jpg` beside the `.webp` it ships
so an operator can drop either in, and the phone lists `apps/*/*.js` for apps that do not
exist yet. Neither warns at boot. A LITERAL path listed and absent is reported, because that
one can only be a mistake.

A file sitting on disk that no page references is not reported either: it may be waiting to be
wired up, and deciding that is not a checker's job.

Exit code is 1 when something is wrong.
"""

import fnmatch
import io
import os
import re
import sys

ROOT = os.path.join('resources', '[local]')

FILES_BLOCK = re.compile(r'\bfiles\s*\{(.*?)\}', re.S)
QUOTED = re.compile(r"""['"]([^'"]+)['"]""")
UI_PAGE = re.compile(r"""\bui_page\s+['"]([^'"]+)['"]""")
LINE_COMMENT = re.compile(r'--(?!\[\[).*')

# src="x" / href="x", plus the document.write list pattern a couple of pages use to build
# their script tags from an array of names.
REFERENCE = re.compile(r"""\b(?:src|href)\s*=\s*['"]([^'"]+)['"]""")
SCRIPT_LIST = re.compile(r"scripts\s*=\s*\[(.*?)\]", re.S)
NAME_IN_LIST = re.compile(r"'([\w-]+)'")

EXTERNAL = ('http://', 'https://', '//', 'data:', 'nui://', 'mailto:')


def read(path):
    return io.open(path, encoding='utf-8', errors='replace').read()


def manifest_patterns(text):
    out = []
    for block in FILES_BLOCK.finditer(text):
        out += QUOTED.findall(block.group(1))
    out += UI_PAGE.findall(text)
    return [p for p in out if not p.startswith('@')]


def covered(rel, patterns):
    return any(fnmatch.fnmatch(rel, p) or rel == p for p in patterns)


def page_references(html_path, module_dir):
    """Every local file the page asks for, as a module-relative path."""
    text = read(html_path)
    here = os.path.dirname(html_path)
    out = set()

    refs = list(REFERENCE.findall(text))
    for m in SCRIPT_LIST.finditer(text):
        refs += ['js/%s.js' % n for n in NAME_IN_LIST.findall(m.group(1))]

    for ref in refs:
        if ref.startswith(EXTERNAL) or ref.startswith('#'):
            continue
        ref = ref.split('?', 1)[0].split('#', 1)[0]
        # A page that builds its tags by concatenation leaves half a path in the source:
        # `src="js/' + name + '.js"` matches as `js/`. An asset has an extension; a bare
        # directory fragment is the other half of a string the SCRIPT_LIST branch already
        # resolved properly.
        if not ref or ref.endswith('/') or '.' not in os.path.basename(ref):
            continue
        target = os.path.normpath(os.path.join(here, ref))
        out.add(os.path.relpath(target, module_dir).replace('\\', '/'))
    return out


def main():
    if not os.path.isdir(ROOT):
        sys.exit('manifest-check: run me from the repository root')

    problems = 0
    pages = 0

    for name in sorted(os.listdir(ROOT)):
        module = os.path.join(ROOT, name)
        manifest = os.path.join(module, 'fxmanifest.lua')
        if not os.path.exists(manifest):
            continue

        text = LINE_COMMENT.sub('', read(manifest))
        patterns = manifest_patterns(text)

        # A literal entry that is not on disk can only be a mistake.
        for p in patterns:
            if any(ch in p for ch in '*?['):
                continue
            if not os.path.exists(os.path.join(module, p)):
                problems += 1
                print('%s: fxmanifest lists %s, which is not on disk' % (name, p))

        for ui in UI_PAGE.findall(text):
            html = os.path.join(module, ui)
            if not os.path.exists(html):
                continue
            pages += 1
            for ref in sorted(page_references(html, module)):
                if ref.startswith('..'):
                    continue          # reaches outside the resource; not ours to serve
                if not os.path.exists(os.path.join(module, ref)):
                    problems += 1
                    print('%s: %s loads %s, which is not on disk' % (name, ui, ref))
                elif not covered(ref, patterns):
                    problems += 1
                    print('%s: %s loads %s, which fxmanifest does not serve' % (name, ui, ref))

    print('manifest-check: %d NUI page(s) read' % pages)
    if problems:
        print('\n%d problem(s).' % problems)
        return 1
    print('every asset a page loads is listed, and every listed path exists.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
