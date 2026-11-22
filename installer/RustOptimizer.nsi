; Rust Optimizer installer (NSIS 3.x, Unicode).
; Per-user install: no UAC prompt, no admin rights, files go to
; %LOCALAPPDATA%\Programs\RustOptimizer and a desktop shortcut is created.
;
; Build (CI passes the variables explicitly):
;   makensis /DAPP_VERSION=8.2.1 /DAPP_EXE=..\build\Release\RustOptimizer.exe ^
;            /DOUT_EXE=..\build\RustOptimizer-Setup-8.2.1.exe installer\RustOptimizer.nsi

Unicode true
ManifestDPIAware true

; CI passes /DRO_CI_DEFINES and writes installer\defines.nsh with the absolute
; build paths (forward slashes); makensis mangles Windows paths given via /D.
!ifdef RO_CI_DEFINES
  !include "defines.nsh"
!endif

!ifndef APP_VERSION
  !define APP_VERSION "8.2.2"
!endif
!ifndef APP_EXE
  !define APP_EXE "..\build\Release\RustOptimizer.exe"
!endif
!ifndef OUT_EXE
  !define OUT_EXE "..\build\RustOptimizer-Setup-${APP_VERSION}.exe"
!endif

!define APP_NAME "Rust Optimizer"
!define APP_PUBLISHER "Rust Optimizer"
!define APP_ID "RustOptimizer"
!define APP_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
!define INSTALL_DIR "$LOCALAPPDATA\Programs\${APP_ID}"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "${OUT_EXE}"
InstallDir "${INSTALL_DIR}"
InstallDirRegKey HKCU "Software\${APP_ID}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APP_NAME} ${APP_VERSION} вЂ” Р±РµР·РѕРїР°СЃРЅР°СЏ РѕРїС‚РёРјРёР·Р°С†РёСЏ Р±РµР· Р±Р°РЅРѕРІ"

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!define MUI_ICON "..\assets\rust-optimizer.ico"
!define MUI_UNICON "..\assets\rust-optimizer.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\RustOptimizer.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Р—Р°РїСѓСЃС‚РёС‚СЊ Rust Optimizer"
!define MUI_FINISHPAGE_LINK "GitHub РїСЂРѕРµРєС‚Р°"
!define MUI_FINISHPAGE_LINK_LOCATION "https://github.com/proot9078-ux/Rust-Optimizer"

!define MUI_WELCOMEPAGE_TITLE "РЈСЃС‚Р°РЅРѕРІРєР° ${APP_NAME} ${APP_VERSION}"
!define MUI_WELCOMEPAGE_TEXT "РћРїС‚РёРјРёР·Р°С‚РѕСЂ RUST Рё FORTNITE: РєРѕРЅС„РёРіРё, РєСЌС€Рё, РїР°СЂР°РјРµС‚СЂС‹ Р·Р°РїСѓСЃРєР° Рё СЃРёСЃС‚РµРјРЅС‹Рµ С‚РІРёРєРё.$\r$\n$\r$\nР’СЃС‘ РѕР±СЂР°С‚РёРјРѕ: РїРµСЂРµРґ РєР°Р¶РґС‹Рј РёР·РјРµРЅРµРЅРёРµРј СЃРѕР·РґР°С‘С‚СЃСЏ СЂРµР·РµСЂРІРЅР°СЏ РєРѕРїРёСЏ. РЈСЃС‚Р°РЅРѕРІРєР° РЅРµ С‚СЂРµР±СѓРµС‚ РїСЂР°РІ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР°."
!define MUI_DIRECTORYPAGE_TEXT_TOP "РџСЂРѕРіСЂР°РјРјР° Р±СѓРґРµС‚ СѓСЃС‚Р°РЅРѕРІР»РµРЅР° РІ РїР°РїРєСѓ РЅРёР¶Рµ. РЇСЂР»С‹Рє РїРѕСЏРІРёС‚СЃСЏ РЅР° СЂР°Р±РѕС‡РµРј СЃС‚РѕР»Рµ Рё РІ РјРµРЅСЋ В«РџСѓСЃРєВ»."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------- helpers
!macro KillRunning
  DetailPrint "Р—Р°РєСЂС‹РІР°СЋ Р·Р°РїСѓС‰РµРЅРЅС‹Р№ РѕРїС‚РёРјРёР·Р°С‚РѕСЂвЂ¦"
  nsExec::Exec 'taskkill /IM RustOptimizer.exe /F'
  Pop $0
!macroend

; Remove files from a previous install before copying new ones, but keep the
; user's settings and backups (%LOCALAPPDATA%\RustOptimizer is separate).
!macro CleanOldInstall
  ${If} ${FileExists} "$INSTDIR\RustOptimizer.exe"
    Delete "$INSTDIR\RustOptimizer.exe"
  ${EndIf}
!macroend

Function .onInit
  ; Refuse to run from a network path silently? No: keep it simple and robust.
  SetShellVarContext current
FunctionEnd

Section "Rust Optimizer" SecMain
  SectionIn RO
  !insertmacro KillRunning

  SetOutPath "$INSTDIR"
  !insertmacro CleanOldInstall

  File "/oname=RustOptimizer.exe" "${APP_EXE}"
  File "/oname=LICENSE.txt" "..\LICENSE"
  File "/oname=README.md" "..\README.md"
  File "/oname=rust-optimizer.ico" "..\assets\rust-optimizer.ico"

  ; Desktop + Start menu shortcuts.
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\RustOptimizer.exe" "" \
                 "$INSTDIR\rust-optimizer.ico" 0 SW_SHOWNORMAL "" "РћРїС‚РёРјРёР·Р°С‚РѕСЂ RUST Рё FORTNITE"
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\RustOptimizer.exe" "" \
                 "$INSTDIR\rust-optimizer.ico" 0 SW_SHOWNORMAL "" "РћРїС‚РёРјРёР·Р°С‚РѕСЂ RUST Рё FORTNITE"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\РЈРґР°Р»РёС‚СЊ ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"

  ; Uninstaller + Add/Remove Programs entry.
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\${APP_ID}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${APP_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${APP_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${APP_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "${APP_KEY}" "DisplayIcon" "$INSTDIR\rust-optimizer.ico"
  WriteRegStr HKCU "${APP_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${APP_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${APP_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${APP_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${APP_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  nsExec::Exec 'taskkill /IM RustOptimizer.exe /F'
  Pop $0

  Delete "$INSTDIR\RustOptimizer.exe"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\rust-optimizer.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\РЈРґР°Р»РёС‚СЊ ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  DeleteRegKey HKCU "${APP_KEY}"
  DeleteRegKey HKCU "Software\${APP_ID}"
SectionEnd
