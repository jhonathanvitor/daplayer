; Instalador do DaPlayer (Inno Setup 6)
; Compilar: ISCC.exe installer\daplayer.iss   (depois de: flutter build windows --release)
#define AppName "DaPlayer"
#define AppVersion "1.0.0"
#define AppExe "daplayer.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B7F3A1C2-5D4E-4A8B-9C61-DA17A9E40001}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Permite o usuario escolher a pasta de instalacao
DisableDirPage=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=DaPlayer-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Code]
// O app fica na bandeja ao fechar a janela; encerra o processo antes de instalar/desinstalar.
procedure KillApp();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function InitializeSetup(): Boolean;
begin
  KillApp();
  Result := True;
end;

function InitializeUninstall(): Boolean;
begin
  KillApp();
  Result := True;
end;

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na area de trabalho"; GroupDescription: "Atalhos:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
; Configuração local (credenciais): copiada para a pasta do app se existir na raiz do projeto
Source: "..\.env"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\oauth_config.json"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Abrir o {#AppName}"; Flags: nowait postinstall skipifsilent
