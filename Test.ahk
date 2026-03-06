#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include "Rat King.ahk"
#Include <Yunit\Yunit>
#Include <Yunit\Window>

Yunit.Use(YunitWindow).Test(TestAutoTile)

class TestAutoTile {
    static HSHELL_WINDOWDESTROY := 2
    static HSHELL_WINDOWACTIVATED := 4
    static HSHELL_RUDEAPPACTIVATED := 32772

    static CreateTestWindow(
        options := "+MaximizeBox +Resize +AlwaysOnTop +Caption"
    ) {
        g := Gui(options)
        g.Show("w300 h200 Center NA")
        return g
    }

    static ActivateWithoutShellHook(g) {
        global lastActiveWindow

        ; XXX: Convert from pointer to numeric.
        lastActiveWindow := g.Hwnd + 0
        WinActivate("ahk_id " g.Hwnd)
        WinWaitActive("ahk_id " g.Hwnd, , 0.2)
        return g
    }

    static Activate(g) {
        WinActivate("ahk_id " g.Hwnd)
        WinWaitActive("ahk_id " g.Hwnd, , 0.2)
        return g
    }

    static Destroy(g) {
        tempHwnd := g.Hwnd
        g.Destroy()
        WinWaitClose("ahk id " tempHwnd, , 0.2)
    }

    static GetRect(hwnd) {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return {x:x, y:y, w:w, h:h}
    }

    static ExpectNoChange(g, fn := unset) {
        before := TestAutoTile.GetRect(g.Hwnd)
        before.active := WinActive("ahk_id " g.Hwnd)
        if IsSet(fn)
            fn()
        Sleep(50)
        after := TestAutoTile.GetRect(g.Hwnd)
        after.active := WinActive("ahk_id " g.Hwnd)
        Yunit.Assert(before.x == after.x)
        Yunit.Assert(before.y == after.y)
        Yunit.Assert(before.w == after.w)
        Yunit.Assert(before.h == after.h)
        Yunit.Assert(before.active == after.active)
    }   
    
    static ExpectNoMove(g, fn := unset) {
        before := TestAutoTile.GetRect(g.Hwnd)
        if IsSet(fn)
            fn()
        Sleep(50)
        after := TestAutoTile.GetRect(g.Hwnd)
        Yunit.Assert(before.x == after.x)
        Yunit.Assert(before.y == after.y)
        Yunit.Assert(before.w == after.w)
        Yunit.Assert(before.h == after.h)
    }

    static ExpectActive(g) {
        Yunit.Assert(g.Hwnd == WinExist("A"))
    }

    static ExpectInactive(g) {
        Yunit.Assert(g.Hwnd != WinExist("A"))
    }

    static ExpectOpaque(g) {
        t := WinGetTransparent("ahk_id " g.Hwnd)
        Yunit.Assert(t = "" || t = 255)
    }

    class TestLoadLayouts {
        LayoutsLoaded() {
            global appliedLayoutsFile := A_ScriptDir . "\Fixtures\applied-layouts.json"
            global customLayoutsFile := A_ScriptDir . "\Fixtures\custom-layouts.json"
            
            LoadLayouts()

            Yunit.Assert(IsObject(appliedLayout))
            Yunit.Assert(IsObject(customLayouts))
        }
    }

    class TestOnShellMessage {
        FloatWindowGarbageCollected() {
            global floatWindows

            g := TestAutoTile.CreateTestWindow()

            tempHwnd := g.Hwnd
            floatWindows[tempHwnd] := true

            Yunit.Assert(floatWindows.Has(tempHwnd))
            TestAutoTile.Destroy(g)
            Yunit.Assert(!floatWindows.Has(tempHwnd))
        }

        NonExistantWindowDoesntSnap() {
            ; XXX: To activate a non-existant hwnd we explicitly call OnShellMessage
            OnShellMessage(
                TestAutoTile.HSHELL_WINDOWACTIVATED
                , 0xFFFFFF
                , ""
                , A_ScriptHwnd
            )
            Yunit.Assert(true)
        }

        LastActiveWindowDoesntSnap() {
            global lastActiveWindow
            
            g := TestAutoTile.CreateTestWindow()
            ; XXX: Convert from pointer to numeric.
            lastActiveWindow := g.Hwnd + 0

            TestAutoTile.ExpectNoMove(g, () => TestAutoTile.Activate(g))
            TestAutoTile.Destroy(g)
        }

        ; XXX: When deleting a window a new window is focused automatically. We 
        ; don't want automatic snapping for windows activated without user input.
        LastWindowDeletedDoesntSnap() {
            g1 := TestAutoTile.CreateTestWindow()
            g2 := TestAutoTile.CreateTestWindow()

            TestAutoTile.ActivateWithoutShellHook(g2)
            TestAutoTile.Activate(g1)

            TestAutoTile.ExpectNoMove(g2, () => g1.Destroy())
            TestAutoTile.ExpectActive(g2)
            TestAutoTile.Destroy(g2)
        }

        ; XXX: When minimizing a window a new window is focused automatically. We
        ; don't want automatic snapping for windows activated without user input.
        LastWindowMinimizedDoesntSnap() {
            g1 := TestAutoTile.CreateTestWindow()
            g2 := TestAutoTile.CreateTestWindow()

            TestAutoTile.ActivateWithoutShellHook(g1)
            TestAutoTile.ActivateWithoutShellHook(g2)
            TestAutoTile.ExpectNoMove(g1, () => WinMinimize("ahk_id " g2.Hwnd))
            
            TestAutoTile.Destroy(g1)
            TestAutoTile.Destroy(g2)
        }

        ; XXX: A hack to prevent animations from changing lastActiveWindow.
        ; Ideally we would test with an actual window for animations etc.
        ToolWindowDoesntSetLastWindow() {
            global lastActiveWindow
            g := TestAutoTile.CreateTestWindow("+ToolWindow")
            TestAutoTile.Activate(g)
            Yunit.Assert(g.Hwnd != lastActiveWindow)
            TestAutoTile.Destroy(g)
        }

        UnresizeableWindowDoesntSnap() {
            g := TestAutoTile.CreateTestWindow("-Resize")
            TestAutoTile.ExpectNoMove(g, () => TestAutoTile.Activate(g))
            TestAutoTile.Destroy(g)
        }

        FloatedWindowDoesntSnap() {
            global floatWindows

            g := TestAutoTile.CreateTestWindow()
            floatWindows[g.Hwnd] := true

            TestAutoTile.ExpectNoMove(g, () => TestAutoTile.Activate(g))
            TestAutoTile.Destroy(g)
        }
    }

    class TestGetZoneIndices {
        WithMockedZonesMask() {
            static PropName := "FancyZones_zones"

            g := TestAutoTile.CreateTestWindow()
            mask := 45
            DllCall("SetPropW", "Ptr", g.Hwnd, "Str", PropName, "Uint64", mask)
            
            indices := GetZoneIndices(g.Hwnd)
            
            expected := [1, 3, 4, 6]
            Yunit.Assert(indices.Length == expected.Length)
            for (index, value in indices)
                Yunit.Assert(value == expected[index])
        }
    }

    class TestSnapWindowToCursorZone {
        WindowAlreadySnappedDoesntSnap() {
            static PropName := "FancyZones_zones"

            g := TestAutoTile.CreateTestWindow()
            tempHwnd := WinExist("A")
            MouseMove(0, 0)
            DllCall("SetPropW", "Ptr", g.Hwnd, "Str", PropName, "UPtr", 1)
            TestAutoTile.ExpectNoMove(g, () => TestAutoTile.Activate(g))
            TestAutoTile.Destroy(g)
            WinActivate("ahk_id " tempHwnd)
        }

        ; WindowTransparentWhileMovingAndSnapping() {
        ; }

        WindowEndsOpaque() {
            g := TestAutoTile.CreateTestWindow()

            TestAutoTile.Activate(g)
            TestAutoTile.ExpectOpaque(g)
            TestAutoTile.Destroy(g)
        }

        WindowEndsInZoneIndex() {
            g := TestAutoTile.CreateTestWindow()
            tempHwnd := WinExist("A")
            MouseMove(0, 0)
            WinMove(0, 0, , , "ahk_id " g.Hwnd)
            TestAutoTile.Activate(g)
            Yunit.Assert(GetZoneIndices(g.Hwnd).Length >= 1)
            TestAutoTile.Destroy(g)
            WinActivate("ahk_id " tempHwnd)
        }
    }

    class TestCursorToZone {
        DoNothingIfZoneNumberTooLarge() {
            MouseGetPos(&mx1, &my1)
            CursorToZone(999)
            MouseGetPos(&mx2, &my2)
            Yunit.Assert(mx1 == mx2 && my1 == my2)
        }

        MoveToCenterOfZone() {
            global appliedLayoutsFile := A_ScriptDir . "\Fixtures\applied-layouts.json"
            global customLayoutsFile := A_ScriptDir . "\Fixtures\custom-layouts.json"

            tempHwnd := WinExist("A")
            CursorToZone(3)
            MouseGetPos(&mx, &my)
            WinActivate("ahk_id " tempHwnd)

            Yunit.Assert(mx == 1440)
            Yunit.Assert(my == 810)
        }
        
        ; XXX: Requires real running FancyZones with at least two zones.
        ActivateSnappedWindowInZone() {
            g1 := TestAutoTile.CreateTestWindow()
            g2 := TestAutoTile.CreateTestWindow()
            
            tempHwnd := WinExist("A")
            CursorToZone(1)
            MouseGetPos(&mx, &my)
            WinMove(mx, my, , , "ahk_id " g1.Hwnd)
            TestAutoTile.Activate(g1)

            CursorToZone(2)
            MouseGetPos(&mx, &my)
            WinMove(mx, my, , , "ahk_id " g2.Hwnd)
            TestAutoTile.Activate(g2)

            CursorToZone(1)
            
            TestAutoTile.ExpectActive(g1)
            TestAutoTile.Destroy(g1)
            TestAutoTile.Destroy(g2)
            WinActivate("ahk_id " tempHwnd)
        }
    }

    class TestGetColPositions {
        GetColPositionsForEvenSplit1080p() {
            colPcs := [5000, 5000]
            colPositions := GetPositionArray(colPcs, 0, 1920)

            for (index, value in colPositions) {
                Yunit.Assert(value == [0, 960, 1920][index])
            }
        }
    }

    class TestGetRowPositions {
        GetRowPositionsForEvenSplit1080p() {
            colPcs := [5000, 5000]
            rowPositions := GetPositionArray(colPcs, 0, 1080)

            for (index, value in rowPositions) {
                Yunit.Assert(value == [0, 540, 1080][index])
            }        
        }
    }

    class TestInitializeZoneRects {
        InitializeZoneRectsForThreeZones() {
            cellMap := [[0,1],[0,2]]
            zoneRects := InitializeZoneRects(cellMap)

            Yunit.Assert(zoneRects.Length == 3)
            for (, zoneRect in zoneRects) {
                Yunit.Assert(zoneRect.x == 1e9)
                Yunit.Assert(zoneRect.y == 1e9)
                Yunit.Assert(zoneRect.w == 0)
                Yunit.Assert(zoneRect.h == 0)
            }
        }
    }

    class TestGetZoneRect {
        ZoneRectsSuccessfull() {
            global appliedLayoutsFile := A_ScriptDir . "\Fixtures\applied-layouts.json"
            global customLayoutsFile := A_ScriptDir . "\Fixtures\custom-layouts.json"

            zoneRects := GetZoneRects(1)

            mock := [
                {x:0, y:0, w:960, h:1080},
                {x:960, y:0, w:960, h:540},
                {x:960, y:540, w:960, h:540},
            ]

            for (index, zoneRect in zoneRects) {
                Yunit.Assert(mock[index].x == zoneRect.x)
                Yunit.Assert(mock[index].y == zoneRect.y)
                Yunit.Assert(mock[index].w == zoneRect.w)
                Yunit.Assert(mock[index].h == zoneRect.h)
            }
        }
    }
}