{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit shortcut_util;

{$mode unleashed}

interface

// desktop shortcut. Windows: .lnk via IShellLinkW; Linux: .desktop in ~/Desktop/ + ~/.local/share/applications/
// name taken => ' (N)' is appended, N counting up from 2, so an existing shortcut is never overwritten; on Linux each dir is numbered on its own
function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
// shortcut placed directly inside Dir (the install folder). Windows: Dir\Name.lnk; Linux: Dir/<sanitized>.desktop
function CreateFolderShortcut(const Dir, TargetPath, Args, ShortcutName: string): Boolean;
// true when the desktop already holds a shortcut launching targetPath, under any file name (the user may have renamed it)
function desktopShortcutExists(const targetPath: string): boolean;
// same check for shortcuts placed directly inside dir
function folderShortcutExists(const dir, targetPath: string): boolean;

implementation

uses
  SysUtils
  {$ifdef WINDOWS}, Windows, ActiveX, ComObj, ShlObj{$endif}
  {$ifdef LINUX}, Classes, proc_util{$endif};

{$ifdef WINDOWS}
function GetDesktopPath: string;
var
  Buf: array[0..MAX_PATH] of AnsiChar;
begin
  Result := '';
  // CSIDL_DESKTOPDIRECTORY = physical per-user desktop dir; CSIDL_DESKTOP is the virtual folder (My Computer etc)
  if SHGetFolderPathA(0, CSIDL_DESKTOPDIRECTORY, 0, 0, @Buf[0]) = S_OK then Result := AnsiString(Buf);
end;

// write a .lnk at LnkPath pointing at TargetPath with Args; icon index 0 = first group in the exe
function WriteLnk(const LnkPath, TargetPath, Args: string): Boolean;
begin
  Result := False;
  if FAILED(CoInitialize(nil)) then Exit;
  try
    var Link: IShellLinkW := CreateComObject(CLSID_ShellLink) as IShellLinkW;
    var WTarget: WideString := UTF8Decode(TargetPath);
    Link.SetPath(PWideChar(WTarget));
    if Args <> '' then begin
      var WArgs: WideString := UTF8Decode(Args);
      Link.SetArguments(PWideChar(WArgs));
    end;
    var WWorkDir: WideString := UTF8Decode(ExtractFilePath(TargetPath));
    Link.SetWorkingDirectory(PWideChar(WWorkDir));
    Link.SetIconLocation(PWideChar(WTarget), 0);
    var Persist: IPersistFile := Link as IPersistFile;
    var WLnkPath: WideString := UTF8Decode(LnkPath);
    Result := Persist.Save(PWideChar(WLnkPath), True) = S_OK;
  finally
    CoUninitialize;
  end;
end;

function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  var DesktopDir := GetDesktopPath;
  if DesktopDir = '' then Exit;
  var Base := IncludeTrailingPathDelimiter(DesktopDir);
  var LnkPath := Base+ShortcutName+'.lnk';
  var N := 2;
  while FileExists(LnkPath) do begin
    LnkPath := Base+ShortcutName+' ('+IntToStr(N)+').lnk';
    Inc(N);
  end;
  Result := WriteLnk(LnkPath, TargetPath, Args);
end;

function CreateFolderShortcut(const Dir, TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  if Dir = '' then Exit;
  ForceDirectories(Dir);
  Result := WriteLnk(IncludeTrailingPathDelimiter(Dir)+ShortcutName+'.lnk', TargetPath, Args);
end;

// true when any .lnk directly inside dir points at targetPath; SLGP_RAWPATH returns the stored path without resolving it
function dirHasLnkTo(const dir, targetPath: string): boolean;
var sr: TSearchRec;
begin
  result := false;
  if FAILED(CoInitialize(nil)) then exit;
  try
    var link: IShellLinkW := CreateComObject(CLSID_ShellLink) as IShellLinkW;
    var persist: IPersistFile := link as IPersistFile;
    var want := LowerCase(targetPath);
    var buf: array[MAX_PATH] of WideChar;
    var base := IncludeTrailingPathDelimiter(dir);
    if FindFirst(base+'*.lnk', faAnyFile, sr) = 0 then try
      repeat
        var wLnk: WideString := UTF8Decode(base+sr.Name);
        if FAILED(persist.Load(PWideChar(wLnk), STGM_READ)) then Continue;
        if FAILED(link.GetPath(@buf[0], MAX_PATH, nil, SLGP_RAWPATH)) then Continue;
        if LowerCase(UTF8Encode(WideString(PWideChar(@buf[0])))) = want then exit(true);
      until FindNext(sr) <> 0;
    finally
      SysUtils.FindClose(sr);
    end;
  finally
    CoUninitialize;
  end;
end;

function desktopShortcutExists(const targetPath: string): boolean;
begin
  var desktopDir := GetDesktopPath;
  result := (desktopDir <> '') and (dirHasLnkTo(desktopDir, targetPath));
end;

function folderShortcutExists(const dir, targetPath: string): boolean;
begin
  result := (dir <> '') and (dirHasLnkTo(dir, targetPath));
end;
{$endif}

{$ifdef LINUX}
// XDG Desktop Entry body; Categories=Development;IDE; lands under Programming on GNOME/KDE/Cinnamon/XFCE
function BuildDesktopEntry(const TargetPath, Args, ShortcutName: string): string;
begin
  var ExecLine := TargetPath;
  if Args <> '' then ExecLine := TargetPath+' '+Args;
  // probe icon names; Lazarus 2.x: ide_icon.png, 3.x: ide_icon48x48.png, 4.x+: ide_icon128x128.png. Missing Icon= => placeholder
  var LazDir := IncludeTrailingPathDelimiter(ExtractFilePath(TargetPath))+'images/';
  var IconCandidates: array of string := [LazDir+'ide_icon128x128.png', LazDir+'ide_icon48x48.png', LazDir+'ide_icon.png'];
  var IconPath: string := '';
  for var i := Low(IconCandidates) to High(IconCandidates) do
    if FileExists(IconCandidates[i]) then begin
      IconPath := IconCandidates[i];
      Break;
    end;
  Result := '[Desktop Entry]'#10+'Type=Application'#10+'Version=1.0'#10+'Name='+ShortcutName+#10+'Comment=Unleashed Pascal IDE'#10+'Exec='+ExecLine+#10+
            (if IconPath <> '' then 'Icon='+IconPath+#10 else '')+'Terminal=false'#10+'Categories=Development;IDE;'#10+'StartupNotify=false'#10;
end;

function WriteDesktopFile(const Path, Body: string): Boolean;
begin
  Result := False;
  ForceDirectories(ExtractFilePath(Path));
  try
    var Sl := autofree TStringList.Create;
    Sl.Text := Body;
    Sl.SaveToFile(Path);
  except
    Exit;
  end;
  // GNOME 3.34+ wants 0755 for double-click launch; KDE doesn't care. Best-effort; failure non-fatal
  RunSilent('/bin/chmod', ['0755', Path]);
  Result := True;
end;

// ascii letters/digits/dot/dash/underscore; whitespace -> '-'; everything else dropped
function SanitizeName(const ShortcutName: string): string;
begin
  Result := '';
  for var i := 1 to Length(ShortcutName) do begin
    var c := ShortcutName[i];
    case c of
      'A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_': Result := Result+c;
      ' ', #9: Result := Result+'-';
    end;
  end;
  if Result = '' then Result := 'unleashed-pascal-ide';
end;

function CreateFolderShortcut(const Dir, TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  if Dir = '' then Exit;
  var Body := BuildDesktopEntry(TargetPath, Args, ShortcutName);
  Result := WriteDesktopFile(IncludeTrailingPathDelimiter(Dir)+SanitizeName(ShortcutName)+'.desktop', Body);
end;

// true when any .desktop directly inside dir has an Exec= line launching targetPath (bare or followed by arguments)
function dirHasDesktopEntryTo(const dir, targetPath: string): boolean;
var sr: TSearchRec;
begin
  result := false;
  var base := IncludeTrailingPathDelimiter(dir);
  if FindFirst(base+'*.desktop', faAnyFile, sr) = 0 then try
    var lines := autofree TStringList.Create;
    repeat
      try
        lines.LoadFromFile(base+sr.Name);
      except
        Continue;
      end;
      var execLine := lines.Values['Exec'];
      if (execLine = targetPath) or (Pos(targetPath+' ', execLine) = 1) then exit(true);
    until FindNext(sr) <> 0;
  finally
    SysUtils.FindClose(sr);
  end;
end;

function desktopDir: string;
begin
  result := '';
  var home := GetEnvironmentVariable('HOME');
  if home <> '' then result := IncludeTrailingPathDelimiter(home)+'Desktop/';
end;

function menuDir: string;
begin
  result := '';
  var home := GetEnvironmentVariable('HOME');
  if home <> '' then result := IncludeTrailingPathDelimiter(home)+'.local/share/applications/';
end;

// one entry per dir: an entry already launching targetPath there is left alone, otherwise a new one is written,
// named after shortcutName with ' (N)' appended while that name is taken in this dir (and only this dir)
function ensureDesktopEntry(const dir, targetPath, args, shortcutName: string): boolean;
begin
  if dirHasDesktopEntryTo(dir, targetPath) then exit(true);
  var displayName := shortcutName;
  var fileBase := SanitizeName(displayName);
  var n := 2;
  while FileExists(dir+fileBase+'.desktop') do begin
    displayName := shortcutName+' ('+IntToStr(n)+')';
    fileBase := SanitizeName(displayName);
    Inc(n);
  end;
  result := WriteDesktopFile(dir+fileBase+'.desktop', BuildDesktopEntry(targetPath, args, displayName));
end;

function CreateDesktopShortcut(const TargetPath, Args, ShortcutName: string): Boolean;
begin
  Result := False;
  if desktopDir = '' then exit;
  // best-effort: write both. Succeed if either lands
  var wroteDesktop := ensureDesktopEntry(desktopDir, TargetPath, Args, ShortcutName);
  var wroteMenu := ensureDesktopEntry(menuDir, TargetPath, Args, ShortcutName);
  result := (wroteDesktop) or (wroteMenu);
end;

// both places must hold an entry, so a missing one is recreated by CreateDesktopShortcut without touching the other
function desktopShortcutExists(const targetPath: string): boolean;
begin
  result := (desktopDir <> '') and (dirHasDesktopEntryTo(desktopDir, targetPath)) and (dirHasDesktopEntryTo(menuDir, targetPath));
end;

function folderShortcutExists(const dir, targetPath: string): boolean;
begin
  result := (dir <> '') and (dirHasDesktopEntryTo(dir, targetPath));
end;
{$endif}

end.
