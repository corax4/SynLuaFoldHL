unit Unit1;

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, Forms, Controls, Graphics, Dialogs, SynEdit, SynLuaFoldHL;

type

    { TForm1 }

    TForm1 = class(TForm)
        SynEdit1: TSynEdit;
        procedure FormCreate(Sender: TObject);
    private
        FSynLuaHL: TSynLuaHL;
    public

    end;

var
    Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
    FSynLuaHL := TSynLuaHL.Create(Self);
    SynEdit1.Highlighter := FSynLuaHL;
end;

end.

