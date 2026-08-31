// 選択・図形作成ツールをコード描画アイコンで選択するControlを提供する。
unit VectArtDesignerToolPalette;

interface

uses
  System.Classes, System.Types, Vcl.Controls, VectArtDesignerEditorState;

type
  TVectArtToolPaletteControl = class(TCustomControl)
  private
    FEditorState: TVectArtEditorState;
    function ButtonRect(Index: Integer): TRect;
    procedure DrawButton(Index: Integer);
    procedure SetEditorState(const Value: TVectArtEditorState);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshState;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
  end;

implementation

uses
  Vcl.Graphics;

const
  BUTTON_SIZE = 46;
  COLOR_BACKGROUND = TColor($00252525);
  COLOR_BUTTON = TColor($002D2D2D);
  COLOR_SELECTED = TColor($0046382B);
  COLOR_ICON = TColor($00E0E0E0);

function TVectArtToolPaletteControl.ButtonRect(Index: Integer): TRect;
begin
  Result := Rect(6, 6 + Index * (BUTTON_SIZE + 6),
    ClientWidth - 6, 6 + Index * (BUTTON_SIZE + 6) + BUTTON_SIZE);
end;

constructor TVectArtToolPaletteControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
end;

procedure TVectArtToolPaletteControl.DrawButton(Index: Integer);
var
  Bounds: TRect;
  CenterX: Integer;
  CenterY: Integer;
  Selected: Boolean;
begin
  Bounds := ButtonRect(Index);
  CenterX := (Bounds.Left + Bounds.Right) div 2;
  CenterY := (Bounds.Top + Bounds.Bottom) div 2;
  Selected := (FEditorState <> nil) and
    (Ord(FEditorState.CurrentTool) = Index);
  if Selected then
    Canvas.Brush.Color := COLOR_SELECTED
  else
    Canvas.Brush.Color := COLOR_BUTTON;
  Canvas.FillRect(Bounds);
  Canvas.Pen.Color := COLOR_ICON;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  if Index = 0 then
  begin
    Canvas.MoveTo(CenterX - 8, CenterY - 11);
    Canvas.LineTo(CenterX + 7, CenterY + 2);
    Canvas.LineTo(CenterX, CenterY + 4);
    Canvas.LineTo(CenterX + 4, CenterY + 12);
    Canvas.LineTo(CenterX, CenterY + 14);
    Canvas.LineTo(CenterX - 4, CenterY + 6);
    Canvas.LineTo(CenterX - 9, CenterY + 10);
    Canvas.LineTo(CenterX - 8, CenterY - 11);
  end
  else if Index = 1 then
    Canvas.Rectangle(CenterX - 10, CenterY - 8, CenterX + 10,
      CenterY + 8)
  else if Index = 2 then
  begin
    Canvas.MoveTo(CenterX - 11, CenterY + 8);
    Canvas.LineTo(CenterX + 11, CenterY - 8);
  end
  else
  begin
    Canvas.MoveTo(CenterX - 11, CenterY + 8);
    Canvas.LineTo(CenterX - 4, CenterY - 8);
    Canvas.LineTo(CenterX + 10, CenterY - 3);
    Canvas.LineTo(CenterX + 5, CenterY + 10);
    Canvas.LineTo(CenterX - 11, CenterY + 8);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.Rectangle(CenterX - 13, CenterY + 6, CenterX - 9, CenterY + 10);
    Canvas.Rectangle(CenterX - 6, CenterY - 10, CenterX - 2, CenterY - 6);
    Canvas.Rectangle(CenterX + 8, CenterY - 5, CenterX + 12, CenterY - 1);
    Canvas.Rectangle(CenterX + 3, CenterY + 8, CenterX + 7, CenterY + 12);
  end;
end;

procedure TVectArtToolPaletteControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  if (Button = mbLeft) and (FEditorState <> nil) then
    for I := 0 to 3 do
      if PtInRect(ButtonRect(I), Point(X, Y)) then
      begin
        FEditorState.CurrentTool := TVectArtEditorTool(I);
        Break;
      end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtToolPaletteControl.Paint;
var
  I: Integer;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  for I := 0 to 3 do
    DrawButton(I);
end;

procedure TVectArtToolPaletteControl.RefreshState;
begin
  Invalidate;
end;

procedure TVectArtToolPaletteControl.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FEditorState := Value;
  RefreshState;
end;

end.
