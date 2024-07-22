#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/[tables, macros, json, strutils, sequtils, sets]
import pkg/gura
export tables

type
  Lang = OrderedTable[string, string]
  Locale = OrderedTable[string, Lang]

proc localeStorage(input = Locale(), set = false): var Locale {.discardable.} =
  var s {.global.}: Locale
  if set: s = input
  return s

proc langStorage(input = Lang(), set = false): var Lang {.discardable.} =
  var l {.global.}: Lang
  if set: l = input
  return l

proc parseLanguage*(data: string): Locale =
  let jnode = fromGura(data)
  if jnode.kind == JObject:
    for name, table in jnode:
      if table.kind != JObject:
        continue

      var lang: Lang
      for key, val in table:
        lang[key] = val.getStr()

      result[name] = lang

template staticLoadLang*(data: static[string]) =
  static:
    discard localeStorage(parseLanguage(data), set=true)

template loadLang*(data: string) =
  discard localeStorage(parseLanguage(data), set=true)

template initLang*(name: string) =
  const ct = localeStorage()
  var rt = localeStorage()
  var lang = ct.getOrDefault(name)
  var rtlang = rt.getOrDefault(name)
  for k, v in rtlang:
    lang[k] = v
  discard langStorage(lang, set=true)

proc staticInitLang*(name: static[string]) =
  const ct = localeStorage()
  static:
    discard langStorage(ct.getOrDefault(name), set=true)

template staticLangs*(): seq[string] =
  const ct = localeStorage()
  if "English" in ct:
    toSeq(ct.keys)
  else:
    "English" + toSeq(ct.keys)

template langs*(): seq[string] =
  const ct = localeStorage()
  var rt = localeStorage()
  var s: OrderedSet[string]
  if "English" notin ct and "English" notin rt:
    s.incl "English"
  for name in ct.keys: s.incl name
  for name in rt.keys: s.incl name
  toSeq(s.items)

proc translate*(text: string): string =
  result = langStorage().getOrDefault(text, text).replace("_", " ")

macro `!`*(symbol: untyped): untyped =
  if symbol.kind in {nnkIdent, nnkStrLit}:
    let str = newStrLitNode(symbol.strVal)
    return quote do:
      translate(`str`)
  else:
    return symbol

macro `!!`*(symbol: untyped): untyped =
  if symbol.kind in {nnkIdent, nnkStrLit}:
    let str = newStrLitNode(symbol.strVal)
    return quote do:
      const s = translate(`str`)
      s
  else:
    return symbol

when isMainModule:
  const lang = """
    English: empty
    正體中文:
      About: "關於"
    简体中文:
      About: "关于"
  """.unindent(4)

  staticLoadLang(lang)
  staticInitLang("正體中文")
  doAssert !!About == "關於"
  doAssert !About == "About"

  initLang("正體中文")
  doAssert !!About == "關於"
  doAssert !About == "關於"

  initLang("简体中文")
  doAssert !!About == "關於"
  doAssert !About == "关于"

  initLang("English")
  doAssert !!About == "關於"
  doAssert !About == "About"
