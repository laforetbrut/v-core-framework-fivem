#!/usr/bin/env python3
"""
Check every module's locale pair.

    python tools/locale-check.py

Three questions, each with a visible answer in game when it goes wrong:

  PARITY   a key in en.lua and not in fr.lua falls back to English mid-sentence for a French
           player, and the other way round for an English one.

  USAGE    a key the Lua asks for and no locale defines is printed raw: the player reads
           `veh.err_nokeys` instead of a sentence.

  DUPLICATES  a key written twice in one file loads twice, and the second silently wins. The
           phone shipped two of those - `ph.soc_avatar` and `ph.soc_bio` - where the plainer
           of the two labels was the one that showed. Nothing errors, and the file reads
           correctly at the first occurrence, which is where anybody would look.

TWO THINGS THIS HAS TO GET RIGHT, both learned by getting them wrong first:

  * Keys are built at runtime. `L('drug.err_' .. reason)` leaves the literal `drug.err_` in
    the source, and a naive scan reports it as a missing key in seventeen modules at once.
    A literal followed by a concatenation is a prefix, not a key, and is skipped - with a
    count printed, because a prefix is exactly what this check cannot verify.

  * Comments mention keys. v-core's locale header documents the API as `calls L('key', ...)`,
    which is prose, not a call. Comments are stripped before anything is matched.

THE INTERFACE ASKS FOR KEYS TOO, and for a while this check could not see any of them. A module
whose interface is a NUI page keeps its text in JavaScript: v-phone asks for 591 keys from
app.js and four from Lua, so reading only .lua validated four keys out of 852 and reported
success. The phone resolves with `const L = (k) => S[k] || k`, which renders the key itself when
it is absent, so the failure this missed is a player reading `ph.mail_kept` in the interface.

JavaScript is not matched with the Lua pattern, because the keys sit in places that pattern
cannot reach: `L(saved ? 'ph.a' : 'ph.b')` holds two of them and starts with neither. The JS
scan walks parentheses and string state instead, so a literal anywhere inside an L( call is
found however it is nested. A literal glued to a `+` is a prefix finished at runtime, counted
and not judged, exactly as `..` is on the Lua side.

Exit code is 1 when something is wrong, so a hook or a CI step can fail on it.
"""

import collections
import io
import os
import re
import sys

ROOT = os.path.join('resources', '[local]')

KEY_DEF = re.compile(r"\['([^']+)'\]\s*=")
# Anchored to the start of a line: a definition, not a mention inside a longer expression.
KEY_LINE = re.compile(r"^\s*\['([^']+)'\]\s*=", re.M)

# A locale call whose first argument is a literal. The trailing group tells a whole key from
# the prefix of one that is finished at runtime.
#
# The optional leading argument - the `src` of LP(src, 'key') - must not contain a bracket.
# Allowing one let the pattern walk out of the call it started in: `notify(src, (...):format(
# L(def.label)), 'success')` matched from `L(`, swallowed `def.label)), ` as an argument and
# reported the OUTER call's notification level as a missing locale key, in four modules.
CALL = re.compile(r"\b(?:L|LP|Lang|T)\(\s*(?:[^,'\"()]+,\s*)?'([A-Za-z0-9_.\-]+)'\s*(\.\.)?")

LINE_COMMENT = re.compile(r'--(?!\[\[).*')
BLOCK_COMMENT = re.compile(r'--\[\[.*?\]\]', re.S)


KEY_SHAPE = re.compile(r'^[A-Za-z0-9_]+\.[A-Za-z0-9_.\-]+$')
L_BEFORE = re.compile(r'\bL\s*$')


def read(path):
    return io.open(path, encoding='utf-8', errors='replace').read()


def js_locale_keys(text):
    """Every string literal sitting inside an L( call, with whether it is a fragment.

    Walks the source rather than matching it: the keys are nested inside ternaries and
    argument lists that no anchored pattern reaches. Tracks string state so a `//` inside a
    URL is not read as a comment, and a `(` inside a string does not open a call.
    """
    out = []
    paren_is_call = []          # one flag per open paren: did an L open it
    i, n = 0, len(text)
    while i < n:
        c = text[i]

        if c == '/' and i + 1 < n and text[i + 1] in '/*':
            if text[i + 1] == '/':
                end = text.find('\n', i)
            else:
                end = text.find('*/', i + 2)
                end = n if end < 0 else end + 2
            i = n if end < 0 else end
            continue

        if c in '\'"`':
            j, buf = i + 1, []
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == c:
                    break
                buf.append(text[j])
                j += 1
            if any(paren_is_call):
                literal = ''.join(buf)
                glued = bool(re.search(r'\+\s*$', text[max(0, i - 40):i])) or \
                        bool(re.match(r'\s*\+', text[j + 1:j + 41]))
                out.append((literal, glued))
            i = j + 1
            continue

        if c == '(':
            paren_is_call.append(bool(L_BEFORE.search(text[max(0, i - 8):i])))
        elif c == ')' and paren_is_call:
            paren_is_call.pop()
        i += 1

    return out


def strip_comments(text):
    return LINE_COMMENT.sub('', BLOCK_COMMENT.sub('', text))


def module_dirs():
    if not os.path.isdir(ROOT):
        sys.exit('locale-check: run me from the repository root')
    for name in sorted(os.listdir(ROOT)):
        path = os.path.join(ROOT, name)
        if os.path.isdir(path):
            yield name, path


def main():
    problems = 0
    checked = 0
    prefixes = 0

    for name, path in module_dirs():
        en = os.path.join(path, 'locales', 'en.lua')
        fr = os.path.join(path, 'locales', 'fr.lua')
        if not os.path.exists(en):
            continue
        checked += 1

        # A key written twice: the second definition wins and the first is never seen.
        for locale_path in (en, fr):
            if not os.path.exists(locale_path):
                continue
            text = read(locale_path)
            counted = collections.Counter(KEY_LINE.findall(text))
            twice = sorted(k for k, n in counted.items() if n > 1)
            if twice:
                problems += 1
                print('%s: %d key(s) defined twice in %s' %
                      (name, len(twice), os.path.basename(locale_path)))
                lines = text.splitlines()
                for key in twice[:8]:
                    at = [i + 1 for i, l in enumerate(lines)
                          if re.match(r"\s*\['" + re.escape(key) + r"'\]\s*=", l)]
                    print('      %-32s lines %s' % (key, at))

        defined_en = set(KEY_DEF.findall(read(en)))
        defined_fr = set(KEY_DEF.findall(read(fr))) if os.path.exists(fr) else None

        if defined_fr is not None:
            for missing, where in ((defined_en - defined_fr, 'fr'),
                                   (defined_fr - defined_en, 'en')):
                if missing:
                    problems += 1
                    print('%s: %d key(s) missing from %s.lua' % (name, len(missing), where))
                    for key in sorted(missing)[:8]:
                        print('      %s' % key)

        asked = set()
        for base, dirs, files in os.walk(path):
            # `preview` holds a generated copy of the interface; judging it would double every
            # finding and report the generator's output as if it were source.
            dirs[:] = [d for d in dirs
                       if d not in ('locales', 'tools', 'node_modules', 'preview')]
            for f in files:
                full = os.path.join(base, f)
                if f.endswith('.lua'):
                    for key, concat in CALL.findall(strip_comments(read(full))):
                        if concat:
                            prefixes += 1     # finished at runtime; nothing to verify here
                        else:
                            asked.add(key)
                elif f.endswith('.js'):
                    for literal, glued in js_locale_keys(read(full)):
                        if glued or not KEY_SHAPE.match(literal):
                            prefixes += 1
                        else:
                            asked.add(literal)

        undefined = sorted(k for k in asked if k not in defined_en)
        if undefined:
            problems += 1
            print('%s: %d key(s) used in code and defined nowhere' % (name, len(undefined)))
            for key in undefined[:8]:
                print('      %s' % key)

    print('locale-check: %d module(s) with a locale, %d runtime-built key(s) left unverified'
          % (checked, prefixes))
    if problems:
        print('\n%d problem(s).' % problems)
        return 1
    print('every key defined once, on both sides, and every key asked for exists.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
