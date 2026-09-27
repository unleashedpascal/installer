{ Unleashed Pascal Installer - (c) 2026 Unleashed Pascal. See LICENSE. }

unit expert_form;

{$mode unleashed}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls;

type
  twinexpert = class(TForm)
    panbody: TPanel;
    lblide: TLabel;
    inpide: TEdit;
    lblcmp: TLabel;
    inpcmp: TEdit;
    panfoot: TPanel;
    bvlsep: TBevel;
    btnsave: TButton;
    btncls: TButton;
  end;

implementation

{$R *.lfm}

end.
