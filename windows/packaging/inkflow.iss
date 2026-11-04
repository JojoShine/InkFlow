#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildNumber
  #error BuildNumber is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
[Setup]
AppId={{949B7141-39F5-491E-A591-A11B8D958050}
AppName=InkFlow
AppVersion={#AppVersion}
AppVerName=InkFlow {#AppVersion}
AppPublisher=JojoShine
VersionInfoVersion={#AppVersion}.{#BuildNumber}
DefaultDirName={localappdata}\Programs\InkFlow
DefaultGroupName=InkFlow
UninstallDisplayIcon={app}\inkflow.exe
OutputDir={#OutputDir}
OutputBaseFilename=InkFlow-{#AppVersion}+{#BuildNumber}-windows-x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupMutex=InkFlowSetup
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\InkFlow"; Filename: "{app}\inkflow.exe"
Name: "{autodesktop}\InkFlow"; Filename: "{app}\inkflow.exe"; Tasks: desktopicon
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\inkflow.exe"; Description: "Launch InkFlow"; Flags: nowait postinstall skipifsilent
