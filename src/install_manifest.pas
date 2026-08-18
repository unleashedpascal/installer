{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit install_manifest;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  // snapshot of installed state; lets re-run decide skip vs refresh against current selection
  TInstallManifest = record
    Present: Boolean;
    FpcBranch: string;
    FpcSha: string;
    // True iff CheckBoxLatest was ticked at install time; FpcSha still holds resolved SHA for display/compare
    FpcLatest: Boolean;
    LazBranch: string;
    LazSha: string;
    LazLatest: Boolean;
    CrossWin64: Boolean;       // cross to x86_64-win64 (only built on linux64 host)
    CrossWin32: Boolean;       // legacy 32-bit
    CrossLinux64: Boolean;     // cross to x86_64-linux (only built on win64 host)
    CrossLinux32: Boolean;     // legacy 32-bit
    CrossWasm: Boolean;
    // optional IDE addons -- written so a re-run can pre-tick the right checkboxes
    InstallMinimap: Boolean;
    InstallUnleashedMinimap: Boolean;
    InstallCPUView: Boolean;
    // windows-only design-time plugin; field exists everywhere so manifest is portable across hosts
    InstallToggleAffinity: Boolean;
    // MetaDarkStyle (runtime) + metadarkstyledsgn (design-time), travel together
    InstallMetaDarkStyle: Boolean;
    // CHM documentation present in <lazarus>\docs\chm; recorded from disk
    // state, not from the checkbox, so a failed download does not claim it
    InstallHelpFiles: Boolean;
    // last launch-after-install state, restored to checkbox on re-run
    LaunchAfter: Boolean;
    // which IDE launch shortcuts were created (at least one is required by the UI)
    MakeDesktopShortcut: Boolean;
    MakeFolderShortcut: Boolean;
    InstalledAt: string;
    // absolute path to install root recorded at write time; useful for tooling that
    // wants to locate the install without re-running the picker
    InstallPath: string;
  end;

const
  MANIFEST_FILE = 'installer.ini';

function ManifestPathFor(const InstallDir: string): string;
function ReadManifest(const InstallDir: string): TInstallManifest;
function WriteManifest(const InstallDir: string; const M: TInstallManifest): Boolean;

implementation

function ManifestPathFor(const InstallDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(InstallDir)+MANIFEST_FILE;
end;

function StrToBoolDefSafe(const S: string; const Def: Boolean): Boolean;
begin
  if (S = 'yes') or (S = 'true') or (S = '1') then Result := True
  else if (S = 'no') or (S = 'false') or (S = '0') then Result := False
  else Result := Def;
end;

function BoolFlag(B: Boolean): string;
begin
  if B then Result := 'yes' else Result := 'no';
end;

function ReadManifest(const InstallDir: string): TInstallManifest;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Present := False;
  var Path := ManifestPathFor(InstallDir);
  if not FileExists(Path) then Exit;

  var Lines := autofree TStringList.Create;
  Lines.NameValueSeparator := '=';
  try
    Lines.LoadFromFile(Path);
  except
    Exit;
  end;
  Result.FpcBranch    := Lines.Values['fpc-branch'];
  Result.FpcSha       := LowerCase(Lines.Values['fpc-sha']);
  // pre-fpc-latest manifests: True iff SHA empty (legacy "empty SHA == latest")
  Result.FpcLatest    := StrToBoolDefSafe(Lines.Values['fpc-latest'], Result.FpcSha = '');
  Result.LazBranch    := Lines.Values['lazarus-branch'];
  Result.LazSha       := LowerCase(Lines.Values['lazarus-sha']);
  Result.LazLatest    := StrToBoolDefSafe(Lines.Values['lazarus-latest'], Result.LazSha = '');
  Result.CrossWin64   := StrToBoolDefSafe(Lines.Values['cross-x86_64-win64'], False);
  Result.CrossWin32   := StrToBoolDefSafe(Lines.Values['cross-i386-win32'], False);
  Result.CrossLinux64 := StrToBoolDefSafe(Lines.Values['cross-x86_64-linux'], False);
  Result.CrossLinux32 := StrToBoolDefSafe(Lines.Values['cross-i386-linux'], False);
  // accept legacy 'cross-wasm32-wasi' key so historical flag survives
  Result.CrossWasm    := StrToBoolDefSafe(Lines.Values['cross-wasm32-wasip1'], StrToBoolDefSafe(Lines.Values['cross-wasm32-wasi'], False));
  Result.InstallMinimap          := StrToBoolDefSafe(Lines.Values['extras-minimap'], False);
  Result.InstallUnleashedMinimap := StrToBoolDefSafe(Lines.Values['extras-unleashed-minimap'], False);
  Result.InstallCPUView          := StrToBoolDefSafe(Lines.Values['extras-cpuview'], False);
  Result.InstallToggleAffinity   := StrToBoolDefSafe(Lines.Values['extras-toggle-affinity'], False);
  Result.InstallMetaDarkStyle    := StrToBoolDefSafe(Lines.Values['extras-metadarkstyle'], False);
  Result.InstallHelpFiles        := StrToBoolDefSafe(Lines.Values['help-chm'], False);
  Result.LaunchAfter  := StrToBoolDefSafe(Lines.Values['launch-after-install'], True);
  // legacy installs always made a desktop shortcut -> default True; folder shortcut is new -> default False
  Result.MakeDesktopShortcut := StrToBoolDefSafe(Lines.Values['shortcut-desktop'], True);
  Result.MakeFolderShortcut  := StrToBoolDefSafe(Lines.Values['shortcut-install-folder'], False);
  Result.InstalledAt  := Lines.Values['installed-at'];
  Result.InstallPath  := Lines.Values['install-path'];
  Result.Present      := True;
end;

function WriteManifest(const InstallDir: string; const M: TInstallManifest): Boolean;
begin
  Result := False;
  var Lines := autofree TStringList.Create;
  Lines.Add('# Unleashed Installer manifest - written automatically');
  Lines.Add('# Do not edit; the installer relies on these values to detect updates.');
  Lines.Add('fpc-branch='+M.FpcBranch);
  Lines.Add('fpc-sha='+LowerCase(M.FpcSha));
  Lines.Add('fpc-latest='+BoolFlag(M.FpcLatest));
  Lines.Add('lazarus-branch='+M.LazBranch);
  Lines.Add('lazarus-sha='+LowerCase(M.LazSha));
  Lines.Add('lazarus-latest='+BoolFlag(M.LazLatest));
  Lines.Add('cross-x86_64-win64='+BoolFlag(M.CrossWin64));
  Lines.Add('cross-i386-win32='+BoolFlag(M.CrossWin32));
  Lines.Add('cross-x86_64-linux='+BoolFlag(M.CrossLinux64));
  Lines.Add('cross-i386-linux='+BoolFlag(M.CrossLinux32));
  Lines.Add('cross-wasm32-wasip1='+BoolFlag(M.CrossWasm));
  Lines.Add('extras-minimap='+BoolFlag(M.InstallMinimap));
  Lines.Add('extras-unleashed-minimap='+BoolFlag(M.InstallUnleashedMinimap));
  Lines.Add('extras-cpuview='+BoolFlag(M.InstallCPUView));
  Lines.Add('extras-toggle-affinity='+BoolFlag(M.InstallToggleAffinity));
  Lines.Add('extras-metadarkstyle='+BoolFlag(M.InstallMetaDarkStyle));
  Lines.Add('help-chm='+BoolFlag(M.InstallHelpFiles));
  Lines.Add('launch-after-install='+BoolFlag(M.LaunchAfter));
  Lines.Add('shortcut-desktop='+BoolFlag(M.MakeDesktopShortcut));
  Lines.Add('shortcut-install-folder='+BoolFlag(M.MakeFolderShortcut));
  Lines.Add('installed-at='+M.InstalledAt);
  Lines.Add('install-path='+M.InstallPath);
  try
    Lines.SaveToFile(ManifestPathFor(InstallDir));
    Result := True;
  except
    // best effort
  end;
end;

end.
