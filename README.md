# rollcall

Roll call for a pop order, in Vanacore-style windows (vcmenu).

- **Start rolls** posts *"Start your rolls! You have 60 seconds."* in party and records every `/random`
  (`Dice roll! Name rolls 523!`) until the timer runs out.
- The rolls become the **pop order**, highest first (a tie goes to whoever rolled first). It is saved, and every
  roll call is kept on the **History** page.
- **Post order** puts the order in party; **Call up** / **Next** call people up as they pop.
- Add people by hand, move them up or down, mark them popped, or take them out.

    /addon load rollcall
    /rc               open the window      (/rollcall works too)

## Pop Order

1. **Start rolls** opens the roll window (60 s by default; Settings). The window shows the time left and the live
   rolls, highest first. With the countdown on it posts "30 seconds left" and "10 seconds left".
   **Close rolls now** ends it early; **Cancel** ends it without changing the pop order.
2. When the rolls close, the order is saved (per character). If nobody rolled, the old order stays.
3. **Pops each** (the − / + beside the buttons, or Settings) is how many pops everyone gets. The order goes
   round: whoever has the fewest pops is up next, top of the order first, until everyone has that many.
4. **Up next** (gold, with the accent bar in the list) shows who is up, with who is on deck.
   - **Call up** posts `Up to pop (#2 of 8): Name - on deck: Name` (with `- pop 2 of 3` when pops each is over 1).
   - **Next** gives them one pop and, with "Next also posts who is up" on, posts the next person.
   - **Back** takes back the last pop given with Next.
5. In the list: the **Pops** column has − / + to change anyone's count by hand (green once they have all their
   pops), the **arrows** move people up or down, and **x** removes them.
6. **Add someone**: a name, a roll (optional) and a spot (optional: 1 = the top; blank = the bottom).
   While rolls are open, a roll is needed and they go in by roll.
7. **Post order**, **Sort by roll** (puts it back in roll order), **Reset pops** (everyone back to 0), **Clear**.

## History

The last 25 roll calls: **Use this order** makes one the pop order again; **Post it** posts it; **Delete**.
Every roll call is also written to `config/addons/rollcall/roll_history.txt`.

## Settings

Chat channel (Party, Linkshell, Linkshell 2, Say, Shout), seconds between lines, how long rolls stay open,
the countdown, first roll only (rerolls are ignored), post the order when rolls close, Next posts who is up,
and the opening / closing messages (`%d` = the seconds).

## Commands

    /rc start [sec]                 open rolls          /rc stop | cancel
    /rc post [p|l|l2|s|sh]          post the order
    /rc call | next | back          who is up | give a pop and call next | undo
    /rc pops <n>                    pops each person gets
    /rc count <name> <n>            set someone's pop count
    /rc add <name> [roll] [spot]    add someone
    /rc remove <name>               take someone out
    /rc move <name> <spot>          move someone
    /rc sort | reset | clear        by roll | un-pop everyone | empty
    /rc history | settings          open a page

Saved in `config/addons/rollcall/<Character>.json` (settings, pop order, history).
