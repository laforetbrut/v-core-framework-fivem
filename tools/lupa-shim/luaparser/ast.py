"""luaparser.ast.parse stand-in: compiles with the real liblua5.4 and raises on a syntax error.

Author: vyrriox. Only a syntax check: it returns True, not a tree.
"""
import lupa

_rt = None


def parse(src):
    global _rt
    if _rt is None:
        _rt = lupa.LuaRuntime()
    ok, err = _rt.eval('function(s) local f, e = load(s, "=chunk", "t") return f ~= nil, e end')(src)
    if not ok:
        raise SyntaxError(err)
    return True
