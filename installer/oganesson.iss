; Inno Setup script: builds Oganesson-Setup.exe from the Flutter release build.
; Installs per user (no admin rights needed), with Start menu entry,
; optional desktop shortcut and an uninstaller.

#define AppVersion GetEnv("APP_VERSION")
#if AppVersion == ""
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F1C3A52-8E4B-4F6A-9D2E-7C5B1A9E3F41}
AppName=Oganesson
AppVersion={#AppVersion}
AppPublisher=Rafa
AppPublisherURL=https://github.com/rafaeldb22/Oganesson-TakeNotes
DefaultDirName={localappdata}\Programs\Oganesson
DefaultGroupName=Oganesson
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Oganesson-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Oganesson.exe
UninstallDisplayName=Oganesson
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Oganesson"; Filename: "{app}\Oganesson.exe"
Name: "{autodesktop}\Oganesson"; Filename: "{app}\Oganesson.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Oganesson.exe"; Description: "{cm:LaunchProgram,Oganesson}"; Flags: nowait postinstall skipifsilent
; Silent install = in-app update: reopen the app when it finishes.
Filename: "{app}\Oganesson.exe"; Flags: nowait; Check: WizardSilent
