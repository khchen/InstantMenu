#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/[parseopt, strutils, strformat, os, dynlib]
import pkg/[wAuto, memlib]
import pkg/winim/lean except CURSORSHAPE
import pkg/[nimpk, nimpk/src]
import pkg/[zippy, zippy/ziparchives]

# ==============================
# VM typedef and type converters
# ==============================

type
  MyVm = ref object of NpVm
    processCls: NpVar
    menuItemCls: NpVar
    windowCls: NpVar
    regDataCls: NpVar

proc new(vm: NpVm, x: wPoint|wSize|wRect): NpVar =
  result = vm.list(x)

proc to[T](v: NpVar): T =
  when T is set[ProcessOption]:
    if not (v of NpList):
      raise newException(NimPkError, fmt"{$v.kind} cannot convert to {$T}.")

    for i in 0..<v.len:
      result.incl to[ProcessOption](v[i])

  elif T is wPoint:
    if not (v of NpList) or v.len != 2:
      raise newException(NimPkError, fmt"{$v.kind} cannot convert to {$T}.")

    result = wDefaultPoint
    if not v[0].isNull: result[0] = to[int](v[0])
    if not v[1].isNull: result[1] = to[int](v[1])

  elif T is wSize:
    if not (v of NpList) or v.len != 2:
      raise newException(NimPkError, fmt"{$v.kind} cannot convert to {$T}.")

    result = wDefaultSize
    if not v[0].isNull: result[0] = to[int](v[0])
    if not v[1].isNull: result[1] = to[int](v[1])

  elif T is wRect:
    if not (v of NpList) or v.len != 4:
      raise newException(NimPkError, fmt"{$v.kind} cannot convert to {$T}.")

    result = wDefaultRect
    if not v[0].isNull: result[0] = to[int](v[0])
    if not v[1].isNull: result[1] = to[int](v[1])
    if not v[2].isNull: result[2] = to[int](v[2])
    if not v[3].isNull: result[3] = to[int](v[3])

  else:
    nimpk.to[T](v)

# Using iterator in cdecl proc will report
#   "Error: internal error: inconsistent environment type"
# So use iterator in global proc instead

proc process_windows(vm: NpVm, self: Process): NpVar =
  result = vm.list()
  for window in self.windows():
    result.add (vm.MyVm.windowCls)(int window)

proc process_allWindows(vm: NpVm, process: Process): NpVar =
  result = vm.list()
  for window in process.allWindows():
    result.add (vm.MyVm.windowCls)(int window)

proc pkEcho(v: NpVar, repr=false) =
  case v.kind
  of NpList:
    write(stdout, "[")
    for i in 0 ..< v.len:
      if i != 0: write(stdout, ", ")
      pkEcho(v[i], true)
    write(stdout, "]")

  of NpMap:
    write(stdout, "{")
    var keys = v.keys
    var values = v.values
    for i in 0 ..< keys.len:
      if i != 0: write(stdout, ", ")
      pkEcho(keys[i], true)
      write(stdout, ":")
      pkEcho(values[i], true)
    write(stdout, "}")

  of NpString:
    if repr:
      write(stdout, $v.call("_repr"))
    else:
      write(stdout, $v)

  else:
    write(stdout, $v)

proc injectBuiltinFns(vm: MyVm, parameters: seq[string]) =
  var cmdParams {.threadvar.}: seq[string]
  cmdParams = parameters

  vm.def:
    [zip]:
      DefaultCompression = DefaultCompression
      BestCompression = BestCompression
      BestSpeed = BestSpeed
      NoCompression = NoCompression
      HuffmanOnly = HuffmanOnly
      Detect = ord dfDetect
      Zlib = ord dfZlib
      Gzip = ord dfGzip
      Deflate = ord dfDeflate

      compress:
        ## compress(src: String, level: Number = DefaultCompression, dataFormat = Gzip) -> String
        ##
        ## Compresses src and returns the compressed data.
        var
          src = string args[0]
          level = if args.len > 1: int args[1] else: DefaultCompression
          dataFormat = if args.len > 2: CompressedDataFormat int args[2] else: dfGzip
        return compress(src, level, dataFormat)

      uncompress:
        ## uncompress(src: String, dataFormat = Detect) -> String
        ##
        ## Uncompresses src and returns the uncompressed data.
        var
          src = string args[0]
          dataFormat = if args.len > 1: CompressedDataFormat int args[1] else: dfDetect
        return uncompress(src, dataFormat)

    "echo":
      ## echo(...) -> Null
      ##
      ## Writes and flushes the parameters to the standard output.
      for arg in args: pkEcho(arg)
      echo ""

    args:
      ## args() -> List
      ##
      ## Returns the command line parameters.
      return cmdParams

    load:
      ## load(path: String) -> Module
      ##
      ## Load a script or dynamic library as module.
      try:
        var file = string args[0]
        return vm.import(file)
      except:
        return vm.null()

    msgbox do (title: string, text: string, flag: int = 0) -> int:
      ## msgbox(tilte: String, text: String, Flag: Number = 0) -> Number
      ##
      ## Displays a simple message box.
      return MessageBox(0, text, title, flag)

proc injectWauto(vm: MyVm) =
  vm.def:
    [wAuto]:
      # ==========================
      # Common variables and class
      # ==========================

      Default = wDefault
      DefaultPoint = [wDefault, wDefault]
      STILL_ACTIVE = STILL_ACTIVE

      [MouseButton] of MouseButton
      ## Mouse buttons.

      [CursorShape] of CursorShape
      ## Mouse cursor shapes.

      [ProcessOption] of ProcessOption
      ## Options to create child process.

      [ProcessPriority] of ProcessPriority
      ## Priority of process.

      [MenuItem] of MenuItem:
        ## Represents a menu item.
        block:
          vm.menuItemCls = vm["wAuto"]{"MenuItem"}

          proc new(vm: NpVm, item: MenuItem): NpVar =
            result = (vm.MyVm.menuItemCls)()
            result[] = item

        "_str" do (self: MenuItem) -> string:
          return fmt"MenuItem(id: ""{self.id}"", text: ""{self.text}"")"

        "_getter" do (vm: NpVm, self: NpVar, attr: string) -> NpVar:
          let item = to[MenuItem](self)
          for key, val in item.fieldPairs:
            if attr == key:
              return vm(val)

          return self{attr}

      # =====================
      # Misc global Functions
      # =====================

      opt
      ## opt(key:String) -> Number
      ## opt(key:String, value:Number) -> Number
      ##
      ## Gets or sets the current setting value.

      clipGet
      ## clipGet(allowFiles=false) -> String
      ##
      ## Retrieves text from the clipboard.
      ## When allowFiles is true and multiple selecting file/dir are stored in the clipboard,
      ## the filename/dirname are returned as texts separated by "\n".

      clipPut
      ## clipPut(text:String)
      ##
      ## Writes text to the clipboard. An empty string "" will empty the clipboard.

      isAdmin
      ## isAdmin() -> Bool
      ##
      ## Checks if the current user has full administrator privileges.

      requireAdmin
      ## requireAdmin(raiseError=true)
      ##
      ## Elevate the current process during runtime by restarting it.

      send do (text: string, raw = false, window = InvalidWindow,
          attach = false, restoreCapslock = false):
        ## send(text:String, raw=false, window=InvalidWindow, attach=false, restoreCapslock=false)
        ##
        ## Sends simulated keystrokes to the active window.
        send(text, raw, window, attach, restoreCapslock)

      # ===============
      # Mouse Functions
      # ===============

      click do (button = mbLeft, pos = wDefaultPoint, clicks = 1, speed: range[0 .. 100] = 10):
        ## click(button=MouseButton.mbLeft, pos=DefaultPoint, clicks=1, speed=10)
        ##
        ## Perform a mouse click operation at the position pos.
        click(button, pos, clicks, speed)

      move do (pos = wDefaultPoint, speed: range[0 .. 100] = 10):
        ## move(pos=DefaultPoint, speed=10)
        ##
        ## Moves the mouse pointer to pos.
        move(pos, speed)

      clickDrag
      ## clickDrag(button=MouseButton.mbLeft, pos1=DefaultPoint pos2=DefaultPoint, speed=10)
      ##
      ## Perform a mouse click and drag operation from pos1 to pos2.

      down
      ## down(button=MouseButton.mbLeft)
      ##
      ## Perform a mouse down event at the current mouse position.

      up
      ## up(button=MouseButton.mbLeft)
      ##
      ## Perform a mouse up event at the current mouse position.

      wheelDown
      ## wheelDown(clicks=1)
      ##
      ## Moves the mouse wheel down.

      wheelUp
      ## wheelUp(clicks=1)
      ##
      ## Moves the mouse wheel up.

      getCursorPosition
      ## getCursorPosition() -> List
      ##
      ## Retrieves the current position of the mouse cursor.

      getCursorShape
      ## getCursorShape() -> CursorShape
      ##
      ## Returns the current mouse cursor shape.

      # =============
      # Process Class
      # =============

      [Process] of Process:
        ## The class of a process.
        block:
          vm.processCls = vm["wAuto"]{"Process"}

          proc new(vm: NpVm, p: Process): NpVar =
            (vm.MyVm.processCls)(int p)

          proc new(vm: NpVm, ps: ProcessStats): NpVar =
            return vm.map(ps)

        "_init" do (self: var Process, pid: int):
          self = Process pid

        "_str" do (self: Process) -> string:
          return if self == InvalidProcess: "Process(Invalid)"
          else: fmt"Process({$self})"

        "==" do (self: Process, x: Process) -> bool:
          return self == x

        "_getter" do (vm: NpVm, self: NpVar, attr: string) -> NpVar:
          let process = to[Process](self)
          return case attr.toLowerAscii
            of "commandline": vm process.commandLine
            of "handle": vm process.handle
            of "name": vm process.name
            of "path": vm process.path
            of "priority": vm process.priority
            of "stats": vm process.stats
            else: self{attr}

        "_setter" do (vm: NpVm, self: Npvar, attr: string, val: NpVar):
          case attr.toLowerAscii
            of "priority": self.setPriority(val)
            else: self{attr} = val

      # ==========================================
      # Global variables and functions for Process
      # ==========================================

      InvalidProcess = InvalidProcess

      getCurrentProcess
      ## getCurrentProcess() -> Process

      getProcess
      ## getProcess(name:String) -> Process
      ##
      ## Returns the process of specified name or InvalidProcess if not found.

      isProcessExists
      ## isProcessExists(name:String) -> bool
      ##
      ## Checks to see if a specified process exists.

      killProcess
      ## killProcess(name:String)
      ##
      ## Terminates all processes with the same name.

      waitProcess
      ## waitProcess(name:String, timeout=0) -> Process
      ##
      ## Pauses until a given process exists. timeout specifies how long to wait (in seconds).
      ## Default (0) is to wait indefinitely.
      ## Returns the process or InvalidProcess if timeout reached.

      shellExecute
      ## shellExecute(file:String, parameters="", workingdir="", verb="", show=ProcessOption.poShow) -> Process
      ##
      ## Runs an external program using the ShellExecute API.

      shellExecuteWait
      ## shellExecuteWait(file:String, parameters="", workingdir="", verb="", show=ProcessOption.poShow) -> Number
      ##
      ## Runs an external program using the ShellExecute API and pauses script execution until it finishes.
      ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.

      run do (path: string, workingDir = "", options: set[ProcessOption] = {}) -> Process:
        ## run(path:String, workingDir="", options=[]) -> Process
        ##
        ## Runs an external program. Returns the process or InvalidProcess if error occured.
        ## Options should be list of ProcessOption.

        # avoid overloaded vm.run
        return run(path, workingDir, options)

      runWait
      ## runWait(path:String, workingDir="", options=[], timeout=0) -> Number
      ##
      ## Runs an external program and pauses execution until the program finishes.
      ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.
      ## options should be list of ProcessOption.

      runAs
      ## runAs(path:String, username:String, password:String, domain="", workingDir="", options=[]) -> Process
      ##
      ## Runs an external program under the context of a different user.
      ## Returns the process or InvalidProcess if error occured.
      ## options should be list of ProcessOption.

      runAsWait
      ## runAsWait(path:String, username:String, password:String, domain="", workingDir="", options=[], timeout=0) -> Number
      ##
      ## Runs an external program under the context of a different user and pauses execution until the program finishes.
      ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.
      ## options should be list of ProcessOption.

      processes do (vm: NpVm, name = NpNil) -> NpVar:
        ## processes() -> Map
        ## processes(name:String) -> List
        ##
        ## Lists all processes or processes of specified name.
        if name.isNull:
          result = vm.map()
          for name, process in processes():
            result[name] = process
        else:
          let name = string name
          result = vm.list()
          for process in processes(name):
            result.add process

      # allWindows do (vm: NpVm, process: Process) -> NpVar:
      #   result = vm.list()
      #   for window in process.allWindows():
      #     result.add (vm.MyVm.windowCls)(int window)

      process_allWindows -> "allWindows"
      ## allWindows(process:Process) -> List
      ##
      ## Lists all windows that created by the specified process.

      # ==========================================
      # Member variables and functions for Process
      # ==========================================

      [+Process]:
        getCommandLine
        ## Process.getCommandLine() -> String
        ##
        ## Gets the command line of a process.

        getHandle
        ## Process.getHandle() -> Number
        ##
        ## Gets the Win32 process ID (PID) from the specified process.

        getName
        ## Process.getName() -> String
        ##
        ## Gets the name of a process.

        getPath
        ## Process.getPath() -> String
        ##
        ## Gets the path of a process.

        getPriority
        ## Process.getPriority() -> Number
        ##
        ## Gets the priority of a process.

        getStats
        ## Process.getStats() -> Map
        ##
        ## Returns Memory and IO infos of a running process.

        isExists
        ## Process.isExists() -> Bool
        ##
        ## Checks to see if a specified process exists.

        isWow64
        ## Process.isWow64() -> Bool
        ##
        ## Determines whether the specified process is running under WOW64
        ## or an Intel64 of x64 processor.

        kill
        ## Process.kill() -> Bool
        ##
        ## Terminates a process.

        resume
        ## Process.resume() -> Bool
        ##
        ## Resume a process.

        setPriority
        ## Process.setPriority(priority:Number) -> Bool
        ##
        ## Changes the priority of a process.

        stderrRead
        ## Process.stderrRead(peek=false) -> String
        ##
        ## Reads from the STDERR stream of a previously run child process.

        stdinWrite
        ## Process.stdinWrite(data:String) -> Number
        ##
        ## Writes to the STDIN stream of a previously run child process.

        stdoutRead
        ## Process.stdoutRead(peek=false) -> String
        ##
        ## Reads from the STDOUT stream of a previously run child process.

        stdioClose
        ## Process.stdioClose(options=[])
        ##
        ## Closes resources associated with a process previously run with STDIO redirection.
        ## Options should be list of ProcessOption.

        suspend
        ## Process.suspend() -> Bool
        ##
        ## Suspend a process.

        waitClose
        ## Process.waitClose(timeout=0) -> Number
        ##
        ## Pauses until a given process does not exist.
        ## Timeout specifies how long to wait (in seconds).
        ## Default (0) is to wait indefinitely.
        ## Returns exit code of the process or STILL_ACTIVE(259) if timeout reached.

        # windows do (vm: NpVm, self: Process) -> NpVar:
        #   result = vm.list()
        #   for window in self.windows():
        #     result.add (vm.MyVm.windowCls)(int window)

        process_windows -> "windows"
        ## Process.windows() -> List
        ##
        ## Lists all top-level windows that created by the specified process.

      # ============
      # Window Class
      # ============

      [Window] of Window:
        ## The class of a window.
        block:
          vm.windowCls = vm["wAuto"]{"Window"}

          proc new(vm: NpVm, w: Window): NpVar =
            result = (vm.MyVm.windowCls)(int w)

          proc new(vm: NpVm, s: seq[Window]): NpVar =
            result = vm.list()
            for win in s:
              result.add win

        "_init" do (self: var Window, hwnd: int):
          self = Window hwnd

        "_str" do (self: Window) -> string:
          return if self == InvalidWindow: "Window(Invalid)"
          else: fmt"Window(class: ""{self.getClassName()}"", title: ""{self.getTitle()}"")"

        "==" do (self: Window, x: Window) -> bool:
          return self == x

        "_getter" do (vm: NpVm, self: NpVar, attr: string) -> NpVar:
          let window = to[Window](self)
          return case attr.toLowerAscii
            of "caretpos": vm window.caretPos
            of "children": vm window.children
            of "classname": vm window.className
            of "clientposition": vm window.clientPosition
            of "clientsize": vm window.clientSize
            of "handle": vm window.handle
            of "parent": vm window.parent
            of "position": vm window.position
            of "process": vm window.process
            of "rect": vm window.rect
            of "size": vm window.size
            of "statusbartext": vm window.statusBarText
            of "text": vm window.text
            of "title": vm window.title
            of "transparent": vm window.transparent
            else: self{attr}

        "_setter" do (vm: NpVm, self: NpVar, attr: string, val: NpVar):
          case attr.toLowerAscii
            of "ontop": self.setOnTop(val)
            of "position": self.setPosition(val)
            of "rect": self.setRect(val)
            of "size": self.setSize(val)
            of "title": self.setTitle(val)
            of "transparent": self.setTransparent(val)
            else: self{attr} = val

      # =========================================
      # Global variables and functions for Window
      # =========================================

      InvalidWindow = InvalidWindow

      getActiveWindow
      ## getActiveWindow() -> Window
      ##
      ## Get the currently active window.

      minimizeAll
      ## minimizeAll()
      ##
      ## Minimizes all windows. Equal to send("#m").

      minimizeAllUndo
      ## minimizeAllUndo()
      ##
      ## Undoes a previous minimizeAll(). Equal to send("#+m").

      windows do (vm: NpVm) -> NpVar:
        ## windows() -> List
        ##
        ## Iterates over all the top-level windows.
        result = vm.list()
        for win in enumerate(true): result.add win

      allWindows do (vm: NpVm) -> NpVar:
        ## allWindows() -> List
        ##
        ## List all top-level windows and their descendants.
        result = vm.list()
        for win in enumerateAll(true): result.add win

      waitAny do (fn: NpVar, timeout = 0) -> Window:
        ## waitAny(fn:Closure, timeout:Number = 0): Window
        ##
        ## Repeatly call fn(window) on all the top-level windows until it returns true.
        ## Timeout specifies how long to wait (in seconds). Default (0) is to wait indefinitely.
        ## Returns the window that stop the loop or InvalidWindow if timeout.
        return waitAny(bool fn(window), timeout)

      waitAll do (fn: NpVar, timeout = 0):
        ## waitAll(fn:Closure, timeout=0)
        ##
        ## Repeatly call fn(window) on all the top-level windows until it returns true
        ## for all windows. Timeout specifies how long to wait (in seconds).
        ## Default (0) is to wait indefinitely.
        waitAll(bool fn(window), timeout)

      # =========================================
      # Member variables and functions for Window
      # =========================================

      [+Window]:
        activate
        ## Window.activate()
        ##
        ## Activates (gives focus to) a window.

        disable
        ## Window.disable()
        ##
        ## Disables the window.

        enable
        ## Window.enable()
        ##
        ## Enables the window.

        click do (window: Window, item: MenuItem):
          ## Window.click(item:MenuItem)
          ## Window.click(button=MouseButton.mbLeft, pos=DefaultPoint, clicks=1)
          ##
          ## Invokes a menu item of a window,
          ## or sends a mouse click command to a given window. The default position is center.
          window.click(item)

        click do (window: Window, button = mbLeft, pos = wDefaultPoint, clicks = 1):
          window.click(button, pos, clicks)

        close do (window: Window):
          ## Window.close()
          ##
          ## Closes a window.
          window.close()

        flash
        ## Window.flash(flashes=4, delay=500, wait=true)
        ##
        ## Flashes a window in the taskbar.

        focus
        ## Window.focus()
        ##
        ## Focus a window.

        getCaretPos
        ## Window.getCaretPos() -> List
        ##
        ## Returns the coordinates of the caret in the given window.

        getChildren
        ## Window.getChildren() -> List
        ##
        ## Retrieves the children of a given window.

        getClassName
        ## Window.getClassName() -> String
        ##
        ## Retrieves the class name of a window.

        getClientPosition
        ## Window.getClientPosition(pos:List) -> List
        ## Window.getClientPosition(x:Number, y:Number) -> List
        ##
        ## Retrieves the screen coordinates of specified client-area coordinates.

        getClientSize
        ## Window.getClientSize() -> List
        ##
        ## Retrieves the size of a given window's client area.

        getHandle
        ## Window.getHandle() -> Number
        ##
        ## Gets the Win32 hWnd from the specified window.

        getParent
        ## Window.getParent() -> Window
        ##
        ## Retrieves the parent of a given window.

        getPosition
        ## Window.getPosition() -> List
        ##
        ## Retrieves the screen coordinates of specified window position.

        getProcess
        ## Window.getProcess() -> Process
        ##
        ## Retrieves the process associated with a window.

        getRect
        ## Window.getRect() -> List
        ##
        ## Retrieves the position and size of a given window.

        getSize do (window: Window) -> wSize:
          ## Window.getSize() -> List
          ##
          ## Retrieves the size of a given window.
          return window.getSize()

        getStatusBarText
        ## Window.getStatusBarText(index=0) -> String
        ##
        ## Retrieves the text from a standard status bar control.

        getText
        ## Window.getText(detectHidden=false) -> String
        ##
        ## Retrieves the text from a window.

        getTitle
        ## Window.getTitle() -> String
        ##
        ## Retrieves the title of a window.

        getTransparent
        ## Window.getTransparent() -> Number
        ##
        ## Gets the transparency of a window. Return -1 if failed.

        hide do (window: Window):
          ## Window.hide()
          ##
          ## Hides window.
          window.hide()

        isActive
        ## Window.isActive() -> Bool
        ##
        ## Checks to see if a specified window is currently active.

        isEnabled
        ## Window.isEnabled() -> Bool
        ##
        ## Checks to see if a specified window is currently enabled.

        isExists
        ## Window.isExists() -> Bool
        ##
        ## Checks to see if a specified window exists.

        isFocused
        ## Window.isFocused() -> Bool
        ##
        ## Checks to see if a specified window has the focus.

        isMaximized
        ## Window.isMaximized() -> Bool
        ##
        ## Checks to see if a specified window is currently maximized.

        isMinimized
        ## Window.isMinimized() -> Bool
        ##
        ## Checks to see if a specified window is currently minimized.

        isVisible
        ## Window.isVisible() -> Bool
        ##
        ## Checks to see if a specified window is currently minimized.

        kill do (window: Window, byProcess = true):
          ## Window.kill(byProcess=true)
          ##
          ## Forces a window to close by terminating the related process or thread.
          window.kill(byProcess)

        maximize
        ## Window.maximize()
        ##
        ## Maximize the window.

        minimize
        ## Window.minimize()
        ##
        ## Minimize the window.

        restore
        ## Window.restore()
        ##
        ## Undoes a window minimization or maximization.

        setOnTop
        ## Window.setOnTop(flag=true)
        ##
        ## Change a window's "Always On Top" attribute.

        setPosition
        ## Window.setPosition(pos:List)
        ## Window.setPosition(x:Number, y:Number)
        ##
        ## Moves a window.

        setRect
        ## Window.setRect(rect:List)
        ## Window.setRect(x:Number, y:Number, width:Number, height:Number)
        ##
        ## Moves and resizes a window.

        setSize
        ## Window.setSize(size:List)
        ## Window.setSize(width:Number, height:Number)
        ##
        ## Resizes a window.

        setTitle
        ## Window.setTitle(title:String)
        ##
        ## Changes the title of a window.

        setTransparent
        ## Window.setTransparent(alpha:Number)
        ##
        ## Sets the transparency (0-255) of a window.
        ## A value of 0 sets the window to be fully transparent.

        show do (window: Window):
          ## Window.show()
          ##
          ## Shows window.
          window.show()

        send do (window: Window, text: string):
          ## Window.Send(text:String)
          ##
          ## Sends a string of characters to a window.
          ## This window must process WM_CHAR event, for example: an editor contorl.
          send(window, text)

        menuItems do (vm: NpVm, self: Window) -> NpVar:
          ## Window.menuItems() -> List
          ##
          ## Lists all the menu items in the specified window.
          result = vm.list()
          for i in self.menuItems():
            result.add i

        windows do (vm: NpVm, self: Window) -> NpVar:
          ## Window.windows() -> List
          ##
          ## Lists the children that belong to the specified parent window.
          result = vm.list()
          for win in self.enumerate(true): result.add win

        allWindows do (vm: NpVm, self: Window) -> NpVar:
          ## Window.allWindows() -> List
          ##
          ## Lists all the descendants that belong to the specified window.
          result = vm.list()
          for win in self.enumerateAll(true): result.add win

      block:
        template body(fn: untyped): bool =
          let ret = fn(window)
          if ret of NpBool:
            if bool ret: true
            else: enumerateBreak
          else: false

      enumerate do (vm: NpVm, fn = NpNil) -> NpVar:
        ## enumerate(fn=null): List
        ##
        ## Enumerates all the top-level windows.
        ## Returns a list containing the windows which closure fn returns true.
        ## Fn returns false to break the enumeration.
        if fn of NpClosure:
          return vm(enumerate(body(fn)))
        else:
          return vm(enumerate(true))

      enumerateAll do (vm: NpVm, fn = NpNil) -> NpVar:
        ## enumerateAll(fn=null): List
        ##
        ## Enumerates all top-level windows and their descendants.
        ## Returns a list containing the windows which closure fn returns true.
        ## Fn returns false to break the enumeration.
        if fn of NpClosure:
          return vm(enumerateAll(body(fn)))
        else:
          return vm(enumerateAll(true))

      [+Window]:
        enumerate do (vm: NpVm, self: Window, fn = NpNil) -> NpVar:
          ## Window.enumerate(fn=null): List
          ##
          ## Enumerates the children that belong to the specified parent window.
          ## Returns a list containing the windows which closure fn returns true.
          ## Fn returns false to break the enumeration.
          if fn of NpClosure:
            return vm(enumerate(self, body(fn)))
          else:
            return vm(enumerate(self, true))

        enumerateAll do (vm: NpVm, self: Window, fn = NpNil) -> NpVar:
          ## Window.enumerateAll(fn=null): List
          ##
          ## Enumerates all the descendants that belong to the specified window.
          ## Returns a list containing the windows which closure fn returns true.
          ## Fn returns false to break the enumeration.
          if fn of NpClosure:
            return vm(enumerateAll(self, body(fn)))
          else:
            return vm(enumerateAll(self, true))

      # ====================================
      # RegData Class and registry functions
      # ====================================

      [RegKind] of RegKind
      ## The kinds of data type in registry.

      [RegData] of RegData:
        ## The kind and data for the specified value in registry.
        block:
          vm.regDataCls = vm["wAuto"]{"RegData"}

          proc new(vm: NpVm, r: RegData): NpVar =
            result = (vm.MyVm.regDataCls)()
            result[] = r

        "_init" do (self: var RegData, kind: RegKind = rkRegError, data: NpVar = NpNil):
          self = case kind
          of rkRegError:
            RegData(kind: kind)
          of rkRegDword, rkRegDwordBigEndian:
            RegData(kind: kind, dword: to[int32](data))
          of rkRegQword:
            RegData(kind: kind, qword: to[int64](data))
          else:
            RegData(kind: kind, data: to[string](data))

        "_str" do (self: RegData) -> string:
          return case self.kind
          of rkRegError:
            fmt"RegData(kind: {self.kind})"
          of rkRegDword, rkRegDwordBigEndian:
            fmt"RegData(kind: {self.kind}, value: {self.dword})"
          of rkRegQword:
            fmt"RegData(kind: {self.kind}, value: {self.qword})"
          else:
            fmt"RegData(kind: {self.kind}, value: {self.data.escape()})"

        "==" do (self: RegData, x: RegData) -> bool:
          return self == x

        "_getter" do (vm: NpVm, self: NpVar, attr: string) -> NpVar:
          let regData = to[RegData](self)
          case attr.toLowerAscii
          of "kind":
            return vm regData.kind
          of "value":
            return case regData.kind
            of rkRegError: vm.null
            of rkRegDword, rkRegDwordBigEndian: vm regData.dword
            of rkRegQword: vm regData.qword
            else: vm regData.data
          else:
            return self{attr}

        "_setter" do (vm: NpVm, self: NpVar, attr: string, val: NpVar):
          let regData = to[RegData](self)
          case attr.toLowerAscii
            of "kind":
              raise newException(NimPkError, "kind of RegData is immutable.")
            of "value":
              self[] = to[RegData]((vm.MyVm.regDataCls)(regData.kind, val))
            else: self{attr} = val

      regDelete
      ## regDelete(key:String) -> Bool
      ## regDelete(key:String, name:String) -> Bool
      ##
      ## Deletes the entire key or a value from the registry.

      regWrite
      ## regWrite(key:String) -> Bool
      ## regWrite(key:String, name:String, value:RegData|Number|String) -> Bool
      ##
      ## Creates a key or a value in the registry.

      regRead
      ## regRead(key:String, value:String) -> RegData
      ##
      ## Reads a value from the registry.

      regKeys do (vm: NpVm, key: string, fn: NpVar = NpNil) -> NpVar:
        ## regKeys(key:String, fn=null) -> List
        ##
        ## Returns a list of subkeys.
        ## Fn returns false to break the enumeration.
        result = vm.list()
        for subkey in wAuto.regKeys(key):
          result.add subkey
          if fn of NpClosure:
            let ret = fn(subkey)
            if ret of NpBool and bool ret == false:
              break

      regValues do (vm: NpVm, key: string, fn: NpVar = NpNil) -> NpVar:
        ## regValues(key:String, fn=null) -> List
        ##
        ## Returns a list of name and kind of values.
        ## Fn returns false to break the enumeration.
        result = vm.list()
        for tup in wAuto.regValues(key):
          let val = vm.map(tup)
          result.add val
          if fn of NpClosure:
            let ret = fn(val)
            if ret of NpBool and bool ret == false:
              break

# ===================
# For cli environment
# ===================

type pkExportModuleFn = proc(vm: ptr PkVM): ptr PkHandle {.cdecl.}

proc pathResolveImport(vm: ptr PKVM, fro: cstring, path: cstring): cstring {.importc, cdecl.}
proc osLoadDL(vm: ptr PKVM, path: cstring): pointer {.importc, cdecl.}
proc osImportDL(vm: ptr PKVM, handle: pointer): ptr PkHandle {.importc, cdecl.}
proc osUnloadDL(vm: ptr PKVM, handle: pointer) {.importc, cdecl.}

proc makeNativeApi(): PkNativeApi =
  result.pkNewConfiguration = pkNewConfiguration
  result.pkNewVM = pkNewVM
  result.pkFreeVM = pkFreeVM
  result.pkSetUserData = pkSetUserData
  result.pkGetUserData = pkGetUserData
  result.pkRegisterBuiltinFn = pkRegisterBuiltinFn
  result.pkGetBuiltinFn = pkGetBuiltinFn
  result.pkGetBuildinClass = pkGetBuildinClass
  result.pkAddSearchPath = pkAddSearchPath
  result.pkRealloc = pkRealloc
  result.pkReleaseHandle = pkReleaseHandle
  result.pkNewModule = pkNewModule
  result.pkRegisterModule = pkRegisterModule
  result.pkModuleAddFunction = pkModuleAddFunction
  result.pkNewClass = pkNewClass
  result.pkClassAddMethod = pkClassAddMethod
  result.pkModuleAddSource = pkModuleAddSource
  result.pkModuleInitialize = pkModuleInitialize
  result.pkRunString = pkRunString
  result.pkRunFile = pkRunFile
  result.pkRunREPL = pkRunREPL
  result.pkSetRuntimeError = pkSetRuntimeError
  result.pkSetRuntimeErrorObj = pkSetRuntimeErrorObj
  result.pkGetRuntimeError = pkGetRuntimeError
  result.pkGetRuntimeStackReport = pkGetRuntimeStackReport
  result.pkGetSelf = pkGetSelf
  result.pkGetArgc = pkGetArgc
  result.pkCheckArgcRange = pkCheckArgcRange
  result.pkValidateSlotBool = pkValidateSlotBool
  result.pkValidateSlotNumber = pkValidateSlotNumber
  result.pkValidateSlotInteger = pkValidateSlotInteger
  result.pkValidateSlotString = pkValidateSlotString
  result.pkValidateSlotType = pkValidateSlotType
  result.pkValidateSlotInstanceOf = pkValidateSlotInstanceOf
  result.pkIsSlotInstanceOf = pkIsSlotInstanceOf
  result.pkReserveSlots = pkReserveSlots
  result.pkGetSlotsCount = pkGetSlotsCount
  result.pkGetSlotType = pkGetSlotType
  result.pkGetSlotBool = pkGetSlotBool
  result.pkGetSlotNumber = pkGetSlotNumber
  result.pkGetSlotString = pkGetSlotString
  result.pkGetSlotHandle = pkGetSlotHandle
  result.pkGetSlotNativeInstance = pkGetSlotNativeInstance
  result.pkSetSlotNull = pkSetSlotNull
  result.pkSetSlotBool = pkSetSlotBool
  result.pkSetSlotNumber = pkSetSlotNumber
  result.pkSetSlotString = pkSetSlotString
  result.pkSetSlotStringLength = pkSetSlotStringLength
  result.pkSetSlotHandle = pkSetSlotHandle
  result.pkGetSlotHash = pkGetSlotHash
  result.pkPlaceSelf = pkPlaceSelf
  result.pkGetClass = pkGetClass
  result.pkNewInstance = pkNewInstance
  result.pkNewRange = pkNewRange
  result.pkNewList = pkNewList
  result.pkNewMap = pkNewMap
  result.pkListInsert = pkListInsert
  result.pkListPop = pkListPop
  result.pkListLength = pkListLength
  result.pkGetSubscript = pkGetSubscript
  result.pkSetSubscript = pkSetSubscript
  result.pkCallFunction = pkCallFunction
  result.pkCallMethod = pkCallMethod
  result.pkGetAttribute = pkGetAttribute
  result.pkSetAttribute = pkSetAttribute
  result.pkImportModule = pkImportModule
  result.pkGetMainModule = pkGetMainModule

proc pkAllocString(vm: ptr PKVM, str: string): cstring =
  var buff = cast[cstring](pkRealloc(vm, nil, csizet str.len + 1))
  if buff == nil: return nil

  if str.len == 0:
    buff[0] = '\0'
  else:
    copyMem(buff, unsafeAddr str[0], str.len + 1)

  return buff

template withInstantVm*(body: untyped) =
  block:
    var vm {.inject, used.} = newVm(MyVm, nil)
    defer:
      NpVm(vm).free()
      vm = nil

    vm.pkReserveSlots(1) # mare sure fiber exists
    vm.pkSetSlotNull(0)
    vm.injectWauto()
    vm.injectBuiltinFns(commandLineParams())
    if true: # avoid compile error if last call has discardable value
      body

template withInstantVmCustomConfig(body: untyped) =
  var config = pkNewConfiguration()
  config.use_ansi_escape = true

  config.resolve_path_fn = proc (vm: ptr PKVM, fro: cstring, path: cstring): cstring {.cdecl.} =
    var embedPath = ($path).replace("../", "^").replace("/", ".")

    if $path in embeds:
      return pkAllocString(vm, $path)

    elif embedPath & ".pk" in embeds:
      return pkAllocString(vm, embedPath & ".pk")

    when defined(windows):
      if embedPath & ".dll" in embeds:
        return pkAllocString(vm, embedPath & ".dll")

    return pathResolveImport(vm, fro, path)

  config.load_script_fn = proc (vm: ptr PKVM, path: cstring): cstring {.cdecl.} =
    if $path in embeds:
      var path = ($path).replace("../", "^").replace("/", ".")
      let contents = zipReader.extractFile($path).replace("\r\n", "\n")
      return pkAllocString(vm, contents)

    else:
      return pkAllocString(vm, readFile($path).replace("\r\n", "\n"))

  config.load_dl_fn = proc (vm: ptr PKVM, path: cstring): pointer {.cdecl.} =
    when defined(windows):
      if $path in embeds:
        type pkInitApi = proc(api: ptr PkNativeApi) {.cdecl.}
        let path = ($path).replace("../", "^").replace("/", ".")
        let contents = zipReader.extractFile($path)

        var lib = loadLib(DllContent contents)
        if lib == nil: return nil

        var initFn = cast[pkInitApi](lib.symAddr("pkInitApi"))
        if initFn == nil:
          lib.unloadLib()
          return nil

        var api = makeNativeApi()
        initFn(addr api)

        return lib

      else:
        return osLoadDL(vm, path)

    else:
      return osLoadDL(vm, path)

  config.import_dl_fn = proc (vm: ptr PKVM, handle: pointer): ptr PkHandle {.cdecl.} =
    result = osImportDL(vm, handle)
    when defined(windows):
      if result == nil:
        var lib = cast[MemoryModule](handle)
        var exportFn = cast[pkExportModuleFn](lib.symAddr("pkExportModule"))
        if exportFn == nil: return nil
        return exportFn(vm)

  config.unload_dl_fn = proc (vm: ptr PKVM, handle: pointer) {.cdecl.} =
    when defined(windows):
      if symAddr(cast[LibHandle](handle), "pkExportModule") != nil:
        osUnloadDL(vm, handle)

      else:
        var lib = cast[MemoryModule](handle)
        var cleanupFn = cast[pkExportModuleFn](lib.symAddr("pkCleanupModule"))
        if cleanupFn != nil:
          discard cleanupFn(vm)
        lib.unloadLib()

    else:
      osUnloadDL(vm, handle)

  block:
    var vm {.inject, used.} = newVm(MyVm, config)
    defer:
      NpVm(vm).free()
      vm = nil

    vm.pkReserveSlots(1) # mare sure fiber exists
    vm.pkSetSlotNull(0)
    vm.injectWauto()
    vm.injectBuiltinFns(cmdParams)
    if true: # avoid compile error if last call has discardable value
      body

const Help = """
Usage: InstantMenu [options] [file] [arguments]
    -c, --cmd:<str>   Evaluate and run the passed string.
    -e, --echo:<expr> Evaluate the expression, and then print the result.
    -z, --zip:path    Load zip archive as embeded file container.
    -h, --help        Prints this help message."""

proc instantVmCli*() =
  var
    cmdParams = commandLineParams()
    embeds {.threadvar.}: seq[string]
    zipReader {.threadvar.}: openZipArchive("").type

  var
    help, echoing = false
    file, script: string
    p = initOptParser()

  for kind, key, value in p.getOpt():
    case kind
    of cmdArgument:
      if file == "":
        file = key
        cmdParams = p.remainingArgs
        break

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        help = true

      of "cmd", "c":
        script = value
        echoing = false

      of "echo", "e":
        script = value
        echoing = true

      of "zip", "z":
        try:
          zipReader = openZipArchive(value)
          embeds.setLen(0)
          for path in zipReader.walkFiles:
            embeds.add path

        except:
          echo "Error loading archive: ", value

    of cmdEnd:
      discard

  withInstantVmCustomConfig:
    if help:
      echo Help
      quit(0)

    if script != "":
      if echoing:
        quit(int vm.runString fmt"print ({script})")
      else:
        quit(int vm.runString script)

    if file == "" and "_init.pk" in embeds:
      file = "_init.pk"

    if file != "":
      quit(int vm.runFile(file))

when isMainModule:
  withInstantVm:
    vm.run """
      import wAuto
      msgbox("Hello", "World!")
      wAuto.send("abc")
      echo args()
    """
