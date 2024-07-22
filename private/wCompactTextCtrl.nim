#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import pkg/winim/[lean, inc/shellapi]
import pkg/wNim/[wApp, wMacros, wClientDC, wTextCtrl]

type
  wCompactTextCtrl* = ref object of wTextCtrl
    mDraw: bool

wClass(wCompactTextCtrl of wTextCtrl):

  proc compact(self: wCompactTextCtrl, path: string): string =
    var
      dc = ClientDC(self)
      buffer = T(max(path.len, MAX_PATH) + 1)

    buffer << +$path

    result =
      if PathCompactPath(dc.handle, buffer, cint self.size.width - 5):
        $buffer.nullTerminated()
      else:
        path

  proc init*(self: wCompactTextCtrl, parent: wWindow, id = wDefaultID,
      value: string = "", pos = wDefaultPoint, size = wDefaultSize,
      style: wStyle = wTeLeft) {.validate.} =

    wValidate(parent)
    self.wTextCtrl.init(parent, id, value, pos, size, style)

    self.mDraw = false

    self.wEvent_Paint do (event: wEvent):
      event.skip()

      if not self.hasFocus and not self.mDraw:
        let oldValue = self.value
        let newValue = self.compact(oldValue)

        if oldValue != newValue:
          event.veto
          self.mDraw = true
          self.changeValue(newValue)
          self.sendMessage(wEvent_Paint, event.wParam, event.lParam)
          self.mDraw = false
          self.changeValue(oldValue)
          self.setToolTip(oldValue)

          # after value change, system will invalidate the client
          # just validate it to avoid generating paint event again
          ValidateRect(self.handle, nil)
        else:
          self.setToolTip("")

    self.wEvent_LeftDown do (event: wEvent):
      if not self.hasFocus():
        self.setFocus()
      else:
        event.skip

    self.wEvent_SetFocus do (event: wEvent):
      self.selectAll()
      event.skip

when isMainModule:
  import pkg/wNim/[wFrame, wPanel]

  let app = App(wSystemDpiAware)
  let frame = Frame(title="wCompactTextCtrl", size=(400, 150))
  let panel = Panel(frame)

  let textctrl1 = CompactTextCtrl(panel, style=wBorderSunken)
  let textctrl2 = TextCtrl(panel, style=wBorderSunken)

  textctrl1.value = currentSourcePath()
  textctrl2.value = textctrl1.value

  textctrl1.WM_SYSKEYDOWN do (event: wEvent):
    echo event.keyCode
    # event.skip

  textctrl1.enableAutoComplete(wAcDir)
  textctrl2.enableAutoComplete(wAcDir)

  proc layout() =
    panel.autolayout """
      H:|-[textctrl1,textctrl2]-|
      V:|-[textctrl1]-[textctrl2(textctrl1)]-|
    """

  panel.wEvent_Size do ():
    layout()

  layout()
  frame.center()
  frame.show()
  app.run()
