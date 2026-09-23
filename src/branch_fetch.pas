{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit branch_fetch;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

type
  TBranchFetchThread = class(TThread)
  private
    FOwner, FRepo: string;
    FBranches: TStringList;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AOwner, ARepo: string; AOnDone: TNotifyEvent);
    destructor Destroy; override;
    property Owner: string read FOwner;
    property Repo: string read FRepo;
    // safe to read on main thread inside OnTerminate
    property Branches: TStringList read FBranches;
    property ErrorMsg: string read FError;
  end;

implementation

uses
  fpjson, jsonparser
  {$ifdef WINDOWS}, Windows, WinInet{$endif}
  {$ifdef LINUX}, process{$endif};

const
  AGENT      = 'UnleashedInstaller/1.0';
  HEADERS    = 'Accept: application/vnd.github+json'#13#10;
  CHUNK_SIZE = 4096;

constructor TBranchFetchThread.Create(const AOwner, ARepo: string; AOnDone: TNotifyEvent);
begin
  inherited Create(True);
  FOwner := AOwner;
  FRepo := ARepo;
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
    var Connection := InternetOpenUrl(Session, PChar(URL), PChar(HEADERS), Length(HEADERS),
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
  P.Parameters.Add('-H');              P.Parameters.Add('Accept: application/vnd.github+json');
  P.Parameters.Add(URL);
  P.Options := [poUsePipes];

  try
    P.Execute;
  except
    on E: Exception do raise Exception.Create('curl not found in PATH (install: apt install curl): '+E.Message);
  end;

  // drain both pipes; stdout = JSON, stderr = curl error text on -S
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

procedure TBranchFetchThread.Execute;
begin
  try
    var Url := Format('https://api.github.com/repos/%s/%s/branches?per_page=100', [FOwner, FRepo]);
    var Body: string;
    if not HttpGet(Url, Body) then begin
      FError := 'HTTP GET failed for '+Url;
      Exit;
    end;

    var J := autofree GetJSON(Body);
    if not (J is TJSONArray) then begin
      FError := 'unexpected response: '+Copy(Body, 1, 200);
      Exit;
    end;
    var Arr := TJSONArray(J);
    // store as "name=sha" so callers can list Names[i] and look up Values[branch] in O(1)
    for var i := 0 to Arr.Count-1 do begin
      var Obj := Arr.Objects[i];
      if Obj <> nil then FBranches.Add(Obj.Get('name', '')+'='+TJSONObject(Obj.Find('commit')).Get('sha', ''));
    end;
  except
    on E: Exception do FError := E.ClassName+': '+E.Message;
  end;
  // OnTerminate fires via Synchronize once Execute exits
end;

end.
