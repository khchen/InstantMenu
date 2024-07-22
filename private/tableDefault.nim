#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/tables

template `{}`*[A, B](t: OrderedTable[A, B]; key: A): B =
  t.getOrDefault(key)

template `{}`*[A, B](t: OrderedTable[A, B]; key: A; default: B): B =
  t.getOrDefault(key, default)

template `{}`*[A, B](t: OrderedTableRef[A, B]; key: A): B =
  t.getOrDefault(key)

template `{}`*[A, B](t: OrderedTableRef[A, B]; key: A; default: B): B =
  t.getOrDefault(key, default)

template `{}`*[A, B](t: Table[A, B]; key: A): B =
  t.getOrDefault(key)

template `{}`*[A, B](t: Table[A, B]; key: A; default: B): B =
  t.getOrDefault(key, default)

template `{}`*[A, B](t: TableRef[A, B]; key: A): B =
  t.getOrDefault(key)

template `{}`*[A, B](t: TableRef[A, B]; key: A; default: B): B =
  t.getOrDefault(key, default)
