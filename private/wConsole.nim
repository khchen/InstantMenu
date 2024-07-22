#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/strutils
import pkg/winim/lean
import pkg/wNim/[wApp, wListBox, wMacros]
import redirect, timer

type
  Input = object
    channel: ptr Channel[string]
    stdoutPipe: Pipe
    stderrPipe: Pipe

  wConsole* = ref object of wListBox
    mStdoutPipe: Pipe
    mStderrPipe: Pipe
    mChannel: Channel[string]
    mThread: Thread[Input]

wClass(wConsole of wListBox):

  proc add(self: wConsole, text: string) =
    var
      lastIndex: int
      lines = text.splitLines(keepEol=true)

    for line in lines:
      if self.len == 0:
        lastIndex = self.append(line)
        continue

      var lastLine = self.getText(self.len - 1)
      if lastLine.len != 0 and lastLine[^1] in {'\n', '\r'}:
        lastIndex = self.append(line)
        continue

      lastLine.add line
      self.setText(self.len - 1, lastLine)

    self.ensureVisible(lastIndex)

  proc final*(self: wConsole) =
    self.mStdoutPipe.close()
    self.mStderrPipe.close()

  proc init*(self: wConsole, parent: wWindow, id= wDefaultID,
      pos=wDefaultPoint, size=wDefaultSize, style: wStyle = wLbSingle) =

    self.wListBox.init(parent=parent, id=id, pos=pos, size=size, style=style)

    AllocConsole()
    ShowWindow(GetConsoleWindow(), SW_HIDE)
    discard reopen(stdout, "CONOUT$", fmWrite)
    discard reopen(stderr, "CONOUT$", fmWrite)

    self.mStdoutPipe = redirectStdout()
    self.mStderrPipe = redirectStderr()
    self.mChannel.open()

    proc thread(input: Input) {.thread.} =
      try: {.gcsafe.}:
        while true:
          Sleep(1)
          var data = input.stdoutPipe.read()
          if data.len != 0:
            input.channel[].send(data)

          data = input.stderrPipe.read()
          if data.len != 0:
            input.channel[].send(data)

      except IOError:
        return

    createThread(self.mThread, thread, Input(
      channel: addr self.mChannel,
      stdoutPipe: self.mStdoutPipe,
      stderrPipe: self.mStderrPipe
    ))

    self.startTimer(0.01) do (event: wEvent):
      let (ok, data) = self.mChannel.tryRecv()
      if ok:
        self.add data

when isMainModule:
  import wNim/[wFrame, wMenu, wUtils, wDataObject]

  let app = App(wSystemDpiAware)
  let frame = Frame()
  let console = Console(frame, style=wLbMultiple or wLbNeededScroll or wLbExtended)

  console.wEvent_KeyDown do (event: wEvent):
    if event.ctrlDown and not (event.shiftDown or event.altDown or event.winDown):
      case event.keyCode
      of wKey_A:
        console.selectAll()
        return
      else: discard

    if not (event.ctrlDown or event.shiftDown or event.altDown or event.winDown):
      case event.keyCode
      of wKey_Esc:
        console.deselectAll()
        return

      of wKey_Delete:
        let selections = console.selections
        console.deselectAll()
        for i in countdown(selections.high, 0):
          console.delete(selections[i])
        return
      else: discard

    event.skip()


  console.wEvent_ContextMenu do ():
    type MenuId = enum
      Clear = 1, ClearSelection, CopyAll, CopySelection, SelectAll

    let menu = Menu()
    menu.append(Clear, "Clear").enable(console.len != 0)
    menu.append(CopyAll, "CopyAll").enable(console.len != 0)
    menu.append(SelectAll, "SelectAll").enable(console.len != 0)
    menu.appendSeparator()
    menu.append(ClearSelection, "ClearSelection").enable(console.selections.len != 0)
    menu.append(CopySelection, "CopySelection").enable(console.selections.len != 0)

    case console.popupMenu(menu, flag=wPopMenuReturnId)
    of Clear:
      console.clear()

    of ClearSelection:
      let selections = console.selections
      console.deselectAll()
      for i in countdown(selections.high, 0):
        console.delete(selections[i])

    of CopyAll:
      var text: string
      for i in 0 ..< console.len:
        text.add console.getText(i)
      wSetClipboard(DataObject(text))
      wFlushClipboard()

    of CopySelection:
      var text: string
      for i in console.selections:
        text.add console.getText(i)
      wSetClipboard(DataObject(text))
      wFlushClipboard()

    of SelectAll:
      console.selectAll()

    else: discard

  frame.shortcut(wAccelNormal, wKey_F2) do ():
    echo "中文測試"
    for i in 1..10:
      echo i, " the quick brown fox jumped over the lazy dog"
      if i mod 10 == 0:
        echo ""

  frame.center()
  frame.show()
  app.run()
