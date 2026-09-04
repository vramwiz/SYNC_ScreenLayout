// 選択・図形作成ツールをコード描画アイコンで選択するControlを提供する。
unit ScreenLayoutToolPalette;

interface

uses
  System.Classes, System.Types, Vcl.Controls, ScreenLayoutDocument,
  ScreenLayoutEditorState;

type
  TVectArtToolPaletteControl = class(TCustomControl)
  private
    FEditorState: TVectArtEditorState;
    function ButtonRect(Index: Integer): TRect;
    function ButtonSelected(Index: Integer): Boolean;
    function ButtonTool(Index: Integer): TVectArtEditorTool;
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
  Vcl.Graphics, Winapi.Windows;

const
  BUTTON_SIZE = 46;
  PALETTE_BUTTON_COUNT = 9;
  COLOR_BACKGROUND = TColor($00252525);
  COLOR_BUTTON = TColor($002D2D2D);
  COLOR_SELECTED = TColor($0046382B);
  COLOR_ICON = TColor($00E0E0E0);
  COLOR_SHAPE_FILL = TColor($00808080);

procedure DrawPathKindIcon(ACanvas: TCanvas; CenterX, CenterY: Integer;
  Closed: Boolean; Kind: TScreenLayoutVertexKind);
var
  Anchors: array[0..3] of TPoint;
  BezierPoints: TArray<TPoint>;
  I: Integer;
begin
  Anchors[0] := Point(CenterX - 12, CenterY + 7);
  Anchors[1] := Point(CenterX - 5, CenterY - 7);
  Anchors[2] := Point(CenterX + 3, CenterY + 5);
  Anchors[3] := Point(CenterX + 12, CenterY - 5);
  if Closed then
    Anchors[3] := Point(CenterX + 10, CenterY + 8);
  if Closed then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_SHAPE_FILL;
  end;
  if Kind = slvkSharp then
  begin
    if Closed then
      ACanvas.Polygon(Anchors)
    else
    begin
      ACanvas.MoveTo(Anchors[0].X, Anchors[0].Y);
      for I := 1 to High(Anchors) do
        ACanvas.LineTo(Anchors[I].X, Anchors[I].Y);
    end;
  end
  else
  begin
    SetLength(BezierPoints, 10 + Ord(Closed) * 3);
    BezierPoints[0] := Anchors[0];
    BezierPoints[1] := Point(CenterX - 11, CenterY - 2);
    BezierPoints[2] := Point(CenterX - 8, CenterY - 8);
    BezierPoints[3] := Anchors[1];
    BezierPoints[4] := Point(CenterX - 2, CenterY - 6);
    BezierPoints[5] := Point(CenterX, CenterY + 5);
    BezierPoints[6] := Anchors[2];
    BezierPoints[7] := Point(CenterX + 7, CenterY + 5);
    BezierPoints[8] := Point(CenterX + 10, CenterY - 5);
    BezierPoints[9] := Anchors[3];
    if Closed then
    begin
      BezierPoints[10] := Point(CenterX + 3, CenterY + 11);
      BezierPoints[11] := Point(CenterX - 8, CenterY + 11);
      BezierPoints[12] := Anchors[0];
    end;
    if Closed then
      BeginPath(ACanvas.Handle);
    ACanvas.PolyBezier(BezierPoints);
    if Closed then
    begin
      EndPath(ACanvas.Handle);
      StrokeAndFillPath(ACanvas.Handle);
    end;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_ICON;
  for I := 0 to High(Anchors) do
    if Kind = slvkBezier then
      ACanvas.Ellipse(Anchors[I].X - 2, Anchors[I].Y - 2,
        Anchors[I].X + 2, Anchors[I].Y + 2)
    else
      ACanvas.Rectangle(Anchors[I].X - 2, Anchors[I].Y - 2,
        Anchors[I].X + 2, Anchors[I].Y + 2);
  ACanvas.Brush.Style := bsClear;
end;

function TVectArtToolPaletteControl.ButtonRect(Index: Integer): TRect;
begin
  Result := Rect(6, 6 + Index * (BUTTON_SIZE + 6),
    ClientWidth - 6, 6 + Index * (BUTTON_SIZE + 6) + BUTTON_SIZE);
end;

function TVectArtToolPaletteControl.ButtonSelected(Index: Integer): Boolean;
var
  Tool: TVectArtEditorTool;
begin
  Result := False;
  if FEditorState = nil then
    Exit;
  Tool := ButtonTool(Index);
  if Tool = vetRectangle then
    Result := FEditorState.CurrentTool in [vetRectangleLine, vetRectangle]
  else if Tool = vetRoundedRectangle then
    Result := FEditorState.CurrentTool in [vetRoundedRectangleLine,
      vetRoundedRectangle]
  else if Tool = vetEllipse then
    Result := FEditorState.CurrentTool in [vetEllipseLine, vetEllipse]
  else if Tool = vetArcShape then
    Result := FEditorState.CurrentTool in [vetArc, vetArcShape]
  else if Tool = vetText then
    Result := FEditorState.CurrentTool in [vetText, vetTextPath]
  else
    Result := FEditorState.CurrentTool = Tool;
end;

function TVectArtToolPaletteControl.ButtonTool(
  Index: Integer): TVectArtEditorTool;
begin
  case Index of
    0: Result := vetSelect;
    1: Result := vetLine;
    2: Result := vetPath;
    3: Result := vetRectangle;
    4: Result := vetRoundedRectangle;
    5: Result := vetEllipse;
    6: Result := vetArcShape;
    7: Result := vetShape;
  else
    Result := vetText;
  end;
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
  Tool: TVectArtEditorTool;
  VertexKind: TScreenLayoutVertexKind;
begin
  Bounds := ButtonRect(Index);
  CenterX := (Bounds.Left + Bounds.Right) div 2;
  CenterY := (Bounds.Top + Bounds.Bottom) div 2;
  Selected := ButtonSelected(Index);
  Tool := ButtonTool(Index);
  if Selected then
    Tool := FEditorState.CurrentTool;
  VertexKind := slvkSharp;
  if FEditorState <> nil then
    VertexKind := FEditorState.NextVertexKind;
  if Selected then
    Canvas.Brush.Color := COLOR_SELECTED
  else
    Canvas.Brush.Color := COLOR_BUTTON;
  Canvas.FillRect(Bounds);
  Canvas.Pen.Color := COLOR_ICON;
  Canvas.Font.Color := COLOR_ICON;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  if Tool = vetSelect then
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
  else if Tool = vetRectangleLine then
    Canvas.Rectangle(CenterX - 10, CenterY - 8, CenterX + 10,
      CenterY + 8)
  else if Tool = vetRectangle then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.Rectangle(CenterX - 10, CenterY - 8, CenterX + 10,
      CenterY + 8);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetRoundedRectangleLine then
    Canvas.RoundRect(CenterX - 11, CenterY - 9, CenterX + 11,
      CenterY + 9, 8, 8)
  else if Tool = vetRoundedRectangle then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.RoundRect(CenterX - 11, CenterY - 9, CenterX + 11,
      CenterY + 9, 8, 8);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetEllipseLine then
    Canvas.Ellipse(CenterX - 12, CenterY - 9, CenterX + 12,
      CenterY + 9)
  else if Tool = vetEllipse then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.Ellipse(CenterX - 12, CenterY - 9, CenterX + 12,
      CenterY + 9);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetArc then
    Canvas.Arc(CenterX - 12, CenterY - 9, CenterX + 12, CenterY + 9,
      CenterX + 12, CenterY, CenterX - 12, CenterY)
  else if Tool = vetArcShape then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_ICON;
    Canvas.Pie(CenterX - 12, CenterY - 9, CenterX + 12, CenterY + 9,
      CenterX + 12, CenterY, CenterX - 12, CenterY);
    Canvas.Brush.Style := bsClear;
  end
  else if Tool = vetLine then
  begin
    Canvas.MoveTo(CenterX - 11, CenterY + 8);
    Canvas.LineTo(CenterX + 11, CenterY - 8);
  end
  else if Tool = vetPath then
    DrawPathKindIcon(Canvas, CenterX, CenterY, False,
      VertexKind)
  else if Tool = vetTextPath then
  begin
    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Height := -18;
    Canvas.Font.Style := [fsBold];
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(CenterX - Canvas.TextWidth('T') div 2,
      CenterY - 11, 'T');
    Canvas.Font.Style := [];
    Canvas.MoveTo(CenterX - 12, CenterY + 8);
    Canvas.LineTo(CenterX - 4, CenterY + 5);
    Canvas.LineTo(CenterX + 4, CenterY + 7);
    Canvas.LineTo(CenterX + 12, CenterY + 3);
  end
  else if Tool = vetText then
  begin
    Canvas.Font.Name := 'Segoe UI';
    Canvas.Font.Height := -25;
    Canvas.Font.Style := [fsBold];
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(CenterX - Canvas.TextWidth('T') div 2,
      CenterY - Canvas.TextHeight('T') div 2, 'T');
    Canvas.Font.Style := [];
  end
  else
    DrawPathKindIcon(Canvas, CenterX, CenterY, True,
      VertexKind);
end;

procedure TVectArtToolPaletteControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  if (Button = mbLeft) and (FEditorState <> nil) then
    for I := 0 to PALETTE_BUTTON_COUNT - 1 do
      if PtInRect(ButtonRect(I), Point(X, Y)) then
      begin
        FEditorState.ActivateTool(ButtonTool(I));
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
  for I := 0 to PALETTE_BUTTON_COUNT - 1 do
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
