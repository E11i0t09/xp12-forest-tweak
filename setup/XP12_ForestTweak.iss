; XP12 Forest Tweak - Windows setup (Inno Setup)
; (c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission, see LICENSE.
;
; Installs for the current user only (no admin rights) into <X-Plane 12>\ForestDensityTweak\app, next to the
; backups of the tool. X-Plane itself is not changed by the setup - the settings are chosen in the app.
; Build: build_setup.bat (needs Inno Setup 7). Folder layout: this file in setup\, the tool files one level up
; (Windows\, data\, FlyWithLua\, LICENSE, README_Windows.txt).

#define AppVer "1.6.0"
#define PS "{sys}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId={{6F3B2C1E-8A44-4D5B-9C2E-5E11F0A70912}
AppName=XP12 Forest Tweak
AppVersion={#AppVer}
AppVerName=XP12 Forest Tweak {#AppVer}
AppPublisher=E11i0t09
AppPublisherURL=https://github.com/E11i0t09/xp12-forest-tweak
AppSupportURL=https://github.com/E11i0t09/xp12-forest-tweak/issues
AppUpdatesURL=https://github.com/E11i0t09/xp12-forest-tweak/releases
PrivilegesRequired=lowest
DefaultDirName={code:GetDefaultDir}
UsePreviousAppDir=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DirExistsWarning=no
AppendDefaultDirName=no
LicenseFile=..\LICENSE
SetupIconFile=forest.ico
UninstallDisplayIcon={app}\forest.ico
UninstallDisplayName=XP12 Forest Tweak
OutputDir=out
OutputBaseFilename=XP12_ForestTweak_v{#AppVer}_Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
ShowLanguageDialog=auto

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
english.XPTitle=X-Plane 12 folder
english.XPSub=Where is your X-Plane 12?
english.XPText=Found automatically. Change it if you use another installation. The tool is placed in ForestDensityTweak\app inside this folder, next to its backups.
english.XPBad=No X-Plane 12 here: the folder must contain "Resources\default scenery" and "Custom Scenery".
english.XPFound=Found:
english.XPNone=X-Plane 12 not found yet - please choose its folder.
english.XPRun=X-Plane is running - please quit it before you change anything in the app.
english.TaskLua=In-sim window (FlyWithLua): switch the tree density during flight
english.TaskStart=Start menu entry
english.TaskDesk=Desktop shortcut
english.Group=Also:
english.RunNow=Open Forest Tweak now
english.RestoreQ=The forest tweak may still be active in X-Plane.%n%nRestore the original forests and hedges first? (recommended)%n%nYes = restore, then uninstall%nNo = only uninstall the app (X-Plane keeps the changed forests)
german.XPTitle=X-Plane-12-Ordner
german.XPSub=Wo ist dein X-Plane 12?
german.XPText=Automatisch gefunden. Ändern, wenn du eine andere Installation nutzt. Das Tool kommt nach ForestDensityTweak\app in diesem Ordner, neben seine Sicherungen.
german.XPBad=Hier ist kein X-Plane 12: Der Ordner muss "Resources\default scenery" und "Custom Scenery" enthalten.
german.XPFound=Gefunden:
german.XPNone=X-Plane 12 noch nicht gefunden - bitte den Ordner wählen.
german.XPRun=X-Plane läuft - bitte beenden, bevor du in der App etwas änderst.
german.TaskLua=Fenster im Sim (FlyWithLua): Baumdichte während des Flugs umschalten
german.TaskStart=Eintrag im Startmenü
german.TaskDesk=Verknüpfung auf dem Desktop
german.Group=Außerdem:
german.RunNow=Forest Tweak jetzt öffnen
german.RestoreQ=Der Wald-Tweak ist in X-Plane vielleicht noch aktiv.%n%nZuerst die originalen Wälder und Hecken wiederherstellen? (empfohlen)%n%nJa = wiederherstellen, dann deinstallieren%nNein = nur die App deinstallieren (X-Plane behält die geänderten Wälder)

[Tasks]
Name: "lua"; Description: "{cm:TaskLua}"; Check: HasFlyWithLua
Name: "startmenu"; Description: "{cm:TaskStart}"; GroupDescription: "{cm:Group}"; Flags: unchecked
Name: "desktopicon"; Description: "{cm:TaskDesk}"; GroupDescription: "{cm:Group}"; Flags: unchecked

[Files]
Source: "..\Windows\XP12_ForestTweak.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Windows\XP12_ForestTweak_Gui.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Windows\Start_ForestTweak.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Windows\Start_ForestTweak_Console.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs
Source: "..\FlyWithLua\ForestDensityToggle.lua"; DestDir: "{app}\FlyWithLua"; Flags: ignoreversion
Source: "..\FlyWithLua\ForestDensityToggle.lua"; DestDir: "{code:XPDir}\Resources\plugins\FlyWithLua\Scripts"; Tasks: lua; Flags: ignoreversion
Source: "..\README_Windows.txt"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "forest.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{code:XPDir}\Forest Tweak"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Minimized -File ""{app}\XP12_ForestTweak_Gui.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\forest.ico"; Comment: "XP12 Forest Tweak"
Name: "{userprograms}\XP12 Forest Tweak"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Minimized -File ""{app}\XP12_ForestTweak_Gui.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\forest.ico"; Tasks: startmenu
Name: "{userdesktop}\XP12 Forest Tweak"; Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Minimized -File ""{app}\XP12_ForestTweak_Gui.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\forest.ico"; Tasks: desktopicon

[Run]
Filename: "{#PS}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Minimized -File ""{app}\XP12_ForestTweak_Gui.ps1"""; WorkingDir: "{app}"; Description: "{cm:RunNow}"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\installed_by_setup.txt"
Type: filesandordirs; Name: "{app}\_update_backup"

[Code]
var
  XPPage: TInputDirWizardPage;
  XPInfo: TNewStaticText;

function IsXP(const D: String): Boolean;
begin
  Result := (D <> '') and DirExists(AddBackslash(D) + 'Resources\default scenery') and DirExists(AddBackslash(D) + 'Custom Scenery');
end;

function FindXP(): String;
var
  Lines: TArrayOfString;
  I: Integer;
  P: String;
begin
  Result := '';
  if LoadStringsFromFile(ExpandConstant('{localappdata}\x-plane_install_12.txt'), Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
    begin
      P := RemoveBackslashUnlessRoot(Trim(Lines[I]));
      StringChangeEx(P, '/', '\', True);
      if IsXP(P) then begin Result := P; Exit; end;
    end;
end;

function GetDefaultDir(Param: String): String;
var
  X: String;
begin
  X := FindXP();
  if X = '' then X := ExpandConstant('{localappdata}\XP12 Forest Tweak');
  Result := AddBackslash(X) + 'ForestDensityTweak\app';
end;

function XPDir(Param: String): String;
begin
  // the app folder is <X-Plane>\ForestDensityTweak\app
  Result := ExtractFileDir(ExtractFileDir(RemoveBackslashUnlessRoot(WizardDirValue)));
end;

function HasFlyWithLua(): Boolean;
begin
  Result := DirExists(AddBackslash(XPDir('')) + 'Resources\plugins\FlyWithLua');
end;

function HasDirLike(const Parent, Mask: String): Boolean;
var
  F: TFindRec;
begin
  Result := False;
  if FindFirst(AddBackslash(Parent) + Mask, F) then
  try
    repeat
      if (F.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then begin Result := True; Exit; end;
    until not FindNext(F);
  finally
    FindClose(F);
  end;
end;

function IsXPRunning(): Boolean;
var
  Loc, Svc, Res: Variant;
begin
  Result := False;
  try
    Loc := CreateOleObject('WbemScripting.SWbemLocator');
    Svc := Loc.ConnectServer('.', 'root\CIMV2');
    Res := Svc.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name = ''X-Plane.exe''');
    Result := Res.Count > 0;
  except
  end;
end;

procedure UpdateXPInfo(Sender: TObject);
var
  D, S: String;
begin
  D := RemoveBackslashUnlessRoot(Trim(XPPage.Values[0]));
  if not IsXP(D) then
  begin
    XPInfo.Caption := CustomMessage('XPNone');
    Exit;
  end;
  S := CustomMessage('XPFound') + ' X-Plane 12';
  if HasDirLike(D + '\Custom Scenery', 'simHeaven_X-World-Pro*') then S := S + ', simHeaven X-WORLD Pro'
  else if HasDirLike(D + '\Custom Scenery', 'simHeaven_X-World*') then S := S + ', simHeaven X-World';
  if HasDirLike(D + '\Custom Scenery', 'Global*Forests*v2*') then S := S + ', Global Forests v2';
  if DirExists(D + '\Resources\plugins\FlyWithLua') then S := S + ', FlyWithLua';
  if IsXPRunning() then S := S + #13#10#13#10 + CustomMessage('XPRun');
  XPInfo.Caption := S;
end;

procedure InitializeWizard();
var
  X: String;
begin
  XPPage := CreateInputDirPage(wpLicense, CustomMessage('XPTitle'), CustomMessage('XPSub'), CustomMessage('XPText'), False, '');
  XPPage.Add('');
  X := XPDir('');
  if not IsXP(X) then X := FindXP();
  XPPage.Values[0] := X;
  XPInfo := TNewStaticText.Create(XPPage);
  XPInfo.Parent := XPPage.Surface;
  XPInfo.Top := XPPage.Edits[0].Top + XPPage.Edits[0].Height + ScaleY(16);
  XPInfo.Left := 0;
  XPInfo.Width := XPPage.SurfaceWidth;
  XPInfo.AutoSize := False;
  XPInfo.Height := ScaleY(80);
  XPInfo.WordWrap := True;
  XPPage.Edits[0].OnChange := @UpdateXPInfo;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = XPPage.ID then UpdateXPInfo(nil);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  D: String;
begin
  Result := True;
  if CurPageID = XPPage.ID then
  begin
    D := RemoveBackslashUnlessRoot(Trim(XPPage.Values[0]));
    if not IsXP(D) then
    begin
      MsgBox(CustomMessage('XPBad'), mbError, MB_OK);
      Result := False;
      Exit;
    end;
    WizardForm.DirEdit.Text := AddBackslash(D) + 'ForestDensityTweak\app';
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // marks a setup install: the app then updates itself with the new setup instead of the ZIP
  if CurStep = ssPostInstall then
    SaveStringToFile(ExpandConstant('{app}\installed_by_setup.txt'), 'installed by XP12_ForestTweak_v{#AppVer}_Setup.exe' + #13#10, False);
end;

function TweakActive(const XP: String): Boolean;
var
  T: String;
  Size: Int64;
begin
  T := AddBackslash(XP) + 'ForestDensityTweak\';
  Result := FileExists(T + 'switched_off.json') or DirExists(AddBackslash(XP) + 'Custom Scenery\XP12_ForestTweak_Knicks')
    or DirExists(AddBackslash(XP) + 'Custom Scenery\XP12_ForestTweak_HedgerowMap');
  if not Result and FileSize64(T + 'backup.log', Size) then Result := Size > 2;
  if not Result and FileSize64(T + 'hedges.log', Size) then Result := Size > 2;
end;

function InitializeUninstall(): Boolean;
var
  App, XP: String;
  RC: Integer;
begin
  Result := True;
  App := ExpandConstant('{app}');
  XP := ExtractFileDir(ExtractFileDir(App));
  if TweakActive(XP) and FileExists(App + '\XP12_ForestTweak_Gui.ps1') then
    case MsgBox(CustomMessage('RestoreQ'), mbConfirmation, MB_YESNOCANCEL) of
      IDYES: Exec(ExpandConstant('{#PS}'), '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Minimized -File "' + App + '\XP12_ForestTweak_Gui.ps1" -UninstallRestore', App, SW_SHOWMINIMIZED, ewWaitUntilTerminated, RC);
      IDCANCEL: Result := False;
    end;
end;
