#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

# Package
version       = "0.3.0"
author        = "Ward"
description   = "InstantMenu - A Portable Launcher Tool for Windows"
license       = "MIT"
skipDirs      = @["bin"]

# Dependencies
requires "nim >= 2.0.0"
requires "winim >= 3.9.4"
requires "wNim >= 1.0.0"
requires "wAuto >= 1.3.0"
requires "gura >= 0.1.0"
requires "NimPk >= 1.0.2"
requires "hashlib >= 1.0.1"
requires "malebolgia >= 1.3.2"

task bin, "Build the program":
  # --mm:orc has some problems with this program; I think it's a compiler bug,
  # but I don't know how to fix it.
  # --mm:orc --exceptions:goto: The compilation time is unusually long,
  # and the executable file size is unusually large.
  # If we ignore the unusually large executable file size,
  # the execution is normal.
  # --mm:orc --exceptions:setjmp: The compilation time and file size is normal,
  # but the program occasionally exits unexpectedly when an exception occurs.
  # Using --mm:refc seems to be an inevitable choice.
  # both -d:lto and -d:danger casue some problems
  exec "nim c --mm:refc -d:script -d:release -d:strip --app:gui --opt:size -o:bin/InstantMenu InstantMenu.nim"
