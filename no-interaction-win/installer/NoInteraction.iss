; NoInteraction Windows installer.
; Packages the self-contained single-file build (dist\NoInteraction.exe, produced by
; ..\build.ps1) into a double-clickable setup .exe using Inno Setup.
;
; Build from no-interaction-win\ with:
;   .\build.ps1              (publishes + signs dist\NoInteraction.exe)
;   ISCC installer\NoInteraction.iss
; or just run .\build-installer.ps1, which does both steps.

#define MyAppName "NoInteraction"
#define MyAppVersion "1.10.0"
#define MyAppPublisher "NoInteraction"
#define MyAppExeName "NoInteraction.exe"
#define MyAppMutex "NoInteraction_SingleInstance_Mutex"

[Setup]
AppId={{58BDE7A6-084D-4A7F-9CE6-85B2F5A9340A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppSupportURL=https://github.com/sachin6174/no-interaction
; Per-user install under LocalAppData, matching app.manifest's asInvoker execution
; level and install.ps1's existing layout — no admin rights or UAC prompt needed,
; so a plain double-click is enough to install.
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=NoInteractionSetup
SetupIconFile=..\app.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; AppVersion alone only sets the installer's ProductVersion resource field — FileVersion
; needs its own directive or it's left blank, so Explorer's Properties > Details tab
; wouldn't show a version for the installer itself.
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductVersion={#MyAppVersion}.0
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductTextVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
; Matches the mutex NoInteraction itself holds while running (App.xaml.cs), so Setup
; can detect a running instance and prompt to close it instead of failing mid-copy.
AppMutex={#MyAppMutex}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startupicon"; Description: "Launch {#MyAppName} automatically when Windows starts"; GroupDescription: "Additional options:"; Flags: checkedonce
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional options:"; Flags: unchecked

[Files]
Source: "..\dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startupicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Best-effort: make sure the app isn't holding its own exe open when Uninstall removes it.
Filename: "{cmd}"; Parameters: "/C taskkill /IM {#MyAppExeName} /F"; Flags: runhidden skipifdoesntexist waituntilterminated; RunOnceId: "KillNoInteraction"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Belt-and-suspenders alongside AppMutex: if an old instance is still running
  // (e.g. started before this session's single-instance mutex fix), make sure it's
  // gone before we try to overwrite its exe.
  Exec('taskkill.exe', '/IM {#MyAppExeName} /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
