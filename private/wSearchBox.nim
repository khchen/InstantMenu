#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import pkg/winim/lean
import pkg/wNim/[wApp, wFrame, wStaticText, wTextCtrl, wListBox, wUtils, wMacros]
import locale

type
  wSearchBox* = ref object of wFrame
    mStaticText: wStaticText
    mTextCtrl: wTextCtrl
    mListBox: wListBox
    mFn: proc (x: string): seq[string]
    mValue: string

method getBestSize(self: wListBox): wSize =
  let itemHeight = int SendMessage(self.handle, LB_GETITEMHEIGHT, 0, 0)
  result.height = self.len * itemHeight + 2

proc ForceSetForegroundWindow(hWnd: HWND) =
  var ip = INPUT(`type`: INPUT_KEYBOARD)

  # Press the "ALT" key
  ip.ki.wVk = VK_MENU  # virtual-key code for the "ALT" key
  ip.ki.dwFlags = 0    # 0 for key press
  SendInput(1, &ip, cint sizeof(INPUT))

  # Sleep(100) # Sometimes SetForegroundWindow will fail and the window will flash instead of it being show. Sleeping for a bit seems to help.
  SetForegroundWindow(hWnd)

  # Release the "ALT" key
  ip.ki.dwFlags = KEYEVENTF_KEYUP # KEYEVENTF_KEYUP for key release
  SendInput(1, &ip, cint sizeof(INPUT))

wClass(wSearchBox of wFrame) :

  proc getValue*(self: wSearchBox): string {.property.} =
    return self.mValue

  proc layout(self: wSearchBox) =
    var h = newVariable()

    if not self.mListBox.isShownOnScreen():
      self.autorelayout """
        alias: label=`self.mStaticText`, text=`self.mTextCtrl`
        spacing: 5
        H:|-[label]-[text]-|
        V:|-[text(label.height + 2)]

        C: label.height = label.bestHeight
        C: label.centerY = text.centerY
        C: h = text.height + 10
      """

    else:
      self.autorelayout """
        alias: label=`self.mStaticText`, text=`self.mTextCtrl`, list=`self.mListBox`
        spacing: 5
        H:|-[label(label.bestWidth)]-[text,list]-|
        V:|-[text(label.height + 2)][list(list.bestHeight)]

        C: label.height = label.bestHeight
        C: label.centerY = text.centerY
        C: h = text.height + list.height + 10
      """

    self.minClientSize = (wDefault, int h.value)
    self.maxClientSize = (wDefault, int h.value)

  proc close*(self: wSearchBox) =
    self.hide()

  proc show*(self: wSearchBox, fn: proc (x: string): seq[string]) =
    self.mFn = fn
    self.mValue = ""
    self.mListBox.clear()
    self.mListBox.hide()
    self.mTextCtrl.changeValue("")
    self.position = wGetMousePosition()
    self.sendMessage(wEvent_Size)
    self.startTimer(0.01)
    self.show()
    ForceSetForegroundWindow(self.handle)
    self.mTextCtrl.setFocus()

  proc init*(self: wSearchBox) =

    self.wFrame.init(nil, title="", size=(300, 30),
      style=wBorderDouble or wHideTaskbar or wStayOnTop)

    self.clearWindowStyle(wCaption)
    self.setBackgroundColor(GetSysColor(COLOR_BTNFACE))
    SetWindowPos(self.handle, 0, 0, 0, 0, 0,
      SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or
      SWP_NOZORDER or SWP_NOOWNERZORDER)

    self.mStaticText = StaticText(self, label = !Search & ":", style=wAlignMiddle)
    self.mTextCtrl = TextCtrl(self, style=wBorderSunken)
    self.mListBox = ListBox(self, style=wBorderSunken)
    self.mListBox.hide()

    self.setDraggable(true)

    self.mListBox.wEvent_LeftDown do (event: wEvent):
      self.processMessage(wEvent_LeftDown, event.wParam, event.lParam)

    self.mStaticText.wEvent_LeftDown do (event: wEvent):
      self.processMessage(wEvent_LeftDown, event.wParam, event.lParam)

    self.wEvent_Size do ():
      self.layout()

    self.mTextCtrl.wEvent_Navigation do (event: wEvent):
      event.veto()

    self.mTextCtrl.wEvent_Text do ():
      let value = self.mTextCtrl.value

      self.redraw = false
      self.mListBox.clear()
      if value != "":
        for line in self.mFn(value):
          self.mListBox.append(line)
      self.redraw = true

      if value == "" or self.mListBox.len == 0:
        self.mListBox.hide()
      else:
        self.mListBox.show()

      self.layout()

    self.mTextCtrl.wEvent_Char do (event: wEvent):
      if event.keyCode in {wKey_Enter, wKey_Esc}:
        event.veto()
      else:
        event.skip()

    self.mTextCtrl.wEvent_KeyDown do (event: wEvent):
      case event.keyCode
      of wKey_Esc:
        if self.mTextCtrl.value.len != 0:
          self.mTextCtrl.value = ""
        else:
          self.close()

      of wKey_Enter:
        self.mValue = self.mTextCtrl.value
        self.close()

        if self.mValue != "":
          let event = Event(window=self, msg=wEvent_Text)
          self.processEvent(event)

      else:
        event.skip()

    self.wEvent_Timer do (event: wEvent):
      if GetForegroundWindow() != self.handle:
        self.stopTimer()
        self.close()

when isMainModule:
  import random, sugar
  import pkg/wNim/[wButton, wPanel, wHotkeyCtrl]
  import pkg/wAuto

  staticLoadLang(staticRead("../InstantMenu.lang"))
  initLang("English")

  let app = App(wSystemDpiAware)
  let frame = Frame()
  let panel = Panel(frame)
  let button = Button(panel, label="Open")
  let searchBox = SearchBox()

  proc showSearchBox() =
    searchBox.show do (x: string) -> seq[string]:
      for i in 0..rand(10):
        result.add "item " & $i

    searchBox.wEvent_Text do (event: wEvent):
      dump searchBox.value

  button.wEvent_Button do ():
    showSearchBox()

  frame.registerHotKeyEx(1, wStringToHotkey("F2"))

  frame.wEvent_HotKey do (event: wEvent):
    showSearchBox()

  frame.wEvent_Close do ():
    searchBox.delete()

  frame.center()
  frame.show()

  app.run()
