--[[
rollcall - the roll call and the pop order.

    the roll window   "Start your rolls", a timer, every "Dice roll! Name rolls ###!" recorded
    the pop order     highest roll first; edited by hand (add, move, remove), marked as people pop
    chat              a queue, one line every cfg.delay seconds (the game drops chat sent too fast)
--]]

require('common');
local chat  = require('chat');
local store = require('store');

local roll = {};
roll.session = nil;     -- while rolls are open: { length, ends, started, list, seen, n, warned }
roll.events  = {};      -- on_start()

local function cap(s)
    s = tostring(s or ''):gsub('[^%a]', '');
    if s == '' then return ''; end
    return s:sub(1, 1):upper() .. s:sub(2):lower();
end
roll.cap = cap;

function roll.say(t)  print(chat.header(addon.name):append(chat.message(t))); end
function roll.warn(t) print(chat.header(addon.name):append(chat.error(t))); end

function roll.my_name()
    local ok, n = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    end);
    if ok and n and n ~= '' then return cap(n); end
    return nil;
end

--------------------------------------------------------------------------------
-- Chat
--------------------------------------------------------------------------------
roll.CHANNELS = { { 'p', 'Party' }, { 'l', 'Linkshell' }, { 'l2', 'Linkshell 2' }, { 's', 'Say' }, { 'sh', 'Shout' } };
local CHANNEL_CMD = { p = '/p', l = '/l', l2 = '/l2', s = '/s', sh = '/sh' };

function roll.channel_name(ch)
    for _, c in ipairs(roll.CHANNELS) do if c[1] == ch then return c[2]; end end
    return '/' .. tostring(ch);
end

local queue, next_send = {}, 0;

--- Queues a line for the chat channel (Settings), or `channel` when given.
function roll.post(text, channel)
    local ch = channel or store.me.cfg.channel;
    text = (tostring(text):gsub('<', '('):gsub('>', ')'));   -- (no <t> style substitutions)
    queue[#queue + 1] = (CHANNEL_CMD[ch] or ('/' .. ch)) .. ' ' .. text;
end

function roll.queue_size() return #queue; end

--------------------------------------------------------------------------------
-- Sorting: highest roll first; a tie goes to whoever rolled first; no roll goes last
--------------------------------------------------------------------------------
local function sorted(list)
    local pos = {};
    for i, e in ipairs(list) do pos[e] = i; end
    table.sort(list, function (a, b)
        local ra, rb = a.roll or -1, b.roll or -1;
        if ra ~= rb then return ra > rb; end
        return (a.n or pos[a]) < (b.n or pos[b]);
    end);
    return list;
end

--------------------------------------------------------------------------------
-- The roll window
--------------------------------------------------------------------------------
function roll.left()
    if roll.session == nil then return 0; end
    return math.max(0, roll.session.ends - os.clock());
end

--- The rolls so far, sorted.
function roll.live()
    local c = {};
    for i, e in ipairs(roll.session and roll.session.list or {}) do c[i] = e; end
    return sorted(c);
end

--- What the window shows: the live rolls while the window is open, else the pop order.
function roll.list()
    if roll.session then return roll.live(); end
    return store.me.order;
end

function roll.start(sec)
    if roll.session then roll.warn('Rolls are already open.'); return false; end
    local cfg = store.me.cfg;
    sec = math.floor(tonumber(sec) or tonumber(cfg.duration) or 60);
    sec = math.max(5, math.min(600, sec));
    roll.session = { length = sec, ends = os.clock() + sec, started = os.time(), list = {}, seen = {}, n = 0, warned = {} };
    local m = tostring(cfg.start_msg or ''):gsub('%%d', tostring(sec));
    if m ~= '' then roll.post(m); end
    roll.say(('Recording /random for %d seconds.'):format(sec));
    if roll.events.on_start then pcall(roll.events.on_start); end
    return true;
end

function roll.close(silent)
    local s = roll.session;
    if s == nil then return; end
    roll.session = nil;
    local cfg = store.me.cfg;
    if not silent and (cfg.end_msg or '') ~= '' then roll.post(cfg.end_msg); end

    if #s.list == 0 then
        roll.say('Rolls closed: nobody rolled, so the pop order is unchanged.');
        return;
    end
    local order = {};
    for _, e in ipairs(sorted(s.list)) do order[#order + 1] = { name = e.name, roll = e.roll, pops = 0 }; end
    store.me.order, store.me.order_time, store.me.pop_log = order, s.started, {};
    local h = store.me.history;
    table.insert(h, 1, { time = s.started, list = store.copy(order) });
    while #h > store.HISTORY_MAX do table.remove(h); end
    store.save();
    store.append_log(s.started, order);
    roll.say(('Rolls closed: %d in the pop order.'):format(#order));
    if not silent and cfg.auto_post then roll.post_order(); end
end

function roll.cancel()
    if roll.session == nil then return; end
    roll.session = nil;
    roll.post('Roll call cancelled.');
    roll.say('Roll call cancelled; the pop order is unchanged.');
end

local function record(name, n)
    local s = roll.session;
    name = cap(name);
    if s == nil or name == '' then return; end
    local e = s.seen[name];
    if e then
        if store.me.cfg.first_only then
            roll.say(('Ignored a reroll from %s (%d); their first roll was %d.'):format(name, n, e.roll));
        else
            e.roll = n;
        end
        return;
    end
    s.n = s.n + 1;
    e = { name = name, roll = n, n = s.n };
    s.list[#s.list + 1] = e;
    s.seen[name] = e;
end

--- Incoming chat: FFXI prints "Dice roll! Name rolls 523!"
function roll.on_text(msg)
    if roll.session == nil then return; end
    local t = tostring(msg or ''):gsub('\x1E.', ''):gsub('\x1F.', ''):gsub('\x7F.', ''):gsub('%c', ' ');
    local name, n = t:match('Dice roll!%s*(%a+) rolls (%d+)');
    if name then record(name, tonumber(n)); end
end

--- Every frame: sends the next queued line, runs the timer.
function roll.tick()
    local now = os.clock();
    if #queue > 0 and now >= next_send then
        local line = table.remove(queue, 1);
        pcall(function() AshitaCore:GetChatManager():QueueCommand(1, line); end);
        next_send = now + math.max(1.0, tonumber(store.me.cfg.delay) or 2.0);
    end
    local s = roll.session;
    if s == nil then return; end
    local left = s.ends - now;
    if left <= 0 then
        roll.close(false);
    elseif store.me.cfg.countdown then
        for _, mark in ipairs({ 30, 10 }) do
            if left <= mark and s.length > mark + 2 and not s.warned[mark] then
                s.warned[mark] = true;
                roll.post(('%d seconds left to roll!'):format(mark));
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The pop order
--------------------------------------------------------------------------------
function roll.find(name)
    name = cap(name);
    for i, e in ipairs(roll.list()) do
        if e.name == name then return i, e; end
    end
    return nil;
end

--------------------------------------------------------------------------------
-- Pops: each person has a count; the order runs round and round until everyone
-- has popped `pops_each` times (Settings, or the - / + on the Pop Order page).
--------------------------------------------------------------------------------
function roll.goal()
    return math.max(1, math.floor(tonumber(store.me.cfg.pops_each) or 1));
end

function roll.set_goal(n)
    store.me.cfg.pops_each = math.max(1, math.min(99, math.floor(tonumber(n) or 1)));
    store.save();
end

function roll.pops(e) return math.max(0, math.floor(tonumber(e and e.pops) or 0)); end

--- Who is up: the fewest pops so far (under the goal), the highest in the order first.
function roll.current()
    local best, low = nil, roll.goal();
    for i, e in ipairs(store.me.order) do
        local p = roll.pops(e);
        if p < low then best, low = i, p; end
    end
    return best;
end

--- Who comes after `i` (the next one with the fewest pops, counting `i` as having popped).
function roll.on_deck(i)
    local o = store.me.order;
    if i == nil or o[i] == nil then return nil; end
    o[i].pops = roll.pops(o[i]) + 1;
    local n = roll.current();
    o[i].pops = o[i].pops - 1;
    if n == i then return nil; end
    return n;
end

--- Sets someone's pop count (0 and up).
function roll.set_pops(i, n)
    local e = store.me.order[i];
    if e == nil then return; end
    e.pops = math.max(0, math.floor(tonumber(n) or 0));
    store.save();
end

--- Adds someone. While rolls are open a roll is needed; else roll and spot are optional.
function roll.add(name, n, spot)
    name = cap(name);
    if name == '' then roll.warn('Type a name first.'); return false; end
    n = tonumber(n);
    if n then n = math.floor(n); if n < 0 then n = nil; end end

    local s = roll.session;
    if s then
        if n == nil then roll.warn('While rolls are open, add someone with their roll.'); return false; end
        local e = s.seen[name];
        if e then
            e.roll = n;
        else
            s.n = s.n + 1;
            e = { name = name, roll = n, n = s.n };
            s.list[#s.list + 1] = e;
            s.seen[name] = e;
        end
        roll.say(('Added %s (%d) to the rolls.'):format(name, n));
        return true;
    end

    local o = store.me.order;
    if roll.find(name) then roll.warn(name .. ' is already in the pop order.'); return false; end
    local e = { name = name, roll = n, pops = 0 };
    spot = tonumber(spot);
    if spot and spot >= 1 and spot <= #o then
        spot = math.floor(spot);
        table.insert(o, spot, e);
    else
        o[#o + 1] = e;
        spot = #o;
    end
    if (store.me.order_time or 0) == 0 then store.me.order_time = os.time(); end
    store.save();
    roll.say(('Added %s at #%d.'):format(name, spot));
    return true;
end

function roll.remove(i)
    local s = roll.session;
    if s then
        local e = roll.live()[i];
        if e == nil then return; end
        for k = #s.list, 1, -1 do if s.list[k] == e then table.remove(s.list, k); end end
        s.seen[e.name] = nil;
        return;
    end
    if store.me.order[i] then
        table.remove(store.me.order, i);
        store.save();
    end
end

--- Moves the person at spot i to spot `to` (the pop order only).
function roll.move(i, to)
    local o = store.me.order;
    if roll.session or o[i] == nil then return; end
    to = math.max(1, math.min(#o, math.floor(tonumber(to) or i)));
    if to == i then return; end
    local e = table.remove(o, i);
    table.insert(o, to, e);
    store.save();
end

local function all_done_text()
    local g = roll.goal();
    if g == 1 then return 'Everyone in the pop order has popped!'; end
    return ('Everyone in the pop order has popped %d times!'):format(g);
end
roll.all_done_text = all_done_text;

--- Posts who is up (and who is on deck).
function roll.call()
    local o = store.me.order;
    if #o == 0 then roll.warn('The pop order is empty.'); return; end
    local i = roll.current();
    if i == nil then roll.post(all_done_text()); return; end
    local m = ('Up to pop (#%d of %d): %s'):format(i, #o, o[i].name);
    if roll.goal() > 1 then m = m .. (' - pop %d of %d'):format(roll.pops(o[i]) + 1, roll.goal()); end
    local d = roll.on_deck(i);
    if d then m = m .. '  -  on deck: ' .. o[d].name; end
    roll.post(m);
end

--- Gives the person up one more pop, then (Settings) posts the next one.
function roll.next()
    local i = roll.current();
    if i == nil then roll.warn(all_done_text()); return; end
    local o = store.me.order;
    o[i].pops = roll.pops(o[i]) + 1;
    store.me.pop_log = store.me.pop_log or {};
    table.insert(store.me.pop_log, o[i].name);
    store.save();
    if store.me.cfg.call_next then roll.call(); end
end

--- Takes back the last pop given with Next.
function roll.back()
    local log = store.me.pop_log or {};
    while #log > 0 do
        local name = table.remove(log);
        for i, e in ipairs(store.me.order) do
            if e.name == name and roll.pops(e) > 0 then
                roll.set_pops(i, roll.pops(e) - 1);
                roll.say(('Took back a pop from %s (now %d).'):format(name, roll.pops(e)));
                return;
            end
        end
    end
    store.save();
    roll.warn('Nothing to take back.');
end

--- Posts the whole order (or `list`), packed a few names to a line.
function roll.post_order(channel, list)
    list = list or roll.list();
    if #list == 0 then roll.warn('The pop order is empty.'); return; end
    roll.post(('Pop order (%d):'):format(#list), channel);
    local line = '';
    for i, e in ipairs(list) do
        local piece = e.roll and ('%d.%s(%d)'):format(i, e.name, e.roll) or ('%d.%s'):format(i, e.name);
        if line ~= '' and #line + #piece + 1 > 95 then
            roll.post(line, channel);
            line = piece;
        else
            line = (line == '') and piece or (line .. ' ' .. piece);
        end
    end
    if line ~= '' then roll.post(line, channel); end
end

function roll.sort()
    if roll.session then return; end
    sorted(store.me.order);
    store.save();
end

function roll.reset()
    for _, e in ipairs(store.me.order) do e.pops = 0; end
    store.me.pop_log = {};
    store.save();
end

function roll.clear()
    store.me.order, store.me.order_time, store.me.pop_log = {}, 0, {};
    store.save();
end

--- Makes a past roll call the pop order again (every count back to 0).
function roll.use_history(h)
    local o = {};
    for _, e in ipairs(h.list or {}) do o[#o + 1] = { name = e.name, roll = e.roll, pops = 0 }; end
    store.me.order, store.me.order_time, store.me.pop_log = o, tonumber(h.time) or os.time(), {};
    store.save();
end

return roll;
