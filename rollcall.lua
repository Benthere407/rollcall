addon.name    = 'rollcall';
addon.author  = 'Benthere';
addon.version = '1.0.0';
addon.desc    = 'Roll call for a pop order: "Start your rolls", a timer, every /random recorded highest first, then call people up as they pop.';

require('common');
local chat  = require('chat');
local store = require('store');
local roll  = require('roll');
local ui    = require('ui');

local ready = false;      -- the character's file is loaded

local function try_ready()
    if ready then return true; end
    local name = roll.my_name();
    if name == nil then return false; end
    if store.load_char(name) then
        ui.init();
        ready = true;
    end
    return ready;
end

ashita.events.register('load', 'rollcall_load', function ()
    try_ready();
end);

ashita.events.register('unload', 'rollcall_unload', function ()
    if ready then
        if roll.session then roll.close(true); end
        store.save();
    end
end);

ashita.events.register('d3d_present', 'rollcall_present', function ()
    if not try_ready() then return; end
    roll.tick();
    ui.render();
end);

ashita.events.register('text_in', 'rollcall_text_in', function (e)
    if not ready or e.injected then return; end
    local ok, err = pcall(roll.on_text, e.message);
    if not ok then print(chat.header('rollcall'):append(chat.error(tostring(err)))); end
end);

local function help()
    roll.say('/rc  - open the window.   /rc start [sec]  - open rolls.   /rc stop | cancel   /rc post [p|l|l2|s|sh]');
    roll.say('/rc call | next | back   /rc pops <n>   /rc count <name> <n>   /rc add <name> [roll] [spot]   /rc remove <name>   /rc move <name> <spot>   /rc sort | reset | clear');
end

ashita.events.register('command', 'rollcall_command', function (e)
    local args = e.command:args();
    if #args == 0 then return; end
    local c = args[1]:lower();
    if c ~= '/rollcall' and c ~= '/rc' then return; end
    e.blocked = true;
    if not try_ready() then roll.warn('Not logged in yet.'); return; end

    local sub = (args[2] or ''):lower();
    if sub == '' then
        ui.toggle();
    elseif sub == 'help' then
        help();
    elseif sub == 'start' or sub == 'go' then
        roll.start(args[3]);
    elseif sub == 'stop' or sub == 'close' then
        if roll.session then roll.close(false); else roll.warn('Rolls are not open.'); end
    elseif sub == 'cancel' then
        roll.cancel();
    elseif sub == 'post' or sub == 'say' then
        local ch = args[3] and (args[3]:lower():gsub('^/', '')) or nil;
        roll.post_order(ch);
    elseif sub == 'call' then
        roll.call();
    elseif sub == 'next' then
        roll.next();
    elseif sub == 'back' then
        roll.back();
    elseif sub == 'add' then
        if args[3] == nil then roll.warn('/rc add <name> [roll] [spot]'); return; end
        roll.add(args[3], args[4], args[5]);
    elseif sub == 'remove' or sub == 'del' then
        local i, e2 = roll.find(args[3] or '');
        if i then roll.remove(i); roll.say('Removed ' .. e2.name .. '.'); else roll.warn('Not in the list: ' .. tostring(args[3])); end
    elseif sub == 'move' then
        local i, e2 = roll.find(args[3] or '');
        local to = tonumber(args[4]);
        if roll.session then roll.warn('Move people once the rolls close.');
        elseif i and to then roll.move(i, to); roll.say(('Moved %s to #%d.'):format(e2.name, math.max(1, math.min(#store.me.order, to))));
        else roll.warn('/rc move <name> <spot>'); end
    elseif sub == 'sort' then
        roll.sort();
    elseif sub == 'reset' then
        roll.reset(); roll.say('Everyone is back to 0 pops.');
    elseif sub == 'pops' then
        if args[3] then roll.set_goal(args[3]); end
        roll.say(('Pops each: %d'):format(roll.goal()));
    elseif sub == 'count' then
        local i, e2 = roll.find(args[3] or '');
        local n = tonumber(args[4]);
        if roll.session then roll.warn('Set pop counts once the rolls close.');
        elseif i and n then roll.set_pops(i, n); roll.say(('%s: %d pop(s).'):format(e2.name, roll.pops(e2)));
        else roll.warn('/rc count <name> <number>'); end
    elseif sub == 'clear' then
        roll.clear(); roll.say('Pop order cleared.');
    elseif sub == 'history' then
        ui.toggle('history');
    elseif sub == 'settings' then
        ui.toggle('settings');
    else
        help();
    end
end);
