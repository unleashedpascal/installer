{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit file_assoc;

{$mode unleashed}

// per-user file associations for the IDE. Windows: HKCU\Software\Classes
// (no UAC needed); Linux: freedesktop MIME package + .desktop + mimeapps.list

interface

uses
  Classes, SysUtils;

type
  TAssocLogEvent = procedure(const msg: string) of object;

const
  // extension, MIME type (Linux), MIME parent, description
  ASSOC_EXTS: array[0..6, 0..3] of string = (
    ('lpi', 'text/lazarus-project-information', 'text/xml', 'Unleashed Pascal project'),
    ('lpr', 'text/lazarus-project-source', 'text/x-pascal', 'Unleashed Pascal project source'),
    ('lfm', 'text/lazarus-form', 'text/plain', 'Unleashed Pascal form'),
    ('lpk', 'text/lazarus-package', 'text/xml', 'Unleashed Pascal package'),
    ('pas', 'text/x-pascal', '', 'Pascal source'),
    ('pp', 'text/x-pascal', '', 'Pascal source'),
    ('inc', 'text/x-pascal', '', 'Pascal include'));

// install root or already the IDE binary -> path of the IDE binary; exeSub is the per-OS 'lazarus/lazarus[.exe]'
function normalizeIdePath(const path, exeSub: string): string;
// exts: indexes into ASSOC_EXTS. result false when at least one step failed; every step is logged
function setAssociations(const exePath: string; const exts: array of Integer; log: TAssocLogEvent): Boolean;
function unsetAssociations(const exts: array of Integer; log: TAssocLogEvent): Boolean;

implementation

uses
  {$ifdef WINDOWS} Registry, ShlObj; {$endif}
  {$ifdef LINUX} IniFiles, proc_util, linux_deps; {$endif}

function normalizeIdePath(const path, exeSub: string): string;
begin
  result := Trim(path);
  if result = '' then exit;
  var tail := Copy(result, Length(result)-Length(exeSub)+1, Length(exeSub));
  {$ifdef WINDOWS}
  if SameText(tail, exeSub) then exit;
  {$else}
  if tail = exeSub then exit;
  {$endif}
  result := IncludeTrailingPathDelimiter(result)+exeSub;
end;

{$ifdef WINDOWS}
const
  PROGID_PREFIX = 'UnleashedPascal.';
  FILE_EXTS_KEY = 'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\';

// a ProgID belongs to the IDE when its name or its open command names the IDE
// binary. A manual "Open with" can leave a name like Lazarus.ProjectInfo with
// no class key behind it at all, so the name alone has to be enough
function isIdeProgId(reg: TRegistry; const progId: string): Boolean;
begin
  result := False;
  if progId = '' then exit;
  var low := LowerCase(progId);
  if (Pos('lazarus', low) > 0) or (Pos(LowerCase(PROGID_PREFIX), low) = 1) then exit(True);
  if not reg.OpenKeyReadOnly('Software\Classes\'+progId+'\shell\open\command') then exit;
  var cmd := LowerCase(reg.ReadString(''));
  reg.CloseKey;
  result := Pos('lazarus', cmd) > 0;
end;

// the UserChoice key carries a hash only Explorer can produce and wins over
// HKCU\Classes. It has a deny ACE on Set Value but not on Delete, so the whole
// key goes and Windows falls back to the .ext default ProgID
procedure deleteUserChoice(reg: TRegistry; const ext: string; onlyOurs: Boolean; log: TAssocLogEvent);
begin
  var key := FILE_EXTS_KEY+'.'+ext+'\UserChoice';
  if not reg.KeyExists(key) then exit;
  if onlyOurs then begin
    var progId := '';
    if reg.OpenKeyReadOnly(key) then begin
      progId := reg.ReadString('ProgId');
      reg.CloseKey;
    end;
    if not isIdeProgId(reg, progId) then exit;
  end;
  if reg.DeleteKey(key) then log('  removed UserChoice for .'+ext)
  else log('  WARNING: could not remove UserChoice for .'+ext+', the previous default stays');
end;

// Explorer keeps its own per-extension handler list next to UserChoice. With
// no UserChoice and no .ext ProgID left, a single entry here is still enough
// for Explorer to call the extension associated, so the IDE's entries go too
procedure cleanOpenWithProgids(reg: TRegistry; const ext: string; log: TAssocLogEvent);
begin
  var key := FILE_EXTS_KEY+'.'+ext+'\OpenWithProgids';
  if not reg.KeyExists(key) then exit;
  var names := autofree TStringList.Create;
  if reg.OpenKeyReadOnly(key) then begin
    reg.GetValueNames(names);
    reg.CloseKey;
  end;
  // isIdeProgId opens keys of its own, so decide first and delete afterwards
  var doomed := autofree TStringList.Create;
  for var i := 0 to names.Count-1 do
    if isIdeProgId(reg, names[i]) then doomed.Add(names[i]);
  if doomed.Count = 0 then exit;
  if not reg.OpenKey(key, False) then exit;
  for var i := 0 to doomed.Count-1 do begin
    reg.DeleteValue(doomed[i]);
    log('  dropped OpenWithProgids entry '+doomed[i]+' for .'+ext);
  end;
  var rest := autofree TStringList.Create;
  reg.GetValueNames(rest);
  reg.CloseKey;
  if rest.Count = 0 then reg.DeleteKey(key);
end;

// same list, the "recently used applications" half: value names are single
// letters ordered by MRUList, values are bare exe names
procedure cleanOpenWithList(reg: TRegistry; const ext: string; log: TAssocLogEvent);
begin
  var key := FILE_EXTS_KEY+'.'+ext+'\OpenWithList';
  if not reg.KeyExists(key) then exit;
  if not reg.OpenKey(key, False) then exit;
  var names := autofree TStringList.Create;
  reg.GetValueNames(names);
  var mru := reg.ReadString('MRUList');
  var dropped := '';
  for var i := 0 to names.Count-1 do begin
    if SameText(names[i], 'MRUList') then Continue;
    if Pos('lazarus', LowerCase(reg.ReadString(names[i]))) = 0 then Continue;
    reg.DeleteValue(names[i]);
    dropped := dropped+names[i];
    log('  dropped OpenWithList entry for .'+ext);
  end;
  if dropped = '' then begin
    reg.CloseKey;
    exit;
  end;
  var newMru := '';
  for var c in mru do
    if Pos(c, dropped) = 0 then newMru := newMru+c;
  if newMru <> '' then begin
    reg.WriteString('MRUList', newMru);
    reg.CloseKey;
  end else begin
    reg.CloseKey;
    reg.DeleteKey(key);
  end;
end;

function setAssociations(const exePath: string; const exts: array of Integer; log: TAssocLogEvent): Boolean;
begin
  result := False;
  var reg := autofree TRegistry.Create;
  reg.RootKey := HKEY_CURRENT_USER;
  var allOk := True;
  for var i in exts do begin
    var ext := ASSOC_EXTS[i, 0];
    var progId := PROGID_PREFIX+ext;
    log('.'+ext+' -> '+exePath);
    var ok := reg.OpenKey('Software\Classes\.'+ext, True);
    if ok then begin
      reg.WriteString('', progId);
      reg.CloseKey;
    end;
    ok := ok and reg.OpenKey('Software\Classes\'+progId, True);
    if ok then begin
      reg.WriteString('', ASSOC_EXTS[i, 3]);
      reg.CloseKey;
    end;
    ok := ok and reg.OpenKey('Software\Classes\'+progId+'\DefaultIcon', True);
    if ok then begin
      reg.WriteString('', '"'+exePath+'",0');
      reg.CloseKey;
    end;
    ok := ok and reg.OpenKey('Software\Classes\'+progId+'\shell\open\command', True);
    if ok then begin
      reg.WriteString('', '"'+exePath+'" "%1"');
      reg.CloseKey;
    end;
    if not ok then begin
      log('  ERROR: cannot write HKCU\Software\Classes for .'+ext);
      allOk := False;
      Continue;
    end;
    deleteUserChoice(reg, ext, False, log);
  end;
  // without this Explorer keeps the old icons and handler until the next logon
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
  result := allOk;
end;

function unsetAssociations(const exts: array of Integer; log: TAssocLogEvent): Boolean;
begin
  result := False;
  var reg := autofree TRegistry.Create;
  reg.RootKey := HKEY_CURRENT_USER;
  var allOk := True;
  for var i in exts do begin
    var ext := ASSOC_EXTS[i, 0];
    var progId := PROGID_PREFIX+ext;
    var extKey := 'Software\Classes\.'+ext;
    // only drop the .ext key when it still points at the IDE, under our ProgID
    // or one a manual "Open with" left there; another app may own it by now
    if reg.OpenKeyReadOnly(extKey) then begin
      var current := reg.ReadString('');
      reg.CloseKey;
      if isIdeProgId(reg, current) then begin
        if reg.DeleteKey(extKey) then log('.'+ext+' association removed')
        else begin
          log('  ERROR: cannot delete HKCU\'+extKey);
          allOk := False;
        end;
      end else log('.'+ext+' is owned by '+current+', left alone');
    end else log('.'+ext+' had no association');
    if reg.KeyExists('Software\Classes\'+progId) and (not reg.DeleteKey('Software\Classes\'+progId)) then begin
      log('  ERROR: cannot delete HKCU\Software\Classes\'+progId);
      allOk := False;
    end;
    deleteUserChoice(reg, ext, True, log);
    cleanOpenWithProgids(reg, ext, log);
    cleanOpenWithList(reg, ext, log);
  end;
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nil, nil);
  result := allOk;
end;
{$endif}

{$ifdef LINUX}
const
  DESKTOP_ID = 'unleashed-pascal-ide.desktop';
  MIME_PKG   = 'unleashed-pascal.xml';

function homeDir: string;
begin
  result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME'));
end;

function mimeDir: string;
begin
  result := homeDir+'.local/share/mime/';
end;

function applicationsDir: string;
begin
  result := homeDir+'.local/share/applications/';
end;

function mimeAppsPath: string;
begin
  result := homeDir+'.config/mimeapps.list';
end;

// shared-mime-info package: one <mime-type> per distinct MIME type, all globs
// of the chosen extensions inside. text/x-pascal exists system-wide; listing it
// here only adds globs (.pp is already there, .inc is not)
function buildMimeXml(const exts: array of Integer): string;
begin
  result := '<?xml version="1.0" encoding="utf-8"?>'#10+'<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">'#10;
  var done := '';
  for var i in exts do begin
    var mime := ASSOC_EXTS[i, 1];
    if Pos(' '+mime+' ', done) > 0 then Continue;
    done += ' '+mime+' ';
    result += '  <mime-type type="'+mime+'">'#10;
    if ASSOC_EXTS[i, 2] <> '' then result += '    <sub-class-of type="'+ASSOC_EXTS[i, 2]+'"/>'#10+'    <comment>'+ASSOC_EXTS[i, 3]+'</comment>'#10;
    for var j in exts do
      if ASSOC_EXTS[j, 1] = mime then result += '    <glob pattern="*.'+ASSOC_EXTS[j, 0]+'"/>'#10;
    result += '  </mime-type>'#10;
  end;
  result += '</mime-info>'#10;
end;

function mimeList(const exts: array of Integer): string;
begin
  result := '';
  for var i in exts do
    if Pos(ASSOC_EXTS[i, 1]+';', result) = 0 then result += ASSOC_EXTS[i, 1]+';';
end;

function buildDesktopEntry(const exePath: string; const exts: array of Integer): string;
begin
  result := '[Desktop Entry]'#10'Type=Application'#10'Version=1.0'#10'Name=Unleashed Pascal IDE'#10'Comment=Unleashed Pascal IDE'#10+
    'Exec='+exePath+' %F'#10'Terminal=false'#10'Categories=Development;IDE;'#10'StartupNotify=false'#10'MimeType='+mimeList(exts)+#10;
end;

function writeTextFile(const path, body: string; log: TAssocLogEvent): Boolean;
begin
  result := False;
  try
    ForceDirectories(ExtractFilePath(path));
    var sl := autofree TStringList.Create;
    sl.Text := body;
    sl.SaveToFile(path);
    log('  wrote '+path);
    result := True;
  except
    on e: Exception do log('  ERROR: cannot write '+path+': '+e.Message);
  end;
end;

// custom globs reach the file manager only after the databases are rebuilt;
// missing tools are reported, the rest of the association still works
procedure refreshDatabases(log: TAssocLogEvent);
begin
  var exe := whichExe('update-mime-database');
  if exe = '' then log('  WARNING: update-mime-database not found, new extensions will not be recognized')
  else if RunSilent(exe, [ExcludeTrailingPathDelimiter(mimeDir)]) <> 0 then log('  WARNING: update-mime-database failed');
  exe := whichExe('update-desktop-database');
  if exe = '' then log('  WARNING: update-desktop-database not found')
  else if RunSilent(exe, [ExcludeTrailingPathDelimiter(applicationsDir)]) <> 0 then log('  WARNING: update-desktop-database failed');
end;

// mimeapps.list: [Default Applications] picks the handler, [Added Associations]
// lists it in "Open with"; both keyed by MIME type, values ';'-separated desktop ids
function editMimeApps(const exts: array of Integer; add: Boolean; log: TAssocLogEvent): Boolean;
begin
  result := False;
  try
    ForceDirectories(ExtractFilePath(mimeAppsPath));
    var ini := autofree TIniFile.Create(mimeAppsPath, [ifoCaseSensitive]);
    for var i in exts do begin
      var mime := ASSOC_EXTS[i, 1];
      if add then begin
        ini.WriteString('Default Applications', mime, DESKTOP_ID);
        var added := ini.ReadString('Added Associations', mime, '');
        if Pos(DESKTOP_ID+';', added+';') = 0 then ini.WriteString('Added Associations', mime, added+DESKTOP_ID+';');
      end else begin
        if ini.ReadString('Default Applications', mime, '') = DESKTOP_ID then ini.DeleteKey('Default Applications', mime);
        var added := StringReplace(ini.ReadString('Added Associations', mime, '')+';', DESKTOP_ID+';', '', []);
        added := StringReplace(added, ';;', ';', [rfReplaceAll]);
        if (added = '') or (added = ';') then ini.DeleteKey('Added Associations', mime)
        else ini.WriteString('Added Associations', mime, added);
      end;
    end;
    ini.UpdateFile;
    log('  updated '+mimeAppsPath);
    result := True;
  except
    on e: Exception do log('  ERROR: cannot update '+mimeAppsPath+': '+e.Message);
  end;
end;

function anyDefaultLeft: Boolean;
begin
  result := False;
  if not FileExists(mimeAppsPath) then exit;
  var ini := autofree TIniFile.Create(mimeAppsPath, [ifoCaseSensitive]);
  var values := autofree TStringList.Create;
  ini.ReadSectionValues('Default Applications', values);
  for var i := 0 to values.Count-1 do
    if values.ValueFromIndex[i] = DESKTOP_ID then exit(True);
end;

function setAssociations(const exePath: string; const exts: array of Integer; log: TAssocLogEvent): Boolean;
begin
  result := False;
  for var i in exts do log('.'+ASSOC_EXTS[i, 0]+' -> '+exePath);
  if not writeTextFile(mimeDir+'packages/'+MIME_PKG, buildMimeXml(exts), log) then exit;
  if not writeTextFile(applicationsDir+DESKTOP_ID, buildDesktopEntry(exePath, exts), log) then exit;
  if not editMimeApps(exts, True, log) then exit;
  refreshDatabases(log);
  result := True;
end;

function unsetAssociations(const exts: array of Integer; log: TAssocLogEvent): Boolean;
begin
  result := False;
  for var i in exts do log('.'+ASSOC_EXTS[i, 0]+' association removed');
  if not editMimeApps(exts, False, log) then exit;
  // the MIME package and the .desktop serve every extension at once, so they
  // stay until the last default pointing at us is gone
  if not anyDefaultLeft then begin
    if FileExists(mimeDir+'packages/'+MIME_PKG) then DeleteFile(mimeDir+'packages/'+MIME_PKG);
    if FileExists(applicationsDir+DESKTOP_ID) then DeleteFile(applicationsDir+DESKTOP_ID);
    log('  removed '+MIME_PKG+' and '+DESKTOP_ID);
  end;
  refreshDatabases(log);
  result := True;
end;
{$endif}

end.
