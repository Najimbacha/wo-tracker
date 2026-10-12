; Windows installer for the work order tracker (Inno Setup 6, free).
; Built by scripts\setup-app.ps1 -Installer, which passes AppVersion and SourceDir.
; Installs per user (no admin needed). Updating = running a newer installer over it;
; the data lives in the user's app-data folder and is never touched by install,
; update or uninstall.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\app\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7C1E4A52-2B9D-4F0E-9A51-3D7B0C6E8F21}
AppName=WO Tracker
AppVersion={#AppVersion}
AppPublisher=Engr Najim Bacha
DefaultDirName={localappdata}\Programs\WO Tracker
DefaultGroupName=WO Tracker
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build
OutputBaseFilename=WO-Tracker-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\wo_tracker.exe
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\WO Tracker"; Filename: "{app}\wo_tracker.exe"
Name: "{autodesktop}\WO Tracker"; Filename: "{app}\wo_tracker.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\wo_tracker.exe"; Description: "{cm:LaunchProgram,WO Tracker}"; Flags: nowait postinstall skipifsilent
