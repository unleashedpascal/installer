{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit main_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Graphics, LCLType, LCLIntf, Menus, Clipbrd, RegExpr, fileinfo,
  {$ifdef WINDOWS} Windows, ShellApi, {$endif}
  {$ifdef LINUX} process, linux_deps, {$endif}
  branch_fetch, branch_cache, install_pipeline, install_manifest, hash_branch, about_form, app_settings;

const
  GH_OWNER     = 'unleashedpascal';
  REPO_FPC     = 'compiler';
  REPO_LAZARUS = 'ide';

type
  TMainForm = class(TForm)
    bevel1: tbevel;
    bevel2: tbevel;
    bevel3: tbevel;
    button1: tbutton;
    CheckBoxCPUView: tcheckbox;
    checkboxcrosslinux32: tcheckbox;
    checkboxcrosslinux64: tcheckbox;
    checkboxcrosswasm: tcheckbox;
    checkboxcrosswin32: tcheckbox;
    checkboxcrosswin64: tcheckbox;
    checkboxminimap: tcheckbox;
    CheckBoxUnleashedMinimap: TCheckBox;
    checkboxtoggleaffinity: tcheckbox;
    CheckBoxHelpFiles: TCheckBox;
    CheckBoxMetaDarkStyle: TCheckBox;
    GroupBoxTarget: TGroupBox;
    GroupBoxUnleashed: TGroupBox;
    CheckBoxInstallUnleashed: TCheckBox;
    imagelogo: timage;
    labellazarusaddons: tlabel;
    LabelLinkCPUView: TLabel;
    LabelLinkMetaDarkStyle: TLabel;
    labellazarushash1: tlabel;
    LabelUnleashedBranch: TLabel;
    ComboBoxUnleashedBranch: TComboBox;
    LabelUnleashedHash: TLabel;
    EditUnleashedHash: TEdit;
    CheckBoxUnleashedLatest: TCheckBox;
    GroupBoxLazarus: TGroupBox;
    CheckBoxInstallLazarus: TCheckBox;
    CheckBoxDesktopShortcut: TCheckBox;
    CheckBoxInstallFolderShortcut: TCheckBox;
    CheckBoxLaunchAfter: TCheckBox;
    PaintBoxLaunchWarn: TPaintBox;
    ComboBoxLazarusBranch: TComboBox;
    LabelLazarusHash: TLabel;
    EditLazarusHash: TEdit;
    CheckBoxLazarusLatest: TCheckBox;
    LabelCross: TLabel;
    MainMenu1: TMainMenu;
    MenuFile: TMenuItem;
    MenuFileExit: TMenuItem;
    MenuRepo: TMenuItem;
    MenuRepoMain: TMenuItem;
    MenuRepoFreepascal: TMenuItem;
    MenuRepoLazarus: TMenuItem;
    MenuRepoInstaller: TMenuItem;
    MenuHelp: TMenuItem;
    MenuHelpDocs: TMenuItem;
    MenuHelpAbout: TMenuItem;
    panel1: tpanel;
    panel10: tpanel;
    panel11: tpanel;
    panel12: tpanel;
    panel13: tpanel;
    panel14: tpanel;
    panel15: tpanel;
    panel16: tpanel;
    panel17: tpanel;
    panel2: tpanel;
    panel3: tpanel;
    panel4: tpanel;
    panel5: tpanel;
    panel6: tpanel;
    panel7: tpanel;
    panel8: tpanel;
    panel9: tpanel;
    PanelTargetContent: TPanel;
    PanelTargetEdit: TPanel;
    EditTargetDir: TEdit;
    ButtonBrowse: TButton;
    LabelMode: TLabel;
    PanelUnleashedBody: TPanel;
    PanelLazarusBody: TPanel;
    SelectDirDialog: TSelectDirectoryDialog;
    ProgressBar: TProgressBar;
    CheckBoxSaveLog: TCheckBox;
    ButtonInstall: TButton;
    ButtonClose: TButton;
    ListBoxLog: TListBox;
    PopupMenuLog: TPopupMenu;
    MenuCopy: TMenuItem;
    StatusBar: TStatusBar;
    procedure button1click(sender: tobject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ButtonBrowseClick(Sender: TObject);
    procedure ButtonInstallClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
    procedure EditTargetDirChange(Sender: TObject);
    procedure CheckBoxInstallUnleashedChange(Sender: TObject);
    procedure CheckBoxInstallLazarusChange(Sender: TObject);
    procedure CheckBoxUnleashedLatestChange(Sender: TObject);
    procedure CheckBoxLazarusLatestChange(Sender: TObject);
    procedure OnAddonOrCrossChange(Sender: TObject);
    procedure PaintBoxLaunchWarnPaint(Sender: TObject);
    procedure LabelLinkCPUViewClick(Sender: TObject);
    procedure LabelLinkMetaDarkStyleClick(Sender: TObject);
    procedure OnSelectionChange(Sender: TObject);
    procedure ListBoxLogDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure ListBoxLogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MenuCopyClick(Sender: TObject);
    procedure MenuFileExitClick(Sender: TObject);
    procedure MenuRepoMainClick(Sender: TObject);
    procedure MenuRepoFreepascalClick(Sender: TObject);
    procedure MenuRepoLazarusClick(Sender: TObject);
    procedure MenuRepoInstallerClick(Sender: TObject);
    procedure MenuHelpDocsClick(Sender: TObject);
    procedure MenuHelpAboutClick(Sender: TObject);
  protected
    {$ifdef WINDOWS}
    procedure CreateParams(var Params: TCreateParams); override;
    procedure WMEnterSizeMove(var Msg: TMessage); message WM_ENTERSIZEMOVE;
    procedure WMExitSizeMove(var Msg: TMessage); message WM_EXITSIZEMOVE;
    procedure WMNCPaint(var Msg: TMessage); message WM_NCPAINT;
    procedure setComposited(enable: Boolean);
    {$endif}
  private
    {$ifdef WINDOWS}
    FInSizeMove: Boolean;
    {$endif}
    FFetchPending: Integer;
    FUnleashedReady, FLazarusReady: Boolean;
    FShowFired: Boolean;
    FInstalling: Boolean;
    // pkexec is running a package install; the Install click waits for it
    FDepInstalling: Boolean;
    // command the dialog offers to run as root, kept until the user accepts
    FDepCommand: string;
    // snapshot of cfg.InstallLazarus from current install run; combined with
    // live CheckBoxLaunchAfter.Checked at OnInstallComplete to decide launch
    FInstalledLazarus: Boolean;
    FInstallTargetDir: string;
    // last target dir for which cross checkboxes were synced; prevents RefreshTargetState clobbering toggles
    FCrossSyncedFor: string;
    // gate for state-B reset so a re-entry from a checkbox toggle won't clobber the just-made change
    FLastState: Char;
    FLastStateDir: string;
    // raw 'name=sha' lists from branch_fetch; Values[branch] yields head SHA
    FFpcBranchShas: TStringList;
    FLazBranchShas: TStringList;
    // pin hints from filename; one of *Name (predefined) / *HashHex (murmur3 prefix) per repo. Resolved in FillCombo
    FPinnedFpcBranchName: string;
    FPinnedFpcBranchHex:  string;
    FPinnedLazBranchName: string;
    FPinnedLazBranchHex:  string;
    // cache file is rewritten only when BOTH fetches succeed; partial-success can't leave a stale "fresh" file
    FFpcFetchOk: Boolean;
    FLazFetchOk: Boolean;
    // True while target dir is unusable (blank or non-empty w/o installer.ini); gates ButtonInstall
    FFolderError: Boolean;
    // True when IDE install is on but neither shortcut picked; gates ButtonInstall + shows red LabelLaunchWarn
    FShortcutError: Boolean;
    // re-entrancy guard for RefreshTargetState; state-B reset writes to controls whose OnChange re-enters here
    FRefreshingTarget: Boolean;
    // installer_settings.ini as read at startup; used as the fresh-install defaults
    FStoredDefaults: TAppSettings;
    // a commit the binary name pins is not a preference and cannot be reset
    FPinnedHashes: Boolean;
    procedure CopySelectedLogLines;
    procedure SetDoubleBufferedRecursive(c: TWinControl);
    procedure LaunchInstalledIde;
    procedure RefreshTargetState;
    procedure UpdateShortcutError;
    procedure ResetTargetControlsToDefaults;
    function applyStoredSettings: Boolean;
    procedure storeSettings;
    procedure ApplyHashesFromBinaryName;
    function ResolveSelectedFpcSha: string;
    function ResolveSelectedLazSha: string;
    procedure StartBranchFetch;
    procedure OnUnleashedDone(Sender: TObject);
    procedure OnLazarusDone(Sender: TObject);
    procedure FillCombo(Combo: TComboBox; const Repo: string; Branches: TStringList; const ErrorMsg: string);
    procedure FetchTick;
    procedure ApplyUnleashedEnabled;
    procedure ApplyLazarusEnabled;
    procedure SetInputsEnabled(act: Boolean);
{$ifdef LINUX}
    function buildDepsReady: Boolean;
    procedure startDepInstall;
    procedure onDepLog(const msg: string);
    procedure onDepComplete(Sender: TObject);
{$endif}
    procedure OnInstallLog(const msg: string);
    procedure OnInstallProgress(Percent: Integer; const status: string);
    procedure OnInstallComplete(Sender: TObject);
    procedure SetStatus(const msg: string);
    procedure Log(const msg: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{$ifdef LINUX}
// Windows takes the icon from the PE .ico via the project .res; gtk2/qt LCL ignores that
// and needs an in-memory image, so the PNG is baked into the binary here.
// 128px, not the 512px artwork: gdk refuses an icon list once an entry passes
// 262144 longs and 512x512 is two longs over, which leaves the window iconless
{$embedbytes INSTALLER_PNG 'installer_128.png'}
{$endif}

// logo lives in the binary, not in the LFM - keeps main_form.lfm small enough to stay workable in the designer
{$embedbytes INSTALLER_LOGO_PNG 'installer_logo.png'}

var
  // set in FormDestroy; FreeOnTerminate-thread callbacks queued via Synchronize can fire after the
  // form is freed, so they gate on this global; a form field there would be read from freed memory
  GShuttingDown: Boolean = False;

const
  // mirror install_pipeline's per-OS host paths so RefreshTargetState/LaunchInstalledIde see the same files
{$ifdef WINDOWS}
  HostFpcWrapperSub  = 'fpc\bin\x86_64-win64\fpc.exe';
  LazarusBinarySub   = 'lazarus\lazarus.exe';
{$endif}
{$ifdef LINUX}
  HostFpcWrapperSub  = 'fpc/bin/fpc';
  LazarusBinarySub   = 'lazarus/lazarus';
{$endif}

// filesystem is authoritative for what's installed; manifest only records intent (crash leaves no manifest)
function IsDirEffectivelyEmpty(const Dir: string): Boolean;
var SR: TSearchRec;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(Dir)+'*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then begin
        Result := False;
        Exit;
      end;
    until FindNext(SR) <> 0;
  finally
    // SysUtils. qualifier needed -- Windows unit also exports FindClose(HANDLE) which shadows the TSearchRec one
    SysUtils.FindClose(SR);
  end;
end;

function ProbeCrossInstalled(const dir, target: string): Boolean;
begin
  Result := False;
  if dir = '' then Exit;
{$ifdef WINDOWS}
  Result := DirectoryExists(IncludeTrailingPathDelimiter(dir)+'fpc\units\'+target);
{$endif}
{$ifdef LINUX}
  var Base := IncludeTrailingPathDelimiter(dir)+'fpc/lib/fpc/';
  if not DirectoryExists(Base) then Exit;
  var SR: TSearchRec;
  if FindFirst(Base+'*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) <> 0) and (Length(SR.Name) > 0) and (SR.Name[1] in ['0'..'9']) and DirectoryExists(Base+SR.Name+'/units/'+target) then begin
        Result := True;
        Exit;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
{$endif}
end;

// {$I %DATE%}/%TIME% are frozen at build by the FPC preprocessor (not function calls)
const
  BUILD_DATE_RAW = {$I %DATE%};
  BUILD_TIME_RAW = {$I %TIME%};

function GetAppVersion: string;
begin
  Result := '';
  var Info := autofree TFileVersionInfo.Create(nil);
  try
    Info.ReadFileInfo;
    Result := Info.VersionStrings.Values['FileVersion'];
  except
    // resource missing or unreadable -> caller falls back to no version
  end;
end;

{$ifdef WINDOWS}
const
  WS_EX_COMPOSITED = $02000000;

// WS_EX_COMPOSITED makes DWM composite form + ~50 child HWNDs atomically; without it restore/resize shows paint cascade
procedure TMainForm.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // not during install: see setComposited (guards a handle recreate mid-install)
  if not FInstalling then Params.ExStyle := Params.ExStyle or WS_EX_COMPOSITED;
end;

// composited off for the whole install: every log line invalidates a child, each recomposite
// repaints the NC menu bar unbuffered, and DefWindowProc has paths (WM_NCACTIVATE, internal
// menu draw) that bypass WMNCPaint, so swallowing that message alone still left flicker.
// With per-control DoubleBuffered the plain paint path is clean; composition only earns its
// keep on resize/restore, which install-time updates never trigger.
procedure TMainForm.setComposited(enable: Boolean);
begin
  var ex := GetWindowLongPtr(Handle, GWL_EXSTYLE);
  if enable then ex := ex or WS_EX_COMPOSITED else ex := ex and (not WS_EX_COMPOSITED);
  SetWindowLongPtr(Handle, GWL_EXSTYLE, ex);
  // frame recalc applies the style now; doubles as the one-shot NC repaint after install
  SetWindowPos(Handle, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
end;

// menu bar is in NC area which WS_EX_COMPOSITED doesn't cover: every recomposite repaints it
// unbuffered (erase+draw = flicker). Suppress NC paint during drag; redraw the frame once on exit
procedure TMainForm.WMEnterSizeMove(var Msg: TMessage);
begin
  FInSizeMove := True;
  inherited;
end;

procedure TMainForm.WMExitSizeMove(var Msg: TMessage);
begin
  FInSizeMove := False;
  inherited;
  RedrawWindow(Handle, nil, 0, RDW_FRAME or RDW_INVALIDATE);
end;

procedure TMainForm.WMNCPaint(var Msg: TMessage);
begin
  if not FInSizeMove then inherited;
end;
{$endif}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FFpcBranchShas := TStringList.Create;
  FLazBranchShas := TStringList.Create;
  // read before any control is touched: RefreshTargetState's fresh-install reset consults it
  FStoredDefaults := readSettings;

  {$ifdef LINUX}
  var IconStream := autofree TMemoryStream.Create;
  IconStream.WriteBuffer(INSTALLER_PNG, SizeOf(INSTALLER_PNG));
  IconStream.Position := 0;
  var png := autofree TPortableNetworkGraphic.Create;
  png.LoadFromStream(IconStream);
  Application.Icon.Assign(png);
  Self.Icon.Assign(png);
  {$endif}

  var LogoStream := autofree TMemoryStream.Create;
  LogoStream.WriteBuffer(INSTALLER_LOGO_PNG, SizeOf(INSTALLER_LOGO_PNG));
  LogoStream.Position := 0;
  var LogoPNG := autofree TPortableNetworkGraphic.Create;
  LogoPNG.LoadFromStream(LogoStream);
  ImageLogo.Picture.Assign(LogoPNG);

  // augment LFM caption with version + build stamp
  var BuildDate := StringReplace(BUILD_DATE_RAW, '/', '-', [rfReplaceAll]);
  var BuildTime := Copy(BUILD_TIME_RAW, 1, 5);   // HH:MM, drop :SS
  var Ver := GetAppVersion;
  if Ver <> '' then Caption := Caption+' v'+Ver;
  Caption := Caption+' (built at '+BuildDate+' '+BuildTime+')';
  // cross checkbox defaults must be set BEFORE EditTargetDir.Text -- that fires RefreshTargetState which probes the FS
  // and sets FCrossSyncedFor. Overrides applied after that would win against the "nothing installed" probe
  {$ifdef LINUX}
  // host is x86_64-linux; native build covers it. cross-to-win64 starts off so we don't surprise user with downloads
  CheckBoxCrossLinux64.Enabled := False;
  CheckBoxCrossLinux64.Checked := False;
  CheckBoxCrossLinux64.Caption := 'x86_64-linux (native)';
  EditTargetDir.Text := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME'))+'unleashed';
  // Toggle Display Affinity uses Set/GetWindowDisplayAffinity (user32). Package's Register is {$ifdef WINDOWS} so no-op on linux
  CheckBoxToggleAffinity.Enabled := False;
  CheckBoxToggleAffinity.Checked := False;
  {$else}
  // host is x86_64-win64; cross-to-linux64 starts off
  CheckBoxCrossWin64.Enabled := False;
  CheckBoxCrossWin64.Checked := False;
  CheckBoxCrossWin64.Caption := 'x86_64-win64 (native)';
  EditTargetDir.Text := 'C:\unleashed';
  {$endif}
  // per-child DoubleBuffered; form-level only covers background, each child HWND otherwise paints direct to screen
  SetDoubleBufferedRecursive(Self);

  SetStatus('Ready');
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
  RefreshTargetState;
  ApplyHashesFromBinaryName;

  // stored geometry wins; without it 80% of work area, re-centered vertically.
  // LFM Position=poScreenCenter uses designer Height which cramps the log
  if not applyStoredSettings then begin
    Self.Height := Screen.WorkAreaHeight*80 div 100;
    Self.Top := Screen.WorkAreaTop+(Screen.WorkAreaHeight-Self.Height) div 2;
  end;
end;

// Preferences from installer_settings.ini. Returns True when it applied a
// window geometry, so FormCreate knows to skip its own sizing. A manifest
// in the target dir outranks the stored checkboxes: it describes what is
// actually installed there, the settings only carry a habit.
function TMainForm.applyStoredSettings: Boolean;
begin
  result := False;
  var st := FStoredDefaults;
  if not st.Present then exit;

  if st.FpcBranch <> '' then ComboBoxUnleashedBranch.Text := st.FpcBranch;
  if st.LazBranch <> '' then ComboBoxLazarusBranch.Text := st.LazBranch;
  if st.TargetDir <> '' then EditTargetDir.Text := st.TargetDir;
  CheckBoxSaveLog.Checked := st.SaveLog;

  if not ReadManifest(Trim(EditTargetDir.Text)).Present then ResetTargetControlsToDefaults;
  RefreshTargetState;

  if (st.WindowWidth <= 0) or (st.WindowHeight <= 0) then exit;
  // clamp into the current desktop: the monitor that held the window last
  // run may be gone, and an off-screen window is unreachable
  var w := Min(st.WindowWidth, Screen.DesktopWidth);
  var h := Min(st.WindowHeight, Screen.DesktopHeight);
  var l := Max(Screen.DesktopLeft, Min(st.WindowLeft, Screen.DesktopLeft+Screen.DesktopWidth-w));
  var t := Max(Screen.DesktopTop, Min(st.WindowTop, Screen.DesktopTop+Screen.DesktopHeight-h));
  SetBounds(l, t, w, h);
  if st.WindowMaximized then WindowState := wsMaximized;
  result := True;
end;

procedure TMainForm.storeSettings;
begin
  var st: TAppSettings;
  st.Present := True;
  // Restored* is the pre-maximize geometry; Left/Width would store the
  // maximized frame and the window would never come back to its own size
  st.WindowLeft   := RestoredLeft;
  st.WindowTop    := RestoredTop;
  st.WindowWidth  := RestoredWidth;
  st.WindowHeight := RestoredHeight;
  st.WindowMaximized := WindowState = wsMaximized;
  st.TargetDir := Trim(EditTargetDir.Text);
  st.FpcBranch := ComboBoxUnleashedBranch.Text;
  st.LazBranch := ComboBoxLazarusBranch.Text;
  st.CrossWin64   := CheckBoxCrossWin64.Checked;
  st.CrossWin32   := CheckBoxCrossWin32.Checked;
  st.CrossLinux64 := CheckBoxCrossLinux64.Checked;
  st.CrossLinux32 := CheckBoxCrossLinux32.Checked;
  st.CrossWasm    := CheckBoxCrossWasm.Checked;
  st.InstallMinimap          := CheckBoxMinimap.Checked;
  st.InstallUnleashedMinimap := CheckBoxUnleashedMinimap.Checked;
  st.InstallCPUView          := CheckBoxCPUView.Checked;
  st.InstallToggleAffinity   := CheckBoxToggleAffinity.Checked;
  st.InstallMetaDarkStyle    := CheckBoxMetaDarkStyle.Checked;
  st.InstallHelpFiles        := CheckBoxHelpFiles.Checked;
  st.MakeDesktopShortcut     := CheckBoxDesktopShortcut.Checked;
  st.MakeFolderShortcut      := CheckBoxInstallFolderShortcut.Checked;
  st.LaunchAfter := CheckBoxLaunchAfter.Checked;
  st.SaveLog     := CheckBoxSaveLog.Checked;
  st.InstallFpc       := CheckBoxInstallUnleashed.Checked;
  st.InstallLazarus   := CheckBoxInstallLazarus.Checked;
  st.FpcLatest := CheckBoxUnleashedLatest.Checked;
  st.LazLatest := CheckBoxLazarusLatest.Checked;
  st.FpcHash   := Trim(EditUnleashedHash.Text);
  st.LazHash   := Trim(EditLazarusHash.Text);
  writeSettings(st);
end;

procedure tmainform.button1click(sender: tobject);
begin
  ListBoxLog.Clear;
end;

// pull pinned (fpc, laz) from ParamStr(1) or filename. Wire format: README.md "Filename hash pin" + hash_branch.pas
procedure TMainForm.ApplyHashesFromBinaryName;
const
  // legacy fallback only; new encoder produces single hex+digit run with no separators
  HASH_PATTERN = '(?<![0-9a-fA-F])([0-9a-fA-F]{7,12})[^0-9a-fA-F]+([0-9a-fA-F]{7,12})(?![0-9a-fA-F])';
begin
  var parsed: TParsedBinaryName;
  parsed.Present := False;

  // 1. cmdline override via ParamStr(1) -- whole arg as raw blob; falls back to filename if not a valid blob
  if (ParamCount >= 1) and (ParamStr(1) <> '') then begin
    if TryParseBlob(ParamStr(1), parsed) then Log('using cmdline pin: '+ParamStr(1))
    else Log('cmdline arg "'+ParamStr(1)+'" is not a pin blob; falling back to filename');
  end;

  // 2. filename (new length-prefixed format) -- LAST hex run >= 12
  if not parsed.Present then parsed := ParseBinaryName(ExtractFileName(ParamStr(0)));

  if parsed.Present then begin
    FPinnedHashes := True;
    // empty FpcCommit/LazCommit = '0' length digit = "latest of selected branch" sentinel -> tick Latest, clear hash
    Log('binary name carries pinned commit hashes: fpc='+(if parsed.FpcCommit = '' then '(latest)' else parsed.FpcCommit)+' ide='+(if parsed.LazCommit = '' then '(latest)' else parsed.LazCommit));

    if parsed.FpcCommit = '' then begin
      EditUnleashedHash.Text          := '';
      CheckBoxUnleashedLatest.Checked := True;
    end else begin
      EditUnleashedHash.Text          := parsed.FpcCommit;
      CheckBoxUnleashedLatest.Checked := False;
    end;

    if parsed.LazCommit = '' then begin
      EditLazarusHash.Text          := '';
      CheckBoxLazarusLatest.Checked := True;
    end else begin
      EditLazarusHash.Text          := parsed.LazCommit;
      CheckBoxLazarusLatest.Checked := False;
    end;

    // stash branch hints for FillCombo. Hash override (pos 3/4) beats predefined/implicit-main (pos 1/2)
    if parsed.FpcBranchHashOverride <> '' then FPinnedFpcBranchHex := parsed.FpcBranchHashOverride
    else if parsed.FpcBranchFromCommit <> '' then FPinnedFpcBranchName := parsed.FpcBranchFromCommit;
    if parsed.LazBranchHashOverride <> '' then FPinnedLazBranchHex := parsed.LazBranchHashOverride
    else if parsed.LazBranchFromCommit <> '' then FPinnedLazBranchName := parsed.LazBranchFromCommit;

    // companion summary line; hash-overridden branches show the hex here, matching branch name lands later via FillCombo
    var fpcStr: string := if parsed.FpcBranchHashOverride <> '' then parsed.FpcBranchHashOverride else if parsed.FpcBranchFromCommit <> '' then parsed.FpcBranchFromCommit else '(default)';
    var lazStr: string := if parsed.LazBranchHashOverride <> '' then parsed.LazBranchHashOverride else if parsed.LazBranchFromCommit <> '' then parsed.LazBranchFromCommit else '(default)';
    Log('binary name carries pinned branch hashes: fpc='+fpcStr+' ide='+lazStr);

    RefreshTargetState;
    Exit;
  end;

  // 3. legacy two-hash regex fallback; only consulted when neither cmdline nor new-format filename matched
  var Name := ExtractFileName(ParamStr(0));
  var R := autofree TRegExpr.Create;
  R.Expression := HASH_PATTERN;
  if not R.Exec(Name) then Exit;

  var FpcHash := LowerCase(R.&Match[1]);
  var LazHash := LowerCase(R.&Match[2]);
  Log('binary name carries pinned commit hashes (legacy): fpc='+FpcHash+' ide='+LazHash);
  FPinnedHashes := True;
  EditUnleashedHash.Text       := FpcHash;
  CheckBoxUnleashedLatest.Checked := False;
  EditLazarusHash.Text         := LazHash;
  CheckBoxLazarusLatest.Checked := False;
  // RefreshTargetState already ran w/ manifest-restored hashes; rerun so LabelMode reflects the new pin
  RefreshTargetState;
end;

procedure TMainForm.EditTargetDirChange(Sender: TObject);
begin
  RefreshTargetState;
end;

const
  LAUNCH_WARN_MSG = 'Tick at least one IDE shortcut above. A shortcut is the only correct way to launch the IDE; the raw binary skips --pcp and breaks the config.';
  LAUNCH_WARN_PAD = 5;     // inner text padding
  LAUNCH_WARN_RADIUS = 4;  // corner radius

// IDE needs at least one launch shortcut (desktop or install-folder) -- it's
// the only --pcp-correct way to start it. Flag + show the red warning live
procedure TMainForm.UpdateShortcutError;
begin
  FShortcutError := CheckBoxInstallLazarus.Checked and (not CheckBoxDesktopShortcut.Checked) and (not CheckBoxInstallFolderShortcut.Checked);
  if FShortcutError then begin
    // size the box to its wrapped text + vertical padding (top margin is BorderSpacing in the LFM)
    var bmp := autofree Graphics.TBitmap.Create;
    bmp.SetSize(8, 8);
    bmp.Canvas.Font.Assign(PaintBoxLaunchWarn.Font);
    bmp.Canvas.Font.Style := [fsBold];
    var r := Types.Rect(0, 0, PaintBoxLaunchWarn.Width-2*LAUNCH_WARN_PAD, 4000);
    LCLIntf.DrawText(bmp.Canvas.Handle, PChar(LAUNCH_WARN_MSG), Length(LAUNCH_WARN_MSG), r, DT_WORDBREAK or DT_CALCRECT);
    PaintBoxLaunchWarn.Height := (r.Bottom-r.Top)+2*LAUNCH_WARN_PAD;
    PaintBoxLaunchWarn.Invalidate;
  end;
  PaintBoxLaunchWarn.Visible := FShortcutError;
end;

procedure TMainForm.PaintBoxLaunchWarnPaint(Sender: TObject);
begin
  var pb := TPaintBox(Sender);
  var cv := pb.Canvas;
  // clear to parent colour so the rounded corners reveal the panel, not red
  cv.Brush.Style := bsSolid;
  cv.Brush.Color := pb.Color;
  cv.FillRect(0, 0, pb.Width, pb.Height);
  // rounded red fill (pen = fill so there's no contrasting border)
  cv.Pen.Color := clRed;
  cv.Brush.Color := clRed;
  cv.RoundRect(0, 0, pb.Width, pb.Height, LAUNCH_WARN_RADIUS*2, LAUNCH_WARN_RADIUS*2);
  // padded, wrapped, bold black text
  cv.Brush.Style := bsClear;
  cv.Font.Style := [fsBold];
  cv.Font.Color := clBlack;
  var ts: TTextStyle;
  FillChar(ts, SizeOf(ts), 0);
  ts.SingleLine := False;
  ts.Wordbreak := True;
  ts.Alignment := taLeftJustify;
  ts.Layout := tlTop;
  var r := Types.Rect(LAUNCH_WARN_PAD, LAUNCH_WARN_PAD, pb.Width-LAUNCH_WARN_PAD, pb.Height-LAUNCH_WARN_PAD);
  cv.TextRect(r, r.Left, r.Top, LAUNCH_WARN_MSG, ts);
end;

// folder is authoritative; installer.ini carries build SHA for update detection
//   A. blank path           -> error, Install disabled
//   B. dir absent or empty  -> defaults, "New installation"
//   C. dir has installer.ini -> restore from manifest
//   D. dir non-empty w/o ini -> error (someone else's folder)
procedure TMainForm.RefreshTargetState;
begin
  // re-entry guard: bound Edit/Combo writes fire OnSelectionChange -> back here
  if FRefreshingTarget then Exit;
  FRefreshingTarget := True;
  try
  var rawDir := Trim(EditTargetDir.Text);

  // optimistic reset; each branch re-sets the flag as needed
  FFolderError := False;
  LabelMode.Font.Color := clWindowText;
  UpdateShortcutError;

  // ---- state A: no path entered ----
  if rawDir = '' then begin
    FFolderError := True;
    LabelMode.Font.Color := clRed;
    LabelMode.Caption := 'No target directory selected';
    ButtonInstall.Enabled := False;
    FLastState := 'A';
    FLastStateDir := rawDir;
    Exit;
  end;

  var dir            := IncludeTrailingPathDelimiter(rawDir);
  var manifestExists := FileExists(dir+MANIFEST_FILE);
  var dirExists      := DirectoryExists(dir);

  // ---- state B: target absent or empty (no manifest) -> fresh install ----
  // reset only on entry into state-B so checkbox-toggle re-entry doesn't wipe the change
  if (not manifestExists) and ((not dirExists) or IsDirEffectivelyEmpty(dir)) then begin
    if (FLastState <> 'B') or (FLastStateDir <> rawDir) then ResetTargetControlsToDefaults;
    LabelMode.Caption := 'New installation';
    ButtonInstall.Caption := 'Install';
    UpdateShortcutError;
    ButtonInstall.Enabled := (FFetchPending = 0) and (not FInstalling) and (not FShortcutError);
    FLastState := 'B';
    FLastStateDir := rawDir;
    Exit;
  end;

  // ---- state D: dir has content but no manifest -> refuse ----
  // fresh install overwrites fpc/, lazarus/, ... -- a stray unrelated tree would get clobbered
  if not manifestExists then begin
    FFolderError := True;
    LabelMode.Font.Color := clRed;
    LabelMode.Caption := 'Target folder is not empty and is not an Unleashed install (installer.ini not found). Choose an empty directory or an existing Unleashed install location.';
    ButtonInstall.Enabled := False;
    FLastState := 'D';
    FLastStateDir := rawDir;
    Exit;
  end;

  // ---- state C: manifest present -> restore + update / reinstall ----
  var hasFpc := FileExists(dir+HostFpcWrapperSub);
  var hasLaz := FileExists(dir+LazarusBinarySub);

  var parts := '';
  if hasFpc then parts := 'fpc';
  if hasLaz then begin
    if parts <> '' then parts := parts+' + ';
    parts := parts+'lazarus';
  end;
  // list every selectable target, native first. listing native explicitly makes the summary match the cross checkbox set
  {$ifdef WINDOWS}
  var crossTargets: TStringArray := ['x86_64-win64', 'x86_64-linux', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  {$ifdef LINUX}
  var crossTargets: TStringArray := ['x86_64-linux', 'x86_64-win64', 'i386-win32', 'i386-linux', 'wasm32-wasip1'];
  {$endif}
  for var t in crossTargets do
    if ProbeCrossInstalled(rawDir, t) then begin
      if parts <> '' then parts := parts+' + ';
      parts := parts+t;
    end;

  // pull last-installed SHAs from manifest and compare to currently-selected to detect update.
  // user-typed short hash matches manifest's full SHA as prefix in either direction
  var m := ReadManifest(rawDir);
  var updates := '';
  // sync checkboxes once per target dir; gate on manifest-presence so partial install (manifest written, binary missing) still triggers restore
  if FCrossSyncedFor <> dir then begin
    FCrossSyncedFor := dir;
    // {Win64,Linux64} cross synced only on the host where they're not native (other host disables at FormCreate)
    if CheckBoxCrossWin64.Enabled   then CheckBoxCrossWin64.Checked   := ProbeCrossInstalled(rawDir, 'x86_64-win64');
    if CheckBoxCrossLinux64.Enabled then CheckBoxCrossLinux64.Checked := ProbeCrossInstalled(rawDir, 'x86_64-linux');
    CheckBoxCrossWin32.Checked   := ProbeCrossInstalled(rawDir, 'i386-win32');
    CheckBoxCrossLinux32.Checked := ProbeCrossInstalled(rawDir, 'i386-linux');
    CheckBoxCrossWasm.Checked    := ProbeCrossInstalled(rawDir, 'wasm32-wasip1');
    // restore non-FS-detectable selections (branch/hash/addons/launch-after) from manifest
    if m.Present then begin
      CheckBoxMinimap.Checked          := m.InstallMinimap;
      CheckBoxUnleashedMinimap.Checked := m.InstallUnleashedMinimap;
      CheckBoxCPUView.Checked          := m.InstallCPUView;
      CheckBoxMetaDarkStyle.Checked    := m.InstallMetaDarkStyle;
      // help stays ticked once installed; unticking never removes the files, it just skips the fetch
      CheckBoxHelpFiles.Checked        := m.InstallHelpFiles;
      // skip windows-only checkbox restore on linux (FormCreate locked Enabled=False)
      if CheckBoxToggleAffinity.Enabled then CheckBoxToggleAffinity.Checked := m.InstallToggleAffinity;
      CheckBoxLaunchAfter.Checked  := m.LaunchAfter;
      CheckBoxDesktopShortcut.Checked       := m.MakeDesktopShortcut;
      CheckBoxInstallFolderShortcut.Checked := m.MakeFolderShortcut;
      if m.FpcBranch <> '' then begin
        ComboBoxUnleashedBranch.Text := m.FpcBranch;
        // always show last installed SHA in the hash field (display-only while Latest=on); restore explicit Latest flag
        EditUnleashedHash.Text       := m.FpcSha;
        CheckBoxUnleashedLatest.Checked := m.FpcLatest;
      end;
      if m.LazBranch <> '' then begin
        ComboBoxLazarusBranch.Text   := m.LazBranch;
        EditLazarusHash.Text         := m.LazSha;
        CheckBoxLazarusLatest.Checked := m.LazLatest;
      end;
    end;
  end;
  if m.Present then begin

    var selFpc := ResolveSelectedFpcSha;
    var selLaz := ResolveSelectedLazSha;
    if hasFpc and (selFpc <> '') and (m.FpcSha <> '') and (Pos(selFpc, m.FpcSha) <> 1) and (Pos(m.FpcSha, selFpc) <> 1) then updates := updates+' fpc '+Copy(m.FpcSha, 1, 7)+' -> '+Copy(selFpc, 1, 7);
    if hasLaz and (selLaz <> '') and (m.LazSha <> '') and (Pos(selLaz, m.LazSha) <> 1) and (Pos(m.LazSha, selLaz) <> 1) then updates := updates+' lazarus '+Copy(m.LazSha, 1, 7)+' -> '+Copy(selLaz, 1, 7);
    // addon deltas. Pipeline's StepRebuildLazarusForAddons handles them without full reinstall, but labels need to reflect reality
    if hasLaz and (CheckBoxMinimap.Checked <> m.InstallMinimap) then updates := updates+(if CheckBoxMinimap.Checked then ' +minimap' else ' -minimap');
    if hasLaz and (CheckBoxUnleashedMinimap.Checked <> m.InstallUnleashedMinimap) then updates := updates+(if CheckBoxUnleashedMinimap.Checked then ' +unleashed-minimap' else ' -unleashed-minimap');
    if hasLaz and (CheckBoxCPUView.Checked <> m.InstallCPUView) then updates := updates+(if CheckBoxCPUView.Checked then ' +cpuview' else ' -cpuview');
    if hasLaz and (CheckBoxMetaDarkStyle.Checked <> m.InstallMetaDarkStyle) then updates := updates+(if CheckBoxMetaDarkStyle.Checked then ' +metadarkstyle' else ' -metadarkstyle');
    // help files are add-only: nothing gets deleted when the box goes off, so only the +delta is real
    if hasLaz and CheckBoxHelpFiles.Checked and (not m.InstallHelpFiles) then updates := updates+' +help';
    // skip toggle-affinity delta on linux (user can't change it)
    if hasLaz and CheckBoxToggleAffinity.Enabled and (CheckBoxToggleAffinity.Checked <> m.InstallToggleAffinity) then updates := updates+(if CheckBoxToggleAffinity.Checked then ' +toggle-affinity' else ' -toggle-affinity');
    if hasFpc and CheckBoxCrossWin64.Enabled and (CheckBoxCrossWin64.Checked <> m.CrossWin64) then updates := updates+(if CheckBoxCrossWin64.Checked then ' +x86_64-win64' else ' -x86_64-win64');
    if hasFpc and (CheckBoxCrossWin32.Checked <> m.CrossWin32) then updates := updates+(if CheckBoxCrossWin32.Checked then ' +i386-win32' else ' -i386-win32');
    if hasFpc and (CheckBoxCrossLinux64.Checked <> m.CrossLinux64) then updates := updates+(if CheckBoxCrossLinux64.Checked then ' +x86_64-linux' else ' -x86_64-linux');
    if hasFpc and (CheckBoxCrossLinux32.Checked <> m.CrossLinux32) then updates := updates+(if CheckBoxCrossLinux32.Checked then ' +i386-linux' else ' -i386-linux');
    if hasFpc and (CheckBoxCrossWasm.Checked <> m.CrossWasm) then updates := updates+(if CheckBoxCrossWasm.Checked then ' +wasm32-wasip1' else ' -wasm32-wasip1');
  end;

  if updates <> '' then begin
    LabelMode.Caption := 'Update available:'+updates;
    ButtonInstall.Caption := 'Update';
  end else if parts <> '' then begin
    LabelMode.Caption := 'Existing install detected ('+parts+') - Install will overwrite';
    ButtonInstall.Caption := 'Reinstall';
  end else begin
    // manifest present but no FPC/Lazarus binary -- prior install died after writing manifest. Treat as resumable
    LabelMode.Caption := 'Partial install detected (manifest only) - Install will resume';
    ButtonInstall.Caption := 'Resume';
  end;
  UpdateShortcutError;
  ButtonInstall.Enabled := (FFetchPending = 0) and (not FInstalling) and (not FShortcutError);
  FLastState := 'C';
  FLastStateDir := rawDir;
  finally
    FRefreshingTarget := False;
  end;
end;

procedure TMainForm.ResetTargetControlsToDefaults;
begin
  // last session's choices are the defaults for a fresh target; without a
  // settings file fall back to the LFM first-time values
  var d := FStoredDefaults;
  if not d.Present then begin
    d.InstallUnleashedMinimap := True;
    d.InstallCPUView := True;
    d.InstallHelpFiles := True;
    d.InstallFpc := True;
    d.InstallLazarus := True;
    d.FpcLatest := True;
    d.LazLatest := True;
    d.LaunchAfter := True;
    d.MakeDesktopShortcut := True;
    d.MakeFolderShortcut := True;
  end;

  // cross checkboxes -- FormCreate handles host-native Enabled/Caption once at startup
  CheckBoxCrossWin64.Checked   := d.CrossWin64 and CheckBoxCrossWin64.Enabled;
  CheckBoxCrossLinux64.Checked := d.CrossLinux64 and CheckBoxCrossLinux64.Enabled;
  CheckBoxCrossWin32.Checked   := d.CrossWin32;
  CheckBoxCrossLinux32.Checked := d.CrossLinux32;
  CheckBoxCrossWasm.Checked    := d.CrossWasm;

  CheckBoxMinimap.Checked          := d.InstallMinimap;
  CheckBoxUnleashedMinimap.Checked := d.InstallUnleashedMinimap;
  CheckBoxCPUView.Checked          := d.InstallCPUView;
  CheckBoxMetaDarkStyle.Checked    := d.InstallMetaDarkStyle;
  CheckBoxHelpFiles.Checked        := d.InstallHelpFiles;
  // toggle-affinity .Enabled=False on linux; writing False here is a no-op visually and keeps the data model clean
  CheckBoxToggleAffinity.Checked   := d.InstallToggleAffinity and CheckBoxToggleAffinity.Enabled;

  CheckBoxInstallUnleashed.Checked := d.InstallFpc;
  CheckBoxInstallLazarus.Checked   := d.InstallLazarus;
  CheckBoxLaunchAfter.Checked      := d.LaunchAfter;
  CheckBoxDesktopShortcut.Checked       := d.MakeDesktopShortcut;
  CheckBoxInstallFolderShortcut.Checked := d.MakeFolderShortcut;

  // a commit pinned by the binary name outranks anything stored
  if not FPinnedHashes then begin
    CheckBoxUnleashedLatest.Checked := d.FpcLatest;
    CheckBoxLazarusLatest.Checked   := d.LazLatest;
    EditUnleashedHash.Text := d.FpcHash;
    EditLazarusHash.Text   := d.LazHash;
  end;
  if d.FpcBranch <> '' then ComboBoxUnleashedBranch.Text := d.FpcBranch;
  if d.LazBranch <> '' then ComboBoxLazarusBranch.Text := d.LazBranch;

  // forget per-dir cross-sync cache so a transition into a manifest dir re-runs the FS + manifest restore
  FCrossSyncedFor := '';

  // sub-control enabling cascades from masters
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
end;

function TMainForm.ResolveSelectedFpcSha: string;
begin
  // explicit hash wins; otherwise head SHA of currently-selected branch (as of last fetch)
  Result := if (not CheckBoxUnleashedLatest.Checked) and (Trim(EditUnleashedHash.Text) <> '') then LowerCase(Trim(EditUnleashedHash.Text))
            else if ComboBoxUnleashedBranch.Text <> '' then LowerCase(FFpcBranchShas.Values[ComboBoxUnleashedBranch.Text])
            else '';
end;

function TMainForm.ResolveSelectedLazSha: string;
begin
  Result := if (not CheckBoxLazarusLatest.Checked) and (Trim(EditLazarusHash.Text) <> '') then LowerCase(Trim(EditLazarusHash.Text))
            else if ComboBoxLazarusBranch.Text <> '' then LowerCase(FLazBranchShas.Values[ComboBoxLazarusBranch.Text])
            else '';
end;

procedure TMainForm.OnSelectionChange(Sender: TObject);
begin
  // wired to combo + hash edit OnChange; keeps LabelMode's '(update available)' hint live as user picks
  RefreshTargetState;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if FShowFired then Exit;
  FShowFired := True;
  StartBranchFetch;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  storeSettings;
  // worker threads have FreeOnTerminate=True; flag stops their callbacks from touching destroyed widgets
  GShuttingDown := True;
  FFpcBranchShas.Free;
  FLazBranchShas.Free;
end;

// while pipeline runs, install thread touches the target tree; prompt before hard exit
procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FInstalling then CanClose := MessageDlg('Installation in progress', 'An installation is currently running. Closing now will leave the target directory in a half-built state. Close anyway?', mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

// cache age for logs (LoadCache returns seconds); trims leading zero units: 13->"13s", 193->"3m 13s", 90061->"1d 1h 1m 1s"
function ageStr(ageSeconds: Double): string;
begin
  var total := Round(ageSeconds);
  if total < 0 then total := 0;
  var d := total div 86400;
  var h := (total div 3600) mod 24;
  var m := (total div 60) mod 60;
  var s := total mod 60;
  result := '';
  if d > 0 then result := result+IntToStr(d)+'d ';
  if (result <> '') or (h > 0) then result := result+IntToStr(h)+'h ';
  if (result <> '') or (m > 0) then result := result+IntToStr(m)+'m ';
  result := result+IntToStr(s)+'s';
end;

procedure TMainForm.StartBranchFetch;

  // convert bare-name list to 'name=sha' form FillCombo expects; only 'main' gets a SHA from cache
  procedure AppendWithMainSha(Src: TStrings; Dest: TStrings; const MainSha: string);
  begin
    Dest.Clear;
    for var i := 0 to Src.Count-1 do begin
      var name := Src[i];
      if SameText(name, 'main') then Dest.Add(name+'='+MainSha)
      else Dest.Add(name+'=');
    end;
  end;

begin
  SetStatus('Updating branches list...');
  FFetchPending := 2;
  FFpcFetchOk := False;
  FLazFetchOk := False;
  ButtonInstall.Enabled := False;

  // cache-first: skip GitHub fetch if cache file is younger than CACHE_TTL_MINUTES. saves anon API quota across launches
  var fpcNames := autofree TStringList.Create;
  var ideNames := autofree TStringList.Create;
  var age: Double;
  var fpcMainSha, ideMainSha: string;
  if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (age < CACHE_TTL_MINUTES*60) then begin
    Log('using cached branch lists ('+ageStr(age)+' old, file="'+CacheFilePath+'")');
    var fpcCache := autofree TStringList.Create;
    var lazCache := autofree TStringList.Create;
    AppendWithMainSha(fpcNames, fpcCache, fpcMainSha);
    AppendWithMainSha(ideNames, lazCache, ideMainSha);
    FillCombo(ComboBoxUnleashedBranch, REPO_FPC, fpcCache, '');
    FUnleashedReady := True;
    ApplyUnleashedEnabled;
    FetchTick;
    FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, lazCache, '');
    FLazarusReady := True;
    ApplyLazarusEnabled;
    FetchTick;
    Exit;
  end;

  Log('Fetching branches from github.com/'+GH_OWNER+'/'+REPO_FPC+' and /'+REPO_LAZARUS);
  TBranchFetchThread.Create(GH_OWNER, REPO_FPC,     @OnUnleashedDone);
  TBranchFetchThread.Create(GH_OWNER, REPO_LAZARUS, @OnLazarusDone);
end;

// failed-fetch fallback: build 'name=sha' from bare names, attaching the cached HEAD SHA only to 'main'
procedure NamesToShaListWithMain(Src, Dest: TStringList; const MainSha: string);
begin
  Dest.Clear;
  for var i := 0 to Src.Count-1 do
    if SameText(Src[i], 'main') then Dest.Add(Src[i]+'='+MainSha)
    else Dest.Add(Src[i]+'=');
end;

procedure TMainForm.OnUnleashedDone(Sender: TObject);
begin
  if GShuttingDown then exit;
  var T := TBranchFetchThread(Sender);
  if T.ErrorMsg <> '' then begin
    var fpcNames := autofree TStringList.Create;
    var ideNames := autofree TStringList.Create;
    var age: Double;
    var fpcMainSha, ideMainSha: string;
    if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (fpcNames.Count > 0) then begin
      var fallback := autofree TStringList.Create;
      NamesToShaListWithMain(fpcNames, fallback, fpcMainSha);
      Log('FAILED to fetch '+REPO_FPC+' branches ('+T.ErrorMsg+'); using stale cache ('+ageStr(age)+' old)');
      FillCombo(ComboBoxUnleashedBranch, REPO_FPC, fallback, '');
    end else FillCombo(ComboBoxUnleashedBranch, REPO_FPC, T.Branches, T.ErrorMsg);
    FFpcFetchOk := False;
  end else begin
    FillCombo(ComboBoxUnleashedBranch, REPO_FPC, T.Branches, T.ErrorMsg);
    FFpcFetchOk := True;
  end;
  FUnleashedReady := True;
  ApplyUnleashedEnabled;
  FetchTick;
end;

procedure TMainForm.OnLazarusDone(Sender: TObject);
begin
  if GShuttingDown then exit;
  var T := TBranchFetchThread(Sender);
  if T.ErrorMsg <> '' then begin
    var fpcNames := autofree TStringList.Create;
    var ideNames := autofree TStringList.Create;
    var age: Double;
    var fpcMainSha, ideMainSha: string;
    if LoadCache(fpcNames, ideNames, age, fpcMainSha, ideMainSha) and (ideNames.Count > 0) then begin
      var fallback := autofree TStringList.Create;
      NamesToShaListWithMain(ideNames, fallback, ideMainSha);
      Log('FAILED to fetch '+REPO_LAZARUS+' branches ('+T.ErrorMsg+'); using stale cache ('+ageStr(age)+' old)');
      FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, fallback, '');
    end else FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, T.Branches, T.ErrorMsg);
    FLazFetchOk := False;
  end else begin
    FillCombo(ComboBoxLazarusBranch, REPO_LAZARUS, T.Branches, T.ErrorMsg);
    FLazFetchOk := True;
  end;
  FLazarusReady := True;
  ApplyLazarusEnabled;
  FetchTick;
end;

procedure TMainForm.FillCombo(Combo: TComboBox; const Repo: string; Branches: TStringList; const ErrorMsg: string);
begin
  // pick matching SHA map by repo so caller code stays simple
  var shaMap := if Repo = REPO_FPC then FFpcBranchShas else if Repo = REPO_LAZARUS then FLazBranchShas else nil;
  if shaMap <> nil then shaMap.Clear;

  Combo.Items.Clear;
  if ErrorMsg <> '' then begin
    Log('FAILED to fetch '+Repo+' branches: '+ErrorMsg);
    Combo.Items.Add('main');
    Combo.ItemIndex := 0;
    Exit;
  end;
  // Branches is 'name=sha'; Names[i] for combo, Values[name] for SHA
  if shaMap <> nil then shaMap.Assign(Branches);
  for var i := 0 to Branches.Count-1 do Combo.Items.Add(Branches.Names[i]);

  Log('Got '+IntToStr(Branches.Count)+' branches for '+Repo);
  // priority: pinned (filename) -> manifest -> main -> master -> first.
  // csDropDownList drops Combo.Text not in Items, so this must run after Items populates (fetch is async)
  var pinnedBranch: string := '';
  if Combo = ComboBoxUnleashedBranch then begin
    if FPinnedFpcBranchName <> '' then pinnedBranch := FPinnedFpcBranchName
    else if FPinnedFpcBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(Combo.Items, FPinnedFpcBranchHex);
      if pinnedBranch <> '' then Log('fpc branch '''+pinnedBranch+''' matches hash prefix '''+FPinnedFpcBranchHex+''', selecting this branch');
    end;
  end else if Combo = ComboBoxLazarusBranch then begin
    if FPinnedLazBranchName <> '' then pinnedBranch := FPinnedLazBranchName
    else if FPinnedLazBranchHex <> '' then begin
      pinnedBranch := FindBranchByHashPrefix(Combo.Items, FPinnedLazBranchHex);
      if pinnedBranch <> '' then Log('ide branch '''+pinnedBranch+''' matches hash prefix '''+FPinnedLazBranchHex+''', selecting this branch');
    end;
  end;

  var manifestBranch: string := '';
  var m := ReadManifest(Trim(EditTargetDir.Text));
  if m.Present then manifestBranch := if Combo = ComboBoxUnleashedBranch then m.FpcBranch else if Combo = ComboBoxLazarusBranch then m.LazBranch else '';

  // last session's branch; the combo is csDropDownList so a name assigned
  // before the fetch populated Items was dropped
  var storedBranch: string := '';
  if FStoredDefaults.Present then
    storedBranch := if Combo = ComboBoxUnleashedBranch then FStoredDefaults.FpcBranch else if Combo = ComboBoxLazarusBranch then FStoredDefaults.LazBranch else '';

  var idx: Integer := -1;
  if pinnedBranch <> '' then idx := Combo.Items.IndexOf(pinnedBranch);
  if idx < 0 then if manifestBranch <> '' then idx := Combo.Items.IndexOf(manifestBranch);
  if idx < 0 then if storedBranch <> '' then idx := Combo.Items.IndexOf(storedBranch);
  if idx < 0 then idx := Combo.Items.IndexOf('main');
  if idx < 0 then idx := Combo.Items.IndexOf('master');
  if idx < 0 then idx := 0;
  if Combo.Items.Count > 0 then Combo.ItemIndex := idx;
  RefreshTargetState;
end;

procedure TMainForm.FetchTick;
begin
  Dec(FFetchPending);
  if FFetchPending = 0 then begin
    // rewrite cache only on full success; partial-success leaves old file alone for future fallback
    if FFpcFetchOk and FLazFetchOk then begin
      SaveCache(FFpcBranchShas, FLazBranchShas);
      Log('cached branch lists (TTL '+IntToStr(CACHE_TTL_MINUTES)+' min, file="'+CacheFilePath+'")');
    end;
    SetStatus('Ready');
    // folder-error / shortcut-error / install-in-progress gates keep Install off after a successful fetch
    ButtonInstall.Enabled := (not FFolderError) and (not FShortcutError) and (not FInstalling);
  end;
end;

procedure TMainForm.ApplyUnleashedEnabled;
begin
  var act := CheckBoxInstallUnleashed.Checked and (not FInstalling);
  ComboBoxUnleashedBranch.Enabled := act and FUnleashedReady;
  CheckBoxUnleashedLatest.Enabled := act;
  EditUnleashedHash.Enabled := act and (not CheckBoxUnleashedLatest.Checked);
  // crosses are nested under FPC; host's own native target locked Enabled=False at FormCreate
  CheckBoxCrossWin32.Enabled   := act;
  CheckBoxCrossWasm.Enabled    := act;
  CheckBoxCrossLinux32.Enabled := act;
{$ifdef WINDOWS}
  CheckBoxCrossLinux64.Enabled := act;     // cross direction (win -> linux)
{$endif}
{$ifdef LINUX}
  CheckBoxCrossWin64.Enabled := act;       // cross direction (linux -> win)
{$endif}
  RefreshTargetState;
end;

procedure TMainForm.ApplyLazarusEnabled;
begin
  var act := CheckBoxInstallLazarus.Checked and (not FInstalling);
  ComboBoxLazarusBranch.Enabled := act and FLazarusReady;
  CheckBoxLazarusLatest.Enabled := act;
  // shortcut choices feed the pipeline snapshot, so freeze them during install (unlike launch-after)
  CheckBoxDesktopShortcut.Enabled       := act;
  CheckBoxInstallFolderShortcut.Enabled := act;
  // launch-after stays toggleable even during install -- user can change mind mid-install,
  // OnInstallComplete reads the live checkbox value
  CheckBoxLaunchAfter.Enabled := CheckBoxInstallLazarus.Checked;
  EditLazarusHash.Enabled := act and (not CheckBoxLazarusLatest.Checked);
  // addons nested under IDE
  CheckBoxMinimap.Enabled := act;
  CheckBoxUnleashedMinimap.Enabled := act;
  CheckBoxCPUView.Enabled := act;
  CheckBoxMetaDarkStyle.Enabled := act;
  CheckBoxHelpFiles.Enabled := act;
  // toggle-affinity locked off on non-Windows hosts (FormCreate disables it once)
{$ifdef WINDOWS}
  CheckBoxToggleAffinity.Enabled := act;
{$endif}
  RefreshTargetState;
end;

procedure TMainForm.CheckBoxInstallUnleashedChange(Sender: TObject);
begin
  ApplyUnleashedEnabled;
end;

procedure TMainForm.CheckBoxInstallLazarusChange(Sender: TObject);
begin
  ApplyLazarusEnabled;
end;

procedure TMainForm.CheckBoxUnleashedLatestChange(Sender: TObject);
begin
  // on checked->unchecked, pre-fill the now-enabled commit edit.
  // priority: 1) installer.ini SHA (pin to disk install, don't silently stage HEAD); 2) head SHA of selected branch.
  // live fetch knows every branch SHA; cache-hit only knows 'main' so other branches leave the edit blank
  if not CheckBoxUnleashedLatest.Checked then begin
    var sha: string := '';
    var m := ReadManifest(Trim(EditTargetDir.Text));
    if m.Present then sha := m.FpcSha;
    if (sha = '') and (FFpcBranchShas <> nil) and (ComboBoxUnleashedBranch.Text <> '') then sha := FFpcBranchShas.Values[ComboBoxUnleashedBranch.Text];
    if sha <> '' then EditUnleashedHash.Text := sha;
  end;
  ApplyUnleashedEnabled;
end;

procedure TMainForm.CheckBoxLazarusLatestChange(Sender: TObject);
begin
  if not CheckBoxLazarusLatest.Checked then begin
    // mirror Unleashed: manifest first then HEAD
    var sha: string := '';
    var m := ReadManifest(Trim(EditTargetDir.Text));
    if m.Present then sha := m.LazSha;
    if (sha = '') and (FLazBranchShas <> nil) and (ComboBoxLazarusBranch.Text <> '') then sha := FLazBranchShas.Values[ComboBoxLazarusBranch.Text];
    if sha <> '' then EditLazarusHash.Text := sha;
  end;
  ApplyLazarusEnabled;
end;

// i386-linux build needs ppcross386 (i386-win32 cross); auto-tick the prereq
procedure TMainForm.OnAddonOrCrossChange(Sender: TObject);
begin
  if (Sender = CheckBoxCrossLinux32) and CheckBoxCrossLinux32.Checked then CheckBoxCrossWin32.Checked := True;
  RefreshTargetState;
end;

procedure TMainForm.LabelLinkCPUViewClick(Sender: TObject);
begin
  OpenURL('https://github.com/AlexanderBagel/CPUView');
end;

procedure TMainForm.LabelLinkMetaDarkStyleClick(Sender: TObject);
begin
  OpenURL('https://github.com/zamtmn/metadarkstyle');
end;

procedure TMainForm.SetStatus(const msg: string);
begin
  StatusBar.SimpleText := msg;
end;

procedure TMainForm.Log(const msg: string);
begin
  var fullText := FormatDateTime('hh:nn:ss', Now)+'# '+msg;
  ListBoxLog.Items.Add(fullText);

  // grow horizontal scrollbar so wide make/lazbuild lines can scroll into view; +24 for per-line padding
  var lineWidth := ListBoxLog.Canvas.TextWidth(fullText)+24;
  if lineWidth > ListBoxLog.ScrollWidth then ListBoxLog.ScrollWidth := lineWidth;

  // keep last line visible. earlier ClientHeight-div math broke on gtk2 pre-first-paint (ClientHeight=0 -> TopIndex past end)
  ListBoxLog.TopIndex := ListBoxLog.Items.Count-1;
end;

procedure TMainForm.SetDoubleBufferedRecursive(c: TWinControl);
begin
  c.DoubleBuffered := True;
  for var i := 0 to c.ControlCount-1 do
    if c.Controls[i] is TWinControl then SetDoubleBufferedRecursive(TWinControl(c.Controls[i]));
end;

procedure TMainForm.CopySelectedLogLines;
begin
  var s := '';
  for var i := 0 to ListBoxLog.Items.Count-1 do
    if ListBoxLog.Selected[i] then begin
      if s <> '' then s := s+LineEnding;
      s := s+ListBoxLog.Items[i];
    end;
  // fall back to current item if nothing selected
  if (s = '') and (ListBoxLog.ItemIndex >= 0) then s := ListBoxLog.Items[ListBoxLog.ItemIndex];
  if s <> '' then Clipboard.AsText := s;
end;

procedure TMainForm.ListBoxLogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // listbox eats Ctrl+C otherwise; menu shortcut also wired
  if (Key = VK_C) and (ssCtrl in Shift) then begin
    CopySelectedLogLines;
    Key := 0;
  end;
end;

procedure TMainForm.MenuCopyClick(Sender: TObject);
begin
  CopySelectedLogLines;
end;

procedure TMainForm.MenuFileExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.MenuRepoMainClick(Sender: TObject);
begin
  OpenURL('https://github.com/unleashedpascal');
end;

procedure TMainForm.MenuRepoFreepascalClick(Sender: TObject);
begin
  OpenURL('https://github.com/unleashedpascal/compiler');
end;

procedure TMainForm.MenuRepoLazarusClick(Sender: TObject);
begin
  OpenURL('https://github.com/unleashedpascal/ide');
end;

procedure TMainForm.MenuRepoInstallerClick(Sender: TObject);
begin
  OpenURL('https://github.com/unleashedpascal/installer');
end;

procedure TMainForm.MenuHelpDocsClick(Sender: TObject);
begin
  OpenURL('https://github.com/unleashedpascal/compiler/blob/main/unleashed/docs/README.md');
end;

procedure TMainForm.MenuHelpAboutClick(Sender: TObject);
begin
  ShowAbout(Self, Self.Caption);
end;

// first match wins; ordered most-severe to least so "Error: warning" renders red.
// the colon is part of the marker: without it every path holding a unit like
// ParseError.pas turns the compile line red. make announces its own failures
// with a '***' marker and no colon at all.
function ColorForLine(const s: string): TColor;
begin
  if (Pos('Error:', s) > 0) or (Pos('Fatal:', s) > 0) or (Pos('*** ', s) > 0) or (Pos('FAILED', s) > 0) or (Pos('failed:', s) > 0) then Result := clRed
  else if Pos('Warning:', s) > 0 then Result := clOlive
  else if (Pos('===', s) > 0) or (Pos(' ---', s) > 0) then Result := clNavy
  else if (Pos('Compiling ', s) > 0) or (Pos('Linking ', s) > 0) or (Pos('Installing ', s) > 0) then Result := TColor($008000) // dark green
  else if Pos('make[', s) > 0 then Result := clGray
  else Result := clWindowText;
end;

procedure TMainForm.ListBoxLogDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
begin
  var s := ListBoxLog.Items[Index];
  var cv := ListBoxLog.Canvas;
  if odSelected in State then begin
    cv.Brush.Color := clHighlight;
    cv.Font.Color := clHighlightText;
    cv.Font.Style := [];
  end else if Pos('IMPORTANT', s) > 0 then begin
    // banner: bold black on yellow
    cv.Brush.Color := clYellow;
    cv.Font.Color := clBlack;
    cv.Font.Style := [fsBold];
  end else begin
    cv.Brush.Color := clWindow;
    cv.Font.Color := ColorForLine(s);
    cv.Font.Style := [];
  end;
  cv.FillRect(ARect);
  cv.TextOut(ARect.Left+4, ARect.Top, s);
end;

procedure TMainForm.ButtonBrowseClick(Sender: TObject);
begin
  if SelectDirDialog.Execute then EditTargetDir.Text := SelectDirDialog.FileName;
end;

procedure TMainForm.SetInputsEnabled(act: Boolean);
begin
  CheckBoxInstallUnleashed.Enabled := act;
  CheckBoxInstallLazarus.Enabled := act;
  EditTargetDir.Enabled := act;
  ButtonBrowse.Enabled := act;
  // folder-error / shortcut-error gates win over act so post-install re-enable doesn't reopen Install when invalid
  ButtonInstall.Enabled := act and (not FFolderError) and (not FShortcutError);
  ApplyUnleashedEnabled;
  ApplyLazarusEnabled;
end;

{$ifdef LINUX}
// the IDE link step needs the -dev packages, not the .so.N the desktop runs
// on; without them the build dies after half an hour of compiling
function TMainForm.buildDepsReady: Boolean;
begin
  var deps := checkBuildDeps(CheckBoxInstallLazarus.Checked);
  result := deps.ok;
  if result then exit;

  FDepCommand := deps.command;
  Log('missing build dependencies: '+deps.missing);
  if deps.command <> '' then Log('run as root: '+deps.command);

  if deps.canAutoInstall then begin
    if MessageDlg('Missing build dependencies', 'The build needs '+deps.missing+
      '. Install the packages now? The system will ask for your password.', mtConfirmation, [mbYes, mbNo], 0) = mrYes then startDepInstall;
  end else if deps.command <> '' then MessageDlg('Missing build dependencies', 'The build needs '+deps.missing+
    '. Run this as root and start the install again: '+deps.command, mtWarning, [mbOK], 0)
  else MessageDlg('Missing build dependencies', 'The build needs '+deps.missing+
    '. Install the matching development packages of your distribution and start the install again.', mtWarning, [mbOK], 0);
end;

procedure TMainForm.startDepInstall;
begin
  if FInstalling or FDepInstalling or (FDepCommand = '') then exit;
  FDepInstalling := True;
  SetInputsEnabled(False);
  SetStatus('Installing packages');
  Log('--- pkexec '+FDepCommand+' ---');
  TDepInstallThread.Create(FDepCommand, @onDepLog, @onDepComplete);
end;

procedure TMainForm.onDepLog(const msg: string);
begin
  if GShuttingDown then exit;
  Log(msg);
end;

// the packages were only ever a detour, so a good install carries straight on
// into the install the user asked for
procedure TMainForm.onDepComplete(Sender: TObject);
begin
  if GShuttingDown then exit;
  FDepInstalling := False;
  SetInputsEnabled(True);
  var code := TDepInstallThread(Sender).ExitCode;
  if code = 0 then begin
    Log('packages installed');
    SetStatus('Ready');
    ButtonInstallClick(nil);
    exit;
  end;
  // 126 / 127: the password dialog was dismissed, or there was no agent to show it
  Log('package install failed (pkexec exit='+IntToStr(code)+')');
  SetStatus('Failed: package install');
  MessageDlg('Packages not installed', 'The package install ended with exit code '+IntToStr(code)+
    '. The log holds the command; running it in a terminal shows what went wrong.', mtError, [mbOK], 0);
end;
{$endif}

procedure TMainForm.OnInstallLog(const msg: string);
begin
  if GShuttingDown then exit;
  Log(msg);
end;

procedure TMainForm.OnInstallProgress(Percent: Integer; const status: string);
begin
  if GShuttingDown then exit;
  if Percent < 0 then begin
    ProgressBar.Style := pbstMarquee;
    SetStatus(status);
  end else begin
    ProgressBar.Style := pbstNormal;
    if Percent > 100 then Percent := 100;
    if Percent < 0 then Percent := 0;
    ProgressBar.Position := Percent;
    SetStatus(IntToStr(Percent)+'%  '+status);
  end;
end;

procedure TMainForm.OnInstallComplete(Sender: TObject);
begin
  if GShuttingDown then exit;
  var T := TInstallThread(Sender);
  ProgressBar.Style := pbstNormal;
  if T.Success then begin
    Log('=== INSTALL OK ===');
    SetStatus('Done');
    if FInstalledLazarus and CheckBoxLaunchAfter.Checked then LaunchInstalledIde;
  end else begin
    Log('=== INSTALL FAILED: '+T.ErrorMsg+' ===');
    SetStatus('Failed: '+T.ErrorMsg);
    ProgressBar.Position := 0;
  end;
  FInstalling := False;
{$ifdef WINDOWS}
  setComposited(True);
{$endif}
  SetInputsEnabled(True);
end;

procedure TMainForm.LaunchInstalledIde;
begin
  var ExePath := IncludeTrailingPathDelimiter(FInstallTargetDir)+LazarusBinarySub;
  var PcpArg  := '--pcp='+IncludeTrailingPathDelimiter(FInstallTargetDir)+'config_lazarus';
  Log('Launching '+ExePath);
{$ifdef WINDOWS}
  // detached. ShellExecute wants args as one string; quotes protect spaces in target dir
  var Args := '"'+PcpArg+'"';
  ShellExecute(Handle, 'open', PChar(ExePath), PChar(Args), PChar(ExtractFilePath(ExePath)), SW_SHOWNORMAL);
{$endif}
{$ifdef LINUX}
  // TProcess + no poWaitOnExit -> lazarus runs independently of installer (same as +x .desktop double-click)
  var P := TProcess.Create(nil);
  try
    P.Executable := ExePath;
    P.Parameters.Add(PcpArg);
    P.CurrentDirectory := ExtractFilePath(ExePath);
    P.Options := [];
    P.InheritHandles := False;
    P.Execute;
  finally
    // don't Free before Execute returns -- child is running; Free would lose our handle, OS reaps it on installer exit
    P.Free;
  end;
{$endif}
end;

procedure TMainForm.ButtonInstallClick(Sender: TObject);
var
  cfg: TInstallConfig;
begin
  if FInstalling or FDepInstalling then Exit;
  // belt-and-braces: button is disabled while these errors hold, but a stale OnClick race could still land here.
  // refuse before touching the disk (no dir creation) when the IDE would have no launch shortcut
  if FFolderError then Exit;
  if FShortcutError then Exit;

  cfg.TargetDir := Trim(EditTargetDir.Text);
  if cfg.TargetDir = '' then begin
    Log('install dir is empty');
    Exit;
  end;
{$ifdef LINUX}
  if not buildDepsReady then Exit;
{$endif}

  cfg.InstallFpc     := CheckBoxInstallUnleashed.Checked;
  cfg.InstallLazarus := CheckBoxInstallLazarus.Checked;
  // cross choices meaningless w/o FPC (no ppcx64 to drive crossinstall); force-off so pipeline doesn't try
  cfg.CrossWin64     := CheckBoxCrossWin64.Checked   and cfg.InstallFpc;
  cfg.CrossWin32     := CheckBoxCrossWin32.Checked   and cfg.InstallFpc;
  cfg.CrossLinux64   := CheckBoxCrossLinux64.Checked and cfg.InstallFpc;
  cfg.CrossLinux32   := CheckBoxCrossLinux32.Checked and cfg.InstallFpc;
  cfg.CrossWasm      := CheckBoxCrossWasm.Checked    and cfg.InstallFpc;
  // addons meaningless w/o IDE (lazbuild needs IDE)
  cfg.InstallMinimap          := CheckBoxMinimap.Checked          and cfg.InstallLazarus;
  cfg.InstallUnleashedMinimap := CheckBoxUnleashedMinimap.Checked and cfg.InstallLazarus;
  cfg.InstallCPUView          := CheckBoxCPUView.Checked          and cfg.InstallLazarus;
  cfg.InstallMetaDarkStyle    := CheckBoxMetaDarkStyle.Checked    and cfg.InstallLazarus;
  cfg.InstallHelpFiles        := CheckBoxHelpFiles.Checked        and cfg.InstallLazarus;
  // on linux this is always False (FormCreate locks Enabled+Checked=False), so no host ifdef needed
  cfg.InstallToggleAffinity   := CheckBoxToggleAffinity.Checked   and cfg.InstallLazarus;
  cfg.LaunchAfter    := CheckBoxLaunchAfter.Checked;
  // shortcuts only when installing the IDE; UI guarantees >=1 of these when InstallLazarus is on
  cfg.MakeDesktopShortcut := CheckBoxDesktopShortcut.Checked       and cfg.InstallLazarus;
  cfg.MakeFolderShortcut  := CheckBoxInstallFolderShortcut.Checked and cfg.InstallLazarus;

  // snapshot IDE install decision; OnInstallComplete combines with live CheckBoxLaunchAfter.Checked to decide launch
  FInstalledLazarus := cfg.InstallLazarus;
  FInstallTargetDir := cfg.TargetDir;
  cfg.FpcLatest      := CheckBoxUnleashedLatest.Checked;
  cfg.FpcBranch      := ComboBoxUnleashedBranch.Text;
  cfg.FpcHash        := Trim(EditUnleashedHash.Text);
  cfg.LazLatest      := CheckBoxLazarusLatest.Checked;
  cfg.LazBranch      := ComboBoxLazarusBranch.Text;
  cfg.LazHash        := Trim(EditLazarusHash.Text);
  // resolved SHA into manifest for later compare; empty if branch list not yet loaded
  cfg.FpcSelectedSha := ResolveSelectedFpcSha;
  cfg.LazSelectedSha := ResolveSelectedLazSha;
  cfg.SaveLog        := CheckBoxSaveLog.Checked;

  Log('--- install requested ---');
  Log('target dir: '+cfg.TargetDir);
  if cfg.InstallFpc then Log('install compiler: yes ('+cfg.FpcBranch+')') else Log('install compiler: no');
  if cfg.InstallLazarus then Log('install IDE:      yes ('+cfg.LazBranch+')') else Log('install IDE:      no');

  FInstalling := True;
{$ifdef WINDOWS}
  setComposited(False);
{$endif}
  SetInputsEnabled(False);
  ProgressBar.Position := 0;
  ProgressBar.Style := pbstNormal;

  TInstallThread.Create(cfg, @OnInstallLog, @OnInstallProgress, @OnInstallComplete);
end;

procedure TMainForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
