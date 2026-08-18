{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit app_settings;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  // installer's own preferences, stored next to the binary. Distinct from
  // install_manifest, which describes one installed tree and lives inside it
  TAppSettings = record
    Present: Boolean;
    // restored bounds (never the maximized ones -- see Maximized)
    WindowLeft, WindowTop, WindowWidth, WindowHeight: Integer;
    WindowMaximized: Boolean;
    TargetDir: string;
    FpcBranch, LazBranch: string;
    // pinned commits and the "track branch head" flags that shadow them
    FpcHash, LazHash: string;
    FpcLatest, LazLatest: Boolean;
    InstallFpc, InstallLazarus: Boolean;
    // checkbox state carried into a target dir that has no manifest
    CrossWin64, CrossWin32, CrossLinux64, CrossLinux32, CrossWasm: Boolean;
    InstallMinimap, InstallUnleashedMinimap, InstallCPUView, InstallToggleAffinity, InstallMetaDarkStyle, InstallHelpFiles: Boolean;
    MakeDesktopShortcut, MakeFolderShortcut: Boolean;
    LaunchAfter, SaveLog: Boolean;
  end;

const
  SETTINGS_FILE = 'installer_settings.ini';

function settingsPath: string;
function readSettings: TAppSettings;
function writeSettings(const s: TAppSettings): Boolean;

implementation

function settingsPath: string;
begin
  result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+SETTINGS_FILE;
end;

function boolFlag(b: Boolean): string;
begin
  if b then result := 'yes' else result := 'no';
end;

function toBool(const s: string; def: Boolean): Boolean;
begin
  if (s = 'yes') or (s = 'true') or (s = '1') then result := True
  else if (s = 'no') or (s = 'false') or (s = '0') then result := False
  else result := def;
end;

function readSettings: TAppSettings;
begin
  FillChar(result, SizeOf(result), 0);
  var path := settingsPath;
  if not FileExists(path) then exit;

  var lines := autofree TStringList.Create;
  lines.NameValueSeparator := '=';
  try
    lines.LoadFromFile(path);
  except
    exit;
  end;

  result.WindowLeft      := StrToIntDef(lines.Values['window-left'], 0);
  result.WindowTop       := StrToIntDef(lines.Values['window-top'], 0);
  result.WindowWidth     := StrToIntDef(lines.Values['window-width'], 0);
  result.WindowHeight    := StrToIntDef(lines.Values['window-height'], 0);
  result.WindowMaximized := toBool(lines.Values['window-maximized'], False);
  result.TargetDir       := lines.Values['target-dir'];
  result.FpcBranch       := lines.Values['fpc-branch'];
  result.LazBranch       := lines.Values['lazarus-branch'];
  result.FpcHash         := lines.Values['fpc-hash'];
  result.LazHash         := lines.Values['lazarus-hash'];
  result.FpcLatest       := toBool(lines.Values['fpc-latest'], True);
  result.LazLatest       := toBool(lines.Values['lazarus-latest'], True);
  result.InstallFpc      := toBool(lines.Values['install-fpc'], True);
  result.InstallLazarus  := toBool(lines.Values['install-lazarus'], True);
  result.CrossWin64      := toBool(lines.Values['cross-x86_64-win64'], False);
  result.CrossWin32      := toBool(lines.Values['cross-i386-win32'], False);
  result.CrossLinux64    := toBool(lines.Values['cross-x86_64-linux'], False);
  result.CrossLinux32    := toBool(lines.Values['cross-i386-linux'], False);
  result.CrossWasm       := toBool(lines.Values['cross-wasm32-wasip1'], False);
  result.InstallMinimap          := toBool(lines.Values['extras-minimap'], False);
  result.InstallUnleashedMinimap := toBool(lines.Values['extras-unleashed-minimap'], True);
  result.InstallCPUView          := toBool(lines.Values['extras-cpuview'], True);
  result.InstallToggleAffinity   := toBool(lines.Values['extras-toggle-affinity'], False);
  result.InstallMetaDarkStyle    := toBool(lines.Values['extras-metadarkstyle'], False);
  result.InstallHelpFiles        := toBool(lines.Values['help-chm'], True);
  result.MakeDesktopShortcut   := toBool(lines.Values['shortcut-desktop'], True);
  result.MakeFolderShortcut    := toBool(lines.Values['shortcut-install-folder'], True);
  result.LaunchAfter           := toBool(lines.Values['launch-after-install'], True);
  result.SaveLog               := toBool(lines.Values['save-log'], False);
  result.Present := True;
end;

function writeSettings(const s: TAppSettings): Boolean;
begin
  result := False;
  var lines := autofree TStringList.Create;
  lines.Add('# Unleashed Installer settings - written on exit');
  lines.Add('window-left='+IntToStr(s.WindowLeft));
  lines.Add('window-top='+IntToStr(s.WindowTop));
  lines.Add('window-width='+IntToStr(s.WindowWidth));
  lines.Add('window-height='+IntToStr(s.WindowHeight));
  lines.Add('window-maximized='+boolFlag(s.WindowMaximized));
  lines.Add('target-dir='+s.TargetDir);
  lines.Add('fpc-branch='+s.FpcBranch);
  lines.Add('lazarus-branch='+s.LazBranch);
  lines.Add('fpc-hash='+s.FpcHash);
  lines.Add('lazarus-hash='+s.LazHash);
  lines.Add('fpc-latest='+boolFlag(s.FpcLatest));
  lines.Add('lazarus-latest='+boolFlag(s.LazLatest));
  lines.Add('install-fpc='+boolFlag(s.InstallFpc));
  lines.Add('install-lazarus='+boolFlag(s.InstallLazarus));
  lines.Add('cross-x86_64-win64='+boolFlag(s.CrossWin64));
  lines.Add('cross-i386-win32='+boolFlag(s.CrossWin32));
  lines.Add('cross-x86_64-linux='+boolFlag(s.CrossLinux64));
  lines.Add('cross-i386-linux='+boolFlag(s.CrossLinux32));
  lines.Add('cross-wasm32-wasip1='+boolFlag(s.CrossWasm));
  lines.Add('extras-minimap='+boolFlag(s.InstallMinimap));
  lines.Add('extras-unleashed-minimap='+boolFlag(s.InstallUnleashedMinimap));
  lines.Add('extras-cpuview='+boolFlag(s.InstallCPUView));
  lines.Add('extras-toggle-affinity='+boolFlag(s.InstallToggleAffinity));
  lines.Add('extras-metadarkstyle='+boolFlag(s.InstallMetaDarkStyle));
  lines.Add('help-chm='+boolFlag(s.InstallHelpFiles));
  lines.Add('shortcut-desktop='+boolFlag(s.MakeDesktopShortcut));
  lines.Add('shortcut-install-folder='+boolFlag(s.MakeFolderShortcut));
  lines.Add('launch-after-install='+boolFlag(s.LaunchAfter));
  lines.Add('save-log='+boolFlag(s.SaveLog));
  try
    lines.SaveToFile(settingsPath);
    result := True;
  except
    // read-only dir (Program Files, mounted image): preferences are a
    // nice-to-have, never a reason to fail on exit
  end;
end;

end.
