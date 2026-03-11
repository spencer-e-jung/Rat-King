#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include <JXON_ahk2/_JXON>

global fancyZonesPath := EnvGet("LOCALAPPDATA") "\Microsoft\PowerToys\FancyZones"
global appliedLayoutsFile := fancyZonesPath "\applied-layouts.json"
global customLayoutsFile := fancyZonesPath "\custom-layouts.json"
global settingsFile := fancyZonesPath "\settings.json"

global lastMouseCtrlClickTime := 0
global lastActiveWindow := 0
global floatWindows := Map()

global appliedLayout := {}
global customLayouts := {}
global settings := {}

DllCall("RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
global msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
OnMessage(msgNum, OnShellMessage)

CoordMode("Mouse", "Screen")

if (!FileExist(customLayoutsFile)) {
    MsgBox("FancyZones' custom-layout.json not found in LOCALAPPDATA.")
    return
}

if (!FileExist(appliedLayoutsFile)) {
    MsgBox("FancyZones' applied-layout.json not found in LOCALAPPDATA.")
    return
}

if (!FileExist(settingsFile)) {
    MsgBox("FancyZones' settings.json not found in LOCALAPPDATA.")
    return
}

; XXX: We call loadLayouts() without caching on every call to getZoneRect()
LoadLayouts() {
    global appliedLayout, customLayouts, settings

    appliedLayoutFileContents := FileRead(appliedLayoutsFile, "UTF-8")
    customLayoutsFileContents := FileRead(customLayoutsFile, "UTF-8")
    settingsFileContents := FileRead(settingsFile, "UTF-8")

    appliedLayout := Jxon_Load(&appliedLayoutFileContents)
    customLayouts := Jxon_Load(&customLayoutsFileContents)
    settings := Jxon_Load(&settingsFileContents)
}

; XXX: Initial load to get settings.
LoadLayouts()

OnShellMessage(wParam, lParam, msg, hwnd) {
    global lastActiveWindow, floatWindows

    static HSHELL_WINDOWDESTROY := 2
    static HSHELL_WINDOWACTIVATED := 4
    static HSHELL_RUDEAPPACTIVATED := 32772

    if (wParam == HSHELL_WINDOWDESTROY) {
        if (floatWindows.Has(lParam))
            floatWindows.Delete(lParam)
        return
    }

    if (wParam != HSHELL_WINDOWACTIVATED && wParam != HSHELL_RUDEAPPACTIVATED)
        return

    if (!lParam || !WinExist("ahk_id " lParam))
        return

    if (lParam == lastActiveWindow)
       return

    lastDeleted := !WinExist("ahk_id " lastActiveWindow)
    lastMinimized := WinExist("ahk_id " lastActiveWindow) &&
        WinGetMinMax("ahk_id " lastActiveWindow) == -1
    
    ; XXX: Some windows receive HSHELL_WINDOWACTIVATED but never activate. This
    ; includes minimization animations.
    if (WinWaitActive("ahk_id " lParam, , 1))
        lastActiveWindow := lParam

    if (lastMinimized || lastDeleted)
        return
    
    if (A_TickCount - lastMouseCtrlClickTime <= 500)
        return
    
    if (!IsWindowProcessable(lParam))
        return

    for (window in floatWindows)
        if (window == lParam)
            return

    SnapWindowToCursorZone(lParam)
}

CursorInRect(rect, mx, my) {
    return (
        rect.x <= mx && rect.x + rect.w >= mx &&
        rect.y <= my && rect.y + rect.h >= my
    )
}

; XXX: A reimplementation of FancyZonesWindowProcessing::DefineWindowType
; from FancyZoneLib/FancyZonesWindowProcessing.cpp
IsWindowProcessable(hwnd) {
    global settings
    static WS_VISIBLE := 0x10000000
    static WS_EX_TOOLWINDOW := 0x00000080
    static WS_POPUP := 0x800000
    static WS_THICKFRAME := 0x00040000
    static WS_CAPTION := 0x00C00000
    static WS_MINIMIZEBOX := 0x00010000
    static WS_MAXIMIZEBOX := 0x00020000

    if (WinGetMinMax("ahk_id " hwnd) == -1)
       return false
    
    style := WinGetStyle("ahk_id " hwnd)
    exStyle := WinGetExStyle("ahk_id " hwnd)

    if (!(style & WS_VISIBLE))
        return false
    
    if (exStyle & WS_EX_TOOLWINDOW)
        return false

    if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", GA_ROOT := 2) != hwnd)
        return false
    
    allowPopupSnap := settings["properties"]["fancyzones_allowPopupWindowSnap"]["value"]
    isPopup := (style & WS_POPUP) != 0
    hasThickFrame := (style & WS_THICKFRAME) != 0
    hasCaption := (style & WS_CAPTION) != 0
    hasMinMaxButtons := (style & WS_MINIMIZEBOX) != 0 || (style & WS_MAXIMIZEBOX) != 0

    if (isPopup && !(hasThickFrame && (hasCaption || hasMinMaxButtons))) {
        if (!allowPopupSnap)
            return false
    }

    ownerHwnd := DllCall("GetWindow", "Ptr", hwnd, "UInt", GW_OWNER := 4)
    allowChildSnap := settings["properties"]["fancyzones_allowChildWindowSnap"]["value"]
    if (ownerHwnd && !allowChildSnap)
        return false

    processName := WinGetProcessName("ahk_id " hwnd)
    processName := StrLower(processName)
    excludedApps := settings["properties"]["fancyzones_excluded_apps"]["value"]
    for (_, excludedApp in StrSplit(excludedApps, "`r"))
        if (StrLower(excludedApp) == processName)
            return false

    if (IsExcludedByDefault(hwnd))
        return false
    
    ; XXX: Switch between virtual desktops results with posting same windows
    ; messages that also indicate creation of new window. However it shouldn't
    ; be neccessary to check as we only snap if the window is WaitActive in
    ; SnapWindowToCursorZone.
    
    ; if (!IsWindowOnCurrentDesktop(hwnd))
    ;     return false

    return true
}

; XXX: A reimplementation of FancyZonesWindowUtils::IsExcludedByDefault from
; FancyZonesLib/WindowUtils.cpp
IsExcludedByDefault(hwnd) {
    processPath := WinGetProcessPath("ahk_id " hwnd)
    if (!processPath)
        return false

    if (InStr(StrUpper(processPath), "SYSTEMAPPS"))
        return true

    className := WinGetClass("ahk_id " hwnd)
    if (!className)
        return false

    if (IsSystemWindow(hwnd, className) || className == "MsoSplash")
        return true

    processName := WinGetProcessName("ahk_id " hwnd)
    processNameUpper := StrUpper(processName)

    defaultExcludedApps := [
        "WINDOWS.UI.CORE.COREWINDOW",
        "SEARCHUI.EXE",
        "POWERTOYS.FANCYZONESEDITOR.EXE",
    ]

    if (CheckExcludedApp(hwnd, defaultExcludedApps))
        return true

    return false
}

; XXX: A reimplementation of check_excluded_app from
; PowerToys/src/common/utils/excluded_apps.h
CheckExcludedApp(hwnd, excludedApps) {
    processPath := WinGetProcessPath("ahk_id " hwnd)
    if (!processPath)
        return false

    processPathUpper := StrUpper(processPath)

    if (FindAppNameInPath(processPathUpper, excludedApps))
        return true

    if (CheckExcludedAppWithTitle(hwnd, excludedApps))
        return true

    return false
}

; XXX: A reimplementation of find_app_name_in_path from
; PowerToys/src/common/utils/excluded_apps.h
FindAppNameInPath(where, what) {
    for (_, app in what) {
        position := InStr(where, app, , -1)
        if (position) {
            lastBackslash := InStr(where, "\", , -1)
            if (position <= lastBackslash + 1 && 
                position + StrLen(app) > lastBackslash)
                return true
        }
    }
    return false
}

; XXX: A reimplementation of check_excluded_app_with_title from
; PowerToys/src/common/utils/excluded_apps.h
CheckExcludedAppWithTitle(hwnd, excludedApps) {
    title := WinGetTitle("ahk_id " hwnd)
    if (!title)
        return false

    titleUpper := StrUpper(title)

    for _, app in excludedApps {
        if (InStr(titleUpper, app))
            return true
    }

    return false
}

; XXX: A reimplementation of is_system_window from
; PowerToys/src/common/utils/window.h
IsSystemWindow(hwnd, className) {
    static systemClasses := [
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "SysListView32"
    ]

    desktopWnd := DllCall("GetDesktopWindow", "Ptr")
    shellWnd := DllCall("GetShellWindow", "Ptr")

    if (hwnd == desktopWnd || hwnd == shellWnd)
        return true

    for (_, sysClass in systemClasses) {
        if (className == sysClass)
            return true
    }

    return false
}

; XXX: This function does not presently include zones that stretched over.
GetZoneIndices(hwnd) {
    PropName := "FancyZones_zones"

    mask := DllCall("GetPropW", "Ptr", hwnd, "Str", PropName, "UPtr")
    zones := []

    if (mask) {
        i := 0
        while(i <= 63) {
            if (mask & (1 << i))
                zones.Push(i + 1)
            i++
        }
    }

    return zones
}

SnapWindowToCursorZone(hwnd) {
    zoneIndexAndRect := CurrentMouseZoneIndexRect()
    windowZones := GetZoneIndices(hwnd)

    if (!zoneIndexAndRect)
        return

    for (, windowZone in windowZones) {
        if (windowZone == zoneIndexAndRect.index)
            return
    }

    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    zx := zoneIndexAndRect.rect.x + zoneIndexAndRect.rect.w // 2
    zy := zoneIndexAndRect.rect.y + zoneIndexAndRect.rect.h // 2
    newX := zx - ww // 2 + 10
    newY := zy - wh // 2
    WinSetTransparent(0, "ahk_id " hwnd)
    ; XXX: We can't do a ControlSend() because it's not the hwnd that snaps to
    ; the zone. This introduces the possibility for glitches when rapidly
    ; minimizing and restoring an application.
    if (WinWaitActive("ahk_id " hwnd, , 1)) {
        WinMove(newX, newY, , , "ahk_id " hwnd)
        Send("#{Left}")
    }
    WinSetTransparent(255, "ahk_id " hwnd)
}

; XXX: Can return NULL.
CurrentMouseZoneIndexRect() {
    zoneRects := GetZoneRects()

    if (!zoneRects)
        return

    MouseGetPos(&mx, &my)

    for (index, rect in zoneRects) {
        if (CursorInRect(rect, mx, my))
            return {index: index, rect: rect}
    }
}

CursorToZone(zoneNum) {
    zoneRects := GetZoneRects()

    if (!zoneRects || zoneRects.Length < zoneNum)
        return

    zoneRect := zoneRects[zoneNum]
    MouseMove(zoneRect.x + zoneRect.w // 2, zoneRect.y + zoneRect.h // 2, 0)
    MouseGetPos(, , &hwnd)

    if (hwnd) {
        windowZones := GetZoneIndices(hwnd)
        for (windowZone in windowZones) {
            if (windowZone == zoneNum)
                WinActivate("ahk_id " hwnd)
        }
    }
}

GetMouseMonitor() {
    MouseGetPos(&mx, &my)

    monitorCount := MonitorGetCount()

    i := 1
    while (i <= monitorCount){
        MonitorGet(i, &left, &top, &right, &bottom)
        rect := {x: left, y: top, w: right - left, h: bottom - top}
        if (CursorInRect(rect, mx, my)) {
            return i
        }
        i++
    }
}

FindMatchSavePart(source, query, part) {
    for (, matcher in source) {
        if (query(matcher))
            return part(matcher)
    }
}

GetCurrentDesktopUUID() {
    ; XXX: IVirtualDesktop COM
    static CLSID := "{AA509086-5CA9-4C25-8F95-589D3C07B48A}"
    static IID := "{A5CD92FF-29BE-454C-8D04-D82879FB3F1B}"

    obj := ComObject(CLSID, IID)

    ; XXX: first ptr is a vtable.
    vtable := NumGet(obj.Ptr, "Ptr")

    ; XXX: GetWindowDesktopId is the forth function in the vtable.
    functionPointer := NumGet(vtable, 4 * A_PtrSize, "Ptr")

    hwnd := WinExist("A")

    if (!hwnd)
        return

    guid := Buffer(16)
    DllCall(functionPointer, "ptr", obj.Ptr, "ptr", hwnd, "ptr", guid, "cdecl")

    buf := Buffer(78)
    DllCall("ole32\StringFromGUID2", "ptr", guid, "ptr", buf, "int", 39)

    return StrGet(buf, "UTF-16")
}

GetLayoutUUID(monitorNumber, currentVirtualDesktop) {
    global appliedLayout
    
    return FindMatchSavePart(
        appliedLayout["applied-layouts"]
        , (matcher) => matcher["device"]["monitor-number"] == monitorNumber &&
            matcher["device"]["virtual-desktop"] == currentVirtualDesktop
        , (matcher) => matcher["applied-layout"]["uuid"]
    )
}

GetLayout(layoutUUID) {
    global customLayouts

    return FindMatchSavePart(
        customLayouts["custom-layouts"]
        , (matcher) => matcher["uuid"] == layoutUUID
        , (matcher) => matcher
    )
}

GetPositionArray(pct, start, monitorInDirection) {
    position := [start]
    pixels := start
    
    for (, pct in pct) {
        pixels += Round(monitorInDirection * pct / 10000)
        position.Push(pixels)
    }

    return position
}

InitializeZoneRects(cellMap) {
    seen := Map()
    zoneRects := []

    for (, row in cellMap) {
        for (, zone in row) {
            if (!seen.Has(zone))
                zoneRects.Push({x: 1e9, y: 1e9, w: 0, h: 0})
            seen[zone] := true
        }
    }

    return zoneRects
}

GetZoneRects(monitorNumber := GetMouseMonitor()) {
    global appliedLayout, customLayouts

    LoadLayouts()

    currentVirtualDesktop := GetCurrentDesktopUUID()

    if (!currentVirtualDesktop)
        return

    layoutUUID := GetLayoutUUID(monitorNumber, currentVirtualDesktop)

    if (!layoutUUID)
        return

    layout := GetLayout(layoutUUID)

    if (!layout)
        return

    rowsPercent := layout["info"]["rows-percentage"]
    colsPercent := layout["info"]["columns-percentage"]
    cellMap := layout["info"]["cell-child-map"]

    MonitorGet(monitorNumber, &left, &top, &right, &bottom)
    monitorWidth  := right - left
    monitorHeight := bottom - top

    colPosition := GetPositionArray(colsPercent, left, monitorWidth)
    rowPosition := GetPositionArray(rowsPercent, top, monitorHeight)

    zoneRects := InitializeZoneRects(cellMap)

    for (rowNum, row in cellMap) {
        for (colNum, zone in row) {
            zoneRects[zone + 1].x := Min(
                colPosition[colNum],
                zoneRects[zone + 1].x
            )
            
            zoneRects[zone + 1].y := Min(
                rowPosition[rowNum],
                zoneRects[zone + 1].y
            )

            zoneRects[zone + 1].w := Max(
                colPosition[colNum + 1] - zoneRects[zone + 1].x,
                zoneRects[zone + 1].w
            )

            zoneRects[zone + 1].h := Max(
                rowPosition[rowNum + 1] - zoneRects[zone + 1].y,
                zoneRects[zone + 1].h
            )
        }
    }

    return zoneRects
}

*+#1::CursorToZone(1)
*+#2::CursorToZone(2)
*+#3::CursorToZone(3)
*+#4::CursorToZone(4)
*+#5::CursorToZone(5)
*+#6::CursorToZone(6)
*+#7::CursorToZone(7)
*+#8::CursorToZone(8)
*+#9::CursorToZone(9)
*+#0::CursorToZone(10)

*+#F:: {
    global floatWindows
    MouseGetPos(, , &hwnd)
    for (window in floatWindows) {
        if (window == hwnd) {
            floatWindows.Delete(hwnd)
            SnapWindowToCursorZone(hwnd)
            return
        }
    }
    floatWindows[hwnd] := true
}

~*^LButton::
~*^MButton::
~*^RButton:: {
    global lastMouseCtrlClickTime
    lastMouseCtrlClickTime := A_TickCount
}