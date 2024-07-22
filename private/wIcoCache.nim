#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/[tables, strutils, os]
import pkg/winim/mean
import pkg/wNim/[wApp, wBitmap, wImage, wIconImage, wIcon, private/nimpack]
import pkg/hashlib/misc/nimhash
import pkg/zippy

{. warning[Effect]:off .}

type
  # CACHE_HASH = XXHASH64
  CACHE_HASH = NIM_MD5

  wIco* = object
    path: string
    size: int
    shellOnly: bool

  wIcoCache* = object
    table: Table[wIco, string]

proc initIcoCache*(): wIcoCache =
  discard

proc IcoData*(data: string, size: int): wIco =
  result.path = data
  result.size = size

proc IcoPath*(path: string, size: int): wIco =
  result.path = path.toLowerAscii
  result.size = size

proc IcoShell*(path: string, size: int): wIco =
  result.path = path.toLowerAscii
  result.size = size
  result.shellOnly = true

proc Ico*(path: string, size: int): wIco =
  if PathFileExists(path):
    result.path = path.toLowerAscii
  else:
    result.path = path
  result.size = size

proc fromIconImage(ico: wIco): string =
  # ico.path can be static[string] 或 "shell32.dll,10" 等
  # return iconimage data or ""

  # avoid large file
  if ico.path.fileExists:
    try:
      if getFileSize(ico.path) > 5 * 1024 * 1024:
        return ""

    except OSError:
      discard

  try:
    var iconImage = IconImage(ico.path, (ico.size, ico.size))
    if iconImage.size != (ico.size, ico.size):
      let image = Image(iconImage)
      image.rescale((ico.size, ico.size), wImageQualityHigh)
      iconImage = IconImage(image)

    iconImage.toBmp()
    return iconImage.save()

  except CatchableError:
    return ""

proc fromShell(ico: wIco): string =
  # get icon from shell only
  # return iconimage data or ""
  var
    sfi: SHFILEINFO
    iml: ptr IImageList
    hIcon: HICON
    kind = SHIL_LARGE

  if ico.size >= 48:
    kind = SHIL_EXTRALARGE

  if SHGetFileInfo(ico.path, FILE_ATTRIBUTE_NORMAL, sfi, sizeof(sfi), SHGFI_SYSICONINDEX) != 0:
    if SHGetImageList(kind, &IID_IImageList, &iml) == S_OK:
      defer: iml.Release()

      if iml.GetIcon(sfi.iIcon, ILD_TRANSPARENT, &hIcon) == S_OK:
        try:
          var icon = Icon(hIcon, copy=false)
          defer: icon.delete()

          # copy 1st
          var iconImage = IconImage(icon)

          if iconImage.size != (ico.size, ico.size):
            # copy 2nd
            var image = Image(iconImage)
            image.rescale((ico.size, ico.size), quality=wImageQualityHigh)

            # copy 3rd
            iconImage = IconImage(image)

          # after image convertion, it should be bmp
          assert iconImage.isBmp()
          return iconImage.save()

        except CatchableError:
          return ""

proc fromAny(ico: wIco): string =
  if not ico.shellOnly:
    result = fromIconImage(ico)
    if result != "":
      # echo "from iconimage"
      return result

  result = fromShell(ico)
  if result != "":
    # echo "from shell"
    return result

  return ""

proc getData*(cache: var wIcoCache, ico: wIco): string =
  result = cache.table.getOrDefault(ico)
  if result != "":
    # echo "from cache"
    return result

  result = fromAny(ico)

  # save the cache (no need to cache it if ico.path is raw data)
  if result != "" and ico.path.len < result.len:
    cache.table[ico] = result

proc clear*(cache: var wIcoCache) {.inline.} =
  cache.table.clear()

proc len*(cache: wIcoCache): int {.inline.} =
  return cache.table.len

proc getBitmap*(cache: var wIcoCache, ico: wIco): wBitmap =
  let data = cache.getData(ico)
  if data != "":
    return Bitmap(IconImage(data))

proc save*(cache: wIcoCache): string =
  let binary = pack(cache.table)
  var hash = newString(CACHE_HASH.digestSize)
  count[CACHE_HASH](binary, hash.toOpenArray(0, CACHE_HASH.digestSize-1))

  try:
    return hash & compress(binary, BestCompression)
  except CatchableError:
    return ""

proc load*(cache: var wIcoCache, binary: string) =
  try:
    let hash1 = binary[0..CACHE_HASH.digestSize-1]
    let compressed = binary[CACHE_HASH.digestSize..^1]
    var data = uncompress(compressed)

    var hash2 = newString(CACHE_HASH.digestSize)
    count[CACHE_HASH](data, hash2.toOpenArray(0, CACHE_HASH.digestSize-1))
    if hash1 != hash2:
      raise newException(ValueError, "hash mismatch")

    cache.table = unpack(data, type cache.table)

  except CatchableError, Defect:
    cache.table.clear()

when isMainModule:
  import sugar
  const imageOk = staticRead("../resources/ok.ico")

  var cache = initIcoCache()
  dump repr cache.getBitmap(IcoPath("shell32.dll,10", 24))
  dump repr cache.getBitmap(IcoShell("c:\\", 24))
  dump repr cache.getBitmap(IcoData(imageOk, 16))
  dump cache.table.len

  var binary = cache.save()
  dump binary.len

  var cache2: wIcoCache
  cache2.load(binary)
  dump repr cache.getBitmap(IcoPath("shell32.dll,10", 24))
