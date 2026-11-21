-- v-phone | server/adminview.lua
--
-- **Holding somebody else's phone.**
--
-- A staff member opens a target's handset on their OWN screen and uses it as that character:
-- their messages, their contacts, their bank, their apps. Not a read-only inspector - the
-- police forensics terminal is the read-only one, and it is deliberately narrow. This is the
-- support tool: see what they see, and fix it from there.
--
-- **How it works, in one sentence:** every callback in this resource asks `Core.GetPlayer(src)`
-- for who is calling, so a session makes that one function answer with the TARGET's player for
-- the staff member's source, and the entire phone follows without a single app knowing.
--
-- That is also why this file is small and why it sits on its own. One choke point is the only
-- honest way to do this: sixty call sites patched by hand would have left the ones nobody
-- thought of - a bank transfer, an FruitDrop - still acting as the admin, which is worse than
-- not having the feature.
--
-- **What it deliberately does NOT do.** It does not follow the target's position: coordinates
-- still come from the staff member's own ped, so an FruitDrop or a charging point works where the
-- staff member is standing, not where the target is. Making position follow too would mean a
-- second choke point and a much larger blast radius, and none of the support cases need it.
--
-- Paid charging is left on the staff member's own purse for exactly that reason, and it is the
-- one money path that is: the offer is about a charger THEY are standing at, so it would be
-- incoherent for somebody else to pay for it. Everything addressed to "this phone's account" -
-- the bank, Bank Pro, a store purchase, a mail domain - follows the held character.
--
-- Every session is logged with both names, opens only behind the ace, expires on its own, and
-- ends when either player drops. A tool that acts as somebody else has to leave a trail.

local ADMIN = Config.Admin or {}

--- [staff source] = { cid, name, until, opened }
local Viewing = {}

local function viewSeconds()
    return math.max(30, math.floor(tonumber(ADMIN.viewSeconds) or 600))
end

--- Staff whose session ran out and who have not been told yet.
---
--- **An expiry that nobody notices is the worst bug this file can have.** The session simply
--- stopped answering: `AdminViewTarget` returned nil, `Core.GetPlayer` fell back to the staff
--- member, the banner stayed on screen and the page went on showing the held character's data -
--- so the next thing staff did landed on their OWN character. That is exactly how a player was
--- signed up to Hush and the admin got the profile.
---
--- Now an expiry is an event: the phone is told, and until it is, every call FAILS rather than
--- being performed by the wrong person.
---
--- Set by every end the staff member did not ask for - running out, the target leaving - and
--- spent by exactly one thing: the first genuine REQUEST afterwards, which is refused. A clock
--- never spends it. The state tick once did, within two seconds of an expiry, and the message a
--- staff member sent next went out as their own character while the banner still named the
--- target. It is also dropped when the phone reports it has closed the handset (see the
--- `adminViewClosed` event below), because from then on nothing on that screen can send one.
local Expired = {}

--- The lookup, with its two side effects asked for separately.
---
--- `use` decides what an expiry discovered here means: a real use is refused (see `Expired`), an
--- informational read is not. `extend` decides whether this counts as the staff member DOING
--- something, and pushes the clock back when it does.
---
--- They were one flag, and that is how a session never ran out. The battery clock asked
--- `Core.GetPlayer` for every player every two seconds, that call is a use, and a use extended the
--- session - so a staff member who opened somebody's phone and walked away held it for as long as
--- they stayed connected. A clock asking whether somebody exists is not staff activity.
local function heldBy(src, use, extend)
    src = tonumber(src) or 0
    local v = Viewing[src]
    if not v then return nil end

    if os.time() >= v.expires then
        Viewing[src] = nil
        -- Flagged for a request and for a clock. An informational read - the staff menu asking
        -- what is held, the banner checking itself - does not flag, or the next genuine call from
        -- that staff member would be refused for nothing.
        if use then Expired[src] = true end
        V.Log(('admin view: %s ran out while holding %s')
            :format(GetPlayerName(src) or '?', v.name or v.cid))
        -- Tell the phone. client/admin.lua closes the handset, so the page stops drawing somebody
        -- else's data, and then acknowledges.
        TriggerClientEvent('v-phone:client:adminView', src, false)
        return nil
    end

    if extend then v.expires = os.time() + viewSeconds() end
    return v.cid, v.name
end

--- The citizen id a staff member is currently holding, or nil.
---
--- `touch` marks this as real use. A session that is being used does not run out underneath the
--- person using it - the clock is there to stop a forgotten session lasting all night, not to
--- interrupt somebody halfway through typing a profile. Only callers acting for the staff member
--- pass it; anything on a timer must not (see `heldBy`).
function AdminViewTarget(src, touch)
    return heldBy(src, touch, touch)
end

--- Did this staff member's session END without them being told?
---
--- Read by the choke point below, and ONLY for a request. It stays true for one call - long
--- enough for that call to refuse - and is then cleared, so the staff member's own phone works
--- again straight after. A clock that read it would spend the refusal on nobody.
local function justExpired(src)
    src = tonumber(src) or 0
    if not Expired[src] then return false end
    Expired[src] = nil
    return true
end

--- Close a session, and tell the phone so it stops showing the banner.
function AdminViewClose(src)
    src = tonumber(src)
    if not src or not Viewing[src] then return false end
    local v = Viewing[src]
    Viewing[src] = nil
    V.Log(('admin view: %s released %s (%s)')
        :format(GetPlayerName(src) or '?', v.name or '?', v.cid))
    TriggerClientEvent('v-phone:client:adminView', src, false)

    -- **Give the character their own routing back.**
    --
    -- Nothing should have taken it - `ensureNumber` refuses to bind a number to a viewer now -
    -- but a session opened before that fix left the target's number pointing at the staff
    -- member, and a session repaired only at the next reconnect is a player who spends the rest
    -- of the evening not receiving their own messages. Rebinding on release costs one loop and
    -- repairs it whatever caused it.
    local phone = exports[GetCurrentResourceName()]
    local number = phone:GetNumber(v.cid)
    if number and number ~= '' then
        for _, raw in ipairs(GetPlayers()) do
            local other = tonumber(raw)
            local op = other and (Core.GetPlayerReal and Core.GetPlayerReal(other)
                                  or Core.GetPlayer(other))
            if op and tostring(op.citizenid) == tostring(v.cid) then
                if PhoneSetOnline then PhoneSetOnline(number, other) end
                break
            end
        end
    end
    return true
end

--- End a session the staff member did not end themselves: found by a clock, or by an event.
---
--- Leaves the one-call refusal behind. The handset may still be drawing the held character, and
--- a request already on its way must not land on the staff member's own. `AdminViewClose` tells
--- the phone, which closes and clears the refusal once nothing on screen can send one.
local function endUnasked(src)
    src = tonumber(src)
    if not src or not Viewing[src] then return false end
    Expired[src] = true
    return AdminViewClose(src)
end

--- Open one. The target must be ONLINE.
---
--- An offline character would mean building a player object out of the database - a second way
--- of constructing the thing the whole bridge exists to construct, and one that would drift
--- from the real one. Staff who need an offline character have `/phoneadmin info`, `contacts`,
--- `apps` and `wipe`, all of which take a citizen id.
function AdminViewOpen(src, targetSrc)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc then return false, 'nosuchplayer' end
    if src == targetSrc then return false, 'self' end

    local target = Core.GetPlayerReal and Core.GetPlayerReal(targetSrc) or Core.GetPlayer(targetSrc)
    if not target then return false, 'nosuchplayer' end

    Viewing[src] = {
        cid = target.citizenid,
        name = target.name or tostring(targetSrc),
        expires = os.time() + viewSeconds(),
        opened = os.time(),
    }
    V.Log(('admin view: %s (id %d) opened the phone of %s (%s) for up to %d minutes')
        :format(GetPlayerName(src) or '?', src, target.name or '?', target.citizenid,
                math.floor(viewSeconds() / 60)))

    TriggerClientEvent('v-phone:client:adminView', src, {
        name = target.name or '',
        seconds = viewSeconds(),
    })
    -- Their own phone opens on their screen, holding the other character's.
    TriggerClientEvent('v-phone:client:open', src)
    return true, target.name
end

-- ══════════════════════════════════════════════════════════════
-- The choke point
-- ══════════════════════════════════════════════════════════════
-- `Core.GetPlayer` is what every callback in this resource asks who is calling. Wrapping it
-- here, once, is what makes a session work everywhere - and keeping the original under
-- `Core.GetPlayerReal` is what lets the few places that must know the REAL caller ask.
--
-- Loaded after bridge/server/framework.lua, which builds `Core`, and before server/main.lua,
-- which is the first file to use it.

Core.GetPlayerReal = Core.GetPlayer

--- The redirect. `request` is true for `Core.GetPlayer`, which every callback asks who is
--- calling, and false for `Core.PeekPlayer`, which a clock asks.
---
--- A request extends the session, and it is the only thing that may spend the refusal a finished
--- session leaves. A clock does neither: a session a clock kept alive never ran out, and a refusal
--- a clock spent let the next real request act as the wrong character. Once a session is over, a
--- clock is answered for the real character.
local function playerFor(src, request)
    local cid = heldBy(src, true, request)
    if cid then
        local held = Core.GetPlayerByCitizenId(cid)
        -- A target who dropped ends the session rather than silently handing back the staff
        -- member's own phone, which would be the worst possible failure: acting on your own
        -- account while believing you are on somebody else's.
        if held then return held end
        -- A request is refused right here. A clock leaves the refusal for the next request.
        if not request then
            endUnasked(src)
            return Core.GetPlayerReal(src)
        end
        AdminViewClose(src)
        return nil
    end

    -- The session ended a moment ago and the page has not caught up. Answering with the staff
    -- member's own character here is how a write lands on the wrong person, so this call gets
    -- nothing: the callback resolves an error, the phone says the session is over, and nobody's
    -- data is touched. One call, then their own phone is theirs again. A request only: see above.
    if request and justExpired(src) then return nil end

    return Core.GetPlayerReal(src)
end

-- Every callback asks this who is calling, so asking it IS the use, and it extends the session.
Core.GetPlayer = function(src) return playerFor(src, true) end

--- The same player for a clock: the held character while a session is open, the real one once
--- it is over. It never extends a session and never spends a refusal. Asked by the state tick's
--- call check (`hasBars` for a player on a call).
Core.PeekPlayer = function(src) return playerFor(src, false) end

--- Whether a player exists, for a clock: `Core.PeekPlayer`'s answer without building it.
---
--- The state tick asks this instead of building a player it throws away. While a session is open
--- it answers for the held character, as `Core.GetPlayer` would. Once the session is over - run out,
--- or the target gone - it answers for the real character and leaves the refusal where it is. It
--- used to spend it: two seconds after an unnoticed expiry the tick consumed the refusal, and the
--- message the staff member typed next was sent as their own character under a banner still
--- naming the target.
--- **The framework half is remembered for thirty seconds.** The state tick asks every two seconds
--- for every player, and on qb-core the answer crosses into another resource and serialises the
--- whole player object each time. Whether a character is loaded changes only on a load, a logout
--- or a drop: a load and a drop set it at once through `Bridge.SetHere`, and a logout is seen
--- within the thirty seconds. The admin view half below is NOT cached, so a session still ends at
--- the exact second the clock finds it over.
local frameworkHas = Core.HasPlayer
local hereOk, hereAt, HERE_TTL = {}, {}, 30

Core.HasPlayerReal = function(src)
    local key = tonumber(src)
    -- No usable source: nothing to remember, and a nil table key would raise.
    if not key then return frameworkHas(src) and true or false end
    src = key
    local now = os.time()
    local at = hereAt[src]
    if at and now - at < HERE_TTL then return hereOk[src] end
    local ok = frameworkHas(src) and true or false
    hereOk[src], hereAt[src] = ok, now
    return ok
end

--- `ok` true on a character load, nil on a drop.
function Bridge.SetHere(src, ok)
    src = tonumber(src)
    if not src then return end
    hereOk[src], hereAt[src] = ok, (ok ~= nil) and os.time() or nil
end

Core.HasPlayer = function(src)
    local cid = heldBy(src, true, false)
    if cid then
        if Core.GetPlayerByCitizenId(cid) then return true end
        endUnasked(src)
    end
    return Core.HasPlayerReal(src)
end

--- **The source a MONEY call should act on.**
---
--- `Core.GetPlayer` covers everything the phone reads through a player object - messages,
--- contacts, apps, metadata - because those all start from the object. Money does not: the
--- framework bridges take a SOURCE, so `Bridge.Banking.Balances(src)` and
--- `Bridge.RemoveMoney(src, ...)` were still answering for the staff member. Opening the Bank
--- app inside a session showed the staff member their own balance, and a transfer would have
--- moved their own money while the screen said somebody else's name.
---
--- So the money calls that mean "the caller's own account" ask this instead of using `src`
--- directly. It is a second choke point, and it is deliberately NOT a wrapper around
--- `Bridge.AddMoney`: a wrapper would also redirect money being paid TO a staff member who
--- happens to have a session open - a Bank Pro payment from somebody else, say - because a
--- wrapper cannot tell "this source is the caller" from "this source is the recipient". The
--- call sites can, so they are where the question is asked.
---
--- Returns `src` unchanged when no session is open, which is every ordinary call.
---
--- `fromClock` is for a caller on a timer, such as the bank balance poll: the same answer, but it
--- does not count as the staff member using the session. Requests leave it out and extend it.
function PhoneActingSource(src, fromClock)
    src = tonumber(src)
    local cid = heldBy(src, true, not fromClock)
    if not cid then return src end
    local held = Core.GetPlayerByCitizenId(cid)
    if held and held.source then return tonumber(held.source) or src end
    -- Same rule as above: a target who is gone ends the session rather than quietly letting
    -- the staff member act on their own account. A clock leaves the refusal for the next request.
    if fromClock then endUnasked(src) else AdminViewClose(src) end
    return src
end

-- ══════════════════════════════════════════════════════════════
-- Housekeeping
-- ══════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function()
    local src = source
    if Viewing[src] then AdminViewClose(src) end
    -- An expiry nobody was told about belongs to the player who left. Server ids are handed out
    -- again, and a marker left behind refused the first call of whoever was given this one next.
    Expired[src] = nil
    -- And any session held ON this player, by anybody.
    local cid = Core.GetPlayerReal and Core.GetPlayerReal(src)
    cid = cid and cid.citizenid
    if not cid then return end
    -- The staff member did not end these, so each leaves the refusal for their next request.
    for staff, v in pairs(Viewing) do
        if v.cid == cid then endUnasked(staff) end
    end
end)

--- The phone saying it has put away a handset that was showing a finished session.
---
--- client/admin.lua sends this after `v-phone:client:adminView` false has closed the phone. From
--- then on nothing on that screen can still be drawing the held character, so the refusal left for
--- the next request has done its job: kept, it would refuse the reopening of the phone instead.
--- A request sent before the close travels ahead of this on the same event channel, so it is
--- still refused. Ignored while a session is open, which is the only state it could be abused in.
RegisterNetEvent('v-phone:server:adminViewClosed', function()
    local src = tonumber(source)
    if src and not Viewing[src] then Expired[src] = nil end
end)

-- One sweep, rather than a timer per session.
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for staff, v in pairs(Viewing) do
            -- Run out with nobody noticing: the same refusal as any other unrequested end.
            if now >= v.expires then endUnasked(staff) end
        end
    end
end)

--- For another resource's own admin menu.
exports('AdminViewOpen', function(src, targetSrc) return AdminViewOpen(src, targetSrc) end)
exports('AdminViewClose', function(src) return AdminViewClose(src) end)
exports('AdminViewTarget', function(src) return AdminViewTarget(src) end)
