; Inno Setup script for the Windows installer. Built by tool/release.ps1,
; which passes the version from pubspec.yaml:
;   ISCC.exe /DAppVersion=1.1.0 tool\windows\installer.iss
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "Amuse"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{7E0B3F1E-6C1A-4B52-9A3B-A0A5E0000001}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=lexdes
AppPublisherURL=https://amuse.lexdes.com
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\amuse.exe
OutputDir=..\..\build\installer
OutputBaseFilename=amuse-{#AppVersion}-windows-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\..\LICENSE

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\amuse.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\amuse.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\amuse.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
