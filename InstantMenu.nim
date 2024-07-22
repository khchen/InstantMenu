#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

# Todo:
#   parse the links
#   hint to insert system menu if menu is empty
#   add more help function to write script
#     (preivew? choice editor? run in cmd or powershell?)

import std/[os, tables, sets, json, strutils, sequtils, hashes,
  strformat, tempfiles, algorithm, times]

import pkg/wNim/[wApp, wFrame, wPanel, wButton, wStaticBitmap, wComboBox,
  wStaticText, wTreeCtrl, wCheckComboBox, wHotkeyCtrl, wStaticLine,
  wMacros, wTextCtrl, wIconImage, wBitmap, wImageList, wImage, wRegion,
  wPaintDC, wUtils, wMenu, wMenuItem, wWindow, wAcceleratorTable, wToolTip,
  wMessageDialog, wCursor, wIcon, wFileDialog, wDirDialog, wDataObject, wFont,
  private/nimpack]

import pkg/winim/[lean, inc/commctrl, inc/shellapi]

import pkg/[gura, wAuto/process, malebolgia/ticketlocks]

from pkg/wAuto import registerHotKeyEx, unregisterHotKeyEx, Window,
  setOnTop, shellExecute, shellExecuteWait, ProcessOption

import private/[tableDefault, envs, paths, timer, trayHover, popupMenuEx,
  shellContextMenu, searchDialog, pickIconDialog, aboutDialog, wIcoCache,
  wConsole, wCompactTextCtrl, wSearchBox, locale]

when defined(script):
  import pkg/[nimpk, nimpk/src]
  import private/instantVm

type
  Attribs = OrderedTable[string, string]

  Hotkey = tuple[modifiers: int, keyCode: int]

  StaticImage = enum IconDot, IconMenu, IconFolder, IconLine, IconEmpty

  NodeKind = enum
    RootNode, TopNode, DirectoryNode,
    SerialNode, GroupNode, EntryNode,
    FunctionNode, SeparatorNode,
    DirMenu, FileMenu, RecentMenu, HotkeyMenu

  LaunchKind = enum SingleItem, MultipleItem, AdaptiveItem

  NodeOption = enum
    AtStart = "atstart"
    AtExit = "atexit"
    EdgeUp = "edgeup"
    EdgeDown = "edgedown"
    EdgeLeft = "edgeleft"
    EdgeRight = "edgeright"
    TrayHover = "trayhover"
    TrayLeft = "trayleft"
    TrayRight = "trayright"
    # TrayLeftDouble = "trayleftdouble"
    # TrayRightDouble = "trayrightdouble"

  ActionKind = enum
    AddChild, AddAbove, AddBelow, DeleteNode
    MoveInto, MoveAbove, MoveBelow
    EditAttrib, EditOption, ToAbsolutePath, ToRelativePath
    ActionList

  DoKind = enum Do, Undo, Redo

  MenuNode = ref object of RootObj
    attribs: Attribs
    children: seq[MenuNode]
    item: wTreeItem
    small: wBitmap
    large: wBitmap

  SimpleNode = object of RootObj
    attribs: Attribs
    children: seq[SimpleNode]

  wNodeMenu = ref object of wMenu
    mRealized: bool
    mMnemonic: bool
    mShowHotkey: bool
    mShowIcon: bool
    mNodes: seq[MenuNode]

  wPathMenu = ref object of wNodeMenu
    mPath: string
    mPattern: string
    mFileOnly: bool

  wHotkeyMenu = ref object of wNodeMenu

  wRecentMenu = ref object of wNodeMenu

  LaunchSetup = object
    case kind: LaunchKind
    of SingleItem:
      node: MenuNode
    of MultipleItem, AdaptiveItem:
      nodes: seq[MenuNode]
      title: string
      mnemonic: bool
      showHotkey: bool
      showIcon: bool = true

  wMenuWindow = ref object of wWindow

  wWaitFrame = ref object of wFrame
    mImage: wImage

  wMainFrame = ref object of wFrame
    mPanel: wPanel
    mTreeCtrl: wTreeCtrl
    mButtonNew, mButtonDel, mButtonCopy, mButtonPaste: wButton
    mButtonLeft, mButtonUp, mButtonRight, mButtonDown: wButton
    mStaticBitmap: wStaticBitmap
    mComboBoxShow, mComboBoxMode: wComboBox
    mLabelTitle, mLabelPath, mLabelArg, mLabelDir, mLabelTip, mLabelIcon,
      mLabelHotkey, mLabelOption, mLabelBind: wStaticText
    mTextCtrlTitle, mTextCtrlPath, mTextCtrlArg, mTextCtrlDir,
      mTextCtrlTip, mTextCtrlIcon: wCompactTextCtrl
    mCheckComboOption, mCheckComboBind: wCheckComboBox
    mHotkeyCtrl: wHotkeyCtrl
    mStaticLine1, mStaticLine2: wStaticLine
    mButtonIcon, mButtonBrowse, mButtonScript, mButtonExec, mButtonSetting,
      mButtonUndo, mButtonRedo, mButtonOk: wButton
    mConsole: wConsole
    mBaseElement: wButton
    mDragging: bool
    mUndrawable: bool
    mMaximized: bool

  Action = object
    kind: ActionKind
    node: MenuNode
    target: MenuNode
    pos: int
    targetPos: int
    oldParent: MenuNode
    name: string
    attrib: string
    oldValue: string
    newValue: string
    oldOption: Table[string, bool]
    newOption: Table[string, bool]
    oldAttribTable: Table[(MenuNode, string), string]
    noCombine: bool
    alwaysUpdateUi: bool
    multipleActions: seq[Action]

  JobKind = enum Work, Async, Sync, Nop
  Job = object
    case kind: JobKind
    of Work:
      attribs: Attribs
    of Async:
      asyncs: seq[Job]
    of Sync:
      syncs: seq[Job]
    of Nop:
      discard

  Main = object
    root: MenuNode
    copiedNode: MenuNode
    cacheFile: string
    configFile: string
    recentLen: int
    icoSize: int
    icoCache: wIcoCache
    imageList: wImageList
    mainFrame: wMainFrame
    waitFrame: wFrame
    menuWindow: wMenuWindow
    searchBox: wSearchBox

    undoIndex: int
    actions: seq[Action]
    staticImage: array[StaticImage, tuple[index: int, small: wBitmap, large: wBitmap]]
    hotkeyMap: Table[Hotkey, HashSet[MenuNode]]
    optionMap: Table[NodeOption, HashSet[MenuNode]]
    launchSetup: LaunchSetup

    busy: bool
    icoLock: TicketLock
    channelLock: TicketLock
    channel: Channel[string]
    scriptChannel: Channel[string]

# proc `=destroy`(x: type(MenuNode()[])) =
#   echo "=destroy MenuNode: ", x.attribs{"title"}

wEventRegister(wEvent):
  wEvent_LaunchMenu
  wEvent_LaunchNextMenu
  wEvent_LaunchPrevMenu
  wEvent_ShowSearch
  wEvent_ShowAbout
  wEvent_ShowMain
  wEvent_ClearRecent
  wEvent_MouseWheelEdge
  wEvent_TrayHover
  wEvent_Start
  wEvent_Exit
  wEvent_ScriptReturn

const
  Mnemonic = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

  SeparatorTitle = "----"

  MenuKinds = {TopNode, DirectoryNode,
    DirMenu, FileMenu, RecentMenu, HotkeyMenu}

  ExecutableKinds = {EntryNode, GroupNode, SerialNode}

  RootOptionSet = toHashSet [
    "factorx", "factory", "iconsize", "language", "recentlen", "editor"
  ]

  SpecialNodeSet = toHashSet [
    "recentmenu", "hotkeymenu", "separator", "about", "search", "setting", "exit", "recentclear"
  ]

  ComboFolderModeTable = toOrderedTable {
    "": "SubMenu",
    "group": "Async",
    "serial": "Sync"
  }

  ComboItemModeTable = toOrderedTable {
    "": "Normal",
    "min": "Min",
    "max": "Max",
    "filemenu": "FileMenu",
    "dirmenu": "FolderMenu"
  }

  ComboItemScriptTable = toOrderedTable {
    "": "CustomScript"
  }

  ComboShowTable = toOrderedTable {
    "": "Show",
    "hide": "Hide",
    "win32": "Win32",
    "win64": "Win64",
    "disable": "Disable"
  }

  OptionMenuTable = toOrderedTable {
    "notitle": "NoTitle",
    "nohotkey": "NoHotkey",
    "nomnemonic": "NoMnemonic",
    "noicon": "NoIcon",
    "nowheel": "NoTurning"
  }

  OptionItemTable = toOrderedTable {
    $AtStart: "AtStart",
    $AtExit: "AtExit",
    "nohotkey": "NoHotkey",
    "norecent": "Exclude_From_Recent"
  }

  OptionBindTable = toOrderedTable {
    $EdgeUp: "Wheel_Top",
    $EdgeDown: "Wheel_Bottom",
    $EdgeLeft: "Wheel_Left",
    $EdgeRight: "Wheel_Right",
    $TrayHover: "Tray_Hover",
    $TrayLeft: "Tray_Left",
    $TrayRight: "Tray_Right",
    # $TrayLeftDouble: "Tray_Left_Double",
    # $TrayRightDouble: "Tray_Right_Double"
  }

var main {.global.} = Main()

proc init(main: var Main) =
  main.icoLock = initTicketLock()
  main.channelLock = initTicketLock()
  main.channel.open()
  main.scriptChannel.open()

proc exit(main: var Main) =
  main.channel.close()
  main.scriptChannel.close()

# supports pack/unpack for MenuNode
proc pack[T: wTreeItem|wBitmap](s: var string, x: T) =
  discard

proc unpack[T: wTreeItem|wBitmap](s: string, i: var int, x: var T) =
  discard

template UNREACHABLE() =
  doAssert(false, "unreachable code")

template `or`(a, b: ref): untyped =
  if a != nil: a else: b

template await[T](window: wWindow, th: Thread[T], timer: float, body: untyped): untyped =
  # use a window timer to wait for the thread and then run some code
  # keep the local variable `th` alive until the thread finishes
  # note: after event.stoptimer(), the closure calling the template is destroyed,
  # making `th` and other local variables inaccessible
  window.startTimer(timer) do (event: wEvent):
    if not th.running:
      try:
        body
      finally:
        event.stopTimer()

proc node(item: wTreeItem): MenuNode =
  result = cast[MenuNode](item.data)

proc node(item: wMenuItem): MenuNode =
  result = cast[MenuNode](item.data)

proc toSimpleNode(node: MenuNode): SimpleNode =
  result = SimpleNode(attribs: node.attribs)
  for child in node.children:
    result.children.add child.toSimpleNode()

proc toMenuNode(node: SimpleNode): MenuNode =
  result = MenuNode(attribs: node.attribs)
  for child in node.children:
    result.children.add child.toMenuNode()

template hasOption(node: MenuNode, key: string): bool =
  node.attribs{key} == "true"

proc getInt(node: MenuNode, key: string, defaultInt = 0): int =
  try:
    result = parseInt(node.attribs{key})
  except ValueError:
    result = defaultInt

proc getFloat(node: MenuNode, key: string, defaultFloat = 0.0): float =
  try:
    result = parseFloat(node.attribs{key})
  except ValueError:
    result = defaultFloat

proc contains(node: MenuNode, word: string): bool =
  for key, value in node.attribs:
    # word in key or word in value (except option)
    if word in key.toLowerAscii: return true
    if value != "true" and word in value.toLowerAscii: return true

proc getParent(node: MenuNode): MenuNode =
  if node.item.isOk:
    let parentItem = node.item.getParent()
    if parentItem.isOk:
      return parentItem.node
    else: # top item is child of main.root
      return main.root

proc position(node: MenuNode): int =
  let parent = node.getParent()
  assert parent != nil
  result = parent.children.find(node)
  assert result != -1

proc add(parent: MenuNode, node: MenuNode) =
  parent.children.add(node)

proc insert(parent: MenuNode, node: MenuNode, pos: int) =
  parent.children.insert(node, pos)

proc delete(parent: MenuNode, pos: int) =
  parent.children.delete(pos)

proc childless(node: MenuNode): bool {.inline.} =
  return (node.children.len == 0)

# bind attributes table to a ComboBox/CheckComboBox
# for quick item identification in the event handler.
proc setAttribsTable(win: wWindow, table: Attribs) {.property.} =
  win.data = cast[int](addr table)

proc getAttribsTable(win: wWindow): Attribs {.property.} =
  cast[ptr Attribs](win.data)[]

proc copy(node: MenuNode): MenuNode =
  # copy the tree structure only, excluding the resources
  # resources will be recreated when added to the tree
  new(result)
  result.attribs = node.attribs

  result.children.setLen(node.children.len)
  for i, child in node.children:
    result.children[i] = child.copy()

proc title(node: MenuNode): string =
  if node.attribs{"special"} == "separator":
    return SeparatorTitle
  else:
    return node.attribs{"title"}

proc nkind(node: MenuNode): NodeKind =
  if node.attribs{"special"} in SpecialNodeSet:
    return case node.attribs{"special"}
      of "separator": SeparatorNode
      of "recentmenu": RecentMenu
      of "hotkeymenu": HotkeyMenu
      else: FunctionNode

  elif node == main.root:
    return RootNode

  elif node.getParent() == main.root:
    return TopNode

  elif node.children.len != 0:
    return case node.attribs{"mode"}
      of "group": GroupNode
      of "serial": SerialNode
      else: DirectoryNode

  else:
    return case node.attribs{"mode"}
      of "dirmenu": DirMenu
      of "filemenu": FileMenu
      else: EntryNode

proc insertable(node: MenuNode): bool =
  case node.nkind()
  of RootNode, TopNode, DirectoryNode, SerialNode, GroupNode:
    return true

  of SeparatorNode, DirMenu, FileMenu, RecentMenu, HotkeyMenu, FunctionNode:
    return false

  of EntryNode:
    if node.attribs{"path"} == "" and node.attribs{"arg"} == "" and
        node.attribs{"dir"} == "" and node.attribs{"mode"} == "" and
        node.attribs{"script"} == "":
      return true

    else:
      return false

proc walk(node: MenuNode, fn: proc (x: MenuNode)) =
  fn(node)
  for child in node.children:
    walk(child, fn)

proc filter(startNode: MenuNode, fn: proc (x: MenuNode): bool): seq[MenuNode] {.discardable.} =
  var nodes: seq[MenuNode]

  proc walk(node: MenuNode, fn: proc (x: MenuNode): bool) =
    if fn(node):
      nodes.add node

    for child in node.children:
      walk(child, fn)

  walk(startNode, fn)
  result = nodes

proc unlinkTreeNode(node: MenuNode = nil) =
  walk(node or main.root) do (child: MenuNode):
    child.item = TreeItem(nil, 0)

proc nextOrPrevSibling(node: MenuNode, prev=false): MenuNode =
  # find sibling cyclic, return nil if there is no sibling
  if node == nil: return nil
  let parent = node.getParent()
  if parent == nil or parent.children.len == 1: return nil

  var pos = node.position()
  if prev:
    if pos == 0: pos = parent.children.high
    else: pos.dec
  else:
    if pos == parent.children.high: pos = 0
    else: pos.inc

  return parent.children[pos]

proc nextOrPrevMenuSibling(node: MenuNode, prev: bool): MenuNode =
  # find menu sibling cyclic, return nil if not found
  if node == nil: return nil

  var sibling = node
  while true:
    sibling = sibling.nextOrPrevSibling(prev)
    if sibling == nil: return nil

    if sibling.nkind() in MenuKinds and not sibling.hasOption("nowheel"):
      return sibling

proc recentNodes(): seq[MenuNode] =
  var recents: seq[(MenuNode, int)]
  main.root.walk do (node: MenuNode):
    let no = node.attribs{"recent"}
    if no != "":
      try:
        recents.add (node, parseInt(no))
      except ValueError:
        discard

  recents.sort do (a, b: (MenuNode, int)) -> int:
    system.cmp(b[1], a[1])

  for (node, _) in recents:
    if result.len < main.recentLen:
      result.add node
    else:
      node.attribs.del("recent")

  result.reverse()

proc recentClear() =
  main.root.walk do (node: MenuNode):
    node.attribs.del("recent")

proc recentAdd(node: MenuNode) =
  node.attribs["recent"] = $cint.high
  var nodes = recentNodes()
  for i in 0 ..< nodes.len:
    nodes[i].attribs["recent"] = $(i + 1)

proc sort(node: MenuNode) =
  node.children.sort do (a, b: MenuNode) -> int:
    if a.children.len != 0 and b.children.len == 0:
      result = -1
    elif a.children.len == 0 and b.children.len != 0:
      result = 1
    else:
      result = system.cmp(
        a.attribs{"title"}.toLowerAscii,
        b.attribs{"title"}.toLowerAscii
      )

  for child in node.children:
    child.sort()

proc findTitle(node: MenuNode, title: string): int =
  result = -1
  for i, child in node.children:
    if title == child.attribs{"title"}:
      return i

proc addPath(node: MenuNode, path: string, param: SearchParam) =
  var title = path.parseDesign(param.design).strip()
  if title == "": title = path.localName()

  let child = MenuNode()
  child.attribs["title"] = title
  child.attribs["path"] = path
  node.children.add(child)

proc addDir(node: MenuNode, dir: string, param: SearchParam) =

  if SearchRec in param.option:
    for path in walkDirs(dir / "*.*"):
      if (IncludeHiddenDir notin param.option) and path.isHidden(): continue

      if Flat in param.option:
        node.addDir(path, param)

      else:
        let localName = path.localName()
        let pos = node.findTitle(localName)
        if pos >= 0:
          node.children[pos].addDir(path, param)

        else:
          let child = MenuNode()
          child.attribs["title"] = localName
          child.addDir(path, param)
          if child.children.len > 0: # skip empty child
            node.children.add(child)

  for patt in param.pattern.split({';'}):
    let patt = patt.strip

    if SearchFile in param.option:
      for path in walkFiles(dir / patt):
        if IncludeHiddenFile in param.option or (not path.isHidden()):
          node.addPath(path, param)

    if SearchDir in param.option:
      for path in walkDirs(dir / patt):
        if IncludeHiddenDir in param.option or (not path.isHidden()):
          node.addPath(path, param)

proc craft(param: SearchParam): MenuNode =
  if param.dirs.len == 0 or param.dirs[0] == "":
    return

  result = MenuNode()
  result.attribs["title"] = param.dirs[0].env().localName()

  for dir in param.dirs:
    if dir == "": continue
    result.addDir(dir.env(), param)

  result.sort()

proc standardize(node: MenuNode) =
  ## after loading config, validate and correct the menunode

  proc standardizeHotkey(node: MenuNode): bool =
    let hotkey = wStringToHotkey(node.attribs{"hotkey"})
    if hotkey != default(Hotkey):
      node.attribs["hotkey"] = wHotkeyToString(hotkey)
      return true

  proc filterOptions(node: MenuNode, key: string, isMenu: bool) =
    if node.hasOption(key):
      if key in ["expand", "select"]: return
      if key in OptionBindTable: return
      if isMenu and key in OptionMenuTable: return
      if not isMenu and key in OptionItemTable: return

    node.attribs.del key

  discard node.attribs.mgetOrPut("title", !No_Title)

  let
    nkind = node.nkind()
    isMenu = nkind in MenuKinds
    keys = toSeq(node.attribs.keys)

  case nkind
  of RootNode:
    for key in keys:
      var ok = false
      if key in RootOptionSet:
        case key
        of "factorx", "factory":
          ok = node.attribs[key].allCharsInSet(Digits + {'.'})

        of "iconsize":
          ok = node.attribs[key] in ["16", "24", "32", "48"]

        of "language":
          ok = node.attribs[key] in langs()

        of "recentlen":
          ok = node.attribs[key] in ["5", "10", "15", "20", "25", "30", "35"]

        of "editor":
          ok = fileExist(node.attribs[key])

        else:
          UNREACHABLE()

      if not ok:
        node.attribs.del key

  of SeparatorNode:
    # allow ComboShowTable
    for key in keys:
      if key == "special": continue # allow special itself
      if key != "show" or node.attribs{"show"} notin ComboShowTable:
        node.attribs.del key

  of RecentMenu, HotkeyMenu:
    # allow title, icon, hotkey, ComboShowTable, OptionMenuTable, OptionBindTable
    for key in keys:
      case key
      of "special": discard # allow special itself
      of "title", "icon": discard # allow any text
      of "hotkey":
        if not node.standardizeHotkey():
          node.attribs.del key
      of "show":
        if node.attribs{"show"} notin ComboShowTable:
          node.attribs.del key
      else:
        node.filterOptions(key, isMenu)

  of FunctionNode:
    # allow title, tip, icon, hotkey, ComboShowTable, OptionItemTable, OptionBindTable
    for key in keys:
      case key
      of "special": discard # allow special itself
      of "title", "tip", "icon": discard # allow any text
      of "hotkey":
        if not node.standardizeHotkey():
          node.attribs.del key
      of "show":
        if node.attribs{"show"} notin ComboShowTable:
          node.attribs.del key
      else:
        node.filterOptions(key, isMenu)

  of TopNode, DirectoryNode, SerialNode, GroupNode:
    # Top:
    #   allow title, icon, hotkey, ComboShowTable, OptionMenuTable, OptionBindTable
    # Directory, Serial, Group:
    #   same but also ComboFolderModeTable
    for key in keys:
      case key
      of "title", "icon": discard # allow any text
      of "tip":
        if isMenu: node.attribs.del key # menu don't allow tip
        else: discard
      of "hotkey":
        if not node.standardizeHotkey():
          node.attribs.del key
      of "show":
        if node.attribs{"show"} notin ComboShowTable:
          node.attribs.del key
      of "mode":
        if nkind == TopNode:
          node.attribs.del key
        elif node.attribs{"mode"} notin ComboFolderModeTable:
          node.attribs.del key
      of "recent":
        if isMenu or (not node.attribs{"recent"}.allCharsInSet(Digits)):
          node.attribs.del key
      else:
        node.filterOptions(key, isMenu)

  of EntryNode, DirMenu, FileMenu:
    # allow title, path, arg, dir, tip, icon, hotkey,
    #   ComboShowTable, ComboItemModeTable, OptionItemTable, OptionBindTable
    for key in keys:
      case key
      of "title", "path", "arg", "dir", "icon", "script": discard # allow any text
      of "tip":
        if isMenu: node.attribs.del key # menu don't allow tip
        else: discard
      of "hotkey":
        if not node.standardizeHotkey():
          node.attribs.del key
      of "show":
        if node.attribs{"show"} notin ComboShowTable:
          node.attribs.del key
      of "mode":
        if node.attribs{"mode"} notin ComboItemModeTable:
          node.attribs.del key
      of "recent":
        if isMenu or (not node.attribs{"recent"}.allCharsInSet(Digits)):
          node.attribs.del key
      else:
        node.filterOptions(key, isMenu)

proc getIcoPath(node: MenuNode): string =
  result = node.attribs{"icon"}.env()
  if result != "":
    let (path, location) = result.splitIconLocation()
    result = path.whereIs() & location

  else:
    result = node.attribs{"path"}.env().whereIs()

    if result != "" and result.extPart.toLowerAscii == ".lnk":
      let shortcut = result.extractShortcut()
      if shortcut.icon != "":
        result = shortcut.icon.env()

      elif shortcut.path != "":
        result = shortcut.path.env()

  # use a standardized path for icoCache,
  # avoiding absolute paths, especially for cases like shell32.dll.
  if result != "":
    result = result.standardize()

proc loadConfig(jnode: JsonNode) =

  proc toMenuNode(jnode: JsonNode): MenuNode =
    assert jnode.kind == JObject
    result = MenuNode()

    for field, value in jnode.getFields():
      case value.kind
      of JArray:
        if field == "items":
          for item in value:
            let subnode = toMenuNode(item)
            result.children.add subnode

        # omit all other arrays

      of JString:
        # omit empty string
        let str = value.getStr().strip()
        if str != "": result.attribs[field] = str

      of JBool:
        # omit false
        if value.getBool():
          result.attribs[field] = "true"

      of JInt:
        result.attribs[field] = $value.getInt()

      of JFloat:
        result.attribs[field] = $value.getFloat()

      else: discard # omit all other type

  if jnode != nil and jnode.kind == JObject:
    main.root = jnode.toMenuNode()
    walk(main.root, standardize)

  if main.root == nil:
    main.root = MenuNode()

proc saveConfig() =

  proc toJson(node: MenuNode): JsonNode =
    result = newJObject()

    for key, value in node.attribs:
      # discard "expand" and "select"
      if key in ["expand", "select"]: continue
      if value == "": continue

      if value == "true":
        result[key] = newJBool(true)
        continue
      try:
        result[key] = newJInt(parseBiggestInt(value))
      except ValueError:
        try:
          result[key] = newJFloat(parseFloat(value))
        except ValueError:
          result[key] = newJString(value)

    if node.item.isOk:
      if node.item.isExpanded(): result["expand"] = newJBool(true)
      if node.item.isFocused(): result["select"] = newJBool(true)

    if node.children.len != 0:
      var arr = newJArray()
      for child in node.children:
        arr.add child.toJson()
      result["items"] = arr

  try: writeFile(main.configFile, main.root.toJson.toGura(2))
  except IOError: discard

proc loadCache() =
  withLock main.icoLock:
    try: main.icoCache.load(readFile(main.cacheFile))
    except IOError: discard

proc saveCache(wait = true) =
  withLock main.icoLock:
    try: writeFile(main.cacheFile, main.icoCache.save())
    except IOError: discard

proc resetImageList(size: int) =
  const
    imageFolder = staticRead("resources/folder.ico")
    imageDot = staticRead("resources/dot.ico")
    imageSeparator = staticRead("resources/separator.ico")
    imageMenu = staticRead("resources/menu.ico")
    imageEmpty = staticRead("resources/empty.ico")

  main.icoSize = size
  main.imageList = ImageList((size, size), true, 8)

  for tup in [
    (IconFolder, imageFolder),
    (IconDot, imageDot),
    (IconLine, imageSeparator),
    (IconMenu, imageMenu),
    (IconEmpty, imageEmpty)
  ]:
    let (enu, data) = tup
    var small, large: wBitmap
    withLock main.icoLock:
      small = main.icoCache.getBitmap(IcoData(data, size))
      large = main.icoCache.getBitmap(IcoData(data, 64))

    let index = main.imageList.add(small)
    main.staticImage[enu] = (index, small, large)

proc markNoCombine(kind: ActionKind, attrib = "") =
  for i in countdown(main.actions.high, 0):
    if main.actions[i].kind == kind and main.actions[i].attrib == attrib:
      main.actions[i].noCombine = true
      break

proc undoable(): bool {.inline.} =
  main.undoIndex > 0

proc redoable(): bool {.inline.} =
  main.undoIndex < main.actions.len

wClass(wNodeMenu of wMenu) :

  proc init(self: wNodeMenu,
      title = "", mnemonic = false, showHotkey = false, showIcon = true) =

    self.wMenu.init()
    self.mMnemonic = mnemonic
    self.mShowHotkey = showHotkey
    self.mShowIcon = showIcon
    self.mRealized = false

    if title != "":
      self.append(0, title).disable()
      self.appendSeparator()

  proc init(self: wNodeMenu, nodes: seq[MenuNode],
      title = "", mnemonic = false, showHotkey = false, showIcon = true) =

    self.mNodes = nodes
    self.init(title, mnemonic, showHotkey, showIcon)

  proc init(self: wNodeMenu, node: MenuNode) =
    let
      mnemonic = not node.hasOption("nomnemonic")
      showHotkey = not node.hasOption("nohotkey")
      showIcon = not node.hasOption("noicon")
      title =
        if node.hasOption("notitle"): ""
        else: node.attribs{"title"}

    self.init(node.children, title, mnemonic, showHotkey, showIcon)

wClass(wPathMenu of wNodeMenu) :

  proc init(self: wPathMenu, node: MenuNode, fileOnly = false) =
    self.wNodeMenu.init(node)
    self.mNodes = @[] # in case node has children (should not happen)

    self.mFileOnly = fileOnly
    self.mPath = node.attribs{"path"}.env()
    self.mPattern = node.attribs{"arg", "*.*"}

wClass(wHotkeyMenu of wNodeMenu) :

  proc init(self: wHotkeyMenu, node: MenuNode) =
    self.wNodeMenu.init(node)
    self.mNodes = @[] # in case node has children (should not happen)

wClass(wRecentMenu of wNodeMenu) :

  proc init(self: wRecentMenu, node: MenuNode) =
    self.wNodeMenu.init(node)
    self.mNodes = @[] # in case node has children (should not happen)

method realize(self: wNodeMenu) {.base.} =
  self.mRealized = true

  if self.mNodes.len == 0:
    self.append(0, !No_Items).disable()
    return

  var index = 0
  for node in self.mNodes:
    let show = node.attribs{"show"}
    var disable = false
    case show
    of "hide": continue
    of "win32":
      if isWin64(): continue
    of "win64":
      if not isWin64(): continue
    of "disable":
      disable = true
    else: discard

    let nkind = node.nkind()
    if nkind == SeparatorNode:
      self.appendSeparator()

    else:
      let
        title = node.attribs{"title"}
        hotkey = node.attribs{"hotkey"}
        tip = node.attribs{"tip"}
        icon = if self.mShowIcon: node.small else: nil

      var
        item: wMenuItem
        label =
          if self.mMnemonic and index < Mnemonic.len:
            Mnemonic[index] & ' ' & title
          else:
            title

      if self.mShowHotkey:
        label.add "\t" & hotkey

      case nkind
      of SeparatorNode, RootNode:
        UNREACHABLE()

      of EntryNode, SerialNode, GroupNode, FunctionNode:
        item = self.append(self.len, label, help=tip, bitmap=icon) # id = index (self.len)

      of TopNode, DirectoryNode:
        item = self.appendSubMenu(NodeMenu(node), label, bitmap=icon)

      of DirMenu:
        item = self.appendSubMenu(PathMenu(node, false), label, bitmap=icon)

      of FileMenu:
        item = self.appendSubMenu(PathMenu(node, true), label, bitmap=icon)

      of RecentMenu:
        item = self.appendSubMenu(RecentMenu(node), label, bitmap=icon)

      of HotkeyMenu:
        item = self.appendSubMenu(HotkeyMenu(node), label, bitmap=icon)

      index.inc
      if item != nil:
        item.data = cast[int](node)
        if disable:
          item.disable()

method realize(self: wPathMenu) =
  self.mRealized = true

  var
    paths: seq[string]
    files = toSeq(walkFiles(self.mPath / self.mPattern)).sorted()
    dirCount = 0

  if self.mFileOnly:
    paths = files

  else:
    paths = toSeq(walkDirs(self.mPath / "*.*")).sorted()
    dirCount = paths.len
    paths &= files

  for i in 0..<paths.len:
    let
      path = paths[i]
      (_, name, ext) = splitFile(path)
      title = name & ext

    var pathNode = MenuNode()
    self.mNodes.add pathNode
    pathNode.attribs["path"] = path
    pathNode.attribs["title"] = title

    if self.mShowIcon:
      withLock main.icoLock:
        pathNode.small = main.icoCache.getBitmap(
          IcoShell(path, main.icoSize)
        )

    if i < dirCount:
      pathNode.attribs["mode"] = "dirmenu"
      pathNode.attribs["arg"] = self.mPattern
      pathNode.attribs["notitle"] = "true"
      pathNode.attribs["nomnemonic"] = $(not self.mMnemonic)
      pathNode.attribs["noicon"] = $(not self.mShowIcon)

  procCall self.wNodeMenu.realize()

method realize(self: wHotkeyMenu) =
  self.mRealized = true

  self.mNodes = main.root.filter do (node: MenuNode) -> bool:
    let hotkey = node.attribs{"hotkey"}
    if hotkey != "":
      return true

  procCall self.wNodeMenu.realize()

method realize(self: wRecentMenu) =
  self.mRealized = true
  self.mNodes = recentNodes()
  procCall self.wNodeMenu.realize()

  if self.mNodes.len != 0:
    self.appendSeparator()
    let node = MenuNode()
    node.attribs["special"] = "recentclear"
    self.mNodes.add node

    var item = self.append(self.len, !Clear_Recent_Items)
    if item != nil:
      item.data = cast[int](node)

when defined(script):
  proc runScript(script: string, node: SimpleNode): seq[SimpleNode] =
    {.gcsafe.}:
      var threadNode {.threadvar.}: SimpleNode
      threadNode = node
      withInstantVm:
        try:
          vm.def:
            block:
              proc new(vm: NpVm, n: SimpleNode): NpVar =
                result = vm["lang"]{"Node"}()
                result[] = n

            [+lang]:
              [Node] of SimpleNode:
                "_init" do (self: var SimpleNode, map: NpVar = NpNil):
                  if map of NpMap:
                    for k, v in map:
                      self.attribs[$k] = $v

                add do (self: var SimpleNode, child: SimpleNode):
                  self.children.add child

                insert do (self: var SimpleNode, child: SimpleNode, index = 0):
                  self.children.insert(child, index)

                delete do (self: var SimpleNode, i: int):
                  self.children.delete(i)

                pop do (self: var SimpleNode) -> SimpleNode:
                  return self.children.pop()

                len do (self: SimpleNode) -> int:
                  return self.children.len

                children do (vm: NpVm, self: SimpleNode) -> NpVar:
                  var list = vm.list()
                  for child in self.children:
                    list.add vm.new(child)
                  return list

                "_setter" do (self: var SimpleNode, key: string, val: string):
                  self.attribs[key] = val

                "_getter" do (vm: NpVm, self: SimpleNode, key: string) -> string:
                  return self.attribs{key}

                "_str" do (self: SimpleNode) -> string:
                  return $self

                "_call" do (vm: NpVm, self: SimpleNode) -> NpVar:
                  let map = vm.map()
                  for key, val in self.attribs:
                    map[key] = val
                  return map

            "_" do () -> SimpleNode:
              return threadNode

          let ret = vm.run """
            this = _()
            _ = null
          """ & "\n\n" & script

          try:
            # the script can return both node or list of nodes
            if ret of NpList:
              for n in ret:
                result.add to[SimpleNode](n)

            else:
              result.add to[SimpleNode](ret)

          except NimPkError:
            discard

        except NimPkError:
          echo "[ERROR] " & getCurrentExceptionMsg()

# proc runScriptTimeout(attr: Attribs, timeout: float, prompt=false): int =
#   var th: Thread[Attribs]
#   createThread(th, runScript, attr)
#   var time = cpuTime()
#   while th.running():
#     os.sleep(100)
#     if cpuTime() - time > timeout:
#       if prompt:
#         case MessageDialog(message="timeout, stop?", caption="info",
#           style=wYesNo).display()

#         of wIdYes:
#           TerminateThread(th.handle, 0)
#           return

#         of wIdNo:
#           time = cpuTime()

#         else: discard

#       else:
#         TerminateThread(th.handle, 0)
#         return

proc executable(node: MenuNode): bool =
  case node.attribs{"show"}
  of "disable": return false
  of "win32":
    if isWin64(): return false
  of "win64":
    if not isWin64(): return false
  of "hide":
    discard # "hide" mode can be executed by hotkey or click on button, etc
  else:
    discard

  return node.nkind() in ExecutableKinds

proc toJob(node: MenuNode): Job =
  if not node.executable():
    return Job(kind: Nop)

  if node.children.len == 0:
    return Job(kind: Work, attribs: node.attribs)

  else:
    case node.attribs{"mode"}
    of "group":
      result = Job(kind: Async)
      for child in node.children:
        result.asyncs.add toJob(child)

    of "serial":
      result = Job(kind: Sync)
      for child in node.children:
        result.syncs.add toJob(child)

    else: UNREACHABLE()

proc exec(job: Job) {.thread.} =
  case job.kind
  of Work:
    let attr = job.attribs
    if attr{"script"} != "":
      when defined(script):
        var
          script = attr{"script"}
          simpleNode = SimpleNode(attribs: attr)

        simpleNode.attribs.del("script")
        var nodes = runScript(script, simpleNode)
        {.gcsafe.}:
          for n in nodes:
            n.toMenuNode().walk do (node: MenuNode):
              let file = node.getIcoPath()
              if file != "":
                withLock main.icoLock:
                  discard main.icoCache.getData IcoShell(file, main.icoSize)

        {.gcsafe.}:
          withLock main.channelLock:
            main.scriptChannel.send(nodes.pack())
            main.mainFrame.queueMessage(wEvent_ScriptReturn)
      else:
        echo "Script is not supported."

    else:
      let
        path = attr{"path"}.env()
        arg = attr{"arg"}
        dir = attr{"dir"}
        show = case attr{"mode"}
          of "min": poMinimize
          of "max": poMaximize
          else: poShow

      discard shellExecuteWait(path, arg, dir, show=show)

  of Async:
    var ths = newSeq[Thread[Job]](job.asyncs.len)
    for i in 0..<job.asyncs.len:
      createThread(ths[i], exec, job.asyncs[i])
    joinThreads(ths)

  of Sync:
    for job in job.syncs:
      exec(job)

  of Nop:
    discard

proc exec(node: MenuNode, wait = false) =
  let job = toJob(node)
  if job.kind != Nop:

    if wait or main.mainFrame == nil:
      exec(job)

    else:
      var th: Thread[Job]
      createThread(th, exec, job)

      # ensure `th` won't be destroyed before the thread ends
      main.mainFrame.await(th, 0.1):
        discard

proc execAtStartOrExit(option: NodeOption) =
  case option
  of AtStart:
    for node in main.optionMap{option}:
      exec(node, wait=false)

  of AtExit:
    var job = Job(kind: Async)
    for node in main.optionMap{option}:
      job.asyncs.add toJob(node)

    exec(job)

  else: UNREACHABLE()

proc launch(setup: LaunchSetup) =
  main.launchSetup = setup

  case setup.kind
  of AdaptiveItem:
    if setup.nodes.len == 1:
      launch LaunchSetup(
        kind: SingleItem,
        node: setup.nodes[0]
      )
    else:
      launch LaunchSetup(
        kind: MultipleItem,
        nodes: setup.nodes,
        title: setup.title,
        mnemonic: setup.mnemonic,
        showHotkey: setup.showHotkey,
        showIcon: setup.showIcon
      )

  of SingleItem:
    let
      node = main.launchSetup.node
      nkind = node.nkind()

    case node.nkind()
    of RootNode, SeparatorNode:
      UNREACHABLE()

    of EntryNode, GroupNode, SerialNode:
      exec(node)
      if not node.hasOption("norecent"):
        recentAdd(node)
        saveConfig()

    of TopNode, DirectoryNode, DirMenu, FileMenu,
        RecentMenu, HotkeyMenu:
      main.menuWindow.queueMessage(wEvent_LaunchMenu)

    of FunctionNode:
      case node.attribs{"special"}
      of "search":
        EndMenu()
        main.mainFrame.queueMessage(wEvent_ShowSearch)

      of "exit":
        EndMenu()
        main.mainFrame.queueMessage(wEvent_Exit)

      of "setting":
        EndMenu()
        main.mainFrame.queueMessage(wEvent_ShowMain)

      of "about":
        EndMenu()
        main.mainFrame.queueMessage(wEvent_ShowAbout)

      of "recentclear":
        EndMenu()
        main.mainFrame.queueMessage(wEvent_ClearRecent)

      else: discard

  of MultipleItem:
    main.menuWindow.queueMessage(wEvent_LaunchMenu)

wClass(wMenuWindow of wWindow):

  # handle page up/page down events during menu popup.
  proc lowLevelKeyProc(nCode: int32, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
    if wParam == WM_KEYDOWN:
      let pHookStruct = cast[LPKBDLLHOOKSTRUCT](lParam)
      if pHookStruct.vkCode == wKey_PgUp:
        main.menuWindow.queueMessage(wEvent_LaunchNextMenu, 0, 0)
        return 1

      elif pHookStruct.vkCode == wKey_PgDn:
        main.menuWindow.queueMessage(wEvent_LaunchPrevMenu, 0, 0)
        return 1

    return CallNextHookEx(0, nCode, wParam, lParam)

  # handle mouse wheel during menu popup.
  proc lowLevelMouseProc(nCode: cint, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
    if wParam == WM_MOUSEWHEEL:
      let pHookStruct = cast[LPMSLLHOOKSTRUCT](lParam)

      if pHookStruct.mouseData < 0:
        main.menuWindow.queueMessage(wEvent_LaunchNextMenu, 0, 0)
        return 1

      elif pHookStruct.mouseData > 0:
        main.menuWindow.queueMessage(wEvent_LaunchPrevMenu, 0, 0)
        return 1

    return CallNextHookEx(0, nCode, wParam, lParam)

  # handle mouse wheel events when the mouse is at the screen edge.
  proc lowLevelMouseProcEdge(nCode: cint, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
    if wParam == WM_MOUSEWHEEL:
      main.mainFrame.queueMessage(wEvent_MouseWheelEdge)
      return 1

    return CallNextHookEx(0, nCode, wParam, lParam)

  proc popupMenu(self: wMenuWindow, menu: wNodeMenu) =
    # This method might reenter during wWindow.popupMenu
    # (via wEvent_LaunchNextMenu, etc). If reentry happens,
    # wWindow.popupMenu(menu) will fail before EndMenu().
    # To prevent this, we avoid calling wWindow.popupMenu
    # until the old popup menu is closed. Instead, we enqueue
    # wEvent_LaunchMenu again so that the menu will eventually pop up.
    var duringPopup {.global.} = false
    EndMenu()

    if not duringPopup:
      duringPopup = true
      var hHookMouse = SetWindowsHookEx(WH_MOUSE_LL, lowLevelMouseProc, 0, 0)
      var hHookKey = SetWindowsHookEx(WH_KEYBOARD_LL, lowLevelKeyProc, 0, 0)

      self.wWindow.popupMenu(menu)

      UnhookWindowsHookEx(hHookKey)
      UnhookWindowsHookEx(hHookMouse)
      duringPopup = false

    else:
      self.queueMessage(wEvent_LaunchMenu)

  proc handleMenuLaunch(self: wMenuWindow) =

    self.wEvent_LaunchNextMenu do ():
      # find the next menu that can be launched
      if main.launchSetup.kind == SingleItem:
        let node = main.launchSetup.node
        if not node.hasOption("nowheel"):
          let menuSibling = nextOrPrevMenuSibling(node, false)
          if menuSibling != nil:
            launch LaunchSetup(
              kind: SingleItem,
              node: menuSibling
            )
            return

      # otherwise, launch itself again (not found or kind == MultipleItem)
      self.queueMessage(wEvent_LaunchMenu)

    self.wEvent_LaunchPrevMenu do ():
      # find the prev menu that can be launched
      if main.launchSetup.kind == SingleItem:
        let node = main.launchSetup.node
        if not node.hasOption("nowheel"):
          let menuSibling = nextOrPrevMenuSibling(node, true)
          if menuSibling != nil:
            launch LaunchSetup(
              kind: SingleItem,
              node: menuSibling
            )
            return

      # otherwise, launch itself again (not found or kind == MultipleItem)
      self.queueMessage(wEvent_LaunchMenu)

    self.wEvent_LaunchMenu do (event: wEvent):
      case main.launchSetup.kind
      of AdaptiveItem:
        UNREACHABLE()

      of MultipleItem:
        self.popupMenu NodeMenu(
          main.launchSetup.nodes,
          main.launchSetup.title,
          main.launchSetup.mnemonic,
          main.launchSetup.showHotkey,
          main.launchSetup.showIcon
        )

      of SingleItem:
        let
          node = main.launchSetup.node
          nkind = node.nkind()

        assert nkind in MenuKinds
        case node.nkind:
        of TopNode, DirectoryNode:
          self.popupMenu(NodeMenu(node))

        of RecentMenu:
          self.popupMenu(RecentMenu(node))

        of HotkeyMenu:
          self.popupMenu(HotkeyMenu(node))

        of DirMenu, FileMenu:
          let fileOnly = (nkind == FileMenu)
          if node.hasOption("noicon"):
            self.popupMenu(PathMenu(node, fileOnly=fileOnly))

          else:
            if main.busy: return
            main.busy = true

            type Input = object
              fileOnly: bool
              path: string
              pattern: string

            proc thread(input: Input) {.thread.} =
              for file in walkFiles(input.path / input.pattern):
                {.gcsafe.}:
                  withLock main.icoLock:
                    discard main.icoCache.getData IcoShell(file, main.icoSize)

              if not input.fileOnly:
                for dir in walkDirs(input.path / "*.*"):
                  {.gcsafe.}:
                    withLock main.icoLock:
                      discard main.icoCache.getData IcoShell(dir, main.icoSize)

            var
              th: Thread[Input]
              path = node.attribs{"path"}.env()
              pattern = node.attribs{"arg", "*.*"}
              menuShown = false

            createThread(th, thread,
              Input(fileOnly: fileOnly, path: path, pattern: pattern)
            )

            self.await(th, 0.1):
              if menuShown: return

              # and avoid timer proc reentering during popupMenu
              menuShown = true

              self.popupMenu(PathMenu(node, fileOnly=fileOnly))
              main.busy = false

        else: discard

  proc handleTooltip(self: wMenuWindow) =
    var
      tooltip = ToolTip()
      hotMenu: HWND
      hotItem: wMenuItem

    self.wEvent_MenuHighlight do (event: wEvent):
      event.skip()
      hotMenu = event.lParam
      if hotItem == nil:
        self.startTimer(0.4) do (event: wEvent):
          while true:
            if hotMenu == 0: break

            var pt: POINT
            if GetCursorPos(pt) == 0: break

            let index = MenuItemFromPoint(self.handle, hotMenu, pt)
            if index < 0: break

            var rect: RECT
            if GetMenuItemRect(0, hotMenu, index, rect) == 0: break

            var menuHwnd: HWND = 0
            while true:
              menuHwnd = FindWindowEx(0, menuHwnd, "#32768", nil)
              if menuHwnd == 0 or SendMessage(menuHwnd, MN_GETHMENU, 0, 0) == hotMenu:
                break
            if menuHwnd == 0: break

            let menuBase = MenuBase(hotMenu)
            if menuBase == nil or not (menuBase of wNodeMenu): break

            let nodeMenu = wNodeMenu menuBase
            assert index < nodeMenu.len
            let item = nodeMenu[index]
            if item == hotItem:
              # don't use break here (tooltip will be hidden)
              return

            if item.help == "": break

            tooltip.setTip(
              item.help,
              pos=(int rect.left + main.icoSize + 10, int rect.bottom)
            )
            tooltip.show()
            hotItem = item

            return

          # after break of while, end the tip
          hotMenu = 0
          hotItem = nil
          tooltip.hide()
          event.stopTimer()


  proc init(self: wMenuWindow) =
    self.wWindow.init()
    self.handleTooltip()
    self.handleMenuLaunch()

    self.WM_INITMENUPOPUP do (event: wEvent):
      let menuBase = MenuBase(HMENU event.wParam)
      if menuBase != nil and menuBase of wNodeMenu:
        let nodeMenu = wNodeMenu menuBase
        if not nodeMenu.mRealized:
          nodeMenu.realize()

    self.wEvent_Menu do (event: wEvent):
      let node = event.menuItem.node()
      if node != nil:
        launch LaunchSetup(
          kind: SingleItem,
          node: node
        )

    self.wEvent_MenuRightClick do (event: wEvent):
      type
        MenuId = enum
          OpenPath = 1, CopyPath, ItemSetting, RemoveFromRecent, IdLast

      let node = event.menuItem.node()
      if node != nil:
        var
          menu = Menu()
          path = node.attribs{"path"}.env().whereIs()
          id: wCommandID

        if path.pathExist():
          menu.append(OpenPath, !Open_Path)
          menu.append(CopyPath, !"Copy_&Full_Path")
          menu.append(ItemSetting, !Item_Setting)
          if node.attribs{"recent"} != "":
            menu.append(RemoveFromRecent, !Remove_From_Recent_Items)
          menu.appendSeparator()
          id = self.shellContextMenu(menu, path, ord IdLast)

        else:
          menu.append(ItemSetting, !Item_Setting)
          if node.attribs{"recent"} != "":
            menu.append(RemoveFromRecent, !Remove_From_Recent_Items)
          id = self.popupMenu(menu, flag=wPopMenuReturnId or wPopMenuRecurse)

        case id
        of OpenPath:
          shellExecute(if path.dirExist: path else: path.dirPart)

        of CopyPath:
          wSetClipboard(DataObject(path))
          wFlushClipboard()

        of ItemSetting:
          if node.item.isOk:
            node.item.select()
            main.mainFrame.queueMessage(wEvent_ShowMain)

        of RemoveFromRecent:
          node.attribs.del("recent")

        else: discard

wClass(wWaitFrame of wFrame):

  proc init(self: wWaitFrame, owner: wWindow) =
    const png = staticRead(r"resources/wait.png")
    self.mImage = Image(png)
    let size = self.mImage.size

    self.wFrame.init(owner, size=size, style=0)
    self.clearWindowStyle(wCaption)
    self.setDraggable(true)
    self.shape = Region(self.mImage)

    let screenSize = wGetScreenSize()
    self.move(screenSize.width - size.width - 50,
      screenSize.height - size.height - 50)

    self.wEvent_Paint do (event: wEvent):
      var dc = PaintDC(self)
      dc.drawImage(self.mImage)

  proc show(self: wWaitFrame) =
    self.wWindow.show()
    wAuto.setOnTop(wAuto.Window self.handle)

wClass(wMainFrame of wFrame):

  template withoutRedraw(self: wMainFrame, body: untyped): untyped =
    # must reenterable
    var reset = false
    if not self.mUndrawable:
      reset = true
      self.setRedraw(false)
      self.mUndrawable = true

    body

    if reset:
      self.setRedraw(true)
      self.mUndrawable = false

  template withFocusedItem(self: wMainFrame, body: untyped) =
    let item {.inject.} = self.mTreeCtrl.focusedItem
    if item.isOk:
      body

  template withFocusedNode(self: wMainFrame, body: untyped) =
    let item = self.mTreeCtrl.focusedItem
    if item.isOk:
      let node {.inject.} = item.node()
      assert node != nil
      body

  template withFocusedNode(self: wMainFrame, body: untyped, body2) =
    let item = self.mTreeCtrl.focusedItem
    if item.isOk:
      let node {.inject.} = item.node()
      assert node != nil
      body
    else:
      body2

  proc layout(self: wMainFrame) =
    let
      H = self.mBaseElement.size.height

    var
      maxLabelWidth: int
      gapX = newVariable()
      gapY = newVariable()

    once:
      for L in [self.mLabelTitle, self.mLabelPath, self.mLabelArg,
          self.mLabelDir, self.mLabelTip, self.mLabelIcon,
          self.mLabelHotkey, self.mLabelOption, self.mLabelBind]:
        maxLabelWidth = max(maxLabelWidth, L.bestSize.width)

    self.mPanel.autolayout """
      alias:
        tree=`self.mTreeCtrl`
        new=`self.mButtonNew` del=`self.mButtonDel` copy=`self.mButtonCopy` paste=`self.mButtonPaste`
        L=`self.mButtonLeft` U=`self.mButtonUp` D=`self.mButtonDown` R=`self.mButtonRight`
        image=`self.mStaticBitmap` show=`self.mComboBoxShow` mode=`self.mComboBoxMode`
        title=`self.mTextCtrlTitle` path=`self.mTextCtrlPath` arg=`self.mTextCtrlArg`
        dir=`self.mTextCtrlDir` tip=`self.mTextCtrlTip` icon=`self.mTextCtrlIcon`
        hotkey=`self.mHotkeyCtrl` option=`self.mCheckComboOption` bind=`self.mCheckComboBind`
        L1=`self.mLabelTitle` L2=`self.mLabelPath` L3=`self.mLabelArg`
        L4=`self.mLabelDir` L5=`self.mLabelTip` L6=`self.mLabelIcon`
        L7=`self.mLabelHotkey` L8=`self.mLabelOption` L9=`self.mLabelBind`
        I1=title, I2=path, I3=arg, I4=dir, I5=tip, I6=icon, I7=hotkey, I8=option, I9=bind
        choose=`self.mButtonIcon` browse=`self.mButtonBrowse` script=`self.mButtonScript`
        exec=`self.mButtonExec` setting=`self.mButtonSetting`
        undo=`self.mButtonUndo` redo=`self.mButtonRedo` ok=`self.mButtonOk`
        hr1=`self.mStaticLine1` hr2=`self.mStaticLine2`
        console=`self.mConsole`

      batch:
        arrows = U,D,L,R
        btns1 = new, del, copy, paste
        btns2 = choose, browse, script, exec
        btns3 = setting, undo, redo, ok
        combos = show, mode

      # top
      spacing: `H` / 2 - 1
      H: |-[tree]-[new,del,copy,paste]-|
      H: [tree]-[L]-2-[U,D]-2-[R]-|
      V: |-[tree]-15-[hr1]
      V: |-[new]-[del]-[copy]-[paste]->[U]-2-[L,D,R]-15-[hr1]

      HV: [arrows(`H` + 1)]
      V: [btns1(`H` + 1)]

      H: |-[console]-|
      V: |-[console]
      C: console.bottom = tree.bottom

      # middle
      H: |-[image,show,mode]-[hr1]-|
      H: |-[image]-15-[L1..9]-5-[I1..9]-[choose,browse,script,exec]-|
      H: |-[hr2]-|

      V: [image]-[show]-[mode]
      V: [hr1]-15-[choose]-[browse]-[script]-[exec]
      V: [hr1]-15-[title]-6-[path]-6-[arg]-6-[dir]-6-[tip]-6-[icon]-6-[hotkey]-6-[option]-6-[bind]-15-[hr2]
      C: image.top = hr1.top

      HV: [image(`H` * 9 / 2)]
      H: [btns2(new)]
      V: [combos(`H`),btns2(`H`)]
      V: [I1..9(`H` - 2)]
      H: [L1..9(`maxLabelWidth`)]
      V: [L1(L1.bestHeight)]
      V: [L2..9(L1)]
      V: [hr1..2(hr1.defaultHeight)]

      C:
        L1.centerY = I1.centerY
        L2.centerY = I2.centerY
        L3.centerY = I3.centerY
        L4.centerY = I4.centerY
        L5.centerY = I5.centerY
        L6.centerY = I6.centerY
        L7.centerY = I7.centerY
        L8.centerY = I8.centerY
        L9.centerY = I9.centerY

      # bottom
      spacing: `H` / 2 + 1
      H: [setting]-[undo]-[redo]-[ok]-|
      V: [hr2]-[setting,undo,redo,ok]-|
      H: [btns3(new)]
      V: [btns3(`H` + 3)]

      C:
        gapX = setting.left - image.right
        gapY = U.top - paste.bottom
    """

    once:
      let
        width = self.mPanel.layoutSize.width - (int gapX.value) + H div 2 + 1
        height = self.mPanel.layoutSize.height - (int gapY.value) + H div 2 + 1

      self.minClientSize = (width, height)

  proc initUi(self: wMainFrame) =
    self.mPanel = Panel(self, style=wClipChildren)
    self.mTreeCtrl = TreeCtrl(self.mPanel, style=wTrShowSelectAlways or wTrEditLabels)
    self.mButtonNew = Button(self.mPanel, label = !New)
    self.mButtonDel = Button(self.mPanel, label = !Del)
    self.mButtonCopy = Button(self.mPanel, label = !Copy)
    self.mButtonPaste = Button(self.mPanel, label = !Paste)
    self.mButtonLeft = Button(self.mPanel)
    self.mButtonUp = Button(self.mPanel)
    self.mButtonDown = Button(self.mPanel)
    self.mButtonRight = Button(self.mPanel)
    self.mStaticBitmap = StaticBitmap(self.mPanel, style=wBorderStatic or wSbCenter)
    self.mComboBoxShow = ComboBox(self.mPanel, style=wCbReadOnly)
    self.mComboBoxMode = ComboBox(self.mPanel, style=wCbReadOnly)
    self.mLabelTitle = StaticText(self.mPanel, label = !Title & ':')
    self.mLabelPath = StaticText(self.mPanel, label = !Path & ':')
    self.mLabelArg = StaticText(self.mPanel, label = !Args & ':')
    self.mLabelDir = StaticText(self.mPanel, label = !Dir & ':')
    self.mLabelTip = StaticText(self.mPanel, label = !Tip & ':')
    self.mLabelIcon = StaticText(self.mPanel, label = !Icon & ':')
    self.mLabelHotkey = StaticText(self.mPanel, label = !Hotkey & ':')
    self.mLabelOption = StaticText(self.mPanel, label = !Option & ':')
    self.mLabelBind = StaticText(self.mPanel, label = !Binding & ':')
    self.mTextCtrlTitle = CompactTextCtrl(self.mPanel, style=wBorderSunken)
    self.mTextCtrlPath = CompactTextCtrl(self.mPanel, style=wBorderSunken)
    self.mTextCtrlArg = CompactTextCtrl(self.mPanel, style=wBorderSunken)
    self.mTextCtrlDir = CompactTextCtrl(self.mPanel, style=wBorderSunken)
    self.mTextCtrlTip = CompactTextCtrl(self.mPanel, style=wBorderSunken)
    self.mTextCtrlIcon = CompactTextCtrl(self.mPanel, style=wBorderSunken)
    self.mHotkeyCtrl = HotkeyCtrl(self.mPanel, style=wBorderSunken)
    self.mCheckComboOption = CheckComboBox(self.mPanel, style=wCcEndEllipsis or wCcNormalColor)
    self.mCheckComboBind = CheckComboBox(self.mPanel, style=wCcEndEllipsis or wCcNormalColor)
    self.mButtonIcon = Button(self.mPanel, label = !Icon)
    self.mButtonBrowse = Button(self.mPanel, label = !Browse)
    self.mButtonScript = Button(self.mPanel, label = !Script)
    self.mButtonExec = Button(self.mPanel, label = !Execute)
    self.mButtonSetting = Button(self.mPanel, label = !Setting)
    self.mButtonUndo = Button(self.mPanel, label = !Undo)
    self.mButtonRedo = Button(self.mPanel, label = !Redo)
    self.mButtonOk = Button(self.mPanel, label = !Ok)
    self.mStaticLine1 = StaticLine(self.mPanel)
    self.mStaticLine2 = StaticLine(self.mPanel)
    self.mConsole = Console(self.mPanel, style=wLbMultiple or wLbNeededScroll or wLbExtended)
    self.mBaseElement = Button(self.mPanel, label="XXXXXX")

    self.mBaseElement.fit()
    self.mBaseElement.hide()

    self.mConsole.font = Font(10.0, faceName="Consolas")
    self.mConsole.hide()
    self.mConsole.lift()

    const
      imageUp = staticRead("resources/up.ico")
      imageDown = staticRead("resources/down.ico")
      imageLeft = staticRead("resources/left.ico")
      imageRight = staticRead("resources/right.ico")
      imageSetting = staticRead("resources/setting.ico")
      imageUndo = staticRead("resources/undo.ico")
      imageRedo = staticRead("resources/redo.ico")
      imageOk = staticRead("resources/ok.ico")

    for button, image in {
        self.mButtonUp: imageUp,
        self.mButtonDown: imageDown,
        self.mButtonLeft: imageLeft,
        self.mButtonRight: imageRight,
      }.items:

      withLock main.icoLock:
        button.setBitmap(main.icoCache.getBitmap(IcoData(image, 16)))
      button.setBitmapPosition(wCenter)

    for button, image in {
        self.mButtonSetting: imageSetting,
        self.mButtonUndo: imageUndo,
        self.mButtonRedo: imageRedo,
        self.mButtonOk: imageOk,
      }.items:

      withLock main.icoLock:
        button.setBitmap(main.icoCache.getBitmap(IcoData(image, 16)))
      button.setBitmap4Margins(8, 0, 5, 0)

    if wGetWinVersion() >= 6.0:
      self.mTreeCtrl.sendMessage(TVM_SETEXTENDEDSTYLE,
        TVS_EX_DOUBLEBUFFER, TVS_EX_DOUBLEBUFFER)

    self.mTextCtrlPath.enableAutoComplete(wAcFile)
    self.mTextCtrlDir.enableAutoComplete(wAcDir)

    self.mPanel.wEvent_Size do ():
      self.layout()

    self.layout()

  proc handleClientSizeFactor(self: wMainFrame) =
    let
      factorx = main.root.getFloat("factorx", 24)
      factory = main.root.getFloat("factory", 24)
      baseHeight = float self.mBaseElement.size.height

    self.clientSize = (int(baseHeight * factorx), int(baseHeight * factory))

    self.wEvent_Size do (event: wEvent):
      event.skip()
      if not self.isMaximized:
        let
          clientSize = self.clientSize
          baseHeight = self.mBaseElement.size.height

        main.root.attribs["factorx"] = fmt"{(clientSize.width / baseHeight):.2f}"
        main.root.attribs["factory"] = fmt"{(clientSize.height / baseHeight):.2f}"

  proc createTreeNode(self: wMainFrame,
      node: MenuNode = nil, parent: MenuNode = nil, pos = -1) =
    # 'pos' only sets the position for the first child node.

    proc treeAdd(node: MenuNode, parent: MenuNode = nil, pos = -1) =
      # create an empty item for the root,
      # enabling insertItem to work when parent.item == root.
      if node == main.root:
        node.item = TreeItem(self.mTreeCtrl, 0)
        return

      let title = node.title()
      node.item =
        if parent != nil:
          if pos != -1:
            self.mTreeCtrl.insertItem(parent.item, pos, title)
          else:
            self.mTreeCtrl.appendItem(parent.item, title)
        else:
          self.mTreeCtrl.addRoot(title)

      node.item.data = cast[int](node)

    let node = node or main.root
    treeAdd(node, parent, pos)
    for child in node.children:
      self.createTreeNode(child, node)

  proc loadTreeImage(self: wMainFrame, node: MenuNode = nil) =

    proc tryLoadImage(child: MenuNode): bool =
      let file = child.getIcoPath()
      if file != "":
        withLock main.icoLock:
          child.small = main.icoCache.getBitmap(IcoPath(file, main.icoSize))
          child.large = main.icoCache.getBitmap(IcoPath(file, 64))

        if child.small != nil:
          let index = main.imageList.add(child.small)
          child.item.setImage(index)
          return true

    if node == nil:
      self.mTreeCtrl.setImageList(main.imageList)
      self.mTreeCtrl.setIndent(0)

    walk(node or main.root) do (node: MenuNode):

      case node.nkind()
      of RootNode:
        discard

      of TopNode:
        if not node.tryLoadImage():
          node.item.setImage(main.staticImage[IconDot].index)
          node.small = main.staticImage[IconDot].small
          # node.large = main.staticImage[IconDot].large

      of SeparatorNode:
        node.item.setImage(main.staticImage[IconLine].index)
        # node.small = main.staticImage[IconLine].small
        # node.large = main.staticImage[IconLine].large

      of DirectoryNode, GroupNode, SerialNode:
        if not node.tryLoadImage():
          node.item.setImage(main.staticImage[IconFolder].index)
          node.small = main.staticImage[IconFolder].small
          node.large = main.staticImage[IconFolder].large

      of EntryNode, FunctionNode, DirMenu, FileMenu,
          RecentMenu, HotkeyMenu:
        # TODO: ico for function
        if not node.tryLoadImage():
          node.item.setImage(main.staticImage[IconEmpty].index)
          node.small = main.staticImage[IconEmpty].small
          node.large = main.staticImage[IconEmpty].large

  proc resetHotkeyAndOption(self: wMainFrame) =
    main.optionMap.clear()
    var newHotkeyMap: Table[Hotkey, HashSet[MenuNode]]

    walk(main.root) do (node: MenuNode):
      let hotkey = wStringToHotkey(node.attribs{"hotkey"})
      if hotkey != default(Hotkey):
        newHotkeyMap.mgetOrPut(hotkey, initHashSet[MenuNode]()).incl(node)

      for op in NodeOption:
        if node.hasOption($op):
          main.optionMap.mgetOrPut(op, initHashSet[MenuNode]()).incl(node)

    var
      s1 = toHashSet(toSeq(newHotkeyMap.keys))
      s2 = toHashSet(toSeq(main.hotkeyMap.keys))

    main.hotkeyMap = newHotkeyMap

    # old hotkey need to be unregistered
    for hotkey in s2 - s1:
      # echo "unregister hotkey: ", wHotkeyToString(hotkey)
      self.unregisterHotKeyEx(hotkey.hash())

    # new hotkey need to be registered
    for hotkey in s1 - s2:
      # echo "register hotkey: ", wHotkeyToString(hotkey)
      self.registerHotKeyEx(hotkey.hash(), hotkey)

  proc updateUi(self: wMainFrame, node: MenuNode) =
    let
      Title = self.mTextCtrlTitle
      Path = self.mTextCtrlPath
      Arg = self.mTextCtrlArg
      Dir = self.mTextCtrlDir
      Tip = self.mTextCtrlTip
      Icon = self.mTextCtrlIcon
      Hotkey = self.mHotkeyCtrl
      Option = self.mCheckComboOption
      Bind = self.mCheckComboBind
      Show = self.mComboBoxShow
      Mode = self.mComboBoxMode
      Select = self.mButtonIcon
      Browse = self.mButtonBrowse
      Script = self.mButtonScript
      Exec = self.mButtonExec
      Bitmap = self.mStaticBitmap

    # Fix the compiler bug about "ambiguous identifier: 'wControl'"
    type
      wControl = wTypes.wControl

    proc enable(controls: var Table[wControl, bool], list: varargs[wControl]) =
      for control in list:
        controls[control] = true

    proc disable(controls: var Table[wControl, bool], list: varargs[wControl]) =
      for control in list:
        controls[control] = false

    proc update(controls: Table[wControl, bool], keepContents: HashSet[wControl]) =
      for control, enable in controls:
        control.enable(enable)

        # reset controls state
        if enable:
          if not (control of wApp.wButton):
            control.setBackgroundColor(wWhite)

        else:
          if not (control of wApp.wButton):
            control.setBackgroundColor(GetSysColor(COLOR_BTNFACE))

          # clear the content if control is disabled
          if control notin keepContents:

            if control of wApp.wTextCtrl:
              control.wTextCtrl.changeValue("")

            elif control of wApp.wComboBox:
              control.wComboBox.clear()

            elif control of wApp.wHotkeyCtrl:
              control.wHotkeyCtrl.changeHotkey((0, 0))

            elif control of wApp.wCheckComboBox:
              control.wCheckComboBox.changeStyle(wCcEndEllipsis)
              control.wCheckComboBox.empty = ""
              control.wCheckComboBox.clear()

    proc updateComboBox(comboBox: wComboBox, table: Attribs, option: string) =
      comboBox.attribsTable = table
      comboBox.clear()
      for value in table.values:
        comboBox.append(translate(value))
      comboBox.changeValue(translate(table{option, table[""]}))

    proc updateCheckComboBox(checkComboBox: wCheckComboBox, table: Attribs, node: MenuNode) =
      checkComboBox.attribsTable = table
      checkComboBox.changeStyle(wCcEndEllipsis or wCcNormalColor)
      checkComboBox.clear()
      checkComboBox.empty = !None
      for key, value in table:
        checkComboBox.append(translate(value))
        if node.hasOption(key):
          checkComboBox.select(checkComboBox.len - 1)
        # if key == "trayleftdouble":
        #   checkComboBox.disable(checkComboBox.len - 1)

    var
      controls: Table[wControl, bool]
      keepContents: HashSet[wControl]

    # disable all by default
    controls.disable(Title, Path, Arg, Dir, Tip, Icon, Hotkey,
      Option, Bind, Show, Mode, Select, Browse, Script, Exec)

    if node == nil:
      # disable all by default
      Bitmap.setBitmap(nil)
      controls.update(keepContents)
      return

    let
      nkind = node.nkind()
      isMenu = nkind in MenuKinds

    case nkind
    of RootNode:
      UNREACHABLE()

    of SeparatorNode:
      controls.enable(Show)
      Bitmap.setBitmap(main.staticImage[IconLine].large)
      Title.changeValue(!Separator)
      keepContents.incl(Title)

    of FunctionNode, RecentMenu, HotkeyMenu:
      controls.enable(Title, Icon, Hotkey, Show, Option, Bind, Select, Exec)
      if not isMenu: controls.enable(Tip)
      Bitmap.setBitmap(node.large or main.staticImage[IconEmpty].large)
      Path.changeValue(':' & node.attribs{"special"} & ':')
      keepContents.incl(Path)

    of TopNode:
      controls.enable(Title, Icon, Hotkey, Show, Option, Bind, Select, Exec)
      Bitmap.setBitmap(node.large or main.staticImage[IconMenu].large)

    of DirectoryNode, SerialNode, GroupNode:
      controls.enable(Title, Icon, Hotkey, Show, Mode, Option, Bind, Select, Exec)
      if not isMenu: controls.enable(Tip)
      Bitmap.setBitmap(node.large or main.staticImage[IconFolder].large)

    of EntryNode, DirMenu, FileMenu:
      controls.enable(Title, Path, Arg, Dir, Icon, Hotkey,
        Option, Bind, Show, Mode, Select, Browse, Exec)
      if nkind == EntryNode: controls.enable(Script)
      if not isMenu: controls.enable(Tip)
      Bitmap.setBitmap(node.large or main.staticImage[IconEmpty].large)

    if controls[Show]:
      Show.updateComboBox(ComboShowTable, node.attribs{"show"})

    if controls[Mode]:
      case nkind
      of RootNode, TopNode, FunctionNode, RecentMenu,
          HotkeyMenu, SeparatorNode:
        UNREACHABLE()

      of DirectoryNode, SerialNode, GroupNode:
        Mode.updateComboBox(ComboFolderModeTable, node.attribs{"mode"})

      of DirMenu, FileMenu:
        Mode.updateComboBox(ComboItemModeTable, node.attribs{"mode"})

      of EntryNode:
        if node.attribs{"script"} != "":
          Mode.updateComboBox(ComboItemScriptTable, "")
          controls.disable(Mode)
          keepContents.incl(Mode)

        else:
          Mode.updateComboBox(ComboItemModeTable, node.attribs{"mode"})

    if controls[Option]:
      if isMenu:
        Option.updateCheckComboBox(OptionMenuTable, node)
      else:
        Option.updateCheckComboBox(OptionItemTable, node)

    if controls[Bind]:
      Bind.updateCheckComboBox(OptionBindTable, node)

    if controls[Title]: Title.changeValue(node.attribs{"title"})
    if controls[Path]: Path.changeValue(node.attribs{"path"})
    if controls[Arg]: Arg.changeValue(node.attribs{"arg"})
    if controls[Dir]: Dir.changeValue(node.attribs{"dir"})
    if controls[Tip]: Tip.changeValue(node.attribs{"tip"})
    if controls[Icon]: Icon.changeValue(node.attribs{"icon"})
    if controls[Hotkey]: Hotkey.changeHotkey(wStringToHotkey(node.attribs{"hotkey"}))

    controls.update(keepContents)

  proc updateButtonState(self: wMainFrame) =
    if undoable(): self.mButtonUndo.enable()
    if redoable(): self.mButtonRedo.enable()

    if not undoable():
      if self.mButtonUndo.hasFocus() and redoable():
        self.mButtonRedo.setFocus()
      self.mButtonUndo.disable()

    if not redoable():
      if self.mButtonRedo.hasFocus() and undoable():
        self.mButtonUndo.setFocus()
      self.mButtonRedo.disable()

    if main.copiedNode == nil:
      self.mButtonPaste.disable()
    else:
      self.mButtonPaste.enable()

  proc restoreTreeStatus(self: wMainFrame, node: MenuNode = nil) =
    var selected: MenuNode

    walk(node or main.root) do (node: MenuNode):
      if node.hasOption("expand") and node.item.isOk:
        node.item.expand()

      if node.hasOption("select") and node.item.isOk:
        selected = node

    # ensureVisible must after all item expanding
    if selected != nil and selected.item.isOk:
      selected.item.select()
      selected.item.ensureVisible()

    if main.root.childless():
      self.updateUi(nil)

  proc does(self: wMainFrame, action: var Action, doKind: DoKind): bool {.discardable.} =
    defer:
      self.resetHotkeyAndOption()

      if main.root.childless():
        self.updateUi(nil)

    proc itemSelect(node: MenuNode): MenuNode {.discardable, inline.} =
      if node.item.isOk:
        node.item.select()
      return node

    proc itemEnsureVisible(node: MenuNode): MenuNode {.discardable, inline.} =
      if node.item.isOk:
        node.item.ensureVisible()
      return node

    proc itemDelete(node: MenuNode) {.inline.} =
      if node.item.isOk:
        node.item.delete()
      unlinkTreeNode(node)

    proc updateTextCtrl(ctrl: wTextCtrl, action: Action) =
      # call changeValue during editing will reset the position of cursor
      # to avoid it, we call changeValue only if textctrl don't has the focus
      # it means the value is changed by button or other action
      if not action.alwaysUpdateUi and ctrl.hasFocus():
        return

      if ctrl.value == action.newValue:
        return

      ctrl.changeValue(action.newValue)

    let
      node = action.node
      target = action.target
      kind = action.kind
      attrib = action.attrib

    case kind
    of AddChild:
      case doKind
      of Do, Redo:
        if not target.insertable():
          return false

        target.children.add(node)

        self.withoutRedraw:
          self.createTreeNode(node, target)

        # target may be changed from item to folder
        self.loadTreeImage(target)
        node.itemSelect().itemEnsureVisible()
        return true

      of Undo:
        discard target.children.pop()
        # target may be changed from folder to item
        self.loadTreeImage(target)

        # select item before deleting to avoid focus jumping
        target.itemSelect().itemEnsureVisible()
        node.itemDelete()

    of AddAbove, AddBelow:
      case doKind
      of Do, Redo:
        # sibling of top must be Top, Directory, or insertable Entry
        if target.nkind() == TopNode and
            (node.nkind() notin {TopNode, DirectoryNode, EntryNode} or
              not node.insertable()):
          return false

        var
          parent = target.getParent()
          pos = target.position()

        assert parent != nil
        if kind == AddBelow: pos.inc
        parent.insert(node, pos)

        self.withoutRedraw:
          self.createTreeNode(node, parent, pos)

        self.loadTreeImage(node)
        node.itemSelect().itemEnsureVisible()
        return true

      of Undo:
        let
          parent = node.getParent()
          pos = node.position()
        assert parent != nil
        parent.delete(pos)

        # select item before deleting to avoid focus jumping
        target.itemSelect().itemEnsureVisible()
        node.itemDelete()

    of MoveInto:
      case doKind
      of Do, Redo:
        if not target.insertable():
          return false

        let oldParent = node.getParent()
        action.oldParent = oldParent
        action.pos = node.position()

        # cancel this action if move into the same parent
        if oldParent == target:
          return false

        oldParent.delete(action.pos)
        target.add(node)

        # select new item before deleting the old one to avoid focus jumping
        let oldItem = node.item
        self.withoutRedraw:
          self.createTreeNode(node, target)
          node.itemSelect()
          oldItem.delete()

        # target may be changed from item to folder
        # oldParent may be changed from folder to item
        self.loadTreeImage(target)
        self.loadTreeImage(oldParent)
        node.itemEnsureVisible()
        return true

      of Undo:
        discard target.children.pop()
        let parent = action.oldParent
        assert parent != nil
        parent.insert(node, action.pos)

        # select new item before deleting the old one to avoid focus jumping
        let oldItem = node.item
        self.withoutRedraw:
          self.createTreeNode(node, parent, action.pos)
          node.itemSelect()
          oldItem.delete()

        # node.parent may be changed from item to folder
        # target may be changed from folder to item
        self.loadTreeImage(parent)
        self.loadTreeImage(target)
        node.itemEnsureVisible()

    of MoveAbove, MoveBelow:
      case doKind
      of Do, Redo:
        # sibling of top must be Top, Directory, or insertable Entry
        if target.nkind() == TopNode and
            (node.nkind() notin {TopNode, DirectoryNode, EntryNode} or
              not node.insertable()):
          return false

        let oldParent = node.getParent()
        let targetParent = target.getParent()
        action.oldParent = oldParent
        action.pos = node.position()
        action.targetPos = target.position()

        if kind == MoveBelow: action.targetPos.inc

        # cancel this action if move to the same position
        if (oldParent == targetParent) and
            ((kind == MoveAbove and action.pos == action.targetPos - 1) or
              (kind == MoveBelow and action.pos == action.targetPos)):
          return false

        if action.pos > action.targetPos:
          oldParent.delete(action.pos)
          targetParent.insert(node, action.targetPos)
        else:
          targetParent.insert(node, action.targetPos)
          oldParent.delete(action.pos)

        # select new item before deleting the old one to avoid focus jumping
        let oldItem = node.item
        self.withoutRedraw:
          self.createTreeNode(node, targetParent, action.targetPos)
          node.itemSelect()
          oldItem.delete()

        # oldParent may be changed from folder to item
        self.loadTreeImage(node)
        self.loadTreeImage(oldParent)
        node.itemEnsureVisible()
        return true

      of Undo:
        # node.parent = action.oldParent
        let
          targetParent = target.getParent()
          oldParent = action.oldParent
        var pos = action.pos
        if action.pos > action.targetPos and oldParent == targetParent:
          pos.inc

        let oldItem = node.item
        self.withoutRedraw:
          # if the parent is the same, insert before deleting is necessary;
          # otherwise, it doesn't matter.
          oldParent.insert(node, pos)
          self.createTreeNode(node, oldParent, pos)
          targetParent.delete(action.targetPos)

          # select before deleting to prevent multiple focus jumps.
          node.itemSelect()
          oldItem.delete()

        # action.oldParent may be changed from item to folder
        self.loadTreeImage(node)
        self.loadTreeImage(oldParent)
        node.itemEnsureVisible()

    of DeleteNode:
      case doKind
      of Do, Redo:
        # delete from MenuNode and record the pos
        action.oldParent = node.getParent()
        action.pos = node.position()
        assert action.oldParent != nil
        action.oldParent.delete(action.pos)

        # node.parent may be changed from folder to item
        self.loadTreeImage(action.oldParent)

        # delete from treeview
        self.withoutRedraw:
          node.itemDelete()

        return true

      of Undo:
        action.oldParent.insert(node, action.pos)

        self.withoutRedraw:
          self.createTreeNode(node, action.oldParent, action.pos)

        # node.parent may be changed from item to folder
        self.loadTreeImage(action.oldParent)
        node.itemSelect().itemEnsureVisible()

    of EditAttrib:
      case doKind
      of Do, Redo:
        if attrib == "title":
          action.newValue = action.newValue.strip()

        # cancel this action if the value is the same
        if action.newValue == node.attribs{attrib}:
          return false

        if attrib == "title":
          node.item.text = action.newValue
          # cancel this action if title of tree item cannot be changed
          if node.item.text != action.newValue:
            return false

        action.oldValue = node.attribs{attrib}
        node.attribs[attrib] = action.newValue
        node.itemSelect().itemEnsureVisible()

        if attrib in ["path", "icon"]:
          self.loadTreeImage(node)
          self.mStaticBitmap.setBitmap(node.large)

        if attrib in ["script", "mode"] or doKind == Redo:
          self.updateUi(node)

        else:
          case attrib
          of "title": self.mTextCtrlTitle.updateTextCtrl(action)
          of "path": self.mTextCtrlPath.updateTextCtrl(action)
          of "arg": self.mTextCtrlArg.updateTextCtrl(action)
          of "dir": self.mTextCtrlDir.updateTextCtrl(action)
          of "tip": self.mTextCtrlTip.updateTextCtrl(action)
          of "icon": self.mTextCtrlIcon.updateTextCtrl(action)
          else: discard

        return true

      of Undo:
        node.itemSelect().itemEnsureVisible()
        node.attribs[attrib] = action.oldValue

        if attrib in ["path", "icon"]:
          self.loadTreeImage(node)
          self.mStaticBitmap.setBitmap(node.large)

        self.updateUi(node)

    of EditOption:
      case doKind
      of Do, Redo:
        for key, boolean in action.newOption:
          action.oldOption[key] = node.hasOption(key)
          if boolean: node.attribs[key] = "true"
          else: node.attribs.del key

        # cancel this action if the option is the same
        if action.oldOption == action.newOption:
          return false

        node.itemSelect().itemEnsureVisible()

        if doKind == Redo:
          self.updateUi(node)

        return true

      of Undo:
        node.itemSelect().itemEnsureVisible()

        for key, boolean in action.oldOption:
          if boolean: node.attribs[key] = "true"
          else: node.attribs.del key

        self.updateUi(node)

    of ToRelativePath, ToAbsolutePath:
      case doKind
      of Do, Redo:
        var
          modified = false
          oldAttribTable: Table[(MenuNode, string), string]

        proc switch(node: MenuNode, key: string) =
          let value = node.attribs{key}
          if value == "": return

          var opt =
            if kind == ToRelativePath: {PathToRelative}
            else: {PathToAbsolute}

          if key == "icon":
            opt.incl(PathIsIcon)

          let
            valueEnv = value.env()
            newValue = valueEnv.pathSwitch(opt)

          if newValue != "" and newValue != valueEnv:
            oldAttribTable[(node, key)] = value
            modified = true
            node.attribs[key] = newValue

        walk(node) do (child: MenuNode):
          switch(child, "path")
          switch(child, "dir")
          switch(child, "icon")

        if not modified:
          return false

        action.oldAttribTable = oldAttribTable
        self.updateUi(node)
        return true

      of Undo:
        for tup, value in action.oldAttribTable:
          let (child, key) = tup
          child.attribs[key] = value

        self.updateUi(node)

    of ActionList:
      case doKind
      of Do, Redo:
        var doSometing = false
        for action in action.multipleActions.mitems:
          if self.does(action, doKind):
            doSometing = true

        return doSometing

      of Undo:
        for i in countdown(action.multipleActions.high, 0):
          self.does(action.multipleActions[i], doKind)

  proc act(self: wMainFrame, action: Action) =
    var
      action = action
      combined = false

    if not self.does(action, Do): return

    defer:
      if not combined:
        main.actions.add(action)
        main.undoIndex.inc

      self.updateButtonState()

    # once action is done, always discard redoable actions
    main.actions.setLen(main.undoIndex)

    # try to combine the action
    if main.actions.len != 0 and
        main.actions[^1].kind == action.kind and
        main.actions[^1].node == action.node and
        main.actions[^1].attrib == action.attrib and
        (not main.actions[^1].noCombine):

      case action.kind
      of EditAttrib:
        combined = true
        if main.actions[^1].oldValue == action.newValue:
          discard main.actions.pop()
          main.undoIndex.dec
        else:
          main.actions[^1].newValue = action.newValue

      of EditOption:
        combined = true
        if main.actions[^1].oldOption == action.newOption:
          discard main.actions.pop()
          main.undoIndex.dec
        else:
          main.actions[^1].newOption = action.newOption

      else: discard

  proc undo(self: wMainFrame) =
    if not undoable(): return

    defer:
      self.updateButtonState()

    main.undoIndex.dec
    var action = main.actions[main.undoIndex]
    self.does(action, Undo)

  proc redo(self: wMainFrame) =
    if not redoable(): return

    defer:
      self.updateButtonState()

    var action = main.actions[main.undoIndex]
    assert self.does(action, Redo) == true
    main.undoIndex.inc

  proc doDelete(self: wMainFrame) =
    self.withFocusedNode:
      self.act Action(
        kind: DeleteNode,
        node: node,
        name: !Del
      )

  proc doCopy(self: wMainFrame) =
    self.withFocusedNode:
      main.copiedNode = node.copy()
      self.mButtonPaste.enable()

  proc doPaste(self: wMainFrame) =
    if main.copiedNode == nil: return
    self.withFocusedNode:
      self.act Action(
        kind: AddBelow,
        node: main.copiedNode.copy(),
        target: node,
        name: !Paste
      )
    do:
      if main.root.childless():
        self.act Action(
          kind: AddChild,
          node: main.copiedNode.copy(),
          target: main.root,
          name: !Paste
        )

  proc doAddMenu(self: wMainFrame) =
    self.withFocusedNode:
      if node.nkind() == TopNode:
        self.act Action(
          kind: AddBelow,
          node: MenuNode(attribs: toOrderedTable {"title": !New_Menu}),
          target: node,
          name: !Add_Menu
        )
        return

    # no focused node or not focus on top
    self.act Action(
      kind: AddChild,
      node: MenuNode(attribs: toOrderedTable {"title": !New_Menu}),
      target: main.root,
      name: !Add_Menu
    )

  proc doAddNode(self: wMainFrame) =
    self.withFocusedNode:
      self.act Action(
        kind: AddBelow,
        node: MenuNode(attribs: toOrderedTable {"title": !New_Node}),
        target: node,
        name: !Add_Node
      )

  proc doAddSeparator(self: wMainFrame) =
    self.withFocusedNode:
      self.act Action(
        kind: AddBelow,
        node: MenuNode(attribs: toOrderedTable {"special": "separator"}),
        target: node,
        name: !Add_Separator
      )

  proc doInsertNode(self: wMainFrame) =
    self.withFocusedNode:
      self.act Action(
        kind: AddChild,
        node: MenuNode(attribs: toOrderedTable {"title": !New_Node}),
        target: node,
        name: !Insert_Node
      )

  proc doCraft(self: wMainFrame, param: SearchParam) =
    if param.dirs.len == 0: return

    proc thread(param: SearchParam) {.thread.} =
      var ret = ""
      defer:
        {.gcsafe.}:
          withLock main.channelLock:
            main.channel.send(ret)

      var newNode = craft(param)
      if newNode == nil:
        return

      var icos: seq[wIco]
      {.gcsafe.}:
        newNode.walk do (node: MenuNode):
          # imported nodes (by craft) are always full paths,
          # no need to call env() to expand the path.
          icos.add IcoShell(node.attribs{"path"}, main.icoSize)

      if icos.len == 0:
        return

      {.gcsafe.}:
        for ico in icos:
          withLock main.icoLock:
            discard main.icoCache.getData(ico)

      {.gcsafe.}:
        ret = pack(newNode)

    main.waitFrame.show()
    main.busy = true

    var th: Thread[SearchParam]
    createThread(th, thread, param)

    self.await(th, 0.1):
      defer:
        main.busy = false

      main.waitFrame.hide()

      var packed: string
      withLock main.channelLock:
        let (ok, p) = main.channel.tryRecv()
        if not ok or p == "": return
        packed = p

      let newNode = unpack(packed, MenuNode)
      if newNode == nil:
        return

      let msgd = MessageDialog(self,
        message = !Please_select_next_step & ':',
        caption = !Import,
        style=wAbortRetryIgnore or wButton1_Default
      )

      msgd.setAbortRetryIgnoreLabels(!Paste, !Copy, !Cancel)
      case msgd.showModal()
      of wIdAbort:
        self.mButtonPaste.enable()
        main.copiedNode = newNode
        self.doPaste()

      of wIdRetry:
        self.mButtonPaste.enable()
        main.copiedNode = newNode

      else: discard

  proc doChangeIcon(self: wMainFrame) =
    self.withFocusedNode:
      var icon, initDir: string
      let path = node.getIcoPath().splitIconLocation[0]
      if fileExists(path):
        icon = path
        initDir = path.parentDir()
      else:
        icon = "shell32.dll"
        initDir = getCurrentDir()

      var newIcon = self.pickIconDialog(icon, initDir)
      if newIcon != "":
        self.act Action(
          kind: EditAttrib,
          attrib: "icon",
          node: node,
          newValue: newIcon,
          name: !Change_Icon,
          noCombine: true
        )

  proc doImportDirAndFiles(self: wMainFrame) =
    if main.busy: return
    let param = searchDialog(self)
    self.doCraft(param)

  proc doImportStartMenu(self: wMainFrame) =
    if main.busy: return
    var param = SearchParam(
      pattern: "*.*",
      design: "%DisplayName%",
      option: {SearchFile, SearchRec}
    )
    param.dirs.add getSpecialPath(CSIDL_COMMON_STARTMENU)
    param.dirs.add getSpecialPath(CSIDL_STARTMENU)
    self.doCraft(param)

  proc doImportQuickLaunch(self: wMainFrame) =
    if main.busy: return
    var param = SearchParam(
      pattern: "*.*",
      design: "%DisplayName%",
      option: {SearchFile, SearchRec}
    )
    param.dirs.add getQuickLaunchPath(false)
    param.dirs.add getQuickLaunchPath(true)
    self.doCraft(param)

  proc doImportSystemMenu(self: wMainFrame) =

    proc addSpecial(node: MenuNode, special: string, title = "", icon = "") =
      var child = MenuNode()
      child.attribs["special"] = special
      if title != "": child.attribs["title"] = title
      if icon != "": child.attribs["icon"] = icon
      node.children.add child

    let node = MenuNode()
    node.attribs["title"] = !System_Menu
    node.addSpecial("about", !About, "shell32.dll,23")
    node.addSpecial("separator")
    node.addSpecial("recentmenu", !Recent_Items, "shell32.dll,24")
    node.addSpecial("hotkeymenu", !Hotkey_List, "shell32.dll,211")
    node.addSpecial("search", !Search, "shell32.dll,22")
    node.addSpecial("setting", !Menu_Setting, "shell32.dll,21")
    node.addSpecial("separator")
    node.addSpecial("exit", !Exit, "shell32.dll,27")
    node.attribs["trayleft"] = "true"
    node.attribs["trayhover"] = "true"
    node.attribs["notitle"] = "true"
    node.attribs["nomnemonic"] = "true"

    self.act Action(
      kind: AddChild,
      node: node,
      target: main.root,
      name: !Import_System_Menu
    )

  proc doSelectTargetFile(self: wMainFrame, path: string) =
    self.withFocusedNode:
      let (defaultDir, defaultFile) =
        if path.dirExist: (path, "")
        elif path.fileExist: (path.dirPart, path.filenamePart)
        else: (getCurrentDir(), "")

      let newPaths = FileDialog(self, message = !Choose_Target_File,
        defaultDir=defaultDir, defaultFile=defaultFile,
        style=wFdOpen or wFdFileMustExist).display()

      if newPaths.len != 0:
        self.act Action(
          kind: EditAttrib,
          attrib: "path",
          node: node,
          newValue: newPaths[0],
          name: !Change_Attribute,
          noCombine: true
        )

  proc doSelectTargetDir(self: wMainFrame, path: string) =
    self.withFocusedNode:
      let defaultPath =
        if path.dirExist: path
        elif path.fileExist: path.dirPart
        else: getCurrentDir()

      let newDir = DirDialog(self, message = !Choose_Target_Folder,
        defaultPath=defaultPath,
        style=wDdDirMustExist).display()

      if newDir != "":
        self.act Action(
          kind: EditAttrib,
          attrib: "path",
          node: node,
          newValue: newDir,
          name: !Change_Attribute,
          noCombine: true
        )

  proc doSelectDir(self: wMainFrame, path: string, dir: string) =
    self.withFocusedNode:
      let defaultPath =
        if dir.dirExist: dir
        elif path.dirExist: path
        elif path.fileExist: path.dirPart
        else: getCurrentDir()

      let newDir = DirDialog(self, message = !Choose_Working_Directory,
        defaultPath=defaultPath,
        style=wDdDirMustExist).display()

      if newDir != "":
        self.act Action(
          kind: EditAttrib,
          attrib: "dir",
          node: node,
          newValue: newDir,
          name: !Change_Attribute,
          noCombine: true
        )

  proc doOpenTargetDir(self: wMainFrame, path: string) =
    shellExecute(if path.dirExist: path else: path.dirPart)

  proc doOpenDir(self: wMainFrame, dir: string) =
    shellExecute(dir)

  proc doSort(self: wMainFrame) =

    proc removeSeparator(node: MenuNode) =
      for i in countdown(node.children.high, 0):
        let child = node.children[i]
        if child.nkind() == SeparatorNode:
          node.children.delete i

        else:
          child.removeSeparator()

    self.withFocusedNode:
      let newNode = node.copy()
      newNode.removeSeparator()
      newNode.sort()
      newNode.attribs["title"] = strip(newNode.attribs["title"] & fmt" ({!Sorted})")

      self.act Action(
        kind: AddBelow,
        node: newNode,
        target: node,
        name: !Sort
      )

  proc doExtract(self: wMainFrame) =
    self.withFocusedNode:
      let newNode = MenuNode()
      newNode.attribs["title"] = strip(node.attribs["title"] & fmt" ({!Extracted})")

      proc extract(node: MenuNode) =
        case node.nkind()
        of RootNode:
          UNREACHABLE()

        of SerialNode, GroupNode, EntryNode, FunctionNode,
            DirMenu, FileMenu, RecentMenu, HotkeyMenu:
          newNode.add node

        of TopNode, DirectoryNode:
          for child in node.children:
            extract(child)

        of SeparatorNode:
          discard

      extract(node)

      self.act Action(
        kind: AddBelow,
        node: newNode,
        target: node,
        name: !Extract
      )

  proc doToRelative(self: wMainFrame) =
    self.withFocusedNode:
      self.act Action(
        kind: ToRelativePath,
        node: node,
        name: !To_Relative_Path
      )

  proc doToAbsolute(self: wMainFrame) =
    self.withFocusedNode:
      self.act Action(
        kind: ToAbsolutePath,
        node: node,
        name: !To_Absolute_Path
      )

  proc doExpand(self: wMainFrame) =
    self.withFocusedItem:
      item.expandAllChildren()

  proc doCollapse(self: wMainFrame) =
    self.withFocusedItem:
      item.collapseAllChildren()

  proc doExpandAll(self: wMainFrame) =
    self.mTreeCtrl.expandAll()

  proc doCollapseAll(self: wMainFrame) =
    self.mTreeCtrl.collapseAll()

  proc doChangeIconSize(self: wMainFrame, size: int) =
    resetImageList(size)
    self.loadTreeImage()

  proc doChangeRecentLen(self: wMainFrame, len: int) =
    main.recentLen = len

  proc doRecreateCache(self: wMainFrame) =
    proc thread(packed: string) {.thread.} =
      {.gcsafe.}:
        let newNode = unpack(packed, MenuNode)

        newNode.walk do (node: MenuNode):
          let file = node.getIcoPath()
          if file != "":
            withLock main.icoLock:
              discard main.icoCache.getData(IcoPath(file, main.icoSize))
              discard main.icoCache.getData(IcoPath(file, 64))

    withLock main.icoLock:
      main.icoCache.clear()

    let newNode = main.root.copy()

    var th: Thread[string]
    createThread(th, thread, newNode.pack())

    # ensure `th` won't be destroyed before the thread ends
    self.await(th, 0.1):
      discard

  proc doSaveCache(self: wMainFrame) =
    proc thread() {.thread.} =
      {.gcsafe.}:
        saveCache()

    var th: Thread[void]
    createThread(th, thread)

    # ensure `th` won't be destroyed before the thread ends
    self.await(th, 0.1):
      discard

  proc doSetEditor(self: wMainFrame, path = "") =
    if path != "":
      main.root.attribs["editor"] = path.env()

    else:
      self.withFocusedNode:
        let path = node.attribs{"path"}
        if path != "":
          main.root.attribs["editor"] = path.env()

  proc doStartEditor(self: wMainFrame) =
    self.withFocusedNode:
      let
        editor = main.root.attribs{"editor", "notepad"}
        script = node.attribs{"script"}

      let (cfile, path) = createTempFile("InstantMenu_", ".pk")
      cfile.write(script)
      cfile.close()

      let pid = run(&"\"{editor}\" \"{path}\"")

      if pid == InvalidProcess:
        discard tryRemoveFile(path)

      else:
        main.waitFrame.show()
        self.disable()

        self.startTimer(0.1) do (event: wEvent):
          if not pid.isExists():
            defer:
              # stopTimer will destroy the closure,
              # make sure this is the last action
              event.stopTimer()

            try:
              self.act Action(
                kind: EditAttrib,
                attrib: "script",
                node: node,
                newValue: readFile(path),
                name: !Change_Script,
                noCombine: true
              )
            except IOError:
              discard

            discard tryRemoveFile(path)
            self.enable()
            main.waitFrame.hide()
            self.activate()

  proc doSwitchConsole(self: wMainFrame) =
    if self.mConsole.isShown():
      for ctrl in [self.mTreeCtrl,
        self.mButtonNew, self.mButtonCopy,
        self.mButtonDel, self.mButtonPaste,
        self.mButtonUp, self.mButtonDown,
        self.mButtonLeft, self.mButtonRight
      ]:
        ctrl.show()
      self.mConsole.hide()

    else:
      self.mConsole.show()
      for ctrl in [self.mTreeCtrl,
        self.mButtonNew, self.mButtonCopy,
        self.mButtonDel, self.mButtonPaste,
        self.mButtonUp, self.mButtonDown,
        self.mButtonLeft, self.mButtonRight
      ]:
        ctrl.hide()

  proc enableTitleEdit(self: wMainFrame) =
    var
      emptyAccel = AcceleratorTable()
      savedAccel: wAcceleratorTable

    proc disableAccel(self: wMainFrame, flag = true) =
      # disable/enable acceleration, for treview label editing
      if flag:
        savedAccel = self.acceleratorTable
        if emptyAccel != nil:
          self.acceleratorTable = emptyAccel
      else:
        if savedAccel != nil:
          self.acceleratorTable = savedAccel

    self.mTreeCtrl.wEvent_TreeBeginLabelEdit do (event: wEvent):
      let node = event.item.node()
      if node.nkind() notin {RootNode, SeparatorNode}:
        self.disableAccel(true)
        event.item.unselect()
      else:
        event.veto()

    self.mTreeCtrl.wEvent_TreeEndLabelEdit do (event: wEvent):
      self.disableAccel(false)
      # Veto editing initially as the title may change in EditAttrib action;
      # the final value will be set by EditAttrib.
      event.veto()
      event.item.setSelection()
      if event.text != "":
        let node = event.item.node()
        self.act Action(
          kind: EditAttrib,
          attrib: "title",
          node: node,
          newValue: event.text,
          name: !Change_Title
        )

    self.mTextCtrlTitle.wEvent_Text do ():
      self.withFocusedNode:
        self.act Action(
          kind: EditAttrib,
          attrib: "title",
          node: node,
          newValue: self.mTextCtrlTitle.value,
          name: !Change_Title
        )

    # title may be changed in EditAttrib action
    # so reset mTextCtrlTitle after killfocus
    # (it won't be changed during having the focus)
    self.mTextCtrlTitle.wEvent_KillFocus do (event: wEvent):
      event.skip()
      self.withFocusedNode:
        self.mTextCtrlTitle.changeValue(node.attribs{"title"})

      # don't combine the action after kill focus
      markNoCombine(EditAttrib, "title")

    # {Enter} to switch focus bwtween treectrl and attrib
    self.mTextCtrlTitle.wEvent_TextEnter do ():
      self.mTreeCtrl.setFocus()

    self.mTreeCtrl.wEvent_KeyDown do (event: wEvent):
      if not (event.ctrlDown or event.shiftDown or event.altDown or event.winDown):
        case event.keyCode
        # {Del} to delete the node
        of wKey_Delete:
          self.doDelete()
          return

        # {F2} in treectrl can edit the title directly
        of wKey_F2:
          let item = self.mTreeCtrl.focusedItem
          if item.isOk:
            item.editLabel()
            return
        else: discard

      elif event.ctrlDown and not (event.shiftDown or event.altDown or event.winDown):
        if event.keyCode in [wKey_Up, wKey_Down, wKey_Left, wKey_Right]:
          case event.keyCode
          of wKey_Up:
            self.mButtonUp.click()
            self.mTreeCtrl.setFocus()
          of wKey_Down:
            self.mButtonDown.click()
            self.mTreeCtrl.setFocus()
          of wKey_Left:
            self.mButtonLeft.click()
            self.mTreeCtrl.setFocus()
          of wKey_Right:
            self.mButtonRight.click()
            self.mTreeCtrl.setFocus()
          else: discard
          return

      event.skip()

  proc enalbeAttribEdit(self: wMainFrame) =

    proc bindEvent(ctrl: wTextCtrl, attrib: string, name: string) =

      ctrl.wEvent_Text do ():
        self.withFocusedNode:
          self.act Action(
            kind: EditAttrib,
            attrib: attrib,
            node: node,
            newValue: ctrl.value,
            name: name
          )

      # {Enter} to switch focus bwtween treectrl and attrib
      ctrl.wEvent_TextEnter do ():
        self.mTreeCtrl.setFocus()

      # don't combine the action after kill focus
      ctrl.wEvent_KillFocus do (event: wEvent):
        event.skip()
        markNoCombine(EditAttrib, attrib)

    proc bindEvent(ctrl: wHotkeyCtrl, attrib: string, name: string) =

      ctrl.wEvent_HotkeyChanged do ():
        self.withFocusedNode:
          self.act Action(
            kind: EditAttrib,
            attrib: attrib,
            node: node,
            newValue: ctrl.value,
            name: name
          )

      # don't combine the action after kill focus
      ctrl.wEvent_KillFocus do (event: wEvent):
        event.skip()
        markNoCombine(EditAttrib, attrib)

    proc bindEvent(ctrl: wComboBox, attrib: string, name: string) =

      ctrl.wEvent_ComboBox do (event: wEvent):
        self.withFocusedNode:
          let
            index = ctrl.selection
            table = ctrl.attribsTable

          if index >= 0:
            let key = toSeq(table.keys)[index]
            self.act Action(
              kind: EditAttrib,
              attrib: attrib,
              node: node,
              newValue: key,
              name: name
            )

      # don't combine the action after kill focus
      ctrl.wEvent_KillFocus do (event: wEvent):
        event.skip()
        markNoCombine(EditAttrib, attrib)

    proc bindEvent(ctrl: wCheckComboBox, name: string) =

      ctrl.wEvent_CheckComboBox do ():
        self.withFocusedNode:
          let keySeq = toSeq(ctrl.attribsTable.keys)
          var option: Table[string, bool]
          for i in 0..<ctrl.len:
            option[keySeq[i]] = ctrl.isSelected(i)

          self.act Action(
            kind: EditOption,
            node: node,
            newOption: option,
            name: name
          )

      # don't combine the action after kill focus
      ctrl.wEvent_KillFocus do (event: wEvent):
        event.skip()
        markNoCombine(EditOption)

    bindEvent(self.mTextCtrlPath, "path", !Change_Path)
    bindEvent(self.mTextCtrlArg, "arg", !Change_Args)
    bindEvent(self.mTextCtrlDir, "dir", !Change_Dir)
    bindEvent(self.mTextCtrlTip, "tip", !Change_Tip)
    bindEvent(self.mTextCtrlIcon, "icon", !Change_Icon)
    bindEvent(self.mHotkeyCtrl, "hotkey", !Change_Hotkey)
    bindEvent(self.mComboBoxShow, "show", !Change_Show)
    bindEvent(self.mComboBoxMode, "mode", !Change_Mode)
    bindEvent(self.mCheckComboOption, !Change_Option)
    bindEvent(self.mCheckComboBind, !Change_Binding)

  proc enableTreeDrag(self: wMainFrame) =

    self.mTreeCtrl.wEvent_TreeBeginDrag do (event: wEvent):
      self.mDragging = true
      self.mTreeCtrl.enableInsertMark(true)
      event.allow()

    self.mTreeCtrl.wEvent_TreeEndDrag do (event: wEvent):
      self.mDragging = false

      # avoid inserting into self or children
      var item = event.item
      while item.isOk:
        if item == event.oldItem: return
        item = item.parent

      if event.oldItem.isOk and event.item.isOk:
        var actionKind =
          if event.insertMark < 0: MoveAbove
          elif event.insertMark > 0: MoveBelow
          else: MoveInto

        self.act Action(
          kind: actionKind,
          node: event.oldItem.node(),
          target: event.item.node(),
          name: !Move
        )

  proc enableNewCopyPasteDelete(self: wMainFrame) =

    proc newMenu(self: wMainFrame, hover: bool) =
      type MenuID = enum
        AddMenu = 1, InsertNode, AddNode, AddSeparator
        ImportDirAndFiles, ImportStartMenu, ImportQuickLaunch, ImportSystemMenu

      let menu = Menu()
      self.withFocusedNode:
        if node.nkind() == TopNode:
          menu.append(AddMenu, !Add_Menu)
        else:
          menu.append(AddNode, !Add_Node)
          menu.append(AddSeparator, !Add_Separator)

        if node.insertable():
          menu.append(InsertNode, !Insert_Node)

      if menu.len == 0: # no focused node
        menu.append(AddMenu, !Add_Menu)

      menu.appendSeparator()
      menu.append(ImportDirAndFiles, !Import_Files_And_Folders).enable(not main.busy)
      menu.append(ImportStartMenu, !Import_Start_Menu).enable(not main.busy)
      menu.append(ImportQuickLaunch, !Import_Quick_Launch).enable(not main.busy)
      menu.append(ImportSystemMenu, !Import_System_Menu).enable(not main.busy)

      let pos = (0, self.mButtonNew.size.height)
      var flag = wPopMenuTopAlign or wPopMenuReturnId
      if hover: flag = flag or wPopMenuHover

      let id = self.mButtonNew.popupMenuEx(menu, pos, flag)
      if id != 0: self.mButtonNew.setFocus()
      case id
      of AddMenu: self.doAddMenu()
      of InsertNode: self.doInsertNode()
      of AddNode: self.doAddNode()
      of AddSeparator: self.doAddSeparator()
      of ImportDirAndFiles: self.doImportDirAndFiles()
      of ImportStartMenu: self.doImportStartMenu()
      of ImportQuickLaunch: self.doImportQuickLaunch()
      of ImportSystemMenu: self.doImportSystemMenu()
      else: discard

    self.mButtonNew.wEvent_MouseHover do (): self.newMenu(hover=true)
    self.mButtonNew.wEvent_Button do (): self.newMenu(hover=false)
    self.mButtonCopy.wEvent_Button do (): self.doCopy()
    self.mButtonPaste.wEvent_Button do (): self.doPaste()
    self.mButtonDel.wEvent_Button do (): self.doDelete()

  proc enableArrowKeys(self: wMainFrame) =
    self.mButtonUp.wEvent_Button do ():
      self.withFocusedItem:
        let prev = item.prevSibling
        if prev.isOk:
          self.act Action(
            kind: MoveAbove,
            node: item.node(),
            target: prev.node(),
            name: !Move_Up
          )

    self.mButtonDown.wEvent_Button do ():
      self.withFocusedItem:
        let next = item.nextSibling
        if next.isOk:
          self.act Action(
            kind: MoveBelow,
            node: item.node(),
            target: next.node(),
            name: !Move_Down
          )

    self.mButtonLeft.wEvent_Button do ():
      self.withFocusedItem:
        let parent = item.parent
        if parent.isOk:
          self.act Action(
            kind: MoveBelow,
            node: item.node(),
            target: parent.node(),
            name: !Move_Left
          )

    self.mButtonRight.wEvent_Button do ():
      self.withFocusedItem:
        let prev = item.prevSibling
        if prev.isOk:
          self.act Action(
            kind: MoveInto,
            node: item.node(),
            target: prev.node(),
            name: !Move_Right
          )

  proc enableUndoRedo(self: wMainFrame) =

    proc undoMenu(hover: bool) =
      assert undoable()

      let submenu = Menu()
      for i in 0 ..< main.undoIndex:
        submenu.append(i + 1, fmt"{i + 1} {main.actions[i].name}")

      let menu = Menu()
      menu.append(1, !Undo_All)
      menu.appendSubMenu(submenu, !Undo_To & "...")
      menu.appendSeparator()
      menu.append(main.undoIndex, !Undo & " - " &
        main.actions[main.undoIndex - 1].name & "\tCtrl + Z")

      let pos = (0, 0)
      var flag = wPopMenuBottomAlign or wPopMenuReturnId
      if hover: flag = flag or wPopMenuHover

      let index = int self.mButtonUndo.popupMenuEx(menu, pos, flag)
      if index != 0:
        self.withoutRedraw:
          while main.undoIndex >= index:
            self.undo()

    proc redoMenu(hover: bool) =
      assert redoable()

      let submenu = Menu()
      var n = 1
      for i in countdown(main.actions.len - 1, main.undoIndex):
        submenu.append(i + 1, fmt"{n} {main.actions[i].name}")
        n.inc

      let menu = Menu()
      menu.append(main.actions.len, !Redo_All)
      menu.appendSubMenu(submenu, !Redo_To & "...")
      menu.appendSeparator()
      menu.append(main.undoIndex + 1, !Redo & " - " &
        main.actions[main.undoIndex].name & "\tCtrl + Y")

      let pos = (0, 0)
      var flag = wPopMenuBottomAlign or wPopMenuReturnId
      if hover: flag = flag or wPopMenuHover

      let index = int self.mButtonRedo.popupMenuEx(menu, pos, flag)
      if index != 0:
        self.withoutRedraw:
          while main.undoIndex < index:
            self.redo()

    self.mButtonUndo.wEvent_MouseHover do ():
      if undoable(): undoMenu(hover=true)

    self.mButtonUndo.wEvent_KeyDown do (event: wEvent):
      if not (event.ctrlDown or event.shiftDown or event.altDown or event.winDown):
        if event.keyCode == wKey_Apps:
          if undoable(): undoMenu(hover=false)

    self.mButtonUndo.wEvent_Button do ():
      self.undo()

    self.mButtonRedo.wEvent_MouseHover do ():
      if redoable(): redoMenu(hover=true)

    self.mButtonRedo.wEvent_KeyDown do (event: wEvent):
      if not (event.ctrlDown or event.shiftDown or event.altDown or event.winDown):
        if event.keyCode == wKey_Apps:
          if redoable(): redoMenu(hover=false)

    self.mButtonRedo.wEvent_Button do ():
      self.redo()

    self.shortcut(wAccelCtrl, wKey_Z) do ():
      self.undo()

    self.shortcut(wAccelCtrl, wKey_Y) do ():
      self.redo()

  proc enableSpecialEvents(self: wMainFrame) =
    var nodes: seq[MenuNode]

    main.searchBox.wEvent_Text do ():
      if nodes.len != 0:
        launch LaunchSetup(
          kind: AdaptiveItem,
          nodes: nodes,
          title: !Search & ": " & main.searchBox.value,
          mnemonic: true,
          showHotkey: false,
          showIcon: true
        )

    self.wEvent_ShowSearch do ():
      nodes.setLen(0)
      main.searchBox.show do (x: string) -> seq[string]:
        var words = x.splitWhitespace()
        if words.len != 0:
          nodes = main.root.filter do (node: MenuNode) -> bool:
            if node == main.root: return false
            if node.attribs{"special"} == "separator": return false

            for word in words:
              if word notin node:
                return false

            # all words in the node
            return true

        for i, node in nodes:
          let title = node.title()
          if i < Mnemonic.len:
            result.add $Mnemonic[i] & " " & title

          else:
            result.add title

    self.wEvent_ShowAbout do ():
      if self.isShownOnScreen():
        aboutDialog(self)
      else:
        aboutDialog(nil)

    self.wEvent_ClearRecent do ():
      recentClear()

    self.wEvent_ScriptReturn do ():
      var packed: string
      withLock main.channelLock:
        let (ok, p) = main.scriptChannel.tryRecv()
        if not ok or p == "": return
        packed = p

      var
        simpleNodes = unpack(packed, seq[SimpleNode])
        nodes: seq[MenuNode]

      if simpleNodes.len == 0:
        return

      for n in simpleNodes:
        let
          node = n.toMenuNode()
          file = node.getIcoPath()

        if file != "":
          withLock main.icoLock:
            node.small = main.icoCache.getBitmap(IcoPath(file, main.icoSize))

        nodes.add node

      launch LaunchSetup(
        kind: AdaptiveItem,
        nodes: nodes,
        title: !CustomScript,
        mnemonic: true,
        showHotkey: false,
        showIcon: true
      )

  proc enableMouseEvents(self: wMainFrame) =

    proc mouseInEdge(): set[NodeOption] =
      let
        pos = wGetMousePosition()
        size = wGetScreenSize()

      if pos.x == 0:
        result.incl(EdgeLeft)

      if pos.x == size.width - 1:
        result.incl(EdgeRight)

      if pos.y == 0:
        result.incl(EdgeUp)

      if pos.y == size.height - 1:
        result.incl(EdgeDown)

    self.startTimer(0.05) do (event: wEvent):
      var hHook {.threadvar.}: HHOOK
      var hasBind = false
      for op in mouseInEdge():
        if main.optionMap{op}.len != 0:
          hasBind = true
          break

      if hasBind:
        if hHook == 0:
          hHook = SetWindowsHookEx(WH_MOUSE_LL, lowLevelMouseProcEdge, 0, 0)
          if hHook != 0:
            let cursor = wHandCursor
            SetSystemCursor(cursor.handle, OCR_NORMAL)

      else:
        if hHook != 0:
          SystemParametersInfo(SPI_SETCURSORS, 0, nil, 0)
          UnhookWindowsHookEx(hHook)
          hHook = 0

    self.wEvent_MouseWheelEdge do (event: wEvent):
      var nodes: seq[MenuNode]
      for op in mouseInEdge():
        nodes.add toSeq(main.optionMap{op})

      if nodes.len != 0:
        launch LaunchSetup(
          kind: AdaptiveItem,
          nodes: nodes,
          title: !Wheel_Menu,
          mnemonic: true,
          showHotkey: true,
          showIcon: true
        )

    self.wEvent_TrayHover do ():
      var nodes = toSeq(main.optionMap{TrayHover})
      if nodes.len != 0:
        launch LaunchSetup(
          kind: AdaptiveItem,
          nodes: nodes,
          title: !Tary_Hover_Menu,
          mnemonic: true,
          showHotkey: true,
          showIcon: true
        )

    self.wEvent_TrayLeftDown do ():
      var nodes = toSeq(main.optionMap{TrayLeft})
      if nodes.len != 0:
        launch LaunchSetup(
          kind: AdaptiveItem,
          nodes: nodes,
          title: !Tray_Left_Menu,
          mnemonic: true,
          showHotkey: true,
          showIcon: true
        )

    self.wEvent_TrayRightDown do ():
      var nodes = toSeq(main.optionMap{TrayRight})
      if nodes.len != 0:
        launch LaunchSetup(
          kind: AdaptiveItem,
          nodes: nodes,
          title: !Tray_Right_Menu,
          mnemonic: true,
          showHotkey: true,
          showIcon: true
        )

    self.wEvent_TrayLeftDoubleClick do ():
      if self.isShownOnScreen:
        self.close()
      else:
        self.queueMessage(wEvent_ShowMain)

    proc bindCursor(ctrl: wControl, textCtrl: wTextCtrl) =
      ctrl.wEvent_MouseEnter do ():
        ctrl.cursor =
          if textCtrl.value != "" and textCtrl.isEnabled(): wHandCursor
          else: wNilCursor

      ctrl.wEvent_MouseMove do ():
        ctrl.cursor =
          if textCtrl.value != "" and textCtrl.isEnabled(): wHandCursor
          else: wNilCursor

      ctrl.wEvent_MouseLeave do ():
        ctrl.cursor = wNilCursor

    bindCursor(self.mLabelPath, self.mTextCtrlPath)
    bindCursor(self.mLabelDir, self.mTextCtrlDir)
    bindCursor(self.mLabelIcon, self.mTextCtrlIcon)

    proc switch(node: MenuNode, key: string, ctrl: wTextCtrl) =
      let value = node.attribs{key}.env()
      var opt =
        if value.isRelative(): {PathToAbsolute}
        else: {PathToRelative}

      if key == "icon":
        opt.incl(PathIsIcon)

      let newValue = value.pathSwitch(opt)
      if newValue != "" and newValue != value:
        self.act Action(
          kind: EditAttrib,
          attrib: key,
          node: node,
          newValue: newValue,
          name: !Change_Attribute,
          noCombine: true
        )

        # if focus in the textctrl, the value won't be changed by action
        if ctrl.hasFocus():
          ctrl.changeValue(newValue)

    self.mLabelPath.wEvent_CommandLeftClick do (event: wEvent):
      self.withFocusedNode:
        node.switch("path", self.mTextCtrlPath)

    self.mLabelPath.wEvent_CommandLeftDoubleClick do (event: wEvent):
      self.withFocusedNode:
        node.switch("path", self.mTextCtrlPath)

    self.mLabelDir.wEvent_CommandLeftClick do (event: wEvent):
      self.withFocusedNode:
        node.switch("dir", self.mTextCtrlDir)

    self.mLabelDir.wEvent_CommandLeftDoubleClick do (event: wEvent):
      self.withFocusedNode:
        node.switch("dir", self.mTextCtrlDir)

    self.mLabelIcon.wEvent_CommandLeftClick do (event: wEvent):
      self.withFocusedNode:
        node.switch("icon", self.mTextCtrlIcon)

    self.mLabelIcon.wEvent_CommandLeftDoubleClick do (event: wEvent):
      self.withFocusedNode:
        node.switch("icon", self.mTextCtrlIcon)

  proc enableTreeEvents(self: wMainFrame) =
    self.mTreeCtrl.wEvent_TreeSelChanged do (event: wEvent):
      let node = event.item.node()
      self.updateUi(node)

    # {Enter} to switch focus bwtween treectrl and attrib
    self.mTreeCtrl.wEvent_TreeItemActivated do ():
      self.withFocusedNode:
        self.mTextCtrlTitle.setFocus()

    self.mTreeCtrl.wEvent_RightUp do ():
      type MenuID = enum
        AddMenu = 1, Paste, ExpandAll, CollapseAll

      let menu = Menu()
      menu.append(AddMenu, !Add_Menu)

      if main.copiedNode != nil:
        menu.append(Paste, !Paste)

      menu.appendSeparator()
      menu.append(ExpandAll, !Expand_All)
      menu.append(CollapseAll, !Collapse_All)

      case self.popupMenu(menu, flag=wPopMenuReturnId)
      of AddMenu: self.doAddMenu()
      of Paste: self.doPaste()
      of ExpandAll: self.doExpandAll()
      of CollapseAll: self.doCollapseAll()
      else: discard


    self.mTreeCtrl.wEvent_TreeItemMenu do ():
      type MenuID = enum
        AddMenu = 1, InsertNode, AddNode, AddSeparator
        Delete, Copy, Paste, Sort, Extract
        ToRelative, ToAbsolute, Expand, Collapse

      self.withFocusedNode:
        let
          pos = self.mTreeCtrl.position
          rect = node.item.getBoundingRect(textOnly=true)
          menu = Menu()
          nkind = node.nkind()

        if nkind == TopNode:
          menu.append(AddMenu, !Add_Menu)

        else:
          menu.append(AddNode, !Add_Node)
          menu.append(AddSeparator, !Add_Separator)

        if node.insertable():
          menu.append(InsertNode, !Insert_Node)

        menu.appendSeparator()
        menu.append(Delete, !Del)
        menu.append(Copy, !Copy)
        if main.copiedNode != nil:
          menu.append(Paste, !Paste)

        if nkind in {TopNode, DirectoryNode, GroupNode, SerialNode} and
            node.children.len != 0:
          menu.appendSeparator()
          menu.append(Sort, !Sort_And_Remove_Separator)
          menu.append(Extract, !Extract_Into_Single_Node)
          menu.appendSeparator()
          menu.append(ToRelative, !To_Relative_Path)
          menu.append(ToAbsolute, !To_Absolute_Path)
          menu.appendSeparator()
          menu.append(Expand, !Expand_All)
          menu.append(Collapse, !Collapse_All)

        else:
          menu.appendSeparator()
          menu.append(ToRelative, !To_Relative_Path)
          menu.append(ToAbsolute, !To_Absolute_Path)

        case self.popupMenu(menu,
          (pos.x + rect.x, pos.y + rect.y + rect.height),
          flag=wPopMenuReturnId)

        of AddMenu: self.doAddMenu()
        of AddNode: self.doAddNode()
        of InsertNode: self.doInsertNode()
        of AddSeparator: self.doAddSeparator()
        of Delete: self.doDelete()
        of Copy: self.doCopy()
        of Paste: self.doPaste()
        of Sort: self.doSort()
        of Extract: self.doExtract()
        of ToRelative: self.doToRelative()
        of ToAbsolute: self.doToAbsolute()
        of Expand: self.doExpand()
        of Collapse: self.doCollapse()
        else: discard


  proc enableKeyboardEvents(self: wMainFrame) =
    self.shortcut(wAccelNormal, wKey_Esc) do ():
      if self.mDragging:
        self.mTreeCtrl.cancelDrag()
        self.mDragging = false
        return

      let focusedWin = wGetFocusWindow()
      if focusedWin of wApp.wComboBox:
        # esc to dismiss popup window, or reset the options
        let comboBox = focusedWin.wComboBox
        if comboBox.isPopup:
          comboBox.dismiss()
        else:
          comboBox.value = comboBox[0]
          comboBox.processMessage(wEvent_ComboBox)

      elif focusedWin of wApp.wCheckComboBox:
        # esc to dismiss popup window, or reset the options
        let checkComboBox = focusedWin.wCheckComboBox
        if checkComboBox.value.len == 0 and checkComboBox.isPopup:
          checkComboBox.dismiss()
        else:
          checkComboBox.deselectAll()
          checkComboBox.processMessage(wEvent_CheckComboBox)

      elif focusedWin of wApp.wTextCtrl:
        # esc to reset the text
        focusedWin.wTextCtrl.value = ""

      # TODO: add an option to close the main window by {ESC}?
      # else:
      #   self.close()

    self.wEvent_Hotkey do (event: wEvent):
      var nodes = toSeq(main.hotkeyMap[event.hotkey])
      assert nodes.len > 0
      launch LaunchSetup(
        kind: AdaptiveItem,
        nodes: nodes,
        title: wHotkeyToString(event.hotkey),
        mnemonic: true,
        showHotkey: true,
        showIcon: true
      )

  proc enableButtonEvents(self: wMainFrame) =

    proc browseMenu(self: wMainFrame, hover: bool) =
      type MenuID = enum
        SelectTargetFile = 1, SelectTargetDir, SelectDir
        OpenTargetDir, OpenDir

      self.withFocusedNode:
        let path = node.attribs{"path"}.env().whereIs()
        let dir = node.attribs{"dir"}.env().toAbsolute()

        let menu = Menu()
        menu.append(SelectTargetFile, !Choose_Target_File)
        menu.append(SelectTargetDir, !Choose_Target_Folder)
        menu.append(SelectDir, !Choose_Working_Directory)
        menu.appendSeparator()
        menu.append(OpenTargetDir, !Open_Target_Folder).enable(path.pathExist())
        menu.append(OpenDir, !Open_Working_Directory).enable(dir.dirExist())

        let pos = (0, self.mButtonBrowse.size.height)
        var flag = wPopMenuTopAlign or wPopMenuReturnId
        if hover: flag = flag or wPopMenuHover

        let id = self.mButtonBrowse.popupMenuEx(menu, pos, flag)
        if id != 0: self.mButtonBrowse.setFocus()
        case id
        of SelectTargetFile: self.doSelectTargetFile(path)
        of SelectTargetDir: self.doSelectTargetDir(path)
        of SelectDir: self.doSelectDir(path, dir)
        of OpenTargetDir: self.doOpenTargetDir(path)
        of OpenDir: self.doOpenDir(dir)
        else: discard

    proc settingMenu(self: wMainFrame, hover: bool) =
      type MenuID = enum
        English = 1, Chinese
        IconSize16, IconSize24, IconSize32, IconSize48
        RecreateCache, SaveCache
        Recent5, Recent10, Recent15, Recent20, Recent25, Recent30, Recent35
        Notepad, CurrentNode, SwitchConsole, Exit, LangStart

      let langs = langs()
      let menuLang = Menu()
      menuLang.append(0, !Effective_On_Next_Restart).disable()
      menuLang.appendSeparator()
      for i, lang in langs:
        let item = menuLang.append(LangStart.ord + i, lang)
        if lang == main.root.attribs{"language"}:
          item.check()

      let menuEditor = Menu()
      menuEditor.append(0, main.root.attribs{"editor", "notepad"}).disable()
      menuEditor.appendSeparator()
      menuEditor.append(Notepad, !Restore_To_Default)
      let item = menuEditor.append(CurrentNode, !Current_Node_Path)
      var enable = false
      self.withFocusedNode:
        if node.attribs{"path"} != "":
          enable = true
      item.enable(enable)

      let menuIcon = Menu()
      menuIcon.append(IconSize16, "16 x 16").check(main.icoSize == 16)
      menuIcon.append(IconSize24, "24 x 24").check(main.icoSize == 24)
      menuIcon.append(IconSize32, "32 x 32").check(main.icoSize == 32)
      menuIcon.append(IconSize48, "48 x 48").check(main.icoSize == 48)

      let menuCache = Menu()
      menuCache.append(RecreateCache,
        fmt"{!Rebuild_Icon_Cache} ({!Current_Counts}: {main.icoCache.len})")
      menuCache.append(SaveCache, !Save_Cache_Manually)

      let menuRecentLen = Menu()
      menuRecentLen.append(Recent5, "5",).check(main.recentLen == 5)
      menuRecentLen.append(Recent10, "10").check(main.recentLen == 10)
      menuRecentLen.append(Recent15, "15").check(main.recentLen == 15)
      menuRecentLen.append(Recent20, "20").check(main.recentLen == 20)
      menuRecentLen.append(Recent25, "25").check(main.recentLen == 25)
      menuRecentLen.append(Recent30, "30").check(main.recentLen == 30)
      menuRecentLen.append(Recent35, "35").check(main.recentLen == 35)

      let menu = Menu()
      menu.appendSubMenu(menuLang, !Language)
      menu.appendSubMenu(menuEditor, !Editor)
      menu.appendSubMenu(menuIcon, !Icon_Size)
      menu.appendSubMenu(menuCache, !Icon_Cache)
      menu.appendSubMenu(menuRecentLen, !Recent_Items_Count)

      if self.mConsole.isShown():
        menu.append(SwitchConsole, !Close_Console)
      else:
        menu.append(SwitchConsole, !Show_Console)

      menu.append(Exit, !Exit)

      let pos = (0, 0)
      var flag = wPopMenuBottomAlign or wPopMenuReturnId
      if hover: flag = flag or wPopMenuHover

      let id = self.mButtonSetting.popupMenuEx(menu, pos, flag)
      if id != 0: self.mButtonSetting.setFocus()
      case id
      of IconSize16: self.doChangeIconSize(16)
      of IconSize24: self.doChangeIconSize(24)
      of IconSize32: self.doChangeIconSize(32)
      of IconSize48: self.doChangeIconSize(48)
      of RecreateCache: self.doRecreateCache()
      of SaveCache: self.doSaveCache()
      of Recent5: self.doChangeRecentLen(5)
      of Recent10: self.doChangeRecentLen(10)
      of Recent15: self.doChangeRecentLen(15)
      of Recent20: self.doChangeRecentLen(20)
      of Recent25: self.doChangeRecentLen(25)
      of Recent30: self.doChangeRecentLen(30)
      of Recent35: self.doChangeRecentLen(35)
      of Notepad: self.doSetEditor("notepad")
      of CurrentNode: self.doSetEditor()
      of SwitchConsole: self.doSwitchConsole()
      of Exit:
        EndMenu()
        self.queueMessage(wEvent_Exit)
      else:
        let id = int id
        if id >= LangStart.ord:
          main.root.attribs["language"] = langs[id - LangStart.ord]


    self.mButtonBrowse.wEvent_MouseHover do (): self.browseMenu(hover=true)
    self.mButtonBrowse.wEvent_Button do (): self.browseMenu(hover=false)

    self.mButtonSetting.wEvent_MouseHover do (): self.settingMenu(hover=true)
    self.mButtonSetting.wEvent_Button do (): self.settingMenu(hover=false)

    self.mButtonExec.wEvent_Button do ():
      self.withFocusedNode:
        launch LaunchSetup(
          kind: SingleItem,
          node: node
        )

    self.mButtonScript.wEvent_Button do ():
      self.doStartEditor()

    self.mStaticBitmap.wEvent_CommandLeftDoubleClick do ():
      self.doChangeIcon()

    self.mButtonIcon.wEvent_Button do ():
      self.doChangeIcon()

    self.mButtonOk.wEvent_Button do ():
      self.close()

  proc enableShowCloseExitEvents(self: wMainFrame) =
    self.wEvent_ShowMain do ():
      if self.mMaximized:
        self.show(wShowMaximized)
      else:
        self.show(wShowNormal)

      SetForegroundWindow(self.handle)

      self.withFocusedItem:
        item.ensureVisible()

    self.wEvent_Exit do ():
      self.sendMessage(wEvent_Close) # invoke wEvent_Close at first
      execAtStartOrExit(AtExit)
      saveCache()

      main.waitFrame.close()
      main.menuWindow.close()
      main.searchBox.delete()
      self.delete()

    self.wEvent_Close do (event: wEvent):
      self.mMaximized = self.isMaximized()
      self.hide()
      saveConfig()
      event.veto() # hide instead of exit for wEvent_Close

    self.wEvent_Start do (event: wEvent):
      execAtStartOrExit(AtStart)

  proc enableDragDrop(self: wMainFrame) =
    var
      tooltip = ToolTip()
      dataObject: wDataObject
      fileCount: int
      lastPos: wPoint
      lastTip: string

    self.mTreeCtrl.setDropTarget()

    proc endDrag() =
      self.mDragging = false
      TreeView_SetInsertMark(self.mTreeCtrl.mHwnd, 0, 0)
      TreeView_SelectDropTarget(self.mTreeCtrl.mHwnd, 0)
      tooltip.hide()

    proc dragging(self: wTreeCtrl, pos: wPoint): tuple[item: wTreeItem, pos: int] =
      var item = self.hitTest(pos).item
      if item.isOk():
        result.item = item
        var insert = false
        let rect = item.getBoundingRect()
        if rect != wDefaultRect:
          if pos.y < rect.y + rect.height div 4:
            TreeView_SetInsertMark(self.mHwnd, item.mHandle, false)
            TreeView_SelectDropTarget(self.mHwnd, 0)
            insert = true
            result.pos = -1
          elif pos.y > rect.y + rect.height * 3 div 4:
            TreeView_SetInsertMark(self.mHwnd, item.mHandle, true)
            TreeView_SelectDropTarget(self.mHwnd, 0)
            insert = true
            result.pos = 1

        if not insert:
          TreeView_SetInsertMark(self.mHwnd, 0, 0)
          TreeView_SelectDropTarget(self.mHwnd, item.mHandle)
          result.pos = 0

    proc getDropInfo(dataObject: wDataObject, event: wEvent): tuple[node: MenuNode, pos: int, effect: int] =
      # after using HotKeyEx, event.CtrlDown becomes unreliable!
      let isCtrlDown = (GetAsyncKeyState(VK_CONTROL) and 0x8000) != 0
      result.effect = wDragNone
      if dataObject != nil and dataObject.isFiles():
        let (item, pos) = self.mTreeCtrl.dragging(event.mousePos)
        if item.isOk:
          let node = item.node()
          if (pos == 0 and node.insertable()) or
              (pos != 0 and node.nkind() != TopNode):

            result.node = node
            result.pos = pos
            result.effect = if isCtrlDown: wDragCopy else: wDragMove

    self.mTreeCtrl.wEvent_DragEnter do (event: wEvent):
      self.mDragging = true
      dataObject = event.getDataObject()
      if dataObject.isFiles():
        fileCount = dataObject.getFiles().len
        event.setEffect(wDragMove)
      else:
        fileCount = 0
        event.setEffect(wDragNone)

    self.mTreeCtrl.wEvent_DragOver do (event: wEvent):
      let effect = getDropInfo(dataObject, event).effect
      event.setEffect(effect)

      var tip = case effect
      of wDragCopy: !"New_Node_And_Insert_?_Items"
      of wDragMove: !"Insret_?_Items"
      else: ""
      tip = tip.replace("?", $fileCount)

      var screenPos = event.mouseScreenPos
      screenPos.x += 20
      screenPos.y += 20
      if lastPos != screenPos or lastTip != tip:
        tooltip.setTip(tip, screenPos)
      lastPos = screenPos
      lastTip = tip

    self.mTreeCtrl.wEvent_Drop do (event: wEvent):
      dataObject = event.getDataObject()
      var
        (node, pos, effect) = getDropInfo(dataObject, event)
        files = dataObject.getFiles()
        actions: seq[Action]

      files.sort()

      defer:
        if actions.len != 0:
          self.act Action(
            kind: ActionList,
            multipleActions: actions,
            name: !Drag_And_Drop
          )

        endDrag()
        self.mDragging = false

      case effect
      of wDragMove:
        for path in files:
          var newNode = MenuNode()
          newNode.attribs["title"] = path.localName()
          newNode.attribs["path"] = path

          actions.add Action(
            kind: if pos > 0: AddBelow elif pos < 0: AddAbove else: AddChild,
            node: newNode,
            target: node,
            name: !Drag_And_Drop
          )
          if pos > 0: node = newNode

      of wDragCopy:
        let newParent = MenuNode(attribs: toOrderedTable {"title": !Drag_And_Drop})
        actions.add Action(
          kind: if pos > 0: AddBelow elif pos < 0: AddAbove else: AddChild,
          node: newParent,
          target: node,
          name: !Drag_And_Drop
        )

        for path in files:
          var newNode = MenuNode()
          newNode.attribs["title"] = path.localName()
          newNode.attribs["path"] = path

          actions.add Action(
            kind: AddChild,
            node: newNode,
            target: newParent,
            name: !Drag_And_Drop
          )

      else: discard

    self.mTreeCtrl.wEvent_DragLeave do ():
      endDrag()

    proc setTextCtrlDropTarget(ctrl: wTextCtrl, attrib: string, allowPath = false) =
      ctrl.setDropTarget()

      ctrl.wEvent_DragEnter do (event: wEvent):
        var dataObject = event.getDataObject()
        if dataObject.isText() or (allowPath and dataObject.isFiles()):
          event.setEffect(wDragCopy)
        else:
          event.setEffect(wDragNone)

      ctrl.wEvent_Drop do (event: wEvent):
        var dataObject = event.getDataObject()
        self.withFocusedNode:
          var value: string
          if dataObject.isText():
            value = dataObject.getText()

          elif allowPath and dataObject.isFiles():
            let files = dataObject.getFiles()
            if files.len == 1:
              value = files[0]

          if value != "":
            self.act Action(
              kind: EditAttrib,
              attrib: attrib,
              node: node,
              newValue: value,
              name: !Drag_And_Drop,
              noCombine: true,
              alwaysUpdateUi: true
            )

    self.mTextCtrlTitle.setTextCtrlDropTarget("title", allowPath=false)
    self.mTextCtrlPath.setTextCtrlDropTarget("path", allowPath=true)
    self.mTextCtrlArg.setTextCtrlDropTarget("arg", allowPath=false)
    self.mTextCtrlDir.setTextCtrlDropTarget("dir", allowPath=true)
    self.mTextCtrlTip.setTextCtrlDropTarget("tip", allowPath=false)
    self.mTextCtrlIcon.setTextCtrlDropTarget("icon", allowPath=true)

  proc enableConsoleEvents(self: wMainFrame) =

    proc copy(self: wListBox) =
      var text: string
      for i in self.selections:
        text.add self.getText(i)
      wSetClipboard(DataObject(text))
      wFlushClipboard()

    proc delete(self: wListBox) =
      let selections = self.selections()
      self.deselectAll()
      for i in countdown(selections.high, 0):
        self.delete(selections[i])

    self.mConsole.wEvent_KeyDown do (event: wEvent):
      if event.ctrlDown and not (event.shiftDown or event.altDown or event.winDown):
        case event.keyCode
        of wKey_A:
          self.mConsole.selectAll()
          return

        of wKey_C:
          self.mConsole.copy()
        else: discard

      if not (event.ctrlDown or event.shiftDown or event.altDown or event.winDown):
        case event.keyCode
        of wKey_Esc:
          self.mConsole.deselectAll()
          return

        of wKey_Delete:
          self.mConsole.delete()
          return
        else: discard

      event.skip()

    self.mConsole.wEvent_ContextMenu do ():
      type MenuId = enum
        Clear = 1, Delete, Copy, SelectAll

      let
        menu = Menu()
        hasContent = self.mConsole.len != 0
        hasSelection = self.mConsole.selections().len != 0

      menu.append(SelectAll, !Select_All & "\tCtrl + A").enable(hasContent)
      menu.append(Copy, !Copy & "\tCtrl + C").enable(hasSelection)
      menu.append(Delete, !Del & "\tDel").enable(hasSelection)
      menu.appendSeparator()
      menu.append(Clear, !Clear_All).enable(hasContent)

      case self.mConsole.popupMenu(menu, flag=wPopMenuReturnId)
      of SelectAll: self.mConsole.selectAll()
      of Copy: self.mConsole.copy()
      of Delete: self.mConsole.delete()
      of Clear: self.mConsole.clear()
      else: discard


  proc init(self: wMainFrame) =
    const number = getVersionNumber()
    self.wFrame.init(title = !Menu_Setting & fmt" - InstantMenu {number}" , size=(0, 0))
    self.icon = Icon("", 0)
    self.setTrayIcon(self.icon)
    self.enableTrayHoverEvent(wEvent_TrayHover)

    self.initUi()
    self.updateButtonState()
    self.handleClientSizeFactor()
    self.createTreeNode()
    self.loadTreeImage()
    self.resetHotkeyAndOption()

    self.enableTitleEdit()
    self.enalbeAttribEdit()
    self.enableTreeDrag()
    self.enableNewCopyPasteDelete()
    self.enableArrowKeys()
    self.enableUndoRedo()
    self.enableSpecialEvents()
    self.enableMouseEvents()
    self.enableKeyboardEvents()
    self.enableButtonEvents()
    self.enableTreeEvents()
    self.enableShowCloseExitEvents()
    self.enableDragDrop()
    self.enableConsoleEvents()

    # after wEvent_TreeSelChanged event binding
    self.restoreTreeStatus()

    self.queueMessage(wEvent_Start)

proc start() =
  disableWin64Redirection()
  main.init()
  main.cacheFile = appDir() / "InstantMenu.cache"
  main.configFile = appDir() / "InstantMenu.ura"
  let app = App(wSystemDpiAware)

  var jnode: JsonNode
  try:
    jnode = fromGuraFile(main.configFile)
  except GuraError:
    MessageDialog(nil, getCurrentExceptionMsg(), "Error", wIconErr).display()
    quit()
  except OSError:
    discard

  # staticLoadLang(staticRead("InstantMenu.lang"))
  try:
    loadLang(readFile(appDir() / "InstantMenu.lang"))
  except IOError, OSError, GuraError:
    discard

  let language = jnode{"language"}.getStr("English")
  # staticInitLang("English")
  initLang(language)

  loadCache()
  loadConfig(jnode)
  resetImageList(main.root.getInt("iconsize", 24))
  main.recentLen = main.root.getInt("recentlen", 35)

  main.searchBox = SearchBox()
  main.mainFrame = MainFrame()
  main.waitFrame = WaitFrame(main.mainFrame)
  main.menuWindow = MenuWindow()

  main.mainFrame.center()
  if main.root.childless():
    main.mainFrame.doImportSystemMenu()
    main.mainFrame.show()

  app.run()
  main.exit()

when isMainModule:
  when defined(cpu64):
    {.link: "resources/InstantMenu64.res".}
  else:
    {.link: "resources/InstantMenu32.res".}

  start()
