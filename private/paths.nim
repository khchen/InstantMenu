#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/[strutils, os]
import pkg/winim/[lean, winstr, inc/shellapi]

proc longPathName*(path: string): string =
  ## 取得長檔名 (buffer 可能會大於 MAX_PATH)
  ## 若失敗則傳回原 path
  var buffer = T(32767)
  buffer.setLen(GetLongPathName(path, buffer, cint buffer.len))
  result = $buffer
  if result.len == 0: result = path

proc shortPathName*(path: string): string =
  ## 取得短檔名
  ## 若失敗則傳回原 path
  var buffer = T(32767)
  buffer.setLen(GetShortPathName(path, buffer, cint buffer.len))
  result = $buffer
  if result.len == 0: result = path

proc canonicalize*(path: string): string =
  ## 藉由移除 「.」 和 「.」 等導覽元素來產生直接、格式正確的路徑，以簡化路徑
  var buffer = T(32767)
  if PathCanonicalize(buffer, path):
    result = $buffer
  else:
    result = path

proc fullPathName*(path: string): string =
  ## 類似 canonicalize, 但會用 currentdir 把相對目錄轉為絕對目錄
  var buffer = T(32767)
  buffer.setLen(GetFullPathName(path, cint buffer.len, buffer, nil))
  result = $buffer
  if result.len == 0: result = path

proc currentDir*(): string =
  var buffer = T(32767)
  buffer.setLen(GetCurrentDirectory(cint buffer.len, buffer))
  result = $buffer

proc currentDir*(path: string) =
  SetCurrentDirectory(path)

proc pathExist*(path: string): bool =
  let attr = GetFileAttributes(path)
  result = (attr != INVALID_FILE_ATTRIBUTES)

proc dirExist*(path: string): bool =
  let attr = GetFileAttributes(path)
  result = attr != INVALID_FILE_ATTRIBUTES and (attr and FILE_ATTRIBUTE_DIRECTORY) != 0

proc fileExist*(path: string): bool =
  let attr = GetFileAttributes(path)
  result = attr != INVALID_FILE_ATTRIBUTES and (attr and FILE_ATTRIBUTE_DIRECTORY) == 0

# proc isHidden*(path: string): bool =
#   let attr = GetFileAttributes(path)
#   result = attr != INVALID_FILE_ATTRIBUTES and (attr and FILE_ATTRIBUTE_HIDDEN) != 0

proc isRelative*(path: string): bool =
  if path.len == 0:
    return true
  elif path[0] == '/':
    return false
  else:
    result = bool PathIsRelative(path)

proc toAbsolute*(path: string): string =
  if path.len == 2 and path[1] == ':': # c: or d: 會傳回該磁碟的目前路徑
    result = path
  else:
    result = path.fullPathName() # fullPathName 會標準化路徑（去除 .. 或 \\，轉換 / 成 \等）

proc toRelative*(path: string, base = ""): string =
  var buffer = T(32767)
  let path = path.toAbsolute()
  let base =
    if base.len != 0 and base.dirExists: base
    else: currentDir()

  let flag: cint =
    if path.dirExists(): FILE_ATTRIBUTE_DIRECTORY
    else: FILE_ATTRIBUTE_NORMAL

  if PathRelativePathTo(buffer, base, FILE_ATTRIBUTE_DIRECTORY, path, flag) != 0:
    result = $buffer.nullTerminated
  else:
    result = path

  if result.startsWith r".\":
    result = result[2..^1]
    if result.len == 0:
      result = "."

proc standardize*(path: string): string =
  if path.len == 0:
    return ""

  elif not path.isRelative:
    result = path.toAbsolute

    if path[0] in {'\\', '/'} and result.len >= 2 and result[1] == ':': # 移除 C:, D: 等
      result = result[2..^1]

    if result[^1] == '\\' and result.len > 3: # 除非 "c:\"，不然移除最後一個 \
      result.setLen(result.len - 1)

  else:
    result = path.toAbsolute.toRelative

    if result[^1] == '\\': # 移除最後一個 \
      result.setLen(result.len - 1)

proc `\`*(path1, path2: string): string =
  result = path1
  if result.len != 0 and result[^1] != '\\':
    result.add '\\'

  result.add path2
  result = result.standardize

proc filenamePart*(path: string): string =
  var buffer = T(path)
  PathStripPath(buffer)
  result = ($buffer.nullTerminated).standardize

proc dirPart*(path: string): string =
  let filename = path.filenamePart
  let pos = path.rfind(filename)
  if pos != -1:
    result = path[0..<pos].standardize

proc namePart*(path: string): string =
  result = path.filenamePart()
  let pos = result.rfind('.')
  if pos != -1: result.setLen(pos)

proc extPart*(path: string): string =
  let path = path.filenamePart()
  let pos = path.rfind('.')
  if pos != -1: result = path[pos..^1]

proc appPath*(): string =
  var buffer = T(32767)
  buffer.setLen(GetModuleFileName(0, buffer, cint buffer.len))
  result = $buffer

proc appDir*(): string =
  result = appPath().dirPart()

proc appFilename*(): string =
  result = appPath().filenamePart()

type
  WalkOption* = enum
    woFile, woDir, woRec, woAbsolute

iterator walkPathNoRec(pattern: string, option = {woFile, woDir}): string =
  var wfd: WIN32_FIND_DATA
  let baseDir = pattern.dirPart()

  let handle = FindFirstFile(pattern, &wfd)
  if handle != INVALID_HANDLE_VALUE:
    while true:
      let filename = (%$wfd.cFileName).nullTerminated
      if filename != "." and filename != "..":
        if (wfd.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) != 0:
          if woDir in option:
            if woAbsolute in option:
              yield (baseDir \ filename).toAbsolute
            else:
              yield (baseDir \ filename).standardize

        else:
          if woFile in option:
            if woAbsolute in option:
              yield (baseDir \ filename).toAbsolute
            else:
              yield (baseDir \ filename).standardize

      if FindNextFile(handle, &wfd) == 0: break

    FindClose(handle)

iterator walkPath*(pattern: string, option = {woFile, woDir}): string =
  var stack = @[pattern]

  while stack.len > 0:
    let pattern = stack.pop()
    let baseDir = pattern.dirPart()
    let basePattern = pattern.filenamePart()

    for path in walkPathNoRec(pattern, option):
      yield path

    if woRec in option:
      for dir in walkPathNoRec(baseDir \ "*.*", {woDir}):
        stack.add dir \ basePattern

when isMainModule:
  import std/[unittest, sugar]

  let dir = currentDir()
  suite "Test Suite for paths":
    setup:
      currentDir(currentSourcePath().dirPart())

    teardown:
      currentDir(dir)

    test "Path Names":
      check:
        r"c:\a.tmp\".dirPart == r"c:\"
        r"c:\a.tmp\".filenamePart == r"a.tmp"
        r"c:\a.tmp\".namePart == r"a"
        r"c:\a.tmp\".extPart == r".tmp"

        r"c:".pathExist == true
        r"c:\".pathExist == true
        r"b:".pathExist == false
        r"paths.nim".fileExist == true
        r"c:\windows".fileExist == false
        r"paths.nim".dirExist == false
        r"c:\windows".dirExist == true

        r"C:\Program Files".shortPathName == r"C:\PROGRA~1"
        r"C:\PROGRA~1".longPathName == r"C:\Program Files"
        r"c:\abcde~1".longPathName == r"c:\abcde~1"

        r"".isRelative == true
        r"a".isRelative == true
        r"/a".isRelative == false
        r"\a".isRelative == false
        r"c:".isRelative == false

        r"".toAbsolute == ""
        r"".toRelative == ""

        r"a\b\..\c//d\e\..\\f\.\e\\..//.\a\.\.\..\..\a".standardize == r"a\c\d\a"
        r"c:\\a\b\..\c//d\e\..\\f\.\e\\..//.\a\.\.\..\..\a".standardize == r"c:\a\c\d\a"
        r"/abc".standardize == r"\abc"

        r"c:\".standardize == r"c:\"
        r"c:\windows\".standardize == r"c:\windows"

        r"..".toRelative == r".."
        r".".toRelative == r"."
        r"..".standardize == r".."
        r".".standardize == r"."
        r"a\b\c\..\..\..".standardize == "."
        r"a\b\c\..\..\..".standardize == "."

        r"a" \ r"..\abc" == "abc"

  dump appPath()
  dump appDir()
  dump appFilename()
  dump currentDir()
  echo ""
  dump appPath()
  dump appPath().dirPart
  dump appPath().filenamePart
  dump appPath().namePart
  dump appPath().extPart
  dump appFilename().namePart()
