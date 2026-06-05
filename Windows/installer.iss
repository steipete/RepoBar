#define AppName "RepoBar"
#define AppPublisher "RepoBar"
#define AppExeName "RepoBar.Windows.exe"
#define AppVersion GetEnv("REPOBAR_WINDOWS_VERSION")
#define SourceDir GetEnv("REPOBAR_WINDOWS_PUBLISH_DIR")

[Setup]
AppId={{8B67AB82-29DE-4FC5-9B21-72148BA12C72}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\RepoBar
DefaultGroupName=RepoBar
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputBaseFilename=RepoBar-Windows-{#AppVersion}
OutputDir=..\dist\windows
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start RepoBar when Windows starts"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\RepoBar"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\RepoBar"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "RepoBar"; ValueData: """{app}\{#AppExeName}"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch RepoBar"; Flags: nowait postinstall skipifsilent
