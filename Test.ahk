#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include "Rat King.ahk"
#Include <Yunit\Yunit>
#Include <Yunit\Window>

Yunit.Use(YunitWindow).Test(TestRatKing)

class TestRatKing {
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
        before := TestRatKing.GetRect(g.Hwnd)
        before.active := WinActive("ahk_id " g.Hwnd)
        if IsSet(fn)
            fn()
        Sleep(50)
        after := TestRatKing.GetRect(g.Hwnd)
        after.active := WinActive("ahk_id " g.Hwnd)
        Yunit.Assert(before.x == after.x)
        Yunit.Assert(before.y == after.y)
        Yunit.Assert(before.w == after.w)
        Yunit.Assert(before.h == after.h)
        Yunit.Assert(before.active == after.active)
    }   
    
    static ExpectNoMove(g, fn := unset) {
        before := TestRatKing.GetRect(g.Hwnd)
        if IsSet(fn)
            fn()
        Sleep(50)
        after := TestRatKing.GetRect(g.Hwnd)
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

            g := TestRatKing.CreateTestWindow()

            tempHwnd := g.Hwnd
            floatWindows[tempHwnd] := true

            Yunit.Assert(floatWindows.Has(tempHwnd))
            TestRatKing.Destroy(g)
            Yunit.Assert(!floatWindows.Has(tempHwnd))
        }

        NonExistantWindowDoesntSnap() {
            ; XXX: To activate a non-existant hwnd we explicitly call OnShellMessage
            OnShellMessage(
                TestRatKing.HSHELL_WINDOWACTIVATED
                , 0xFFFFFF
                , ""
                , A_ScriptHwnd
            )
            Yunit.Assert(true)
        }

        LastActiveWindowDoesntSnap() {
            global lastActiveWindow
            
            g := TestRatKing.CreateTestWindow()
            ; XXX: Convert from pointer to numeric.
            lastActiveWindow := g.Hwnd + 0

            TestRatKing.ExpectNoMove(g, () => TestRatKing.Activate(g))
            TestRatKing.Destroy(g)
        }

        ; XXX: When deleting a window a new window is focused automatically. We 
        ; don't want automatic snapping for windows activated without user input.
        LastWindowDeletedDoesntSnap() {
            g1 := TestRatKing.CreateTestWindow()
            g2 := TestRatKing.CreateTestWindow()

            TestRatKing.ActivateWithoutShellHook(g2)
            TestRatKing.Activate(g1)

            TestRatKing.ExpectNoMove(g2, () => g1.Destroy())
            TestRatKing.ExpectActive(g2)
            TestRatKing.Destroy(g2)
        }

        ; XXX: When minimizing a window a new window is focused automatically. We
        ; don't want automatic snapping for windows activated without user input.
        LastWindowMinimizedDoesntSnap() {
            g1 := TestRatKing.CreateTestWindow()
            g2 := TestRatKing.CreateTestWindow()

            TestRatKing.ActivateWithoutShellHook(g1)
            TestRatKing.ActivateWithoutShellHook(g2)
            TestRatKing.ExpectNoMove(g1, () => WinMinimize("ahk_id " g2.Hwnd))
            
            TestRatKing.Destroy(g1)
            TestRatKing.Destroy(g2)
        }

        ; XXX: A hack to prevent animations from changing lastActiveWindow.
        ; Ideally we would test with an actual window for animations etc.
        ToolWindowDoesntSetLastWindow() {
            global lastActiveWindow
            g := TestRatKing.CreateTestWindow("+ToolWindow")
            TestRatKing.Activate(g)
            Yunit.Assert(g.Hwnd != lastActiveWindow)
            TestRatKing.Destroy(g)
        }

        UnresizeableWindowDoesntSnap() {
            g := TestRatKing.CreateTestWindow("-Resize")
            TestRatKing.ExpectNoMove(g, () => TestRatKing.Activate(g))
            TestRatKing.Destroy(g)
        }

        FloatedWindowDoesntSnap() {
            global floatWindows

            g := TestRatKing.CreateTestWindow()
            floatWindows[g.Hwnd] := true

            TestRatKing.ExpectNoMove(g, () => TestRatKing.Activate(g))
            TestRatKing.Destroy(g)
        }
    }

    class TestGetZoneIndices {
        WithMockedZonesMask() {
            static PropName := "FancyZones_zones"

            g := TestRatKing.CreateTestWindow()
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

            g := TestRatKing.CreateTestWindow()
            tempHwnd := WinExist("A")
            MouseMove(0, 0)
            DllCall("SetPropW", "Ptr", g.Hwnd, "Str", PropName, "UPtr", 1)
            TestRatKing.ExpectNoMove(g, () => TestRatKing.Activate(g))
            TestRatKing.Destroy(g)
            WinActivate("ahk_id " tempHwnd)
        }

        ; WindowTransparentWhileMovingAndSnapping() {
        ; }

        WindowEndsOpaque() {
            g := TestRatKing.CreateTestWindow()

            TestRatKing.Activate(g)
            TestRatKing.ExpectOpaque(g)
            TestRatKing.Destroy(g)
        }

        WindowEndsInZoneIndex() {
            g := TestRatKing.CreateTestWindow()
            tempHwnd := WinExist("A")
            MouseMove(0, 0)
            WinMove(0, 0, , , "ahk_id " g.Hwnd)
            TestRatKing.Activate(g)
            Yunit.Assert(GetZoneIndices(g.Hwnd).Length >= 1)
            TestRatKing.Destroy(g)
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
            g1 := TestRatKing.CreateTestWindow()
            g2 := TestRatKing.CreateTestWindow()
            
            tempHwnd := WinExist("A")
            CursorToZone(1)
            MouseGetPos(&mx, &my)
            WinMove(mx, my, , , "ahk_id " g1.Hwnd)
            TestRatKing.Activate(g1)

            CursorToZone(2)
            MouseGetPos(&mx, &my)
            WinMove(mx, my, , , "ahk_id " g2.Hwnd)
            TestRatKing.Activate(g2)

            CursorToZone(1)
            
            TestRatKing.ExpectActive(g1)
            TestRatKing.Destroy(g1)
            TestRatKing.Destroy(g2)
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

    class TestVirtualDesktop {
        GetLayoutUUIDForMonitor1AndVirtualDesktop() {
            global appliedLayoutsFile := A_ScriptDir . "\Fixtures\applied-layouts.json"
            global customLayoutsFile := A_ScriptDir . "\Fixtures\custom-layouts.json"
            global settingsFile := A_ScriptDir . "\Fixtures\settings.json"

            layoutUUID := GetLayoutUUID(1, "{2D705FE5-1DE8-48F1-91A6-201FA4689AD6}")

            Yunit.Assert(layoutUUID == "{147845FA-160A-4D15-9622-7058BEE7B327}")
        }

        GetLayoutUUIDForMonitor0AndVirtualDesktop() {
            global appliedLayoutsFile := A_ScriptDir . "\Fixtures\applied-layouts.json"
            global customLayoutsFile := A_ScriptDir . "\Fixtures\custom-layouts.json"
            global settingsFile := A_ScriptDir . "\Fixtures\settings.json"

            layoutUUID := GetLayoutUUID(0, "{2D705FE5-1DE8-48F1-91A6-201FA4689AD6}")

            Yunit.Assert(layoutUUID == "{00000000-0000-0000-0000-000000000000}")
        }

        GetLayoutUUIDReturnsEmptyForUnknownVirtualDesktop() {
            global appliedLayoutsFile := A_ScriptDir . "\Fixtures\applied-layouts.json"
            global customLayoutsFile := A_ScriptDir . "\Fixtures\custom-layouts.json"
            global settingsFile := A_ScriptDir . "\Fixtures\settings.json"

            layoutUUID := GetLayoutUUID(1, "{FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF}")

            Yunit.Assert(layoutUUID == "")
        }

        GetLayoutReturnsCorrectLayoutForUUID() {
            global appliedLayoutsFile := A_ScriptDir . "\Fixtures\applied-layouts.json"
            global customLayoutsFile := A_ScriptDir . "\Fixtures\custom-layouts.json"
            global settingsFile := A_ScriptDir . "\Fixtures\settings.json"

            layout := GetLayout("{147845FA-160A-4D15-9622-7058BEE7B327}")

            Yunit.Assert(layout["name"] == "Three Pane")
            Yunit.Assert(layout["info"]["rows"] == 2)
            Yunit.Assert(layout["info"]["columns"] == 2)
        }
    }
}