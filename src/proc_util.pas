{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit proc_util;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  TLineCallback = procedure(const Line: string) of object;

// run silently, block until exit. stdout/stderr dropped. -1 on launch failure
function RunSilent(const Exe: string; const Args: array of string; const WorkDir: string = ''): Integer;

// run with stdout+stderr captured line-by-line into OnLine. ExtraPath is prepended to child PATH ('' to inherit)
function RunStream(const Exe: string; const Args: array of string; const WorkDir: string; const ExtraPath: string; OnLine: TLineCallback): Integer;

var
  // dir holding the fpc.cfg we generated; forced into every child as
  // PPC_CONFIG_PATH so a user-level fpc.cfg can not outrank it
  fpcConfigDir: string = '';

implementation

uses
  process;

const
  READ_BUF = 4096;

function RunSilent(const Exe: string; const Args: array of string; const WorkDir: string): Integer;
begin
  var P := autofree TProcess.Create(nil);
  P.Executable := Exe;
  for var i := Low(Args) to High(Args) do P.Parameters.Add(Args[i]);
  if WorkDir <> '' then P.CurrentDirectory := WorkDir;
  P.Options := [poNoConsole, poWaitOnExit];
  P.ShowWindow := swoHide;
  try
    P.Execute;
    Result := P.ExitCode;
  except
    on E: Exception do Result := -1;
  end;
end;

{$ifdef LINUX}
// WSL/Wine mounts on PATH can expose Windows GNU-utils (pwd.exe & co); FPC's generated makefiles probe every PATH dir for pwd.exe
// and on a hit switch tool names to .exe + take basedir from the Windows pwd (a //wsl.localhost UNC the native compiler can't open)
function strippwdexedirs(const path: string): string;
begin
  result := '';
  for var dir in path.Split([':']) do begin
    if (dir <> '') and FileExists(IncludeTrailingPathDelimiter(dir)+'pwd.exe') then Continue;
    if result <> '' then result += ':';
    result += dir;
  end;
end;
{$endif}

// vars from an earlier FPC install on the host that redirect the compiler at foreign units or a foreign config:
// FPCDIR feeds the built-in <dir>/units/<target>/rtl fallback, <TARGET>UNITS extends the unit path, PPC_CONFIG_PATH
// picks the fpc.cfg. FPCDIR and <TARGET>UNITS apply even when the right fpc.cfg loads (only -n disables them, and
// make-driven fpc calls don't pass it), so pinning the cfg alone is not enough. Left in place they silently mix a
// stranger's .ppu into our build (token replay then fails mid-generic with a bogus parse error).
function redirectsFpcSearch(const name: string): Boolean;
begin
  result := (name = 'FPCDIR') or (name = 'PPC_CONFIG_PATH') or (name = 'WIN32UNITS') or (name = 'WIN64UNITS') or (name = 'LINUXUNITS');
end;

// copy parent env, optionally prepend Prefix to PATH, strip MAKEFLAGS/MFLAGS (would poison child `make`)
procedure ApplyEnvWithPathPrefix(P: TProcess; const Prefix: string);
begin
  var pathSeen := False;
  for var i := 0 to GetEnvironmentVariableCount-1 do begin
    var envLine := GetEnvironmentString(i);
    if envLine = '' then Continue;
    var eqPos := Pos('=', envLine);
    if eqPos < 2 then Continue;
    var name := UpperCase(Copy(envLine, 1, eqPos-1));
    if (name = 'MAKEFLAGS') or (name = 'MFLAGS') then Continue;
    if redirectsFpcSearch(name) then Continue; // ours is re-injected below
    if name = 'PATH' then begin
      // PathSeparator: ';' on Windows, ':' on Unix
      var parentpath := Copy(envLine, 6, MaxInt);
{$ifdef LINUX}
      parentpath := strippwdexedirs(parentpath);
{$endif}
      if Prefix <> '' then P.Environment.Add('PATH='+Prefix+PathSeparator+parentpath)
      else P.Environment.Add('PATH='+parentpath);
      pathSeen := True;
    end else P.Environment.Add(envLine);
  end;
  if (Prefix <> '') and (not pathSeen) then P.Environment.Add('PATH='+Prefix);
  // belt + suspenders: force MAKEFLAGS/MFLAGS empty regardless of parent env
  P.Environment.Add('MAKEFLAGS=');
  P.Environment.Add('MFLAGS=');
  // pin the config search to our own fpc.cfg; FPC reaches a user-level one
  // first otherwise. Empty until the cfg is generated - that window only
  // spans the FPC build, whose makefiles pass every path explicitly.
  if fpcConfigDir <> '' then P.Environment.Add('PPC_CONFIG_PATH='+fpcConfigDir);
end;

// flush completed lines (split on LF; trailing partial stays in Buf)
procedure FlushLines(var Buf: string; OnLine: TLineCallback);
begin
  if not Assigned(OnLine) then begin Buf := ''; Exit; end;
  repeat
    var p := Pos(#10, Buf);
    if p = 0 then Break;
    var Line := Copy(Buf, 1, p-1);
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then SetLength(Line, Length(Line)-1);
    OnLine(Line);
    Delete(Buf, 1, p);
  until False;
end;

function RunStream(const Exe: string; const Args: array of string; const WorkDir: string; const ExtraPath: string; OnLine: TLineCallback): Integer;
var
  Tmp: array[0..READ_BUF-1] of Byte;
begin
  Result := -1;
  var P := autofree TProcess.Create(nil);
  P.Executable := Exe;
  for var i := Low(Args) to High(Args) do P.Parameters.Add(Args[i]);
  if WorkDir <> '' then P.CurrentDirectory := WorkDir;
  P.Options := [poUsePipes, poNoConsole];
  P.ShowWindow := swoHide;
  ApplyEnvWithPathPrefix(P, ExtraPath);

  var OutBuf := '';
  var ErrBuf := '';
  try
    P.Execute;
  except
    on E: Exception do Exit(-1);
  end;

  while P.Running or (P.Output.NumBytesAvailable > 0) or (P.Stderr.NumBytesAvailable > 0) do begin
    if P.Output.NumBytesAvailable > 0 then begin
      var N := P.Output.Read(Tmp, Length(Tmp));
      if N > 0 then begin
        SetLength(OutBuf, Length(OutBuf)+N);
        Move(Tmp, OutBuf[Length(OutBuf)-N+1], N);
        FlushLines(OutBuf, OnLine);
      end;
    end else if P.Stderr.NumBytesAvailable > 0 then begin
      var N := P.Stderr.Read(Tmp, Length(Tmp));
      if N > 0 then begin
        SetLength(ErrBuf, Length(ErrBuf)+N);
        Move(Tmp, ErrBuf[Length(ErrBuf)-N+1], N);
        FlushLines(ErrBuf, OnLine);
      end;
    end else Sleep(20);
  end;

  // emit any final partial line that didn't end with LF
  if (OutBuf <> '') and Assigned(OnLine) then OnLine(OutBuf);
  if (ErrBuf <> '') and Assigned(OnLine) then OnLine(ErrBuf);

  // ExitCode, not ExitStatus: on Unix the latter is the raw wait status,
  // so a lazbuild that exited 2 would be reported as 512
  Result := P.ExitCode;
end;

end.
