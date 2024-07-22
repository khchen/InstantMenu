#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/times
import pkg/winim/lean
import pkg/wNim/[wApp, wFrame, wUtils]
import timer

proc enableTrayHoverEvent*(frame: wFrame, message: cint) =
  var
    hoverInterval = GetDoubleClickTime().float / 1000
    trackMouse = false
    hoverSent = false

  frame.wEvent_TrayIcon do (event: wEvent):
    event.skip()
    if event.lParam in [
      WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK,
      WM_RBUTTONDOWN, WM_RBUTTONUP, WM_RBUTTONDBLCLK,
    ]:
      hoverSent = true

  frame.wEvent_TrayMove do (event: wEvent):
    if not trackMouse:
      # echo "enter"
      hoverSent = false
      trackMouse = true

    let
      enterTimer = cpuTime()
      lastPos = wGetMousePosition()

    frame.startTimer(0.1) do (event: wEvent):
      if lastPos != wGetMousePosition():
        trackMouse = false
        stopTimer(event)
        # echo "leave"

      if not hoverSent and cpuTime() - enterTimer > hoverInterval:
        frame.queueMessage(message)
        # echo "hover"
        hoverSent = true

when isMainModule:
  import wNim/[wIcon, wMacros]

  when defined(cpu64):
    {.link: "../resources/InstantMenu64.res".}
  else:
    {.link: "../resources/InstantMenu32.res".}

  wEventRegister(wEvent):
    wEvent_TrayHover

  let app = App()
  let frame = Frame()

  frame.icon = Icon("", 0)
  frame.setTrayIcon(frame.icon)
  frame.enableTrayHoverEvent(wEvent_TrayHover)

  frame.wEvent_TrayHover do ():
    echo "wEvent_TrayHover"

  frame.wEvent_TrayLeftDown do ():
    echo "wEvent_TrayLeftDown"

  frame.wEvent_TrayRightDown do ():
    echo "wEvent_TrayRightDown"

  frame.wEvent_TrayLeftDoubleClick do ():
    echo "wEvent_TrayLeftDoubleClick"

  frame.wEvent_TrayRightDoubleClick do ():
    echo "wEvent_TrayRightDoubleClick"

  frame.center()
  frame.show()
  app.run()
