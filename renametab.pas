unit renametab;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Buttons;

type

  { TfmRenameTab }

  TfmRenameTab = class(TForm)
    bbtOk: TBitBtn;
    bbtCancel: TBitBtn;
    edTitle: TEdit;
    Label1: TLabel;
    Panel1: TPanel;
  private

  public

  end;

var
  fmRenameTab: TfmRenameTab;

implementation

{$R *.lfm}

end.

