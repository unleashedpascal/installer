{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit branch_cache;

{$mode unleashed}

interface

uses
  Classes, SysUtils;

const
  // plain-text key=value file in OS per-user temp; reused within CACHE_TTL_MINUTES of timestamp to skip GitHub
  CACHE_FILENAME = 'unleashed-installer.cache';
  CACHE_TTL_MINUTES = 5;

// loads branch lists + per-repo main HEAD SHA + the repo URLs they came from; True iff file parses and has `Cached at:`
function LoadCache(FpcBranches, IdeBranches: TStringList; out AgeSeconds: Double; out FpcMainSha, IdeMainSha, FpcRepo, IdeRepo: string): Boolean;

// writes branch lists + per-repo main SHAs + repo URLs; source TStrings are 'name=sha' pairs
procedure SaveCache(FpcBranches, IdeBranches: TStrings; const FpcRepo, IdeRepo: string);

// full path to cache file (per-user temp + CACHE_FILENAME)
function CacheFilePath: string;

implementation

uses
  DateUtils;

const
  FPC_PREFIX      = 'fpc-branches=';
  IDE_PREFIX      = 'ide-branches=';
  // schema scales: future preload of more branches just adds sha1-fpc-<name>= keys; older readers ignore unknowns
  FPC_HASH_PREFIX = 'sha1-fpc-main=';
  IDE_HASH_PREFIX = 'sha1-ide-main=';
  // the lists only mean something next to the URLs they were fetched from
  FPC_REPO_PREFIX = 'fpc-repo=';
  IDE_REPO_PREFIX = 'ide-repo=';
  TS_PREFIX       = '# Cached at: ';
  HEADER          = '# Unleashed Installer cache file';
  TS_FORMAT       = 'yyyy-mm-dd hh:nn:ss';
  MAIN_BRANCH     = 'main';

function CacheFilePath: string;
begin
  // GetTempDir(False) returns per-user temp with trailing separator on both OSes
  Result := GetTempDir(False)+CACHE_FILENAME;
end;

// split "a, b, c" into Dest; empty tokens dropped, whitespace trimmed
procedure ParseCommaList(const Value: string; Dest: TStringList);
begin
  Dest.Clear;
  var i := 1;
  var L := Length(Value);
  while i <= L do begin
    while (i <= L) and ((Value[i] = ' ') or (Value[i] = #9)) do Inc(i);
    var startPos := i;
    while (i <= L) and (Value[i] <> ',') do Inc(i);
    var token := Trim(Copy(Value, startPos, i-startPos));
    if token <> '' then Dest.Add(token);
    if (i <= L) and (Value[i] = ',') then Inc(i);
  end;
end;

function LoadCache(FpcBranches, IdeBranches: TStringList; out AgeSeconds: Double; out FpcMainSha, IdeMainSha, FpcRepo, IdeRepo: string): Boolean;
begin
  Result := False;
  AgeSeconds := 1e9;
  FpcMainSha := '';
  IdeMainSha := '';
  FpcRepo := '';
  IdeRepo := '';
  FpcBranches.Clear;
  IdeBranches.Clear;
  if not FileExists(CacheFilePath) then Exit;

  var lines := autofree TStringList.Create;
  try
    lines.LoadFromFile(CacheFilePath);
  except
    Exit;
  end;

  var fpcLine := '';
  var ideLine := '';
  var gotTimestamp := False;
  var cachedAt: TDateTime := 0;

  for var i := 0 to lines.Count-1 do begin
    var ln := Trim(lines[i]);
    if ln = '' then Continue;
    // check the `# Cached at:` comment before the generic `#` skip; other `#` lines are free-form
    if Pos(TS_PREFIX, ln) = 1 then begin
      try
        cachedAt := ScanDateTime(TS_FORMAT, Copy(ln, Length(TS_PREFIX)+1, MaxInt));
        gotTimestamp := True;
      except
        Exit;
      end;
      Continue;
    end;
    if ln[1] = '#' then Continue;
    if Pos(FPC_PREFIX, ln) = 1 then fpcLine := Copy(ln, Length(FPC_PREFIX)+1, MaxInt)
    else if Pos(IDE_PREFIX, ln) = 1 then ideLine := Copy(ln, Length(IDE_PREFIX)+1, MaxInt)
    else if Pos(FPC_HASH_PREFIX, ln) = 1 then FpcMainSha := LowerCase(Trim(Copy(ln, Length(FPC_HASH_PREFIX)+1, MaxInt)))
    else if Pos(IDE_HASH_PREFIX, ln) = 1 then IdeMainSha := LowerCase(Trim(Copy(ln, Length(IDE_HASH_PREFIX)+1, MaxInt)))
    else if Pos(FPC_REPO_PREFIX, ln) = 1 then FpcRepo := Trim(Copy(ln, Length(FPC_REPO_PREFIX)+1, MaxInt))
    else if Pos(IDE_REPO_PREFIX, ln) = 1 then IdeRepo := Trim(Copy(ln, Length(IDE_REPO_PREFIX)+1, MaxInt));
  end;

  if not gotTimestamp then Exit;
  AgeSeconds := SecondsBetween(Now, cachedAt);

  ParseCommaList(fpcLine, FpcBranches);
  ParseCommaList(ideLine, IdeBranches);
  Result := True;
end;

procedure SaveCache(FpcBranches, IdeBranches: TStrings; const FpcRepo, IdeRepo: string);

  // join into "a, b, c"; reads Names[i] for 'name=sha' entries, raw entry otherwise
  function JoinNames(L: TStrings): string;
  begin
    Result := '';
    for var i := 0 to L.Count-1 do begin
      var entry := L[i];
      if Pos('=', entry) > 0 then entry := L.Names[i];
      if entry = '' then Continue;
      if Result <> '' then Result := Result+', ';
      Result := Result+entry;
    end;
  end;

  // SHA of 'main' from a 'name=sha' TStrings, '' if absent
  function MainSha(L: TStrings): string;
  begin
    Result := '';
    for var i := 0 to L.Count-1 do
      if SameText(L.Names[i], MAIN_BRANCH) then begin
        Result := L.ValueFromIndex[i];
        Exit;
      end;
  end;

begin
  var f := autofree TStringList.Create;
  f.Add(HEADER);
  f.Add(TS_PREFIX+FormatDateTime(TS_FORMAT, Now));
  f.Add('');
  f.Add(FPC_PREFIX+JoinNames(FpcBranches));
  f.Add(IDE_PREFIX+JoinNames(IdeBranches));
  f.Add(FPC_HASH_PREFIX+MainSha(FpcBranches));
  f.Add(IDE_HASH_PREFIX+MainSha(IdeBranches));
  f.Add(FPC_REPO_PREFIX+FpcRepo);
  f.Add(IDE_REPO_PREFIX+IdeRepo);
  try
    f.SaveToFile(CacheFilePath);
  except
    // best effort; refetch next run
  end;
end;

end.
