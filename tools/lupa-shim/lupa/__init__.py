"""A small lupa stand-in over the system liblua5.4 (ctypes), for machines without lupa.

Author: vyrriox. Used only when lupa is missing: `PYTHONPATH=tools/lupa-shim python3 <check>`.

Covers what the v-phone and v-core tools use: LuaRuntime(unpack_returned_tuples=...),
execute, eval, globals, table, table_from, lua_type, LuaError, and the lupa.lua54 module
path. Python callables cross into Lua as C closures that never longjmp: they return a status
and a Lua-side wrapper raises, so a Python exception becomes a Lua error safely.
"""
import ctypes
import sys
import types

def _load():
    for name in ('liblua5.4.so.0', 'liblua5.4.so', 'liblua.so.5.4', 'lua54.dll'):
        try:
            return ctypes.CDLL(name)
        except OSError:
            continue
    raise ImportError('lupa shim: no Lua 5.4 shared library found (install lupa instead)')


_lib = _load()
P = ctypes.c_void_p
I = ctypes.c_int
LI = ctypes.c_longlong
D = ctypes.c_double
SZ = ctypes.c_size_t
CF = ctypes.CFUNCTYPE(I, P)


def _sig(name, res, *args):
    f = getattr(_lib, name)
    f.restype = res
    f.argtypes = list(args)
    return f


newstate = _sig('luaL_newstate', P)
openlibs = _sig('luaL_openlibs', None, P)
loadbufferx = _sig('luaL_loadbufferx', I, P, ctypes.c_char_p, SZ, ctypes.c_char_p, ctypes.c_char_p)
pcallk = _sig('lua_pcallk', I, P, I, I, I, P, P)
gettop = _sig('lua_gettop', I, P)
settop = _sig('lua_settop', None, P, I)
ltype = _sig('lua_type', I, P, I)
tolstring = _sig('lua_tolstring', P, P, I, ctypes.POINTER(SZ))
toboolean = _sig('lua_toboolean', I, P, I)
tonumberx = _sig('lua_tonumberx', D, P, I, P)
tointegerx = _sig('lua_tointegerx', LI, P, I, P)
isinteger = _sig('lua_isinteger', I, P, I)
pushnil = _sig('lua_pushnil', None, P)
pushboolean = _sig('lua_pushboolean', None, P, I)
pushinteger = _sig('lua_pushinteger', None, P, LI)
pushnumber = _sig('lua_pushnumber', None, P, D)
pushlstring = _sig('lua_pushlstring', P, P, ctypes.c_char_p, SZ)
pushcclosure = _sig('lua_pushcclosure', None, P, CF, I)
pushvalue = _sig('lua_pushvalue', None, P, I)
createtable = _sig('lua_createtable', None, P, I, I)
settable = _sig('lua_settable', None, P, I)
gettable = _sig('lua_gettable', I, P, I)
rawgeti = _sig('lua_rawgeti', I, P, I, LI)
rawlen = _sig('lua_rawlen', ctypes.c_ulonglong, P, I)
nxt = _sig('lua_next', I, P, I)
lref = _sig('luaL_ref', I, P, I)
lunref = _sig('luaL_unref', None, P, I, I)
llen = _sig('luaL_len', LI, P, I)
rotate = _sig('lua_rotate', None, P, I, I)
setglobal = _sig('lua_setglobal', None, P, ctypes.c_char_p)
getglobal = _sig('lua_getglobal', I, P, ctypes.c_char_p)
touserdata = _sig('lua_touserdata', P, P, I)

REG = -1000000 - 1000
MULTRET = -1
TNIL, TBOOL, TLUD, TNUM, TSTR, TTAB, TFUN, TUD, TTHR = range(9)
TYPENAMES = {TNIL: 'nil', TBOOL: 'boolean', TLUD: 'userdata', TNUM: 'number', TSTR: 'string',
             TTAB: 'table', TFUN: 'function', TUD: 'userdata', TTHR: 'thread'}


class LuaError(Exception):
    pass


LuaSyntaxError = LuaError


def _abs(L, idx):
    return idx if idx > 0 or idx <= REG else gettop(L) + idx + 1


class _Ref:
    __slots__ = ('_rt', '_ref', '__weakref__')

    def __init__(self, rt, idx):
        L = rt._L
        pushvalue(L, idx)
        object.__setattr__(self, '_rt', rt)
        object.__setattr__(self, '_ref', lref(L, REG))

    def _push(self):
        rawgeti(self._rt._L, REG, self._ref)

    def __del__(self):
        try:
            if self._rt._L:
                lunref(self._rt._L, REG, self._ref)
        except Exception:
            pass

    def __call__(self, *args):
        return self._rt._call(self, args)


class _LuaTable(_Ref):
    def _get(self, key):
        rt = self._rt
        L = rt._L
        top = gettop(L)
        try:
            self._push()
            rt._push(key)
            gettable(L, -2)
            return rt._pull(-1)
        finally:
            settop(L, top)

    def _set(self, key, value):
        rt = self._rt
        L = rt._L
        top = gettop(L)
        try:
            self._push()
            rt._push(key)
            rt._push(value)
            settable(L, -3)
        finally:
            settop(L, top)

    def __getitem__(self, key):
        return self._get(key)

    def __setitem__(self, key, value):
        self._set(key, value)

    def __getattr__(self, name):
        if name.startswith('__'):
            raise AttributeError(name)
        return self._get(name)

    def __setattr__(self, name, value):
        self._set(name, value)

    def __len__(self):
        L = self._rt._L
        top = gettop(L)
        self._push()
        n = rawlen(L, -1)
        settop(L, top)
        return int(n)

    def _pairs(self):
        rt = self._rt
        L = rt._L
        out = []
        top = gettop(L)
        self._push()
        pushnil(L)
        while nxt(L, -2):
            out.append((rt._pull(-2), rt._pull(-1)))
            settop(L, -2)
        settop(L, top)
        return out

    def __iter__(self):
        return iter([k for k, _ in self._pairs()])

    def keys(self):
        return [k for k, _ in self._pairs()]

    def values(self):
        return [v for _, v in self._pairs()]

    def items(self):
        return self._pairs()

    def __repr__(self):
        return '<Lua table>'


class _LuaFunction(_Ref):
    def __repr__(self):
        return '<Lua function>'


class _LuaOther(_Ref):
    pass


class LuaRuntime:
    def __init__(self, unpack_returned_tuples=False, encoding='utf-8', **_):
        self._L = newstate()
        openlibs(self._L)
        self._unpack = unpack_returned_tuples
        self.lua_version = (5, 4)
        self.lua_implementation = 'Lua 5.4 (system liblua5.4)'
        self._enc = encoding
        self._keep = []
        self._objs = {}
        self._next_id = 1
        self._exc = None
        self._cb = CF(self._dispatch)
        self._keep.append(self._cb)
        # The Lua side of a Python call: the C function answers (ok, ...) and never raises.
        self.execute('''
            local raw = ...
            __pyWrap = function(id)
                return function(...)
                    local r = table.pack(raw(id, ...))
                    if not r[1] then error(r[2], 2) end
                    return table.unpack(r, 2, r.n)
                end
            end
        ''', _CFunc(self._cb))

    # -- conversion ---------------------------------------------------------------------
    def _push(self, v):
        L = self._L
        if v is None:
            pushnil(L)
        elif v is True or v is False:
            pushboolean(L, 1 if v else 0)
        elif isinstance(v, int):
            pushinteger(L, v)
        elif isinstance(v, float):
            pushnumber(L, v)
        elif isinstance(v, str):
            b = v.encode(self._enc)
            pushlstring(L, b, len(b))
        elif isinstance(v, bytes):
            pushlstring(L, v, len(v))
        elif isinstance(v, _Ref):
            v._push()
        elif isinstance(v, _CFunc):
            pushcclosure(L, v.fn, 0)
        elif callable(v):
            oid = self._next_id
            self._next_id += 1
            self._objs[oid] = v
            getglobal(L, b'__pyWrap')
            pushinteger(L, oid)
            if pcallk(L, 1, 1, 0, None, None) != 0:
                raise LuaError(self._errmsg())
        elif isinstance(v, (list, tuple)):
            self.table_from(v)._push()
        elif isinstance(v, dict):
            self.table_from(v)._push()
        else:
            raise TypeError('cannot pass %r to Lua' % type(v))

    def _str(self, idx):
        n = SZ(0)
        p = tolstring(self._L, idx, ctypes.byref(n))
        raw = ctypes.string_at(p, n.value)
        try:
            return raw.decode(self._enc) if self._enc else raw
        except UnicodeDecodeError:
            return raw

    def _pull(self, idx):
        L = self._L
        idx = _abs(L, idx)
        t = ltype(L, idx)
        if t == TNIL or t == -1:
            return None
        if t == TBOOL:
            return bool(toboolean(L, idx))
        if t == TNUM:
            if isinteger(L, idx):
                return int(tointegerx(L, idx, None))
            return float(tonumberx(L, idx, None))
        if t == TSTR:
            return self._str(idx)
        if t == TTAB:
            return _LuaTable(self, idx)
        if t == TFUN:
            return _LuaFunction(self, idx)
        return _LuaOther(self, idx)

    def _errmsg(self):
        L = self._L
        if self._exc is not None:
            exc, self._exc = self._exc, None
            settop(L, -2)
            return exc
        msg = self._str(-1) if ltype(L, -1) == TSTR else repr(self._pull(-1))
        settop(L, -2)
        return msg

    # -- calls ---------------------------------------------------------------------------
    def _call(self, fn, args):
        L = self._L
        top = gettop(L)
        fn._push()
        for a in args:
            self._push(a)
        if pcallk(L, len(args), MULTRET, 0, None, None) != 0:
            msg = self._errmsg()
            settop(L, top)
            if isinstance(msg, BaseException):
                raise msg
            raise LuaError(msg)
        n = gettop(L) - top
        res = [self._pull(top + 1 + i) for i in range(n)]
        settop(L, top)
        if n == 0:
            return None
        if n == 1:
            return res[0]
        return tuple(res)

    def _dispatch(self, L):
        # A call from inside a coroutine arrives on that coroutine's own stack.
        saved, self._L = self._L, L
        try:
            return self._dispatch_on(L)
        finally:
            self._L = saved

    def _dispatch_on(self, L):
        try:
            n = gettop(L)
            oid = int(tointegerx(L, 1, None))
            args = [self._pull(i) for i in range(2, n + 1)]
            res = self._objs[oid](*args)
            settop(L, 0)
            pushboolean(L, 1)
            if self._unpack and isinstance(res, tuple):
                for r in res:
                    self._push(r)
                return 1 + len(res)
            self._push(res)
            return 2
        except BaseException as e:  # noqa: BLE001 - must never escape into C
            settop(L, 0)
            pushboolean(L, 0)
            msg = '%s: %s' % (type(e).__name__, e)
            b = msg.encode('utf-8', 'replace')
            pushlstring(L, b, len(b))
            return 2

    # -- public API ----------------------------------------------------------------------
    def execute(self, code, *args, name='<python>'):
        L = self._L
        if isinstance(code, str):
            code = code.encode(self._enc)
        top = gettop(L)
        if loadbufferx(L, code, len(code), ('=' + name).encode(), b't') != 0:
            msg = self._errmsg()
            settop(L, top)
            raise LuaError(msg)
        fn = _LuaFunction(self, -1)
        settop(L, top)
        return self._call(fn, args)

    def eval(self, expr, *args):
        return self.execute('return ' + expr, *args)

    def globals(self):
        L = self._L
        top = gettop(L)
        rawgeti(L, REG, 2)
        g = _LuaTable(self, -1)
        settop(L, top)
        return g

    def table(self, *items, **kw):
        t = self.table_from(list(items))
        for k, v in kw.items():
            t[k] = v
        return t

    def table_from(self, *objs, recursive=False):
        L = self._L
        top = gettop(L)
        createtable(L, 0, 0)
        t = _LuaTable(self, -1)
        settop(L, top)
        i = 1
        for obj in objs:
            if isinstance(obj, dict):
                for k, v in obj.items():
                    t[k] = self._conv(v, recursive)
            elif isinstance(obj, _LuaTable):
                for k, v in obj.items():
                    t[k] = v
            else:
                for v in obj:
                    t[i] = self._conv(v, recursive)
                    i += 1
        return t

    def _conv(self, v, recursive):
        if recursive and isinstance(v, (dict, list, tuple)):
            return self.table_from(v, recursive=True)
        return v


class _CFunc:
    def __init__(self, fn):
        self.fn = fn


def lua_type(obj):
    if isinstance(obj, _LuaTable):
        return 'table'
    if isinstance(obj, _LuaFunction):
        return 'function'
    if isinstance(obj, _LuaOther):
        L = obj._rt._L
        top = gettop(L)
        obj._push()
        t = TYPENAMES.get(ltype(L, -1))
        settop(L, top)
        return t
    return None


# `import lupa.lua54 as lupa` and `from lupa import lua54` both resolve to this module.
lua54 = sys.modules[__name__]
sys.modules[__name__ + '.lua54'] = lua54
