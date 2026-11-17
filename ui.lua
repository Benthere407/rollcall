--[[
rollcall - the window, in Vanacore's style (vcmenu).

    Pop Order   the roll window (timer, live rolls) and the pop order: call up, next, add, move, remove
    History     past roll calls: use one again, or post it
    Settings    chat channel, roll window, messages
    Help
--]]

require('common');
local imgui = require('imgui');
local vc    = require('vcmenu');
local store = require('store');
local roll  = require('roll');

local C = vc.colors;
local ui = {};

local win = vc.new_state('order');
ui.win = win;

local buf_name, buf_roll, buf_spot = { '' }, { '' }, { '' };
local buf_start, buf_end = { '' }, { '' };

local SEL_OVERLAP = ImGuiSelectableFlags_AllowOverlap or ImGuiSelectableFlags_AllowItemOverlap or 16;

local function z(n) return vc.z(n); end

local function save_scale(s)
    store.me.cfg.ui_scale = s;
    win.scale = s;
    store.save();
end

local function input(id, buf, w, hint, size)
    pcall(imgui.PushItemWidth, w and z(w) or -1);
    local ok, edited;
    if hint then ok, edited = pcall(imgui.InputTextWithHint, id, hint, buf, size or 64); end
    if not ok then ok, edited = pcall(imgui.InputText, id, buf, size or 64); end
    pcall(imgui.PopItemWidth);
    return ok and edited;
end

local function tip(t) if imgui.IsItemHovered() then imgui.SetTooltip(t); end end

local function big(text, col, px)
    if vc.has_fonts() then
        vc.in_font('bi', px or 30, function() imgui.TextColored(col or C.text, text); end);
    else
        pcall(imgui.SetWindowFontScale, 1.8 * vc.scale());
        imgui.TextColored(col or C.text, text);
        pcall(imgui.SetWindowFontScale, vc.scale());
    end
end

local function clock_text(sec)
    sec = math.max(0, math.ceil(sec));
    return ('%d:%02d'):format(math.floor(sec / 60), sec % 60);
end

--- A small icon button: 'up', 'down', 'minus', 'plus' or 'x'. Returns clicked (never while disabled).
local function glyph_button(id, kind, enabled, tiptext)
    local s = z(22);
    local x, y = vc.screen_pos();
    local hit = imgui.InvisibleButton('##gb' .. id, { s, s });
    local hov = imgui.IsItemHovered();
    pcall(function()
        local dl = imgui.GetWindowDrawList();
        if hov and enabled then dl:AddRectFilled({ x, y }, { x + s, y + s }, vc.u32({ 1, 1, 1, 0.08 }), z(4)); end
        local c;
        if not enabled then c = vc.alpha(C.mute, 0.35);
        elseif kind == 'x' then c = hov and C.bad or C.dim;
        else c = hov and C.text or C.acc; end
        c = vc.u32(c);
        local cx, cy, e = x + s / 2, y + s / 2, z(4.5);
        if kind == 'up' then
            dl:AddTriangleFilled({ cx, cy - e }, { cx + e, cy + e * 0.7 }, { cx - e, cy + e * 0.7 }, c);
        elseif kind == 'down' then
            dl:AddTriangleFilled({ cx - e, cy - e * 0.7 }, { cx + e, cy - e * 0.7 }, { cx, cy + e }, c);
        elseif kind == 'minus' or kind == 'plus' then   -- in a round frame, as a stepper
            dl:AddCircle({ cx, cy }, s / 2 - z(2), c, 16, 1.2);
            dl:AddLine({ cx - e * 0.8, cy }, { cx + e * 0.8, cy }, c, 1.6);
            if kind == 'plus' then dl:AddLine({ cx, cy - e * 0.8 }, { cx, cy + e * 0.8 }, c, 1.6); end
        else
            dl:AddLine({ cx - e, cy - e }, { cx + e, cy + e }, c, 1.5);
            dl:AddLine({ cx - e, cy + e }, { cx + e, cy - e }, c, 1.5);
        end
    end);
    if hov and enabled and tiptext then imgui.SetTooltip(tiptext); end
    return hit and enabled;
end

--------------------------------------------------------------------------------
-- Pop Order
--------------------------------------------------------------------------------
local function status_block()
    local cfg = store.me.cfg;
    local s = roll.session;
    if s then
        local left = roll.left();
        -- the countdown: 60, 59, 58 ... with Stop right beside it
        big(tostring(math.ceil(left)), left <= 10 and C.bad or C.gold, 34);
        imgui.SameLine(0, z(6));
        imgui.TextColored(C.dim, 'sec');
        imgui.SameLine(0, z(18));
        if vc.button('Stop', 'primary', 90) then roll.close(false); end
        tip('Stop the timer now and make these rolls the pop order');
        imgui.SameLine();
        if vc.button('Cancel', 'danger') then roll.cancel(); end
        tip('Stop without saving: the pop order stays as it was');
        imgui.SameLine(0, z(18));
        imgui.TextColored(C.dim, ('%d roll%s in'):format(#s.list, #s.list == 1 and '' or 's'));
        vc.progress(left / s.length);
        return;
    end

    local o = store.me.order;
    local i = roll.current();
    local goal = roll.goal();
    if #o == 0 then
        imgui.TextColored(C.dim, 'No pop order yet. Start rolls, or add people by hand below.');
    elseif i then
        local head = ('UP NEXT  -  #%d of %d'):format(i, #o);
        if goal > 1 then head = head .. ('  -  pop %d of %d'):format(roll.pops(o[i]) + 1, goal); end
        imgui.TextColored(C.mute, head);
        big(o[i].name, C.gold, 28);
        local d = roll.on_deck(i);
        if d then
            imgui.SameLine(0, z(16));
            imgui.TextColored(C.dim, 'on deck:');
            imgui.SameLine();
            imgui.TextColored(C.text, o[d].name);
        end
    else
        big(goal == 1 and 'Everyone has popped' or ('Everyone has popped %d times'):format(goal), C.good, 24);
    end
    imgui.Dummy({ 1, z(2) });

    if vc.button(('Start rolls (%ds)'):format(cfg.duration), 'primary') then roll.start(); end
    tip(('Posts "%s" in %s and records every /random for %d seconds'):format(
        tostring(cfg.start_msg):gsub('%%d', tostring(cfg.duration)), roll.channel_name(cfg.channel), cfg.duration));
    if #o > 0 then
        imgui.SameLine();
        if vc.button('Call up') then roll.call(); end
        tip('Posts who is up to pop, and who is on deck');
        imgui.SameLine();
        if vc.button('Next') then roll.next(); end
        tip(cfg.call_next and 'Gives the person up one pop and posts who is up next' or 'Gives the person up one pop');
        imgui.SameLine();
        if vc.button('Back') then roll.back(); end
        tip('Takes back the last pop given with Next');
    end

    -- pops each: the order goes round until everyone has this many
    imgui.SameLine(0, z(24));
    pcall(imgui.AlignTextToFramePadding);
    imgui.TextColored(C.dim, 'Pops each');
    imgui.SameLine(0, z(8));
    if glyph_button('goal-', 'minus', goal > 1, 'One less pop each') then roll.set_goal(goal - 1); end
    imgui.SameLine(0, z(6));
    imgui.TextColored(C.text, tostring(goal));
    imgui.SameLine(0, z(6));
    if glyph_button('goal+', 'plus', goal < 99, 'One more pop each') then roll.set_goal(goal + 1); end
end

local function add_row()
    local s = roll.session;
    vc.section('ADD SOMEONE');
    pcall(imgui.AlignTextToFramePadding);
    input('##rc_name', buf_name, 150, 'Name');
    imgui.SameLine();
    input('##rc_roll', buf_roll, 70, 'Roll');
    tip(s and 'Their roll (needed while rolls are open)' or 'Their roll (optional)');
    if not s then
        imgui.SameLine();
        input('##rc_spot', buf_spot, 60, 'Spot');
        tip('Where in the order: 1 is the top (blank = the bottom)');
    end
    imgui.SameLine();
    if vc.button('Add', 'primary') then
        if roll.add(buf_name[1], buf_roll[1], buf_spot[1]) then buf_name[1], buf_roll[1], buf_spot[1] = '', '', ''; end
    end
end

local COL = { num = 10, name = 42, roll = 196, pop = 250 };

local function order_list()
    local s = roll.session;
    local list = roll.list();
    local cur = (s == nil) and roll.current() or nil;
    vc.section(s and 'LIVE ROLLS' or 'POP ORDER', tostring(#list));

    local x0 = imgui.GetCursorPosX();
    imgui.SetCursorPosX(x0 + z(COL.num + 4)); imgui.TextColored(C.mute, '#');
    imgui.SameLine(x0 + z(COL.name + 4));     imgui.TextColored(C.mute, 'Name');
    imgui.SameLine(x0 + z(COL.roll + 4));     imgui.TextColored(C.mute, 'Roll');
    if s == nil then imgui.SameLine(x0 + z(COL.pop + 4)); imgui.TextColored(C.mute, 'Pops'); end
    local goal = roll.goal();

    local act = nil;   -- one edit per frame, applied after the list is drawn
    vc.list('##rc_order', 44, function ()
        local lx = imgui.GetCursorPosX();
        local w  = vc.avail_w();
        local rh = z(30);
        local fh = imgui.GetFontSize();
        local dl = imgui.GetWindowDrawList();
        for i, e in ipairs(list) do
            local y = imgui.GetCursorPosY();
            local sx, sy = vc.screen_pos();
            imgui.Selectable('##row' .. i, false, SEL_OVERLAP, { 0, rh });
            if i == cur then   -- the person up next: the accent row, as vc.row's selected
                pcall(function()
                    dl:AddRectFilled({ sx, sy + 1 }, { sx + w, sy + rh - 1 }, vc.u32(vc.alpha(C.acc, 0.13)), z(5), 0);
                    dl:AddRectFilled({ sx + 1, sy + z(6) }, { sx + z(4), sy + rh - z(6) }, vc.u32(C.acc), 1, 0);
                end);
            end
            local pops = (s == nil) and roll.pops(e) or 0;
            local done = (s == nil) and pops >= goal;
            local col = C.text;
            if done then col = C.mute; elseif i == cur or (s and i == 1) then col = C.gold; end
            local ty = y + (rh - fh) / 2;
            local function at(cx, t, c) imgui.SetCursorPos({ lx + z(cx), ty }); imgui.TextColored(c, t); end
            at(COL.num, tostring(i), done and C.mute or C.dim);
            at(COL.name, vc.fit_text(e.name, z(COL.roll - COL.name - 8)), col);
            at(COL.roll, e.roll and tostring(e.roll) or '-', done and C.mute or C.text);
            if s == nil then   -- the pop count: - n / goal +
                local by0 = y + (rh - z(22)) / 2;
                imgui.SetCursorPos({ lx + z(COL.pop), by0 });
                if glyph_button('pm' .. i, 'minus', pops > 0, 'One less pop for ' .. e.name) then act = { 'pops', i, pops - 1 }; end
                local txt = (goal > 1) and ('%d/%d'):format(pops, goal) or tostring(pops);
                local tw = vc.xy(imgui.CalcTextSize(txt));
                local mid = lx + z(COL.pop + 22 + 22);   -- centred between the two buttons
                imgui.SetCursorPos({ mid - tw / 2, ty });
                imgui.TextColored(done and C.good or (pops > 0 and C.text or C.mute), txt);
                imgui.SetCursorPos({ lx + z(COL.pop + 66), by0 });
                if glyph_button('pp' .. i, 'plus', pops < 99, 'One more pop for ' .. e.name) then act = { 'pops', i, pops + 1 }; end
            end

            local by = y + (rh - z(22)) / 2;
            local bx = lx + w - z(s and 30 or 82);
            if s == nil then
                imgui.SetCursorPos({ bx, by });
                if glyph_button('u' .. i, 'up', i > 1, 'Move up') then act = { 'move', i, i - 1 }; end
                imgui.SetCursorPos({ bx + z(26), by });
                if glyph_button('d' .. i, 'down', i < #list, 'Move down') then act = { 'move', i, i + 1 }; end
                bx = bx + z(52);
            end
            imgui.SetCursorPos({ bx, by });
            if glyph_button('x' .. i, 'x', true, 'Remove ' .. e.name) then act = { 'remove', i }; end
            imgui.SetCursorPos({ lx, y + rh });
        end
        if #list == 0 then
            imgui.SetCursorPos({ lx + z(10), imgui.GetCursorPosY() + z(8) });
            imgui.TextColored(C.mute, s and 'Waiting for rolls...' or 'Nobody in the pop order yet.');
        end
        imgui.Dummy({ 0, 0 });
    end);

    if act then
        if act[1] == 'move' then roll.move(act[2], act[3]);
        elseif act[1] == 'pops' then roll.set_pops(act[2], act[3]);
        elseif act[1] == 'remove' then roll.remove(act[2]); end
    end

    -- under the list
    imgui.Dummy({ 1, z(2) });
    if vc.button(s and 'Post rolls so far' or 'Post order') then roll.post_order(); end
    tip('Posts the whole list in ' .. roll.channel_name(store.me.cfg.channel));
    if s == nil and #list > 0 then
        imgui.SameLine();
        if vc.button('Sort by roll') then roll.sort(); end
        tip('Puts everyone back in roll order (highest first; no roll last)');
        imgui.SameLine();
        if vc.button('Reset pops') then roll.reset(); end
        tip('Puts everyone back to 0 pops, to run the order again');
        imgui.SameLine();
        if vc.button('Clear', 'danger') then imgui.OpenPopup('##rc_clear'); end
        tip('Empties the pop order');
    end
    if imgui.BeginPopup('##rc_clear') then
        imgui.Text('Empty the whole pop order?');
        if vc.button('Clear it', 'danger') then roll.clear(); imgui.CloseCurrentPopup(); end
        imgui.SameLine();
        if vc.button('Keep it') then imgui.CloseCurrentPopup(); end
        imgui.EndPopup();
    end
end

local function page_order()
    local sub;
    if roll.session then sub = 'rolls are open';
    elseif (store.me.order_time or 0) > 0 then sub = 'rolled ' .. os.date('%m/%d  %H:%M', store.me.order_time);
    end
    vc.title('Pop Order', sub);
    status_block();
    add_row();
    order_list();
end

--------------------------------------------------------------------------------
-- History
--------------------------------------------------------------------------------
local function page_history()
    local h = store.me.history;
    vc.title('History', ('the last %d roll calls'):format(store.HISTORY_MAX));
    if #h == 0 then
        vc.note('Every roll call you close is kept here. Use one to make it the pop order again.');
        return;
    end
    local del = nil;
    for k, rec in ipairs(h) do
        vc.section(os.date('%a %m/%d  %H:%M', tonumber(rec.time) or 0), ('%d rolls'):format(#(rec.list or {})));
        local parts = {};
        for i, e in ipairs(rec.list or {}) do
            parts[#parts + 1] = e.roll and ('%d. %s (%d)'):format(i, e.name, e.roll) or ('%d. %s'):format(i, e.name);
        end
        imgui.PushStyleColor(ImGuiCol_Text, C.dim);
        pcall(imgui.PushTextWrapPos, 0);
        imgui.Text(table.concat(parts, '     '));
        pcall(imgui.PopTextWrapPos);
        imgui.PopStyleColor(1);
        if vc.button('Use this order##hu' .. k) then roll.use_history(rec); win.page = 'order'; end
        tip('Makes this the pop order again (everyone at 0 pops)');
        imgui.SameLine();
        if vc.button('Post it##hp' .. k) then roll.post_order(nil, rec.list or {}); end
        tip('Posts this order in ' .. roll.channel_name(store.me.cfg.channel));
        imgui.SameLine();
        if vc.button('Delete##hd' .. k, 'danger') then del = k; end
    end
    if del then table.remove(h, del); store.save(); end
    imgui.Dummy({ 1, z(6) });
    vc.note('Every roll call is also written to config/addons/rollcall/roll_history.txt.');
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------
local function page_settings()
    local cfg = store.me.cfg;
    vc.title('Settings');
    local changed = false;

    vc.section('CHAT');
    vc.label_row('Post to', 360);
    local v = vc.seg('chan', roll.CHANNELS, cfg.channel);
    if v then cfg.channel = v; changed = true; end
    vc.label_row('Seconds between lines sent', 200);
    v = vc.slider('delay', cfg.delay, 1.0, 5.0, 0.5, '%.1f s', 150);
    if v then cfg.delay = v; changed = true; end
    vc.note('The game drops chat sent too fast, so long orders go out a line at a time.');

    vc.section('ROLL CALL');
    vc.label_row('Rolls stay open for', 200);
    v = vc.slider('dur', cfg.duration, 15, 180, 5, '%d s', 150);
    if v then cfg.duration = math.floor(v); changed = true; end
    v = vc.switch_row('countdown', 'Post "30 / 10 seconds left"', cfg.countdown);
    if v ~= nil then cfg.countdown = v; changed = true; end
    v = vc.switch_row('first', 'First roll only (rerolls are ignored)', cfg.first_only);
    if v ~= nil then cfg.first_only = v; changed = true; end
    v = vc.switch_row('autopost', 'Post the pop order when the rolls close', cfg.auto_post);
    if v ~= nil then cfg.auto_post = v; changed = true; end
    v = vc.switch_row('callnext', 'Next also posts who is up', cfg.call_next);
    if v ~= nil then cfg.call_next = v; changed = true; end
    vc.label_row('Pops each person gets', 200);
    v = vc.slider('popseach', roll.goal(), 1, 10, 1, '%d', 150);
    if v then cfg.pops_each = math.floor(v); changed = true; end

    vc.section('MESSAGES');
    vc.label_row('When rolls open', 330);
    if input('##start_msg', buf_start, 330, 'Start your rolls!', 120) then cfg.start_msg = buf_start[1]; changed = true; end
    vc.label_row('When rolls close', 330);
    if input('##end_msg', buf_end, 330, 'Rolls are closed!', 120) then cfg.end_msg = buf_end[1]; changed = true; end
    vc.note('%d in the opening message becomes the number of seconds. Leave a message empty to post nothing.');

    if changed then store.save(); end
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------
local function page_help()
    vc.title('Roll Call', 'help');
    vc.section('RUNNING A ROLL CALL');
    vc.note('1. Start rolls posts "Start your rolls!" in party (Settings) and records every /random for 60 seconds.');
    vc.note('2. When time runs out (or Close rolls now), the rolls become the pop order, highest first. A tie goes to whoever rolled first.');
    vc.note('3. Post order puts the whole order in chat.');
    vc.section('POPPING');
    vc.note('Call up posts who is up and who is on deck. Next gives them a pop and posts the next person. Back takes that pop back.');
    vc.note('Pops each (- / +) is how many pops everyone gets. The order goes round: whoever has the fewest pops is up next, top of the order first, until everyone has that many.');
    vc.note('The - / + in the Pops column change anyone\'s count by hand. The arrows move people up or down, and x removes them.');
    vc.note('Add someone puts a name in the order; Spot picks where (1 = top), blank adds them at the bottom.');
    vc.section('COMMANDS');
    local W = 190;
    vc.stat('/rc  or  /rollcall', 'open / close this window', C.text, W);
    vc.stat('/rc start [sec]', 'open rolls (stop, cancel to end early)', C.text, W);
    vc.stat('/rc post [p|l|l2|s|sh]', 'post the order', C.text, W);
    vc.stat('/rc call | next | back', 'who is up | give a pop, call next | undo', C.text, W);
    vc.stat('/rc pops <n>', 'pops each person gets', C.text, W);
    vc.stat('/rc count <name> <n>', 'set someone\'s pop count', C.text, W);
    vc.stat('/rc add <name> [roll] [spot]', 'add someone', C.text, W);
    vc.stat('/rc remove <name>', 'take someone out', C.text, W);
    vc.stat('/rc move <name> <spot>', 'move someone', C.text, W);
    vc.stat('/rc sort | reset | clear', 'by roll | un-pop everyone | empty', C.text, W);
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local PAGES = { order = page_order, history = page_history, settings = page_settings, help = page_help };
local SUB = { order = 'Pop order', history = 'History', settings = 'Settings', help = 'Help' };

local function sidebar(nav)
    nav.caption('ROLL CALL');
    if nav.head('list', 'Pop Order', win.page == 'order') then win.page = 'order'; end
    nav.tip('Open rolls and run the pop order');
    if nav.head('files', 'History', win.page == 'history') then win.page = 'history'; end
    nav.tip('Past roll calls');
    nav.gap(8);
    if nav.head('gear', 'Settings', win.page == 'settings') then win.page = 'settings'; end
    if nav.head('about', 'Help', win.page == 'help') then win.page = 'help'; end
end

function ui.init()
    local cfg = store.me.cfg;
    win.scale = tonumber(cfg.ui_scale) or 1;
    buf_start[1] = tostring(cfg.start_msg or '');
    buf_end[1]   = tostring(cfg.end_msg or '');
    roll.events.on_start = function () win.open[1] = true; win.page = 'order'; end
end

function ui.toggle(page)
    if page then win.page = page; win.open[1] = true; return; end
    win.open[1] = not win.open[1];
end

function ui.render()
    if store.me == nil then return; end
    vc.window(win, {
        id = 'rollcall', title = 'Roll Call', size = { 780, 640 }, min = { 700, 480 },
        pages = PAGES, scaler = true, on_scale = save_scale,
        subtitle = function (page) return SUB[page]; end,
        header_right = function ()
            if roll.session then return ('Rolls open  %d s'):format(math.ceil(roll.left())), C.gold; end
            local i = roll.current();
            if i then return 'Up next: ' .. store.me.order[i].name, C.acc; end
            return '', nil;
        end,
        sidebar = sidebar,
    });
end

return ui;
