#====================================================================
#
#       InstantMenu - A Portable Launcher Tool for Windows
#              Copyright (c) Chen Kai-Hung, Ward
#
#====================================================================

import std/[os, strutils]
import pkg/winim/lean
import pkg/wNim/[wApp, wFrame, wPanel, wStaticBox, wStaticText, wButton, wCheckBox,
  wRadioButton, wCheckComboBox, wUtils, wMenu, wTextCtrl, wDirDialog]
import wCompactTextCtrl, locale

type
  SearchOption* {.pure.} = enum
    SearchFile
    SearchDir
    SearchRec
    IncludeHiddenFile
    IncludeHiddenDir
    Flat

  SearchParam* = object
    dirs*: seq[string]
    pattern*: string
    design*: string
    option*: set[SearchOption]

proc searchDialog*(owner: wFrame): SearchParam =
  var ret: SearchParam

  let dialog = Frame(owner=owner, title = !Import)
  let panel = Panel(dialog)
  let base = Button(panel, label="XXXXXX")
  base.fit()
  base.hide()
  dialog.clientSize = (base.size.width * 7, wDefault)

  let staticboxTarget = StaticBox(panel, label = !Target_Settings)
  let labelDir = StaticText(panel, label = !Location & ":")
  let labelName = StaticText(panel, label = !Pattern & ":")
  let labelKind = StaticText(panel, label = !Type & ":")
  let textCtrlDir1 = CompactTextCtrl(panel, style=wBorderSunken)
  let textCtrlDir2 = CompactTextCtrl(panel, style=wBorderSunken)
  let textCtrlDir3 = CompactTextCtrl(panel, style=wBorderSunken)
  let textCtrlDir4 = CompactTextCtrl(panel, style=wBorderSunken)
  let textCtrlDir5 = CompactTextCtrl(panel, style=wBorderSunken)
  let buddy1 = StaticText(panel, label="")
  let buddy2 = StaticText(panel, label="")
  let buddy3 = StaticText(panel, label="")
  let buddy4 = StaticText(panel, label="")
  let buddy5 = StaticText(panel, label="")
  let buttonDir1 = Button(buddy1, label="…")
  let buttonDir2 = Button(buddy2, label="…")
  let buttonDir3 = Button(buddy3, label="…")
  let buttonDir4 = Button(buddy4, label="…")
  let buttonDir5 = Button(buddy5, label="…")
  let buttonOp1 = Button(buddy1, label="+")
  let buttonOp2 = Button(buddy2, label="-")
  let buttonOp3 = Button(buddy3, label="-")
  let buttonOp4 = Button(buddy4, label="-")
  let buttonOp5 = Button(buddy5, label="-")
  let textCtrlName = CompactTextCtrl(panel, style=wBorderSunken)
  let buttonName = Button(panel, label="∨")
  let checkComboKind = CheckCombobox(panel, style=wCcEndEllipsis or wCcNormalColor)
  let staticboxDesign =StaticBox(panel, label = !Node_Design)
  let labelDesign = StaticText(panel, label = !Naming & ":")
  let labelCreation = StaticText(panel, label= !Structure & ":")
  let textCtrlDesign = CompactTextCtrl(panel, style=wBorderSunken)
  let buttonDesign = Button(panel, label="∨")
  let radioTree = RadioButton(panel, label= !Tree)
  let radioFlat = RadioButton(panel, label = !Flat)
  let buttonImport = Button(panel, label = !Import)
  let buttonCancel = Button(panel, label = !Cancel)
  let resizable = Resizable()

  let width = wGetSystemMetric(wSysVScrollX)
  textCtrlDir1.setBuddy(buddy1, wRight, width * 2)
  textCtrlDir2.setBuddy(buddy2, wRight, width * 2)
  textCtrlDir3.setBuddy(buddy3, wRight, width * 2)
  textCtrlDir4.setBuddy(buddy4, wRight, width * 2)
  textCtrlDir5.setBuddy(buddy5, wRight, width * 2)
  textCtrlName.setBuddy(buttonName, wRight, width)
  textCtrlDesign.setBuddy(buttonDesign, wRight, width)

  textCtrlDir1.value = getCurrentDir()
  textCtrlName.value = "*.exe"
  textCtrlDesign.value = "%DisplayName% %FileVersion%"
  checkComboKind.append([!File, !Folder, !Include_Subfolders,
    !Include_Hidden_Files, !Include_Hidden_Folders])
  checkComboKind.select(ord SearchFile)
  checkComboKind.select(ord SearchRec)
  radioTree.click()
  buttonImport.setDefault()

  textCtrlDir2.hide()
  textCtrlDir3.hide()
  textCtrlDir4.hide()
  textCtrlDir5.hide()
  buddy2.hide()
  buddy3.hide()
  buddy4.hide()
  buddy5.hide()

  let menuName = Menu()
  menuName.append(1, !Executable_File & "\t(*.exe)")
  menuName.append(2, !Shortcut & "\t(*.lnk)")
  menuName.append(3, !Help_File & "\t(*.chm; *.hlp)")
  menuName.append(4, !Plain_Text_File & "\t(*.txt)")
  menuName.append(5, !Image_File & "\t(*.bmp; *.png; *.jpg; *.gif)")
  menuName.append(6, !Document_File & "\t(*.doc; *.docx; *.rtf)")
  menuName.append(7, !Web_Page_File & "\t(*.htm; *.html)")
  menuName.append(8, !All_Files & "\t(*.*)")
  menuName.appendSeparator()
  menuName.append(0, !"Use_*_and_?_wildcards;_separate_filenames_with_;").disable

  buttonName.wEvent_Button do ():
    let size = textCtrlName.size
    let pos = int textCtrlName.popupMenu(menuName, (size.width, size.height), flag=wPopMenuReturnId or TPM_RIGHTALIGN)
    if pos > 0:
      let text = menuName[pos - 1].text
      let (lt, rt) = (text.rfind('('), text.rfind(')'))
      if lt > 0 and rt > 0:
        textCtrlName.value = text[(lt + 1) .. (rt - 1)]

  let menuDesign = Menu()
  menuDesign.append(1, !File_Name & "\t%FileName%")
  menuDesign.append(2, !File_Extension & "\t%FileExt%")
  menuDesign.append(3, !Display_Name & "\t%DisplayName%")
  menuDesign.append(4, !File_Version & "\t%FileVersion%")
  menuDesign.append(5, !Product_Name & "\t%ProductName%")

  buttonDesign.wEvent_Button do ():
    let size = textCtrlDesign.size
    let pos = int textCtrlDesign.popupMenu(menuDesign, (size.width, size.height), flag=wPopMenuReturnId or TPM_RIGHTALIGN)
    if pos > 0:
      let text = menuDesign[pos - 1].text
      let lt = text.rfind('\t')
      textCtrlDesign.value = strip(textCtrlDesign.value & " " & text.substr(lt + 1))

  buddy1.autolayout """
    H: |[buttonDir1][buttonOp1(buttonDir1)]|
    V: |[buttonDir1,buttonOp1]|
  """
  buddy2.autolayout """
    H: |[buttonDir2][buttonOp2(buttonDir2)]|
    V: |[buttonDir2,buttonOp2]|
  """
  buddy3.autolayout """
    H: |[buttonDir3][buttonOp3(buttonDir3)]|
    V: |[buttonDir3,buttonOp3]|
  """
  buddy4.autolayout """
    H: |[buttonDir4][buttonOp4(buttonDir4)]|
    V: |[buttonDir4,buttonOp4]|
  """
  buddy5.autolayout """
    H: |[buttonDir5][buttonOp5(buttonDir5)]|
    V: |[buttonDir5,buttonOp5]|
  """

  proc layout() =
    var maxLabelWidth {.threadvar.}: int

    once:
      for label in [labelDir, labelName, labelKind, labelDesign, labelCreation]:
        label.fit()
        maxLabelWidth = max(maxLabelWidth, label.bestSize.width)

      for radio in [radioFlat, radioTree]:
        radio.fit()

    var n = 0
    for ctrl in [textCtrlDir1, textCtrlDir2, textCtrlDir3, textCtrlDir4, textCtrlDir5]:
      if ctrl.isShown:
        n.inc

    panel.autorelayout """
      C: base.height = base.bestHeight
      spacing: base.height / 2 - 5

      batch: labels = labelDir, labelName, labelKind, labelDesign, labelCreation
      H:[labels(`maxLabelWidth`)]

      H:|-[staticboxTarget,staticboxDesign]-|
      V:|-[staticboxTarget]-[staticboxDesign]-[buttonImport,buttonCancel]-[resizable]-|
      H: [buttonImport]-[buttonCancel]-|

      C: labelDir.centerY = textCtrlDir1.centerY
      C: labelName.centerY = textCtrlName.centerY
      C: labelKind.centerY = checkComboKind.centerY
      C: labelDesign.centerY = textCtrlDesign.centerY
      C: labelCreation.centerY = radioTree.centerY

      outer: staticboxTarget
      H: |-[labelDir,labelName,labelKind]-[textCtrlDir1..5,textCtrlName,checkComboKind]-|
      V: |-[textCtrlDir1(base)]-((`n`-1) * base.height + (base.height / 2 - 5))-
        [textCtrlName(base)]-[checkComboKind(base)]-|

      HV: [textCtrlDir2..5(textCtrlDir1)]
      V: [textCtrlDir1][textCtrlDir2][textCtrlDir3][textCtrlDir4][textCtrlDir5]

      outer: staticboxDesign
      H: |-[labelDesign,labelCreation]-[textCtrlDesign]-|
      H: |-[labelDesign,labelCreation]-[radioTree]-[radioFlat]-|
      V: |-[textCtrlDesign(base)]-[radioTree,radioFlat(base)]-|
    """

    var minClientWidth{.global.}: int
    if minClientWidth == 0:
      minClientWidth = panel.layoutSize.width

    let h = panel.layoutSize.height - resizable.layoutSize.height - 3
    dialog.minClientSize = (minClientWidth, h)
    dialog.maxClientSize = (wDefault, h)

  proc selectDir(ctrl: wTextCtrl) =
    let newDir = DirDialog(dialog, message = !Choose_Folder,
      defaultPath=ctrl.value, style=wDdDirMustExist).display()

    if newDir.len != 0:
      ctrl.value = newDir

  proc minusTextCtrl() =
    for (ctrl, buddy) in [
      (textCtrlDir5, buddy5),
      (textCtrlDir4, buddy4),
      (textCtrlDir3, buddy3),
      (textCtrlDir2, buddy2),
    ]:
      if ctrl.isShown:
        ctrl.hide()
        buddy.hide()
        ctrl.changeValue("")
        layout()
        textCtrlName.sendMessage(wEvent_Size)
        textCtrlDesign.sendMessage(wEvent_Size)
        buttonOp1.enable()
        return

  proc plusTextCtrl() =
    for (ctrl, buddy) in [
      (textCtrlDir2, buddy2),
      (textCtrlDir3, buddy3),
      (textCtrlDir4, buddy4),
      (textCtrlDir5, buddy5),
    ]:
      if not ctrl.isShown:
        ctrl.show()
        buddy.show()
        layout()
        textCtrlName.sendMessage(wEvent_Size)
        textCtrlDesign.sendMessage(wEvent_Size)
        if ctrl == textCtrlDir5:
          buttonOp1.disable()
        return

  buttonDir1.wEvent_Button do (): selectDir(textCtrlDir1)
  buttonDir2.wEvent_Button do (): selectDir(textCtrlDir2)
  buttonDir3.wEvent_Button do (): selectDir(textCtrlDir3)
  buttonDir4.wEvent_Button do (): selectDir(textCtrlDir4)
  buttonDir5.wEvent_Button do (): selectDir(textCtrlDir5)

  buttonOp1.wEvent_Button do (): plusTextCtrl()
  buttonOp2.wEvent_Button do (): minusTextCtrl()
  buttonOp3.wEvent_Button do (): minusTextCtrl()
  buttonOp4.wEvent_Button do (): minusTextCtrl()
  buttonOp5.wEvent_Button do (): minusTextCtrl()

  proc checkReady() =
    var ready = true
    var values: seq[string]
    for ctrl in [textCtrlDir1, textCtrlDir2, textCtrlDir3, textCtrlDir4, textCtrlDir5]:
      let value = ctrl.value
      if value != "": values.add value
    if values.len == 0: ready = false
    if textCtrlName.value.len == 0: ready = false
    if not checkComboKind.isSelected(ord SearchFile) and
      not checkComboKind.isSelected(ord SearchDir): ready = false
    if textCtrlDesign.value.len == 0: ready = false

    buttonImport.enable(ready)

  textCtrlDir1.wEvent_Text do (): checkReady()
  textCtrlName.wEvent_Text do (): checkReady()
  textCtrlDesign.wEvent_Text do (): checkReady()
  checkComboKind.wEvent_CheckComboBox do (): checkReady()

  panel.wEvent_Size do ():
    layout()

  dialog.wEvent_Close do ():
    dialog.endModal()

  buttonCancel.wEvent_Button do ():
    dialog.close()

  buttonImport.wEvent_Button do ():
    ret.dirs.setLen(0)
    for ctrl in [textCtrlDir1, textCtrlDir2, textCtrlDir3, textCtrlDir4, textCtrlDir5]:
      let value = ctrl.value
      if value != "": ret.dirs.add value

    ret.pattern = textCtrlName.value
    ret.design = textCtrlDesign.value

    for so in SearchFile..IncludeHiddenDir:
      if checkComboKind.isSelected(ord so):
        ret.option.incl so

    if radioFlat.value:
      ret.option.incl Flat

    dialog.close()

  layout()
  dialog.center()
  dialog.showModal()
  dialog.delete()
  return ret

when isMainModule:
  import pkg/wNim/wMessageDialog

  const dir = currentSourcePath().parentDir()
  staticLoadLang(staticRead(dir / "../bin/InstantMenu.lang"))
  staticInitLang("正體中文")

  App(wSystemDpiAware)

  if MessageDialog(message="English version?", style=wYesNo).display() == wIdYes:
    initLang("English")
  else:
    initLang("正體中文")

  echo searchDialog(nil)
