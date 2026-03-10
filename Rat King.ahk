#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include <JXON_ahk2/_JXON>

global fancyZonesPath := EnvGet("LOCALAPPDATA") "\Microsoft\PowerToys\FancyZones"
global appliedLayoutsFile := fancyZonesPath "\applied-layouts.json"
global customLayoutsFile := fancyZonesPath "\custom-layouts.json"

global lastMouseCtrlClickTime := 0
global lastActiveWindow := 0
global floatWindows := Map()

global appliedLayout := {}
global customLayouts := {}

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

; XXX: We call loadLayouts() without caching on every call to getZoneRect()
LoadLayouts() {
    global appliedLayout, customLayouts

    appliedLayoutFileContents := FileRead(appliedLayoutsFile, "UTF-8")
    customLayoutsFileContents := FileRead(customLayoutsFile, "UTF-8")

    appliedLayout := Jxon_Load(&appliedLayoutFileContents)
    customLayouts := Jxon_Load(&customLayoutsFileContents)
}

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
    if (WinWaitActive("ahk_id " lParam, 1))
        lastActiveWindow := lParam

    if (lastMinimized || lastDeleted)
        return

    if (A_TickCount - lastMouseCtrlClickTime <= 500)
        return

    if (!IsResizeable(lParam))
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

IsResizeable(hwnd) {
    static WS_THICKFRAME := 0x00040000
    static WS_MAXIMIZEBOX := 0x00010000
    style := WinGetStyle("ahk_id " hwnd)
    return ((style & WS_THICKFRAME) || (style & WS_MAXIMIZEBOX))
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

GetLayoutUUID(monitorNumber) {
    global appliedLayout

    return FindMatchSavePart(
        appliedLayout["applied-layouts"]
        , (matcher) => matcher["device"]["monitor-number"] == monitorNumber
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

    layoutUUID := GetLayoutUUID(monitorNumber)

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