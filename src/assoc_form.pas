{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit assoc_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, file_assoc {$ifdef LINUX}, linux_deps{$endif};

type
  TAssocForm = class(TForm)
    pnlBody: TPanel;
    lblPath: TLabel;
    edtPath: TEdit;
    lblExts: TLabel;
    pnlExts: TPanel;
    lblDeps: TLabel;
    btnInstallDeps: TButton;
    pnlFoot: TPanel;
    btnSet: TButton;
    btnUnset: TButton;
    btnClose: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnSetClick(Sender: TObject);
    procedure btnUnsetClick(Sender: TObject);
    procedure btnInstallDepsClick(Sender: TObject);
  private
    fLog: TAssocLogEvent;
    fBoxes: array of TCheckBox;
{$ifdef LINUX}
    fDepCommand: string;
    fDepInstalling: Boolean;
{$endif}
    function checkedExts: TIntegerDynArray;
    procedure setButtons(act: Boolean);
{$ifdef LINUX}
    procedure refreshDeps;
    procedure onDepLog(const msg: string);
    procedure onDepDone(Sender: TObject);
{$endif}
  end;

// exePath: proposed IDE binary; every step is reported through log
procedure showAssocDialog(aOwner: TComponent; const exePath: string; log: TAssocLogEvent);

implementation

{$R *.lfm}

procedure TAssocForm.FormCreate(Sender: TObject);
begin
  SetLength(fBoxes, Length(ASSOC_EXTS));
  for var i := Low(ASSOC_EXTS) to High(ASSOC_EXTS) do begin
    fBoxes[i] := TCheckBox.Create(Self);
    fBoxes[i].Parent := pnlExts;
    fBoxes[i].Caption := '.'+ASSOC_EXTS[i, 0];
    // .inc is not exclusively Pascal, so it starts off
    fBoxes[i].Checked := ASSOC_EXTS[i, 0] <> 'inc';
  end;
end;

procedure TAssocForm.FormShow(Sender: TObject);
begin
{$ifdef LINUX}
  refreshDeps;
{$endif}
end;

function TAssocForm.checkedExts: TIntegerDynArray;
begin
  result := nil;
  for var i := 0 to High(fBoxes) do
    if fBoxes[i].Checked then result := Concat(result, [i]);
end;

procedure TAssocForm.setButtons(act: Boolean);
begin
  btnSet.Enabled := act;
  btnUnset.Enabled := act;
  btnClose.Enabled := act;
  btnInstallDeps.Enabled := act;
end;

procedure TAssocForm.btnSetClick(Sender: TObject);
begin
  var exe := Trim(edtPath.Text);
  if not FileExists(exe) then begin
    MessageDlg('Associate file extensions', 'IDE executable not found: '+exe, mtError, [mbOK], 0);
    exit;
  end;
  var exts := checkedExts;
  if exts = nil then exit;
  fLog('--- associating file extensions ---');
  if setAssociations(exe, exts, fLog) then fLog('file extensions associated')
  else fLog('file extension association finished with errors');
end;

procedure TAssocForm.btnUnsetClick(Sender: TObject);
begin
  var exts := checkedExts;
  if exts = nil then exit;
  fLog('--- removing file extension associations ---');
  if unsetAssociations(exts, fLog) then fLog('file extension associations removed')
  else fLog('file extension removal finished with errors');
end;

{$ifdef LINUX}
procedure TAssocForm.refreshDeps;
begin
  var deps := checkAssocDeps;
  fDepCommand := deps.command;
  lblDeps.Visible := not deps.ok;
  btnInstallDeps.Visible := deps.canAutoInstall;
  if deps.ok then exit;
  lblDeps.Caption := 'Missing: '+deps.missing+'. Without them new extensions are not recognized by the file manager.';
  if not deps.canAutoInstall then begin
    if deps.command <> '' then lblDeps.Caption += ' Run as root: '+deps.command
    else lblDeps.Caption += ' Install them with your package manager.';
  end;
end;

procedure TAssocForm.btnInstallDepsClick(Sender: TObject);
begin
  if fDepInstalling or (fDepCommand = '') then exit;
  fDepInstalling := True;
  setButtons(False);
  fLog('--- pkexec '+fDepCommand+' ---');
  TDepInstallThread.Create(fDepCommand, @onDepLog, @onDepDone);
end;

procedure TAssocForm.onDepLog(const msg: string);
begin
  fLog(msg);
end;

procedure TAssocForm.onDepDone(Sender: TObject);
begin
  fDepInstalling := False;
  setButtons(True);
  var code := TDepInstallThread(Sender).ExitCode;
  if code = 0 then fLog('packages installed')
  // 126 / 127: the password dialog was dismissed, or there was no agent to show it
  else fLog('package install failed (pkexec exit='+IntToStr(code)+')');
  refreshDeps;
end;
{$else}
procedure TAssocForm.btnInstallDepsClick(Sender: TObject);
begin
end;
{$endif}

procedure showAssocDialog(aOwner: TComponent; const exePath: string; log: TAssocLogEvent);
begin
  var dlg := autofree TAssocForm.Create(aOwner);
  dlg.fLog := log;
  dlg.edtPath.Text := exePath;
  dlg.ShowModal;
end;

end.
