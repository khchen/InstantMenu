#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/[strutils, strformat]
import pkg/memlib/rtlib
import pkg/winim/[lean, inc/objbase, inc/shellapi]
import pkg/wAuto/registry
import paths

converter pointerConverter(x: ptr): ptr PVOID = cast[ptr PVOID](x)

template `or`(a, b: string): string =
  if a.len != 0: a else: b

proc disableWin64Redirection*() =
  var oldValue: pointer
  Wow64DisableWow64FsRedirection(&oldValue)

proc isWin64*(): bool =
  when defined(cpu64):
    result = true
  else:
    var isWow64: BOOL
    result = IsWow64Process(GetCurrentProcess(), &isWow64) and isWow64

proc MsiGetShortcutTarget*(
    szShortcutPath: LPCWSTR,
    szProductCode: LPWSTR,
    szFeatureId: LPWSTR,
    szComponentCode: LPWSTR): cint
  {.stdcall, checkedRtlib: "msi", importc: "MsiGetShortcutTargetW", discardable.}

proc MsiGetComponentPath*(
    szProduct: LPCWSTR,
    szComponent: LPCWSTR,
    lpPathBuf: LPWSTR,
    pcchBuf: LPDWORD): cint
  {.stdcall, checkedRtlib: "msi", importc: "MsiGetComponentPathW", discardable.}

proc SHExtractIconsW*(pszFileName: LPCWSTR, nIconIndex: int, cxIcon: int, cyIcon: int,
  phIcon: ptr HICON, pIconId: ptr UINT, nIcons: UINT, flags: UINT ): UINT
  {.discardable, stdcall, dynlib: "shell32", importc.}

proc env*(src: string): string =
  if src == "": return ""

  once:
    let list = [
      ("appdir", appDir()),
      ("appfilename", appFilename()),
      ("currentdir", currentDir()),
    ]

    for (key, val) in list:
      SetEnvironmentVariable(key, val)

  var buffer = T(32767)
  if ExpandEnvironmentStrings(src, &buffer, cint buffer.len) != 0:
    result = ($buffer.nullTerminated).longPathName
  else:
    result = src

# proc expand*(path: string, mustExist=false): string =
#   if path.len == 0: return ""

#   result = path.env()
#   if result.pathExist():
#     result = result.toAbsolute()

#   elif mustExist:
#     result = ""

proc getSpecialPath*(id: DWORD): string =
  let buffer = T(MAX_PATH)
  if SHGetSpecialFolderPath(0, &buffer, id, 0) == 0:
    return ""

  return $buffer.nullTerminated()

proc getQuickLaunchPath*(isGlobal = false): string =
  var dir = getSpecialPath(if isGlobal: CSIDL_COMMON_APPDATA else: CSIDL_APPDATA)
  if dir.len != 0:
    let r = regRead(r"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\explorer\FolderDescriptions\{52a4f021-7b75-48a9-9f6b-4b87a210bc8f}", "RelativePath")
    if r.kind == rkRegSz:
      let relativePath = r.data or r"Microsoft\Internet Explorer\Quick Launch"
      result = dir \ relativePath
      if not result.dirExist(): result = ""

proc loadString*(name: string): string =
  var buffer = T(32768)
  if SHLoadIndirectString(name, buffer, cint buffer.len, nil) == S_OK:
    result = $buffer.nullTerminated()

proc iniRead*(file, section, key: string, default = ""): string =
  var buffer = T(32768)
  buffer.setLen(GetPrivateProfileString(section, key, default, buffer, cint buffer.len, file))
  result = $buffer

proc localDirName*(dir: string): string =
  result = dir.filenamePart()
  let ini = dir \ "desktop.ini"
  if ini.fileExist():
    let newTitle = loadString(ini.iniRead(".ShellClassInfo", "LocalizedResourceName"))
    if newTitle.len != 0:
      result = newTitle

proc localFileName*(path: string): string =
  result = path.filenamePart()
  let ini = path.dirPart() \ "desktop.ini"
  if ini.fileExist():
    let newTitle = loadString(ini.iniRead("LocalizedFileNames", result))
    if newTitle.len != 0:
      result = newTitle

proc localName*(path: string): string =
  var
    path = path.toAbsolute()
    flags: UINT
    pidl: PIDLIST_ABSOLUTE
    psfParent: ptr IShellFolder
    pidlRelative: LPITEMIDLIST # Note  SHBindToParent does not allocate a new PIDL; it simply receives a pointer through this parameter. Therefore, you are not responsible for freeing this resource.
    name: STRRET
    psz: LPTSTR

  defer:
    if pidl != nil: CoTaskMemFree(pidl)
    if psfParent != nil: psfParent.Release()
    if psz != nil: CoTaskMemFree(psz)
    # name 會被 StrRetToStr 釋放

  if SHParseDisplayName(path, nil, &pidl, 0, &flags) != S_OK: return
  if SHBindToParent(pidl, &IID_IShellFolder, &psfParent, &pidlRelative) != S_OK: return
  if psfParent.GetDisplayNameOf(pidlRelative, SHGDN_NORMAL, &name) != S_OK: return
  if StrRetToStr(&name, pidlRelative, &psz) != S_OK: return

  result = ($psz).namePart()

proc getMsiPath(lnk: string): string =
  var productCode = T(39)
  var componentCode = T(39)
  var buffer = T(32768)
  var size = cint buffer.len
  try:
    MsiGetShortcutTarget(lnk, productCode, nil, componentCode)
    MsiGetComponentPath(productCode, componentCode, buffer, &size)
    result = $buffer.nullTerminated()
  except LibraryError:
    result = ""

proc getVersion*(path: string, name = ""): string =
  var unused: DWORD
  let size = GetFileVersionInfoSize(path, &unused)
  if size == 0: return

  var buffer = newString(size)
  if GetFileVersionInfo(path, 0, size, &buffer) == 0: return

  var ffi: ptr VS_FIXEDFILEINFO
  var bytes: UINT

  if name.len == 0:
    if VerQueryValue(&buffer, r"\", &ffi, &bytes) == 0: return
    result = fmt"{ffi.dwFileVersionMS shr 16}.{ffi.dwFileVersionMS and 0xffff}.{ffi.dwFileVersionLS shr 16}.{ffi.dwFileVersionLS and 0xffff}"

  else:
    var lang: ptr array[2, WORD]
    if VerQueryValue(&buffer, r"\VarFileInfo\Translation", &lang, &bytes) == 0 or bytes < 4: return
    let langStr = lang[0].tohex & lang[1].tohex
    let query = fmt"\StringFileInfo\{langStr}\{name}"
    var pstr: LPTSTR

    if VerQueryValue(&buffer, query, &pstr, &bytes) == 0: return
    result = $pstr

proc parseDesign*(path: string, design = ""): string =
  let lowerDesign = design.toLowerAscii

  var list = newSeqOfCap[(string, string)](5)
  if "%filename%" in lowerDesign: list.add ("filename", path.namePart())
  if "%fileext%" in lowerDesign: list.add ("fileext", path.extPart())
  if "%fileversion%" in lowerDesign: list.add ("fileversion", path.getVersion())
  if "%productname%" in lowerDesign: list.add ("productname", path.getVersion("ProductName"))
  if "%displayname%" in lowerDesign: list.add ("displayname", path.localName())

  for (key, value) in list: SetEnvironmentVariable(key, value)
  defer:
    for (key, value) in list: SetEnvironmentVariable(key, nil)

  result = design.env

type
  Shortcut* = object
    path*: string
    dir*: string
    arg*: string
    icon*: string
    show*: string
    hotkey*: tuple[modifiers: int, keyCode: int]

proc extractShortcut*(lnk: string): Shortcut =
  defer:
    if result.path.len != 0: result.path = result.path.env
    if result.dir.len != 0: result.dir = result.dir.env
    if result.icon.len != 0: result.icon = result.icon.env

    # 在 32bit 下，即使已用 Wow64DisableWow64FsRedirection
    # 還是會錯誤地把 Program Files 解為 Program Files (x86)
    if result.path.len != 0 and not result.path.pathExist():
      let programFiles86 = "%ProgramFiles(x86)%".env
      let programFiles = "%ProgramW6432%".env

      let newPath = result.path.replace(programFiles86, programFiles)
      if newPath.fileExist():
        result.path = newPath
        result.dir = result.dir.replace(programFiles86, programFiles)
        result.icon = result.icon.replace(programFiles86, programFiles)

  var pIL: ptr IShellLink
  if CoCreateInstance(&CLSID_ShellLink, nil, CLSCTX_LOCAL_SERVER, &IID_IShellLink, &pIL).SUCCEEDED:
    defer: pIL.Release()

    var pPF: ptr IPersistFile
    if pIL.QueryInterface(&IID_IPersistFile, &pPF).SUCCEEDED:
      defer: pPF.Release()

      if pPF.Load(lnk, STGM_READ).SUCCEEDED:
      # if pPF.Load(lnk, STGM_READ).SUCCEEDED and pIL.Resolve(0, SLR_NO_UI).SUCCEEDED:
        var buffer = T(32768)
        var index: cint
        var hotkey: WORD
        var showCmd: cint

        result.path = getMsiPath(lnk)
        if result.path.len == 0:
          if pIL.GetPath(buffer, cint buffer.len, nil, SLGP_RAWPATH).SUCCEEDED:
            result.path = $buffer.nullTerminated()

        if pIL.GetWorkingDirectory(buffer, cint buffer.len).SUCCEEDED:
          result.dir = $buffer.nullTerminated()

        if pIL.GetArguments(buffer, cint buffer.len).SUCCEEDED:
          result.arg = $buffer.nullTerminated()

        if pIL.GetIconLocation(buffer, cint buffer.len, &index).SUCCEEDED:
          result.icon = $buffer.nullTerminated()
          if index != 0:
            result.icon.add "," & $index
          else:
            # 如果 index 是 0，可能是 .ico 或 .dll,0
            var hIcon: HICON
            var id: cint
            if SHExtractIconsW(result.icon, index, 16, 16, &hIcon, &id, 1, 0) != 0:
              DestroyIcon(hIcon)
              if id != 0 and id != -1:
                result.icon.add ",0"

        if pIL.GetShowCmd(&showCmd).SUCCEEDED:
          result.show = case showCmd
            of SW_SHOWMINNOACTIVE: "min"
            of SW_SHOWMAXIMIZED: "max"
            else: ""

        if pIL.GetHotkey(&hotkey).SUCCEEDED:
          # shortcut use
          # HOTKEYF_SHIFT* = 0x1
          # HOTKEYF_CONTROL* = 0x2
          # HOTKEYF_ALT* = 0x4

          # wNim use
          # MOD_ALT* = 0x0001
          # MOD_CONTROL* = 0x0002
          # MOD_SHIFT* = 0x0004
          # MOD_WIN* = 0x0008
          result.hotkey.keyCode = int(hotkey and 0xff)
          let modifiers = int(hotkey shr 8)
          result.hotkey.modifiers =
            ((modifiers and 1) shl 2) or
            (modifiers and 2) or
            ((modifiers and 4) shr 2)

          # if (modifiers and HOTKEYF_SHIFT) != 0:
          #   result.hotkey.modifiers = result.hotkey.modifiers or MOD_SHIFT

          # if (modifiers and HOTKEYF_CONTROL) != 0:
          #   result.hotkey.modifiers = result.hotkey.modifiers or MOD_CONTROL

          # if (modifiers and HOTKEYF_ALT) != 0:
          #   result.hotkey.modifiers = result.hotkey.modifiers or MOD_ALT

proc getPathExt(): seq[string] =
  var pathext = T(32767)
  pathext.setLen(GetEnvironmentVariable("PATHEXT", &pathext, DWORD pathext.len))
  result = (($pathext).toLowerAscii).split(';')

proc whereIs*(name: string): string = # 結果都轉為小寫
  if name.len == 0:
    return name

  elif name.fileExist:
    return name.toAbsolute.toLowerAscii

  elif {'\\', '/'} in name:
    var pathExt = getPathExt()
    for ext in pathExt:
      let path = name & ext
      if path.fileExist:
        return path.toAbsolute.toLowerAscii

  else:
    var pathExt = getPathExt()
    if name.extPart in pathExt:
      pathExt.insert("", 0)

    var currDir = currentDir()
    var otherDirs = [LPCWSTR currDir, nil]

    for ext in pathExt:
      var buffer = T(name & ext)
      buffer.setLen(32767)
      if PathFindOnPath(&buffer, cast[ptr LPCWSTR](&otherDirs)) != 0:
        return ($buffer).nullTerminated.toLowerAscii

    # dll file?
    if name.extPart.toLowerAscii == ".dll":
      let oldValue = SetErrorMode(SEM_FAILCRITICALERRORS)
      defer: SetErrorMode(oldValue)

      let hDll = LoadLibraryEx(name, 0, DONT_RESOLVE_DLL_REFERENCES)
      if hDll != 0:
        defer:  FreeLibrary(hDll)
        var buffer = T(32767)

        let L = int GetModuleFileName(hDll, &buffer, DWORD buffer.len)
        if L != 0:
          buffer.setLen(L)
          return ($buffer).toLowerAscii

  result = name.toLowerAscii

proc unWhereIs*(path: string, alreadyAbsolute = false): string = # 結果都轉為小寫
  if alreadyAbsolute or (not path.isRelative):
    let name = path.namePart
    if name.whereIs() == path.toLowerAscii:
      return name.toLowerAscii

    let filename = path.filenamePart
    if filename.whereIs() == path.toLowerAscii:
      return filename.toLowerAscii

  result = path.toLowerAscii

proc splitIconLocation*(path: string): tuple[path, location: string] =
  let pos = path.rfind(',')
  if pos >= 0 and path[(pos + 1)..^1].allCharsInSet(Digits + {'-'}):
    result.path = path[0..<pos]
    result.location = path[pos..^1]

  else:
    result.path = path

proc pathSwitch*(path: string, isIcon = false): string = # 結果都轉為小寫
  let path = path.toLowerAscii
  if path.startsWith(":"): return ""

  if isIcon:
    let (path, location) = path.splitIconLocation()
    let ret = path.pathSwitch
    result =
      if ret != "": ret & location
      else: ""

  else:
    if path.isRelative:
      result = path.whereIs
      if result == path:
        result = path.toAbsolute.toLowerAscii
    else:
      result = path.unWhereIs(alreadyAbsolute=true)
      if result == path:
        result = path.toRelative.toLowerAscii

type
  PathSwitchOption* {.pure.} = enum
    PathToRelative, PathToAbsolute, PathIsIcon

proc pathSwitch*(path: string, option: set[PathSwitchOption]): string = # 結果都轉為小寫
  let path = path.toLowerAscii

  if PathIsIcon in option:
    let (path, location) = path.splitIconLocation()
    var opt = option
    opt.excl(PathIsIcon)
    let ret = path.pathSwitch(opt)
    result =
      if ret != "": ret & location
      else: ""

  else:
    if path.isRelative:
      if PathToRelative in option:
        result = path
      else:
        result = path.whereIs()
        if result == path:
          result = path.toAbsolute.toLowerAscii
    else:
      if PathToAbsolute in option:
        result = path
      else:
        result = path.unWhereIs(alreadyAbsolute=true)
        if result == path:
          result = path.toRelative.toLowerAscii

when isMainModule:
  import std/sugar

  disableWin64Redirection()
  CoInitialize(nil)

  dump isWin64()
  dump "%tmp%".env()
  dump "%CommonProgramFiles%;%home%;%currentdir%".env()

  dump getSpecialPath(CSIDL_COMMON_STARTMENU)
  dump getSpecialPath(CSIDL_STARTMENU)

  dump getQuickLaunchPath(false)
  dump getQuickLaunchPath(true)

  let programs = getSpecialPath(CSIDL_COMMON_PROGRAMS)
  dump localDirName(programs & r"\Administrative Tools")
  dump localFileName(programs & r"\Administrative Tools\services.lnk")
  dump localName(programs & r"\Administrative Tools")
  dump localName(programs & r"\Administrative Tools\services.lnk")

  let shortcut = extractShortcut(programs & r"\Word.lnk")
  dump shortcut
  dump parseDesign(shortcut.path, "%FileName%")
  dump parseDesign(shortcut.path, "%DisplayName% %FileVersion%")

  dump whereIs("cmd")
  dump unWhereIs(whereIs("cmd"))

  dump "../git".pathSwitch
  dump "../git".pathSwitch.pathSwitch
  dump r"shell32.dll,1".pathSwitch(true)
  dump r"shell32.dll,1".pathSwitch(true).pathSwitch(true)
  dump pathSwitch("shell32.dll,1", {PathToAbsolute, PathIsIcon})
