{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit branch_fetch;

{$mode unleashed}

interface

uses
  Classes, SysUtils, repo_url;

type
  TBranchFetchThread = class(TThread)
  private
    FURL, FRepo: string;
    FBranches: TStringList;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AURL: string; AOnDone: TNotifyEvent);
    destructor Destroy; override;
    property Repo: string read FRepo;
    // safe to read on main thread inside OnTerminate
    property Branches: TStringList read FBranches;
    property ErrorMsg: string read FError;
  end;

implementation

uses
  {$ifdef WINDOWS} Windows, WinInet {$endif}
  {$ifdef LINUX} process {$endif};

const
  AGENT      = 'UnleashedInstaller/1.0';
  CHUNK_SIZE = 4096;

constructor TBranchFetchThread.Create(const AURL: string; AOnDone: TNotifyEvent);
begin
  inherited Create(True);
  FURL := AURL;
  FRepo := repoName(AURL);
  FBranches := TStringList.Create;
  // OnTerminate runs on main thread; FreeOnTerminate frees us after it returns -- callback must NOT free us
  FreeOnTerminate := True;
  OnTerminate := AOnDone;
  Start;
end;

destructor TBranchFetchThread.Destroy;
begin
  FBranches.Free;
  inherited Destroy;
end;

{$ifdef WINDOWS}
// HTTPS GET via WinINet -- native TLS, no external curl (curl.exe missing on pre-1803 Windows)
function HttpGet(const URL: string; out Body: string): Boolean;
var
  Buf: array[0..CHUNK_SIZE-1] of Byte;
  BytesRead: DWORD;
begin
  Result := False;
  Body := '';
  var Session := InternetOpen(AGENT, INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Session = nil then Exit;
  try
    var Connection := InternetOpenUrl(Session, PChar(URL), nil, 0,
      INTERNET_FLAG_NO_UI or INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_KEEP_CONNECTION, 0);
    if Connection = nil then Exit;
    try
      var Stream := autofree TMemoryStream.Create;
      repeat
        if not InternetReadFile(Connection, @Buf[0], CHUNK_SIZE, BytesRead) then Exit;
        if BytesRead = 0 then Break;
        Stream.Write(Buf[0], BytesRead);
      until False;

      if Stream.Size > 0 then begin
        SetLength(Body, Stream.Size);
        Move(PByte(Stream.Memory)^, Body[1], Stream.Size);
      end;
      Result := True;
    finally
      InternetCloseHandle(Connection);
    end;
  finally
    InternetCloseHandle(Session);
  end;
end;
{$endif}

{$ifdef LINUX}
// HTTPS GET via curl; --retry 3 absorbs transient NAT/TLS/DNS hiccups
function HttpGet(const URL: string; out Body: string): Boolean;
var
  Buf: array[0..4095] of Byte;
  n: LongInt;
begin
  Result := False;
  Body := '';
  var P := autofree TProcess.Create(nil);
  P.Executable := 'curl';
  P.Parameters.Add('-fsSL');
  P.Parameters.Add('--retry');         P.Parameters.Add('3');
  P.Parameters.Add('--retry-delay');   P.Parameters.Add('1');
  P.Parameters.Add('--retry-connrefused');
  P.Parameters.Add('-A');              P.Parameters.Add(AGENT);
  P.Parameters.Add(URL);
  P.Options := [poUsePipes];

  try
    P.Execute;
  except
    on E: Exception do raise Exception.Create('curl not found in PATH (install: apt install curl): '+E.Message);
  end;

  // drain both pipes; stdout = refs, stderr = curl error text on -S
  var StdoutBuf := autofree TMemoryStream.Create;
  var StderrBuf: string := '';
  while P.Running or (P.Output.NumBytesAvailable > 0) or (P.Stderr.NumBytesAvailable > 0) do begin
    if P.Output.NumBytesAvailable > 0 then begin
      n := P.Output.Read(Buf, Length(Buf));
      if n > 0 then StdoutBuf.Write(Buf, n);
    end else if P.Stderr.NumBytesAvailable > 0 then begin
      n := P.Stderr.Read(Buf, Length(Buf));
      if n > 0 then begin
        var chunk: string := '';
        SetLength(chunk, n);
        Move(Buf, chunk[1], n);
        StderrBuf := StderrBuf+chunk;
      end;
    end else Sleep(20);
  end;

  if P.ExitCode <> 0 then raise Exception.CreateFmt('curl failed (exit=%d): %s', [P.ExitCode, Trim(StderrBuf)]);

  if StdoutBuf.Size > 0 then begin
    SetLength(Body, StdoutBuf.Size);
    Move(PByte(StdoutBuf.Memory)^, Body[1], StdoutBuf.Size);
  end;
  Result := True;
end;
{$endif}

// pkt-line body of info/refs: 4 hex digits of length (0000 = flush), then '<sha> <ref>', the first ref
// followed by NUL and the server capabilities; only refs/heads/* matter here
procedure parseRefs(const body: string; branches: TStrings);
begin
  var p := 1;
  while p+4 <= Length(body) do begin
    var len := StrToIntDef('$'+Copy(body, p, 4), 0);
    if len = 0 then begin
      inc(p, 4);
      continue;
    end;
    var line := Copy(body, p+4, len-4);
    inc(p, len);
    var nul := Pos(#0, line);
    if nul > 0 then SetLength(line, nul-1);
    line := Trim(line);
    var sp := Pos(' ', line);
    if (sp <> 41) or (line[1] = '#') then continue;
    var ref := Copy(line, sp+1, MaxInt);
    if Pos('refs/heads/', ref) = 1 then branches.Add(Copy(ref, Length('refs/heads/')+1, MaxInt)+'='+LowerCase(Copy(line, 1, 40)));
  end;
end;

procedure TBranchFetchThread.Execute;
begin
  try
    var Url := repoRefsURL(FURL);
    var Body: string;
    if not HttpGet(Url, Body) then begin
      FError := 'HTTP GET failed for '+Url;
      Exit;
    end;

    // stored as "name=sha" so callers can list Names[i] and look up Values[branch] in O(1)
    parseRefs(Body, FBranches);
    if FBranches.Count = 0 then FError := 'no branches in response: '+Copy(Body, 1, 200);
  except
    on E: Exception do FError := E.ClassName+': '+E.Message;
  end;
  // OnTerminate fires via Synchronize once Execute exits
end;

end.
