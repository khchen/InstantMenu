#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import pkg/winim/lean

const
  c_O_TEXT = cint 0x4000
  c_IONBF = cint 0x0004

type
  Pipe* = object
    read*: HANDLE
    write*: HANDLE

proc c_open_osfhandle(osfhandle: int, flags: cint): cint
  {.importc: "_open_osfhandle", header: "<stdio.h>", discardable.}

proc c_dup2(fd1: cint, fd2: cint): cint
  {.importc: "_dup2", header: "<stdio.h>".}

proc c_fileno(stream: File): cint
  {.importc: "_fileno", header: "<stdio.h>".}

proc setvbuf(stream: File, buffer: cstring, mode: cint, size: csizet): cint
  {.importc: "setvbuf", header: "<stdio.h>".}

proc close*(pipe: Pipe) =
  CloseHandle(pipe.read)
  CloseHandle(pipe.write)

proc redirectStdout*(): Pipe =
  var sa = SECURITY_ATTRIBUTES(
    nLength: cint sizeof(SECURITY_ATTRIBUTES),
    bInheritHandle: true)

  CreatePipe(&result.read, &result.write, &sa, 0)

  let fd = c_open_osfhandle(result.write, c_O_TEXT)
  discard c_dup2(fd, c_fileno(stdout))
  discard setvbuf(stdout, nil, c_IONBF, 0)

proc redirectStderr*(): Pipe =
  var sa = SECURITY_ATTRIBUTES(
    nLength: cint sizeof(SECURITY_ATTRIBUTES),
    bInheritHandle: true)

  CreatePipe(&result.read, &result.write, &sa, 0)

  let fd = c_open_osfhandle(result.write, c_O_TEXT)
  discard c_dup2(fd, c_fileno(stderr))
  discard setvbuf(stderr, nil, c_IONBF, 0)

proc redirectStdin*(): Pipe =
  var sa = SECURITY_ATTRIBUTES(
    nLength: cint sizeof(SECURITY_ATTRIBUTES),
    bInheritHandle: true)

  CreatePipe(&result.read, &result.write, &sa, 0)

  let fd = c_open_osfhandle(result.read, c_O_TEXT)
  discard c_dup2(fd, c_fileno(stdin))
  discard setvbuf(stdin, nil, c_IONBF, 0)

proc read*(pipe: Pipe, L: Positive): string =
  var read: DWORD
  result = newString(L)
  ReadFile(pipe.read, &result, cint result.len, &read, nil)
  result.setLen(read)

proc read*(pipe: Pipe, peek = false): string =
  var read, total: DWORD

  if PeekNamedPipe(pipe.read, nil, 0, nil, &total, nil) == 0:
    raise newException(IOError, "pipe closed")

  if total != 0:
    result = newString(total)

    if peek:
      PeekNamedPipe(pipe.read, &result, cint result.len, &read, nil, nil)
      result.setLen(read)

    else:
      ReadFile(pipe.read, &result, cint result.len, &read, nil)
      result.setLen(read)

proc write*(pipe: Pipe, data: string): int {.discardable} =
  var written: DWORD
  WriteFile(pipe.write, &data, cint data.len, &written, nil)
  return int written

when isMainModule:
  proc c_gets(str: cstring): cstring
    {.importc: "gets", header: "<stdio.h>", discardable.}

  let stdoutPipe = redirectStdout()
  let stderrPipe = redirectStderr()
  let stdinPipe = redirectStdin()
  stdinPipe.write("test\n")

  var buffer = newString(1024)
  echo c_gets(cstring buffer)
  MessageBox(0, stdoutPipe.read(), "", 0)

  stderr.write("error")
  MessageBox(0, stderrPipe.read(), "", 0)
