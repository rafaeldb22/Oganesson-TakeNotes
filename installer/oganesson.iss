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
ChangesAssociations=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "mdfile.ico"; DestDir: "{app}"; Flags: ignoreversion

; Oganesson in "Open with" for .md files, with its own icon (a page with the logo).
[Registry]
Root: HKA; Subkey: "Software\Classes\Oganesson.md"; ValueType: string; ValueData: "Nota de Oganesson (Markdown)"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Oganesson.md\DefaultIcon"; ValueType: string; ValueData: "{app}\mdfile.ico"
Root: HKA; Subkey: "Software\Classes\Oganesson.md\shell\open\command"; ValueType: string; ValueData: """{app}\Oganesson.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: string; ValueName: "Oganesson.md"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: string; ValueName: "Oganesson.md"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\Oganesson.exe\SupportedTypes"; ValueType: string; ValueName: ".md"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\Oganesson.exe\SupportedTypes"; ValueType: string; ValueName: ".markdown"; ValueData: ""

; "Notas" in the shortcut name so Windows search finds the app when typing it.
[InstallDelete]
Type: files; Name: "{autoprograms}\Oganesson.lnk"

[Icons]
Name: "{autoprograms}\Oganesson Notas"; Filename: "{app}\Oganesson.exe"; Comment: "Notas, tareas y calendario"
Name: "{autodesktop}\Oganesson"; Filename: "{app}\Oganesson.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Oganesson.exe"; Description: "{cm:LaunchProgram,Oganesson}"; Flags: nowait postinstall skipifsilent
; Silent install = in-app update: reopen the app when it finishes.
Filename: "{app}\Oganesson.exe"; Flags: nowait; Check: WizardSilent
