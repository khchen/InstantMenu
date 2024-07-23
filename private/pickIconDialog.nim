#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/[strformat, strutils]
import pkg/winim/[lean, inc/shellapi]
import pkg/wNim/[wApp, wFrame, wMenu, wPanel, wStaticText, wButton, wListCtrl,
  wComboBox, wWindowDC, wImageList, wFileDialog, wIcon, wUtils]
import locale
from envs import SHExtractIconsW

proc pickIconDialog*(owner: wWindow, initFile = "shell32.dll", initDir = ""): string =
  const iconFiles = ["accessibilitycpl.dll", "explorer.exe", "gameux.dll",
    "imageres.dll", "mmcndmgr.dll", "mmres.dll", "moricons.dll", "mstscax.dll",
    "netshell.dll", "networkmap.dll", "pifmgr.dll", "sensorscpl.dll",
    "setupapi.dll", "shell32.dll", "wmp.dll", "wmploc.dll", "wpdshext.dll"]

  let
    dialog = Frame(owner=owner, title = !Select_Icon, size=(440, 440),
      style=wCaption or wSystemMenu or wModalFrame or wResizeBorder)

    menu = Menu()
    panel = Panel(dialog)
    staticText = StaticText(panel, style=wBorderStatic or wAlignLeftNoWordWrap)
    select = Button(panel, label = !Browse)
    listCtrl = ListCtrl(panel, style=wLcIcon or wLcAutoArrange or
      wLcSingleSel or wBorderSunken)
    combo = ComboBox(panel, value="48 x 48",
      choices=["16 x 16", "24 x 24", "36 x 36", "48 x 48", "64 x 64"],
      style=wCbReadOnly)
    ok = Button(panel, label = !Ok)
    cancel = Button(panel, label = !Cancel)

  var
    imageList: wImageList
    currentFile = initFile
    ret: string

  proc pickAndClose(index: int) =
    if index != -1:
      ret = if listCtrl.getItemText(index).len == 0:
          currentFile
        else:
          fmt"{currentFile},{index}"

      dialog.close()

  proc showFilename() =
    var
      dc = WindowDC(staticText)
      buffer = +$currentFile
      text: string

    defer:
      delete dc

    if PathCompactPath(dc.handle, buffer, UINT staticText.size.width - 4):
      text = $buffer.nullTerminated()
    else:
      text = currentFile

    staticText.label = text
    staticText.setToolTip(if text != currentFile: currentFile else: "")

  proc showIcons() =
    let
      fields = combo.value.split('x')
      size: wSize = (parseInt(fields[0].strip()), parseInt(fields[1].strip()))

    listCtrl.setRedraw(false)
    defer:
      listCtrl.setRedraw(true)

    if imageList != nil: imageList.delete()
    listCtrl.clearAll()

    imageList = ImageList(size, mask=true)
    listCtrl.setImageList(imageList, wImageListNormal)
    listCtrl.setItemSpacing(size.width + 25, size.height + 25)

    var index = 0

    while true:
      var hIcon: HICON
      var id: cint

      if SHExtractIconsW(currentFile, index, cint size.width, cint size.height,
        &hIcon, &id, 1, 0) == 0 or hIcon == 0: break

      try:
        let icon = Icon(hIcon, copy=false)
        defer: icon.delete()

        imageList.add(icon)
        if id == 0 or id == -1:
          listCtrl.appendItem("", image=0)
        else:
          listCtrl.appendItem($index, image=index)
        index.inc

      except: break

  if wGetWinVersion() < 6.0:
    menu.append(1, !Browse & "...")
    menu.appendSeparator()

  for i, file in iconFiles:
    # MSDN: If this value is -1 and phiconLarge and phiconSmall are both NULL,
    # the function returns the total number of icons
    let n = ExtractIconEx(file, -1, nil, nil, 0)
    if n != 0:
      menu.append(i + 2, fmt"{file} ({n})")

  dialog.icon = Icon("shell32.dll,22")
  select.setDropdownMenu(menu)

  ok.setDefault()
  showIcons()

  proc layout() =
    panel.autolayout """
      spacing: 12
      H:|-[staticText]-[select(select.defaultWidth)]-|
      H:|-[listCtrl]-|
      H:|-[combo(combo.bestWidth)]->[ok(cancel)]-[cancel(cancel.bestWidth+48)]-|
      V:|-[staticText(staticText.defaultHeight)]-[listCtrl]-[combo(combo.bestHeight)]-|
      V:|-[select(staticText.height)]-[listCtrl]-[ok,cancel(combo.height)]-|
    """

    let n = ok.size.width + cancel.size.width + combo.size.width + 12 * 4
    dialog.minClientSize = (n, n)
    showFilename()

  proc browse() =
    var files = FileDialog(dialog, !Select_File,
      defaultDir=initDir, wildcard = !Icon_Files &
        "(*.ico;*.cur;*.dll;*.exe)|*.ico;*.cur;*.dll;*.exe",
      style=wFdOpen or wFdFileMustExist).display()

    if files.len == 1:
      currentFile = files[0]
      showFilename()
      showIcons()

  panel.wEvent_Size do (event: wEvent): layout()

  select.wEvent_Menu do (event: wEvent):
    var i = int event.id
    if i == 1:
      browse()

    else:
      i -= 2
      if i >= 0 and i < iconFiles.len:
        currentFile = iconFiles[i]
        showFilename()
        showIcons()

  dialog.wEvent_ComboBox do ():
    showIcons()

  select.wEvent_Button do ():
    if wGetWinVersion() >= 6.0:
      browse()
    else:
      select.showDropdownMenu()

  cancel.wEvent_Button do ():
    dialog.close()

  ok.wEvent_Button do ():
    let index = listCtrl.getNextItem(0, wListNextAll, wListStateSelected)
    pickAndClose(index)

  listCtrl.wEvent_CommandLeftDoubleClick do (event: wEvent):
    let index = listCtrl.hitTest(event.x, event.y)[0]
    pickAndClose(index)

  dialog.shortcut(wAccelNormal, wKey_Esc) do ():
    dialog.close()

  dialog.wEvent_Close do ():
    dialog.endModal()

  layout()
  dialog.center()
  dialog.showModal()
  dialog.delete()
  return ret

when isMainModule:
  staticLoadLang(staticRead("../InstantMenu.lang"))
  staticInitLang("正體中文")
  initLang("正體中文")

  App(wSystemDpiAware)
  echo pickIconDialog(nil)
