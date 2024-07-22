#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import pkg/winim/com
import pkg/wNim/[wApp, wWindow, wMenu]
import paths

proc shellContextMenu*(window: wWindow, menu: wMenu, path: string, idFirst: cint): wCommandID =
  # Note SHBindToParent does not allocate a new PIDL;
  # it simply receives a pointer through this parameter.
  # Therefore, you are not responsible for freeing this resource.
  var
    path = path.toAbsolute()
    flags: UINT
    pidl: PIDLIST_ABSOLUTE
    psfParent: ptr IShellFolder
    pidlRelative: LPITEMIDLIST
    picm: ptr IContextMenu

  defer:
    if pidl != nil: CoTaskMemFree(pidl)
    if psfParent != nil: psfParent.Release()
    if picm != nil: picm.Release()

  if path.len == 0: return
  if SHParseDisplayName(path, nil, &pidl, 0, &flags) != S_OK: return
  if SHBindToParent(pidl, &IID_IShellFolder, &psfParent, &pidlRelative) != S_OK: return
  if psfParent.GetUIObjectOf(0, 1, &pidlRelative, &IID_IContextMenu, nil, &picm) != S_OK: return

  picm.QueryContextMenu(menu.handle, menu.len, idFirst, uint16.high.cint, CMF_NORMAL)

  let retId = int window.popupMenu(menu, flag=wPopMenuReturnId or wPopMenuRecurse)
  if retId != 0:
    EndMenu()
    if retId >= idFirst:
      var ici = CMINVOKECOMMANDINFO(cbSize: int32 sizeof(CMINVOKECOMMANDINFO))
      ici.hwnd = window.handle
      ici.lpVerb = MAKEINTRESOURCEA(retId - idFirst)
      ici.nShow = SW_SHOWNORMAL
      discard picm.InvokeCommand(ici)

    return wCommandId retId

when isMainModule:
  import wNim/wFrame
  import locale

  staticLoadLang(staticRead("../InstantMenu.lang"))
  staticInitLang("正體中文")

  type
    MenuId = enum
      OpenPath = 1, CopyPath, ItemSetting, IdLast

  let app = App(wSystemDpiAware)
  let frame = Frame()
  frame.center()
  frame.show()

  frame.wEvent_ContextMenu do ():
    let menu = Menu()
    menu.append(OpenPath, !Open_Path)
    menu.append(CopyPath, !"Copy_&Full_Path")
    menu.append(ItemSetting, !Item_Setting)

    menu.appendSeparator()
    echo frame.shellContextMenu(menu, currentSourcePath(), ord IdLast)

  app.run()
