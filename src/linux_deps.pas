{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit linux_deps;

{$mode unleashed}

// the IDE links against GTK3 and libc, so the build dies at the very last step
// when only the runtime .so.N files are installed. this unit finds that out
// before the ~30 minute build starts and installs the packages through pkexec

interface

uses
  Classes, SysUtils, proc_util;

type
  TDepStatus = record
    ok: Boolean;
    // what the linker would not find, in user-facing wording
    missing: string;
    // package-manager command line, argv[0] first; '' when no known manager
    command: string;
    // command known and pkexec present, so the UI may offer a button
    canAutoInstall: Boolean;
  end;

  TDepLogEvent = procedure(const msg: string) of object;

  // runs the command from TDepStatus as root; every output line goes to onLog
  TDepInstallThread = class(TThread)
  private
    fCommand: string;
    fExitCode: Integer;
    fOnLog: TDepLogEvent;
    fLine: string;
    procedure emitLine;
    procedure onLine(const line: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const command: string; onLog: TDepLogEvent; onDone: TNotifyEvent);
    property ExitCode: Integer read fExitCode;
  end;

// wantGtk: only an IDE install links against GTK; a compiler-only run needs the toolchain alone
function checkBuildDeps(wantGtk: Boolean): TDepStatus;
// tools behind file associations: update-mime-database (shared-mime-info), update-desktop-database (desktop-file-utils)
function checkAssocDeps: TDepStatus;
// first PATH entry holding exe, '' when none
function whichExe(const exe: string): string;

implementation

// ld resolves -lfoo through the bare libfoo.so symlink, which lives in the
// -dev/-devel package; the libfoo.so.N the desktop already runs on is not enough
function haveLib(const soName: string): Boolean;
begin
  result := False;
  var dirs: array of string := ['/usr/lib/x86_64-linux-gnu', '/usr/lib64', '/usr/lib', '/usr/local/lib', '/lib/x86_64-linux-gnu'];
  for var dir in dirs do
    if FileExists(dir+'/'+soName) then exit(True);
end;

function whichExe(const exe: string): string;
begin
  result := '';
  for var dir in GetEnvironmentVariable('PATH').Split([':']) do
    if (dir <> '') and FileExists(IncludeTrailingPathDelimiter(dir)+exe) then exit(IncludeTrailingPathDelimiter(dir)+exe);
end;

// package names follow the manager, so finding the manager names the packages too
function checkBuildDeps(wantGtk: Boolean): TDepStatus;

  procedure need(const what: string);
  begin
    if result.missing <> '' then result.missing += ', ';
    result.missing += what;
  end;

begin
  result.ok := False;
  result.missing := '';
  result.command := '';
  result.canAutoInstall := False;

  var needGtk  := wantGtk and ((not haveLib('libgtk-3.so')) or (not haveLib('libgdk-3.so')));
  var needTool := (not haveLib('libc.so')) or (whichExe('ld') = '');
  if not (needGtk or needTool) then begin
    result.ok := True;
    exit;
  end;

  if needGtk then need('GTK3 development files (libgtk-3.so, libgdk-3.so)');
  if needTool then need('C toolchain (libc.so, ld)');

  // one line per manager: <exe> <install verb> <gtk package> <toolchain package>
  var pkgs := '';
  if whichExe('apt-get') <> '' then begin
    result.command := 'apt-get install -y';
    if needGtk then pkgs += ' libgtk-3-dev';
    if needTool then pkgs += ' build-essential';
  end else if whichExe('dnf') <> '' then begin
    result.command := 'dnf install -y';
    if needGtk then pkgs += ' gtk3-devel';
    if needTool then pkgs += ' gcc binutils glibc-devel';
  end else if whichExe('zypper') <> '' then begin
    result.command := 'zypper --non-interactive install';
    if needGtk then pkgs += ' gtk3-devel';
    if needTool then pkgs += ' gcc binutils glibc-devel';
  end else if whichExe('pacman') <> '' then begin
    result.command := 'pacman -S --noconfirm';
    if needGtk then pkgs += ' gtk3';
    if needTool then pkgs += ' base-devel';
  end;

  if result.command <> '' then result.command += pkgs;
  // pkexec asks for the password through the session's polkit agent; without
  // one (server, container, bare WM) there is nothing to prompt with
  result.canAutoInstall := (result.command <> '') and (whichExe('pkexec') <> '');
end;

// the package names are the same under every manager
function checkAssocDeps: TDepStatus;
begin
  result.ok := False;
  result.missing := '';
  result.command := '';
  result.canAutoInstall := False;
  var pkgs := '';
  if whichExe('update-mime-database') = '' then begin
    result.missing := 'shared-mime-info (update-mime-database)';
    pkgs += ' shared-mime-info';
  end;
  if whichExe('update-desktop-database') = '' then begin
    if result.missing <> '' then result.missing += ', ';
    result.missing += 'desktop-file-utils (update-desktop-database)';
    pkgs += ' desktop-file-utils';
  end;
  if pkgs = '' then begin
    result.ok := True;
    exit;
  end;
  if whichExe('apt-get') <> '' then result.command := 'apt-get install -y'+pkgs
  else if whichExe('dnf') <> '' then result.command := 'dnf install -y'+pkgs
  else if whichExe('zypper') <> '' then result.command := 'zypper --non-interactive install'+pkgs
  else if whichExe('pacman') <> '' then result.command := 'pacman -S --noconfirm'+pkgs;
  result.canAutoInstall := (result.command <> '') and (whichExe('pkexec') <> '');
end;

constructor TDepInstallThread.Create(const command: string; onLog: TDepLogEvent; onDone: TNotifyEvent);
begin
  inherited Create(True);
  fCommand := command;
  fOnLog := onLog;
  fExitCode := -1;
  FreeOnTerminate := True;
  OnTerminate := onDone;
  Start;
end;

procedure TDepInstallThread.emitLine;
begin
  if Assigned(fOnLog) then fOnLog(fLine);
end;

procedure TDepInstallThread.onLine(const line: string);
begin
  fLine := line;
  Synchronize(@emitLine);
end;

procedure TDepInstallThread.Execute;
begin
  var parts := fCommand.Split([' ']);
  fExitCode := RunStream('pkexec', parts, '', '', @onLine);
end;

end.
