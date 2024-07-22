#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import pkg/winim/lean
import pkg/wNim/[wApp, wWindow]
import timer

const
  # TPM_HORNEGANIMATION = 0x0800 is max flag for TrackPopupMenu
  wPopMenuHover* = 0x80000

proc isMouseInMenu(): bool =
  var menuHwnd: HWND = 0
  while true:
    menuHwnd = FindWindowEx(0, menuHwnd, "#32768", nil)
    if menuHwnd == 0:
      return false

    var
      rect: RECT
      pt: POINT

    GetWindowRect(menuHwnd, rect)
    GetCursorPos(pt)
    if (PtInRect(rect, pt) != 0):
      return true

proc hoverMenu*(self: wWindow, menu: wMenu, pos=(0, 0), flag = 0): wCommandID {.discardable.} =

  self.startTimer(0.1) do (event: wEvent):
    if not isMouseInMenu() and not self.isMouseInWindow():
      EndMenu()
      event.stopTimer()
      return

  result = self.popupMenu(menu, pos, flag=flag)

proc popupMenuEx*(self: wWindow, menu: wMenu, pos=(0, 0), flag = 0): wCommandID {.discardable.} =
  if (flag and wPopMenuHover) != 0:
    return hoverMenu(self, menu, pos, flag xor wPopMenuHover)
  else:
    return popupMenu(self, menu, pos, flag)

when isMainModule:
  import wNim/[wFrame, wButton, wPanel, wMenu]

  let app = App(wSystemDpiAware)
  let frame = Frame()
  let panel = Panel(frame)
  let button1 = Button(panel, label="Hover")
  let button2 = Button(panel, label="Enter", pos=(0, 100))

  proc testMenu(): wMenu =
    result = Menu()
    result.append(1, "Item 1")
    result.append(2, "Item 2")
    let sub = Menu()
    sub.append(1, "Item 3")
    sub.append(2, "Item 4")
    result.appendSubMenu(sub, "Submenu")

  button1.wEvent_MouseHover do ():
    echo "button1.wEvent_MouseHover"
    let menu = testMenu()
    let size = button1.size
    button1.popupMenuEx(menu, (0, size.height), wPopMenuTopAlign or wPopMenuHover)

  button1.wEvent_Button do ():
    let menu = testMenu()
    let size = button1.size
    button1.popupMenuEx(menu, (0, size.height), wPopMenuTopAlign)

  button2.wEvent_MouseEnter do ():
    echo "button2.wEvent_MouseEnter"
    let menu = testMenu()
    let size = button2.size
    button2.popupMenuEx(menu, (0, size.height), wPopMenuTopAlign or wPopMenuHover)

  button2.wEvent_Button do ():
    let menu = testMenu()
    let size = button2.size
    button2.popupMenuEx(menu, (0, size.height), wPopMenuTopAlign)

  frame.center()
  frame.show()
  app.run()
