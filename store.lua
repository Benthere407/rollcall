--[[
rollcall - saving and loading.

    config/addons/rollcall/<Character>.json    settings, the current pop order and past roll calls
    config/addons/rollcall/roll_history.txt    every closed roll call, as plain text
--]]

require('common');
local json = require('json');

local store = {};

store.HISTORY_MAX = 25;     -- roll calls kept on the History page

local function dir()
    return ('%s\\config\\addons\\rollcall\\'):format(AshitaCore:GetInstallPath());
end

local function read_json(path)
    local f = io.open(path, 'rb');
    if f == nil then return nil; end
    local s = f:read('*a');
    f:close();
    local ok, v = pcall(json.decode, s);
    if ok and type(v) == 'table' then return v; end
    print(('[rollcall] Could not read %s - starting fresh.'):format(path));
    return nil;
end

local function write_json(path, v)
    local ok, s = pcall(json.encode, v);
    if not ok then
        print('[rollcall] Could not save: ' .. tostring(s));
        return false;
    end
    local f = io.open(path, 'wb');
    if f == nil then return false; end
    f:write(s);
    f:close();
    return true;
end

local function deep_copy(t)
    if type(t) ~= 'table' then return t; end
    local o = {};
    for k, v in pairs(t) do o[k] = deep_copy(v); end
    return o;
end
store.copy = deep_copy;

-- Fills missing keys of `t` from `defaults`.
local function merge(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = deep_copy(v); end
    end
    return t;
end

store.DEFAULT_CFG = {
    channel    = 'p',       -- where the addon posts: p party, l linkshell, l2 linkshell 2, s say, sh shout
    delay      = 2.0,       -- seconds between lines the addon sends (chat spam filter)
    duration   = 60,        -- seconds the roll window stays open
    start_msg  = 'Start your rolls! You have %d seconds.',   -- %d = the seconds
    end_msg    = 'Rolls are closed!',
    countdown  = true,      -- post 30 / 10 seconds left
    first_only = true,      -- ignore rerolls (the first roll counts)
    auto_post  = false,     -- post the pop order when the rolls close
    call_next  = true,      -- Next also posts who is up
    pops_each  = 1,         -- how many pops each person gets; the order goes round until everyone has them
    ui_scale   = 1,
};

store.char = nil;   -- the character this was loaded for
store.me   = nil;   -- { cfg, order = { { name, roll, pops } }, order_time, pop_log, history = { { time, list } } }

function store.ensure_dir()
    local d = dir();
    if not ashita.fs.exists(d) then ashita.fs.create_dir(d); end
end

--- Loads the per-character file. Returns true once a character is known.
function store.load_char(name)
    if name == nil or name == '' then return false; end
    store.ensure_dir();
    local me = read_json(dir() .. name .. '.json') or {};
    me.cfg        = merge(type(me.cfg) == 'table' and me.cfg or {}, store.DEFAULT_CFG);
    me.order      = type(me.order) == 'table' and me.order or {};
    me.history    = type(me.history) == 'table' and me.history or {};
    me.order_time = tonumber(me.order_time) or 0;
    me.pop_log    = type(me.pop_log) == 'table' and me.pop_log or {};   -- names given a pop by Next (for Back)
    for _, e in ipairs(me.order) do     -- older files: popped yes/no -> a pop count
        if e.pops == nil then e.pops = e.done and 1 or 0; end
        e.done = nil;
    end
    store.char = name;
    store.me = me;
    return true;
end

function store.save()
    if store.char == nil or store.me == nil then return; end
    store.ensure_dir();
    write_json(dir() .. store.char .. '.json', store.me);
end

--- Appends a closed roll call to roll_history.txt.
function store.append_log(time, list)
    pcall(function()
        store.ensure_dir();
        local f = io.open(dir() .. 'roll_history.txt', 'a');
        if f == nil then return; end
        f:write(('=== %s  (%d rolls) ===\n'):format(os.date('%Y-%m-%d %H:%M:%S', time), #list));
        for i, e in ipairs(list) do
            f:write(('%2d. %-16s %s\n'):format(i, e.name, e.roll and tostring(e.roll) or '-'));
        end
        f:write('\n');
        f:close();
    end);
end

return store;
