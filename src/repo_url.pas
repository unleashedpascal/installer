{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit repo_url;

{$mode unleashed}

interface

var
  // git repos the sources come from, any host git can clone over https; the expert menu swaps them for the running session only
  ideRepoURL: string = 'https://github.com/unleashedpascal/ide';
  fpcRepoURL: string = 'https://github.com/unleashedpascal/compiler';

// last path segment without a trailing '/' or '.git'; a label for logs
function repoName(const url: string): string;

// smart-HTTP ref discovery, the request every `git clone` opens with; lists refs with their SHAs on any git host
function repoRefsURL(const url: string): string;

implementation

uses
  SysUtils;

function trimmedURL(const url: string): string;
begin
  result := Trim(url);
  if (result <> '') and (result[Length(result)] = '/') then SetLength(result, Length(result)-1);
end;

function repoName(const url: string): string;
begin
  var s := trimmedURL(url);
  if LowerCase(ExtractFileExt(s)) = '.git' then SetLength(s, Length(s)-4);
  result := Copy(s, LastDelimiter('/', s)+1, MaxInt);
end;

function repoRefsURL(const url: string): string;
begin
  result := trimmedURL(url)+'/info/refs?service=git-upload-pack';
end;

end.
