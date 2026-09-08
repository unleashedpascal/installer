{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit path_env;

{$mode unleashed}

// per-user PATH entry for the FPC binaries. Windows: HKCU\Environment;
// Linux: a marked block appended to ~/.profile

interface

uses
  Classes, SysUtils;

type
  TPathLogEvent = procedure(const msg: string) of object;

function pathHasDir(const dir: string): Boolean;
function addToPath(const dir: string; log: TPathLogEvent): Boolean;
function removeFromPath(const dir: string; log: TPathLogEvent): Boolean;

implementation

{$ifdef WINDOWS}
uses
  Registry, Windows;
{$endif}

const
{$ifdef WINDOWS}
  LIST_SEP = ';';
{$else}
  LIST_SEP = ':';
{$endif}

// a trailing delimiter or different casing must not make one entry look like two
function samePath(const a, b: string): Boolean;
begin
  var x := ExcludeTrailingPathDelimiter(Trim(a));
  var y := ExcludeTrailingPathDelimiter(Trim(b));
{$ifdef WINDOWS}
  result := SameText(x, y);
{$else}
  result := x = y;
{$endif}
end;

// split a PATH-style list, dropping empty entries
function splitList(const s: string): TStringArray;
begin
  result := nil;
  var cur := '';
  for var i := 1 to Length(s) do
    if s[i] = LIST_SEP then begin
      if Trim(cur) <> '' then result := Concat(result, [Trim(cur)]);
      cur := '';
    end else
      cur := cur + s[i];
  if Trim(cur) <> '' then result := Concat(result, [Trim(cur)]);
end;

function envHasDir(const dir: string): Boolean;
begin
  result := False;
  for var p in splitList(SysUtils.GetEnvironmentVariable('PATH')) do
    if samePath(p, dir) then exit(True);
end;

{$ifdef WINDOWS}
const
  ENV_KEY = 'Environment';

function readUserPath(out expand: Boolean): string;
begin
  result := '';
  expand := False;
  var reg := autofree TRegistry.Create;
  reg.RootKey := HKEY_CURRENT_USER;
  if not reg.OpenKeyReadOnly(ENV_KEY) then exit;
  if reg.ValueExists('Path') then begin
    expand := reg.GetDataType('Path') = rdExpandString;
    result := reg.ReadString('Path');
  end;
  reg.CloseKey;
end;

function writeUserPath(const value: string; expand: Boolean): Boolean;
begin
  var reg := autofree TRegistry.Create;
  reg.RootKey := HKEY_CURRENT_USER;
  result := reg.OpenKey(ENV_KEY, True);
  if not result then exit;
  // an entry like %USERPROFILE%\bin stops resolving if the value turns into a plain string
  if expand or (Pos('%', value) > 0) then reg.WriteExpandString('Path', value)
  else reg.WriteString('Path', value);
  reg.CloseKey;
  // without the broadcast Explorer and everything started from it keeps the old PATH until logoff
  SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
    LPARAM(PWideChar(WideString(ENV_KEY))), SMTO_ABORTIFHUNG, 5000, nil);
end;

function pathHasDir(const dir: string): Boolean;
begin
  result := False;
  if dir = '' then exit;
  var expand: Boolean;
  for var p in splitList(readUserPath(expand)) do
    if samePath(p, dir) then exit(True);
  result := envHasDir(dir);
end;

function addToPath(const dir: string; log: TPathLogEvent): Boolean;
begin
  if pathHasDir(dir) then begin
    log('PATH already has '+dir);
    exit(True);
  end;
  var expand: Boolean;
  var cur := readUserPath(expand);
  if (cur <> '') and (cur[Length(cur)] <> LIST_SEP) then cur := cur+LIST_SEP;
  result := writeUserPath(cur+dir, expand);
  if result then log('added to user PATH: '+dir)
  else log('  ERROR: cannot write HKCU\'+ENV_KEY);
  if result then log('  open a new terminal for it to take effect');
end;

function removeFromPath(const dir: string; log: TPathLogEvent): Boolean;
begin
  var expand: Boolean;
  var cur := readUserPath(expand);
  var kept := '';
  var hit := False;
  for var p in splitList(cur) do
    if samePath(p, dir) then hit := True
    else begin
      if kept <> '' then kept := kept+LIST_SEP;
      kept := kept+p;
    end;
  if not hit then begin
    log('user PATH does not have '+dir);
    exit(True);
  end;
  result := writeUserPath(kept, expand);
  if result then log('removed from user PATH: '+dir)
  else log('  ERROR: cannot write HKCU\'+ENV_KEY);
  if result then log('  open a new terminal for it to take effect');
end;
{$endif}

{$ifdef LINUX}
const
  MARK_BEGIN = '# >>> unleashed pascal >>>';
  MARK_END   = '# <<< unleashed pascal <<<';

function profilePath: string;
begin
  result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME'))+'.profile';
end;

// index of MARK_BEGIN, -1 when the block is not there
function blockStart(lines: TStrings): Integer;
begin
  for var i := 0 to lines.Count-1 do
    if Trim(lines[i]) = MARK_BEGIN then exit(i);
  result := -1;
end;

function pathHasDir(const dir: string): Boolean;
begin
  result := False;
  if dir = '' then exit;
  if FileExists(profilePath) then begin
    var lines := autofree TStringList.Create;
    lines.LoadFromFile(profilePath);
    var i := blockStart(lines);
    if i >= 0 then
      for var j := i to lines.Count-1 do begin
        if Pos(dir, lines[j]) > 0 then exit(True);
        if Trim(lines[j]) = MARK_END then Break;
      end;
  end;
  result := envHasDir(dir);
end;

function addToPath(const dir: string; log: TPathLogEvent): Boolean;
begin
  result := False;
  if pathHasDir(dir) then begin
    log('PATH already has '+dir);
    exit(True);
  end;
  var lines := autofree TStringList.Create;
  if FileExists(profilePath) then lines.LoadFromFile(profilePath);
  lines.Add(MARK_BEGIN);
  lines.Add('export PATH="'+dir+':$PATH"');
  lines.Add(MARK_END);
  try
    lines.SaveToFile(profilePath);
    result := True;
  except
    on E: Exception do log('  ERROR: cannot write '+profilePath+': '+E.Message);
  end;
  if result then begin
    log('added to PATH in '+profilePath+': '+dir);
    log('  log in again for it to take effect');
  end;
end;

function removeFromPath(const dir: string; log: TPathLogEvent): Boolean;
begin
  result := False;
  if not FileExists(profilePath) then begin
    log(profilePath+' does not have a PATH entry');
    exit(True);
  end;
  var lines := autofree TStringList.Create;
  lines.LoadFromFile(profilePath);
  var i := blockStart(lines);
  if i < 0 then begin
    log(profilePath+' does not have a PATH entry');
    exit(True);
  end;
  // markers included; an unterminated block means everything from here on is ours
  var last := lines.Count-1;
  for var j := i to lines.Count-1 do
    if Trim(lines[j]) = MARK_END then begin
      last := j;
      Break;
    end;
  for var j := last downto i do lines.Delete(j);
  try
    lines.SaveToFile(profilePath);
    result := True;
  except
    on E: Exception do log('  ERROR: cannot write '+profilePath+': '+E.Message);
  end;
  if result then begin
    log('removed from PATH in '+profilePath+': '+dir);
    log('  log in again for it to take effect');
  end;
end;
{$endif}

end.
