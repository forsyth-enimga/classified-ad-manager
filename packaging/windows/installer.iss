; Inno Setup script. Build with:  iscc packaging\windows\installer.iss
; (optional: /DBuildDir=C:\path\to\Release /DAppVersion=1.0.0)
; Requires: flutter build windows --release
#define AppName "Classified Ad Manager"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
; The CI passes the real folder with /DBuildDir=...; this default is for local builds.
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6F0B6B7A-3C1D-4D55-9B0E-5E5A0C1AD001}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=..\..\build\installer
OutputBaseFilename=ClassifiedAdManager-Setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
DisableProgramGroupPage=yes

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\classified_ad_manager.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\classified_ad_manager.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\classified_ad_manager.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
