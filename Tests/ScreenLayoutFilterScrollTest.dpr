// 狭い一覧で専用スクロールバーと各行操作が同じ表示位置を参照することを検証する。
program ScreenLayoutFilterScrollTest;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.SysUtils, System.Types, Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  ScreenLayoutDocument, ScreenLayoutFilters, ScreenLayoutFilterListControl,
  VerticalScrollBarControl;
type
  TListAccess = class(TScreenLayoutFilterListControl);
  TObserver = class
    Index: Integer; // 最後に操作されたフィルター番号。
    Destination: Integer; // 並べ替えの移動先。
    procedure Toggle(Sender: TObject; Value: Integer);
    procedure Change(Sender: TObject; Value: Integer; Amount: Single);
    procedure Move(Sender: TObject; FromIndex, ToIndex: Integer);
  end;
procedure TObserver.Toggle(Sender: TObject; Value: Integer);
begin
  Index := Value;
end;
procedure TObserver.Change(Sender: TObject; Value: Integer; Amount: Single);
begin
  Index := Value;
end;
procedure TObserver.Move(Sender: TObject; FromIndex, ToIndex: Integer);
begin
  Index := FromIndex;
  Destination := ToIndex;
end;
procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;
procedure Run;
var
  Host: TForm;
  List: TListAccess;
  Bar: TVerticalScrollBarControl;
  Layer: TVectArtRectangleLayer;
  Observer: TObserver;
  I: Integer;
begin
  Host := TForm.CreateNew(nil);
  Layer := TVectArtRectangleLayer.Create('Test', TRectF.Create(0, 0, 20, 20), clRed);
  Observer := TObserver.Create;
  try
    List := TListAccess.Create(Host);
    List.Parent := Host;
    List.Align := alNone;
    List.SetBounds(0, 0, 240, 76);
    List.OnToggleEnabled := Observer.Toggle;
    List.OnValueChanged := Observer.Change;
    List.OnMoveFilter := Observer.Move;
    Bar := nil;
    for I := 0 to List.ControlCount - 1 do
      if List.Controls[I] is TVerticalScrollBarControl then
        Bar := TVerticalScrollBarControl(List.Controls[I]);
    Check(Bar <> nil, 'dedicated scrollbar missing');
    for I := 0 to 7 do Layer.AddFilter(TScreenLayoutBlurFilter.Create);
    List.Layer := Layer;
    Check(Bar.Visible and (Bar.Maximum = 228), 'overflow range');
    List.DoMouseWheel([], -120, Point(10, 10));
    Check(Bar.Position = 114, 'wheel scroll');
    List.MouseDown(mbLeft, [], 65, 19);
    List.MouseUp(mbLeft, [], 65, 19);
    Check(List.SelectedIndex = 3, 'scrolled row selection');
    List.MouseDown(mbLeft, [], 30, 19);
    Check(Observer.Index = 3, 'scrolled switch');
    List.MouseUp(mbLeft, [], 30, 19);
    List.MouseDown(mbLeft, [], 130, 19);
    List.MouseUp(mbLeft, [], 140, 19);
    Check(Observer.Index = 3, 'scrolled slider');
    List.MouseDown(mbLeft, [], 10, 19);
    List.MouseMove([ssLeft], 10, 57);
    List.MouseUp(mbLeft, [], 10, 57);
    Check((Observer.Index = 3) and (Observer.Destination = 4), 'scrolled reorder');
    List.SelectedIndex := 7;
    Check(Bar.Position = Bar.Maximum, 'selected last row not revealed');
    Layer.DeleteFilter(7);
    List.Layer := Layer;
    Check(Bar.Position = Bar.Maximum, 'delete did not clamp offset');
    List.Height := 400;
    Check(not Bar.Visible and (Bar.Position = 0), 'resize did not clear scroll');
    List.Height := 38;
    Check(Bar.Visible, 'single row viewport lost scrollbar');
    List.Layer := nil;
    Check(not Bar.Visible and (Bar.Position = 0), 'layer change retained scrollbar');
  finally
    Host.Free;
    Observer.Free;
    Layer.Free;
  end;
end;
begin
  Application.Initialize;
  try
    Run;
    Writeln('PASS');
  except on E: Exception do
    begin Writeln('FAIL: ', E.Message); ExitCode := 1; end;
  end;
end.
