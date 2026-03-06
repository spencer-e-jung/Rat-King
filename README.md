<p align="center">
    <img src="./Images/Rat King.png" width="300px">
</p>

# Rat King

At first glance what this script doesn't seem particularly powerful, it does two things:

1. Allows the user to warp the cursor to the center of different zones, activating the snapped window directly under the cursor (by default by pressing Win-Shift-\<number\>).
3. Moves all resizeable windows activated into the zone containing the cursor by default (toggleable on a per window basis with Win-Shift-F, or preventable by Ctrl-\<mouse-button\>).

However, it instantly, and dramatically reduces the amount of window management involved in running Microsoft Windows. With practice and mindfulness it can give a productivity boost, and encourage a more elegant arrangement of windows.

# Requirements

To use this script effectively you must:
1. Install [Microsoft PowerToys](https://learn.microsoft.com/en-us/windows/powertoys/).
2. Configure at least one custom layouts using the FancyZones editor (ideally several bound to Win-Ctrl-Alt-\<number\>).
3. Optionally turn on the Move windows based on Relative postion in the settings (to move windows between zones with Win-<arrow>).
4. Run the script with AutoHotkey v2 64bit.

# Tip

Compile using ahk2exe.
To run for administrator windows run as administrator.

To run automatically go to:

1. Task Scheduler -> Action -> Create Task
2. Input the Location and Name of the script
3. Run with highest privileges -> On (if you want the warp to also work for windows run as administrator.)
4. Trigger -> New... -> On Workstation Unlock
5. Settings -> Stop the task if runs for longer than. -> Off
6. Ok
