; Inno Setup-script til rTorrent Remote
; Byg med build.cmd (kompilerer programmet til build\ og laver installeren i dist\)

#define AppName      "rTorrent Remote"
#ifndef AppVersion
  #define AppVersion "1.0"   ; build.cmd sender versionen med via /DAppVersion
#endif
#define AppPublisher "tristan202"
#define AppURL       "https://github.com/tristan202/rtorrent_remote"
#define AppExe       "rtorrent_remote.exe"

[Setup]
AppId={{D7FA09DE-C41D-40E1-92DC-82DA2193C27A}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; programmet bruger denne mutex til "kun én instans", saa installeren kan se om det koerer
AppMutex=rTorrentRemote_SingleInstance_Mutex
CloseApplications=yes
OutputDir=dist
OutputBaseFilename=rTorrentRemote-{#AppVersion}-setup
SetupIconFile=rtorrent_remote.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "danish"; MessagesFile: "compiler:Languages\Danish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Indstillinger og servere i %APPDATA%\rTorrentRemote bevares ved afinstallation
