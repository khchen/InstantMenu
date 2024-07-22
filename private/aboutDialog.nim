#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/strutils
import pkg/wNim/[wApp, wFrame, wPanel, wStaticText, wStaticLine,
  wStaticBitmap, wBitmap, wIconImage, wFont, wButton, wImage]
import locale

proc getVersionNumber*(): string =
  const nimble = staticRead("../InstantMenu.nimble")
  for line in nimble.splitLines:
    var pair = line.split('=', maxsplit=1)
    if pair[0].strip(chars=Whitespace+{'#'}) == "version":
      return pair[1].strip.replace("\"")

proc getRequires(): string =
  var list: seq[string]
  const nimble = staticRead("../InstantMenu.nimble")
  for line in nimble.splitLines:
    let line = strip(line)
    if line.startsWith "requires ":
      var pair = line.replace("requires ", "").split(">=", maxsplit=1)
      const del = Whitespace+{'"'}
      list.add pair[0].strip(chars=del) & " " & pair[1].strip(chars=del)

  return list.join(", ")

proc aboutDialog*(owner: wWindow) =
  let dialog = Frame(owner=owner, title = !About, style=wDefaultDialogStyle)
  let baseElement = Button(dialog, label="XXXXXX")
  baseElement.fit()
  baseElement.hide()

  let baseSize = baseElement.size
  let ratio = dialog.dpiScaleRatio
  dialog.size = (
    int(baseSize.width.float * 7 * ratio),
    int(baseSize.height.float * 11 * ratio)
  )

  dialog.dpiAutoScale:
    let
      imageSize = 64
      (font8, font12, font24) = (8.0, 12.0, 24.0)
      (okWidth, okHeight) = (100, 30)
      (s2, s5, s15, s25) = (2, 5, 15, 25)

  let image = Image(IconImage(",0", (128, 128)))
  image.rescale((imageSize, imageSize), wImageQualityHigh)
  let bitmap = Bitmap(image)

  let panel1 = Panel(dialog)
  let panel2 = Panel(dialog)
  panel1.backgroundColor = wWhite

  let line = StaticLine(dialog)
  let logo = StaticBitmap(panel1, bitmap=bitmap)
  let title = StaticText(panel1, label="InstanstMenu")
  title.font = Font(font24, faceName="Arial", weight=wFontWeightBold)
  title.foregroundColor = 0x202020
  title.fit()

  const number = getVersionNumber()
  let version = StaticText(panel1, label=number)
  version.font = Font(font12, faceName="Arial", weight=wFontWeightNormal)
  version.foregroundColor = wGrey
  version.fit()

  const requires = getRequires()
  let copyright = StaticText(panel2)
  copyright.label = """
    Copyright © Chen Kai-Hung, Ward.
    Powered by """.unindent() & requires
  copyright.font = Font(font8, weight=wFontWeightNormal)

  let ok = Button(panel2, label="OK")
  ok.setDefault()

  proc layout() =
    dialog.autoLayout """
      H: |[panel1,line,panel2]|
      V: |[panel1][line(`s2`)][panel2(panel1 * 1.3)]|
    """

    panel1.autoLayout """
      spacing: `s25`
      H: |-[title]->[logo]-|
      V: |-[logo,title]

      H: |-[version]
      V: |-[title]-`s5`-[version]
    """

    panel2.autoLayout """
      spacing: `s15`
      H: |-[copyright]-|
      H: [ok(`okWidth`)]-|
      V: |-[copyright]-[ok(`okHeight`)]-|
    """

  dialog.wEvent_Size do ():
    layout()

  dialog.wEvent_Close do ():
    dialog.endModal()

  ok.wEvent_Button do ():
    dialog.close()

  layout()
  dialog.center()
  dialog.showModal()
  dialog.delete()

when isMainModule:
  when defined(cpu64):
    {.link: "../resources/InstantMenu64.res".}
  else:
    {.link: "../resources/InstantMenu32.res".}

  staticLoadLang(staticRead("../InstantMenu.lang"))
  staticInitLang("正體中文")
  initLang("正體中文")

  App(wSystemDpiAware)
  aboutDialog(nil)
