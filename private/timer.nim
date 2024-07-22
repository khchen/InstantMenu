#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/tables
import pkg/wNim/[wApp, wWindow]

var timerProcMap {.threadvar.}: Table[int, wEventProc]

proc timerProc(event: wEvent) =
  timerProcMap.withValue(event.timerId, fn):
    fn[](event)
  do:
    event.skip()

proc stopTimer*(event: wEvent) =
  event.window.stopTimer(event.timerId)
  timerProcMap.del(event.timerId)

proc stopTimer*(window: wWindow, fn: wEventProc) =
  let id = cast[int](fn.rawProc)
  window.stopTimer(id)
  timerProcMap.del(id)

proc startTimer*(window: wWindow, seconds: float, fn: wEventProc) =
  timerProcMap[cast[int](fn.rawProc)] = fn
  window.startTimer(seconds, cast[int](fn.rawProc))
  window.disconnect(wEvent_Timer, timerProc)
  window.connect(wEvent_Timer, timerProc)

when isMainModule:
  import wNim/wFrame

  type Object = object
    data: int

  let app = App()
  let frame = Frame()

  frame.center()
  frame.show()

  const arcLike = defined(gcArc) or defined(gcAtomicArc) or defined(gcOrc)
  when defined(nimAllowNonVarDestructor) and arcLike:
    proc `=destroy`(obj: Object) =
      echo "=destroy Object ", obj
  else:
    proc `=destroy`(obj: var Object) =
      echo "=destroy Object ", obj

  var count = 0

  frame.shortcut(wAccelNormal, wKey_F2) do ():
    count.inc
    var obj = Object(data: count)
    let message = "The quick fox jumped over the lazy dog"

    frame.startTimer(1.0) do (event: wEvent):
      event.stopTimer()
      echo obj.data
      echo message

  frame.startTimer(2) do (event: wEvent):
    echo "every 2 seconds"

  frame.startTimer(1) do (event: wEvent):
    echo "only once"
    event.stopTimer()

  app.run()

