{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit repo_url;

{$mode unleashed}

interface

var
  // GitHub repos the sources come from; the expert menu swaps them for the running session only
  ideRepoURL: string = 'https://github.com/unleashedpascal/ide';
  fpcRepoURL: string = 'https://github.com/unleashedpascal/compiler';

// <owner> and <name> from 'https://github.com/<owner>/<name>', a trailing '.git' or '/' allowed; '' when the URL has no such tail
function repoOwner(const url: string): string;
function repoName(const url: string): string;

// 'https://codeload.github.com/<owner>/<name>/zip/', ready for a branch, tag or SHA appended
function repoZipURLPrefix(const url: string): string;

implementation

uses
  SysUtils;

procedure splitRepoURL(const url: string; out owner, name: string);
begin
  owner := '';
  name := '';
  var s := Trim(url);
  if (s <> '') and (s[Length(s)] = '/') then SetLength(s, Length(s)-1);
  if LowerCase(ExtractFileExt(s)) = '.git' then SetLength(s, Length(s)-4);
  var p := Pos('://', s);
  if p > 0 then Delete(s, 1, p+2);
  // what is left must be exactly host/owner/name
  p := Pos('/', s);
  if p = 0 then exit;
  var rest := Copy(s, p+1, MaxInt);
  p := Pos('/', rest);
  if p = 0 then exit;
  var o := Copy(rest, 1, p-1);
  var n := Copy(rest, p+1, MaxInt);
  if (o = '') or (n = '') or (Pos('/', n) > 0) then exit;
  owner := o;
  name := n;
end;

function repoOwner(const url: string): string;
begin
  var name: string;
  splitRepoURL(url, result, name);
end;

function repoName(const url: string): string;
begin
  var owner: string;
  splitRepoURL(url, owner, result);
end;

function repoZipURLPrefix(const url: string): string;
begin
  result := 'https://codeload.github.com/'+repoOwner(url)+'/'+repoName(url)+'/zip/';
end;

end.
