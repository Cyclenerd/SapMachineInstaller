; sapmachine.nsi
; Author: Nils Knieling - https://github.com/Cyclenerd
;
; Windows Installer for SapMachine (OpenJDK release maintained and supported by SAP)
;
;--------------------------------------------------------------------------------------------------

; The name of the installer
Name "SapMachine ${FULLVERSION}"

; Remove the text 'Nullsoft Install System vX.XX' from the installer window 
BrandingText "Installer by Nils Knieling"

; The default installation directory
InstallDir "$PROGRAMFILES64\SapMachine${VERSION}"

; Registry key to check for directory (so if you install again, it will 
; overwrite the old one automatically)
InstallDirRegKey HKLM "SOFTWARE\SapMachine${VERSION}" "Install_Dir"

; Request application privileges for Windows
RequestExecutionLevel admin


;--------------------------------------------------------------------------------------------------

; Includes
!include LogicLib.nsh
!include x64.nsh

; Pages
Page components
Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles


;--------------------------------------------------------------------------------------------------

; Check CPU architecture
Function .onInit
  ${If} ${IsNativeAMD64}
    DetailPrint 'AMD64 64-bit Windows'
  ${Else}
    MessageBox MB_ICONSTOP "Unsupported CPU architecture!"
    Abort
  ${EndIf}
FunctionEnd


;--------------------------------------------------------------------------------------------------
; Path functions
; Based on:
;    https://raw.githubusercontent.com/ethereum/go-ethereum/master/build/nsis.pathupdate.nsh
;    https://www.smartmontools.org/browser/trunk/smartmontools/os_win32/installer.nsi

; see https://support.microsoft.com/en-us/kb/104011
!define Environ 'HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"'
; HKEY_LOCAL_MACHINE = 0x80000002

; AddToPath - Appends dir to PATH
;   (does not work on Win9x/ME)
;
; Usage:
;   Push "dir"
;   Call AddToPath
Function AddToPath
  Exch $0
  Push $1
  Push $2
  Push $3
  Push $4

  ; NSIS ReadRegStr returns empty string on string overflow
  ; Native calls are used here to check actual length of PATH
  ; $4 = RegOpenKey(HKEY_LOCAL_MACHINE, "SYSTEM\CurrentControlSet\Control\Session Manager\Environment", &$3)
  System::Call "advapi32::RegOpenKey(i 0x80000002, t'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', *i.r3) i.r4"
  IntCmp $4 0 0 done done

  ; $4 = RegQueryValueEx($3, "PATH", (DWORD*)0, (DWORD*)0, &$1, ($2=NSIS_MAX_STRLEN, &$2))
  ; RegCloseKey($3)
  System::Call "advapi32::RegQueryValueEx(i $3, t'PATH', i 0, i 0, t.r1, *i ${NSIS_MAX_STRLEN} r2) i.r4"
  System::Call "advapi32::RegCloseKey(i $3)"

  IntCmp $4 234 0 +4 +4 ; $4 == ERROR_MORE_DATA
    DetailPrint "AddToPath: original length $2 > ${NSIS_MAX_STRLEN}"
    MessageBox MB_OK "PATH not updated, original length $2 > ${NSIS_MAX_STRLEN}"
    Goto done

  IntCmp $4 0 +5 ; $4 != NO_ERROR
    IntCmp $4 2 +3 ; $4 != ERROR_FILE_NOT_FOUND
      DetailPrint "AddToPath: unexpected error code $4"
      Goto done
    StrCpy $1 ""

  ; Check if already in PATH
  Push "$1;"
  Push "$0;"
  Call StrStr
  Pop $2
  StrCmp $2 "" 0 done
  Push "$1;"
  Push "$0\;"
  Call StrStr
  Pop $2
  StrCmp $2 "" 0 done

  ; Prevent NSIS string overflow
  StrLen $2 $0
  StrLen $3 $1
  IntOp $2 $2 + $3
  IntOp $2 $2 + 2 ; $2 = strlen(dir) + strlen(PATH) + sizeof(";")
  IntCmp $2 ${NSIS_MAX_STRLEN} +4 +4 0
    DetailPrint "AddToPath: new length $2 > ${NSIS_MAX_STRLEN}"
    MessageBox MB_OK "PATH not updated, new length $2 > ${NSIS_MAX_STRLEN}."
    Goto done

  ; Append dir to PATH
  DetailPrint "Add to PATH: $0"
  StrCpy $2 $1 1 -1
  StrCmp $2 ";" 0 +2
    StrCpy $1 $1 -1 ; remove trailing ';'
  StrCmp $1 "" +2   ; no leading ';'
    StrCpy $0 "$1;$0"
  
  WriteRegExpandStr ${Environ} "PATH" $0

done:
  Pop $4
  Pop $3
  Pop $2
  Pop $1
  Pop $0
FunctionEnd

; RemoveFromPath - Removes dir from PATH
;
; Usage:
;   Push "dir"
;   Call RemoveFromPath
Function un.RemoveFromPath
  Exch $0
  Push $1
  Push $2
  Push $3
  Push $4
  Push $5
  Push $6

  ; NSIS ReadRegStr returns empty string on string overflow
  ; Native calls are used here to check actual length of PATH
  ; $4 = RegOpenKey(HKEY_LOCAL_MACHINE, "SYSTEM\CurrentControlSet\Control\Session Manager\Environment", &$3)
  System::Call "advapi32::RegOpenKey(i 0x80000002, t'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', *i.r3) i.r4"
  IntCmp $4 0 0 done done

  ; $4 = RegQueryValueEx($3, "PATH", (DWORD*)0, (DWORD*)0, &$1, ($2=NSIS_MAX_STRLEN, &$2))
  ; RegCloseKey($3)
  System::Call "advapi32::RegQueryValueEx(i $3, t'PATH', i 0, i 0, t.r1, *i ${NSIS_MAX_STRLEN} r2) i.r4"
  System::Call "advapi32::RegCloseKey(i $3)"

  IntCmp $4 234 0 +4 +4 ; $4 == ERROR_MORE_DATA
    DetailPrint "RemoveFromPath: original length $2 > ${NSIS_MAX_STRLEN}"
    MessageBox MB_OK "PATH not updated, original length $2 > ${NSIS_MAX_STRLEN}"
    Goto done

  IntCmp $4 0 +5 ; $4 != NO_ERROR
    IntCmp $4 2 +3 ; $4 != ERROR_FILE_NOT_FOUND
      DetailPrint "RemoveFromPath: unexpected error code $4"
      Goto done
    StrCpy $1 ""

  ; length < ${NSIS_MAX_STRLEN} -> ReadRegStr can be used
  ReadRegStr $1 ${Environ} "PATH"
  StrCpy $5 $1 1 -1
  StrCmp $5 ";" +2
  StrCpy $1 "$1;" ; ensure trailing ';'
  Push $1
  Push "$0;"
  Call un.StrStr
  Pop $2 ; pos of our dir
  StrCmp $2 "" done

  DetailPrint "Remove from PATH: $0"
  StrLen $3 "$0;"
  StrLen $4 $2
  StrCpy $5 $1 -$4 ; $5 is now the part before the path to remove
  StrCpy $6 $2 "" $3 ; $6 is now the part after the path to remove
  StrCpy $3 "$5$6"
  StrCpy $5 $3 1 -1
  StrCmp $5 ";" 0 +2
    StrCpy $3 $3 -1 ; remove trailing ';'
  WriteRegExpandStr ${Environ} "PATH" $3

done:
  Pop $6
  Pop $5
  Pop $4
  Pop $3
  Pop $2
  Pop $1
  Pop $0
FunctionEnd

; StrStr - find substring in a string
;
; Usage:
;   Push "this is some string"
;   Push "some"
;   Call StrStr
;   Pop $0 ; "some string"

!macro StrStr un
Function ${un}StrStr
  Exch $R1 ; $R1=substring, stack=[old$R1,string,...]
  Exch     ;                stack=[string,old$R1,...]
  Exch $R2 ; $R2=string,    stack=[old$R2,old$R1,...]
  Push $R3
  Push $R4
  Push $R5
  StrLen $R3 $R1
  StrCpy $R4 0
  ; $R1=substring, $R2=string, $R3=strlen(substring)
  ; $R4=count, $R5=tmp
  ${Do}
    StrCpy $R5 $R2 $R3 $R4
    ${IfThen} $R5 == $R1 ${|} ${ExitDo} ${|}
    ${IfThen} $R5 == ""  ${|} ${ExitDo} ${|}
    IntOp $R4 $R4 + 1
  ${Loop}
  StrCpy $R1 $R2 "" $R4
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Exch $R1 ; $R1=old$R1, stack=[result,...]
FunctionEnd
!macroend
!insertmacro StrStr ""
!insertmacro StrStr "un."


;--------------------------------------------------------------------------------------------------

; Copy stuff to install
Section "Install SapMachine ${VERSION} (required)" COPY_SECTION
  SectionIn RO
  ; Set output path to the installation directory.
  SetOutPath $INSTDIR
  ; Put file there
  File /nonfatal /a /r "sapmachine\" #note back slash at the end
SectionEnd

; Create uninstaller
Section "Uninstaller" UNINST_SECTION
  SectionIn RO
  ; Write the installation path into the registry
  WriteRegStr HKLM "Software\SapMachine${VERSION}" "Install_Dir" "$INSTDIR"
  ; Write the uninstall keys for Windows
  ; https://nsis.sourceforge.io/Add_uninstall_information_to_Add/Remove_Programs
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SapMachine${VERSION}" "DisplayName" "SapMachine ${FULLVERSION} (SAP version of OpenJDK)"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SapMachine${VERSION}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SapMachine${VERSION}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SapMachine${VERSION}" "NoRepair" 1
  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; Update PATH variable
Section "Add to PATH variable (recommended)" PATH_SECTION
  SectionIn 1
  Push "$INSTDIR\bin"
  Call AddToPath
  DetailPrint "PATH environment variable changed"
SectionEnd

; Set JAVA_HOME variable
Section "Set JAVA_HOME variable (recommended)" HOME_SECTION
  SectionIn 1
  WriteRegStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "JAVA_HOME" "$INSTDIR"
  DetailPrint "JAVA_HOME environment variable set"
SectionEnd


;--------------------------------------------------------------------------------------------------

; Uninstaller
Section "Uninstall"
  ; Remove registry keys
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SapMachine${VERSION}"
  DeleteRegKey HKLM "Software\SapMachine${VERSION}"

  ; Remove JAVA_HOME
  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "JAVA_HOME" 
  ${If} $0 == "$INSTDIR"
    DeleteRegValue HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "JAVA_HOME"
    DetailPrint "JAVA_HOME environment variable deleted"
  ${EndIf}
  
  ; Remove install dir from PATH
  Push "$INSTDIR\bin"
  Call un.RemoveFromPath
  
  ; Remove directory
  RMDir /r /REBOOTOK "$INSTDIR"
SectionEnd
