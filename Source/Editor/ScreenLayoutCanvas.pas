// 中央編集領域のキャンバス表示を担当する。
// 論理サイズと画面上の拡大率を分離し、描画にはDirect2Dを優先して使用する。
unit ScreenLayoutCanvas;

interface

uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls, Vcl.Direct2D,
  Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  ScreenLayoutCanvasInteraction,
  ScreenLayoutDocument, ScreenLayoutEditHistory,
  ScreenLayoutEditorState, ScreenLayoutSelectionGeometry,
  ScreenLayoutShapeCreation, ScreenLayoutRenderer;

type
  TVectArtCanvasControl = class(TCustomControl)
  private
    FCanvasBounds: TRect;
    FDirect2DEnabled: Boolean;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FInteraction: TVectArtCanvasInteraction;
    FReferenceBackground: TBitmap;
    FRenderedDocument: TBitmap;
    FRenderBuffer: TVectArtRenderBuffer;
    FRenderedPreviewStrokeWidth: Single;
    FRenderedRevision: Int64;
    FShapeCreation: TVectArtShapeCreation;
    FTextBeforeSelection: TArray<Integer>;
    FTextDragActive: Boolean;
    FTextDragCurrent: TPoint;
    FTextDragStart: TPoint;
    FTextEditing: Boolean;
    FTextEditor: TMemo;
    FTextEnding: Boolean;
    FTextGuideBounds: TRectF;
    FTextLayerIndex: Integer;
    FTextNewLayer: Boolean;
    FTextOriginalData: TScreenLayoutTextData;
    FPanning: Boolean;
    FPanOffset: TPointF;
    FPanStartMouse: TPoint;
    FPanStartOffset: TPointF;
    FViewZoom: Single;
    FZoom: Single;
    procedure CalculateCanvasBounds;
    procedure EndPan;
    procedure PaintDirect2D;
    procedure PaintGDI;
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditorState(const Value: TVectArtEditorState);
    function ToScreenX(Value: Single): Integer;
    function ToScreenY(Value: Single): Integer;
    function GetEditHistory: TVectArtEditHistory;
    function HasReferenceBackground: Boolean;
    procedure UpdateRenderedDocument;
    procedure SetEditHistory(const Value: TVectArtEditHistory);
    procedure BeginExistingTextEdit(Index: Integer);
    procedure BeginNewTextEdit(const GuideBounds: TRectF);
    procedure DrawTextEditingOverlay(ACanvas: TCanvas);
    procedure DrawTextEditingOverlayDirect2D(ACanvas: TDirect2DCanvas);
    procedure FinishTextEdit(Cancel: Boolean;
      RestoreCanvasFocus: Boolean = True);
    procedure TextEditorChange(Sender: TObject);
    procedure TextEditorExit(Sender: TObject);
    procedure TextEditorKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure TextEditorKeyUp(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure UpdateTextEditorPosition;
    procedure UpdateTextLayerFromEditor;
  protected
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 外部ホストのRGBA8画像をDocumentに含めない参照背景として設定する。
    procedure SetReferenceBackgroundRgba(const Pixels: TBytes;
      Width, Height: Integer);
    // コントロール座標が用紙内なら、中央原点の文書座標へ変換する。
    function TryClientPointToLogical(const ClientPoint: TPoint;
      out LogicalPoint: TPointF): Boolean;
    property CanvasBounds: TRect read FCanvasBounds;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read GetEditHistory
      write SetEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
    property Zoom: Single read FZoom;
  end;

const
  DESIGN_CANVAS_WIDTH  = DEFAULT_CANVAS_WIDTH;
  DESIGN_CANVAS_HEIGHT = DEFAULT_CANVAS_HEIGHT;

implementation

uses
  System.Math, Winapi.D2D1, Winapi.Imm, Winapi.Windows,
  ScreenLayoutEllipseGeometry, ScreenLayoutGeometry, ScreenLayoutPathOperations,
  ScreenLayoutShapeOperations, ScreenLayoutTextCommands,
  ScreenLayoutTextGeometry, ScreenLayoutLayerNaming;

const
  CANVAS_MARGIN         = 32;
  CANVAS_SHADOW_OFFSET  = 6;
  COLOR_EDITOR_SURROUND = TColor($00121212);
  COLOR_CANVAS_SHADOW   = TColor($00070707);
  COLOR_ROTATION_MARK   = TColor($00008000);
  COLOR_SELECTION       = clBlack;
  COLOR_TRANSPARENT_A   = TColor($00D8D8D8);
  COLOR_TRANSPARENT_B   = TColor($00FFFFFF);
  TRANSPARENCY_CELL     = 16;
  MAX_VIEW_ZOOM         = 8.0;
  MIN_VIEW_ZOOM         = 0.25;
  VIEW_ZOOM_STEP        = 1.2;
  DEFAULT_TEXT_FONT_FAMILY = 'Yu Gothic UI';
  DEFAULT_TEXT_FONT_SIZE = 32.0;
  DEFAULT_TEXT_GUIDE_WIDTH = 320;
  DEFAULT_TEXT_GUIDE_HEIGHT = 80;
  // Falseにすると編集ビューの細線補正を一括で無効化する。
  ENABLE_THIN_STROKE_PREVIEW = True;
  MIN_PREVIEW_STROKE_WIDTH_PIXELS = 1.0;

procedure DrawPremultipliedBitmap(Target: TCanvas; const Bounds: TRect;
  Bitmap: Vcl.Graphics.TBitmap);
var
  Blend: BLENDFUNCTION;
begin
  if (Bitmap = nil) or (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then
    Exit;
  Blend.BlendOp := AC_SRC_OVER;
  Blend.BlendFlags := 0;
  Blend.SourceConstantAlpha := 255;
  Blend.AlphaFormat := AC_SRC_ALPHA;
  AlphaBlend(Target.Handle, Bounds.Left, Bounds.Top,
    Bounds.Width, Bounds.Height, Bitmap.Canvas.Handle,
    0, 0, Bitmap.Width, Bitmap.Height, Blend);
end;

type
  TPreviewLineSegment = record
    StartPoint: TPoint;
    EndPoint: TPoint;
  end;

function BuildVertexKindIconPoints(const Bounds: TRect;
  Kind: TScreenLayoutVertexKind): TArray<TPoint>;
var
  CenterX: Integer;
begin
  CenterX := (Bounds.Left + Bounds.Right) div 2;
  if Kind = slvkSharp then
  begin
    SetLength(Result, 3);
    Result[0] := Point(Bounds.Left + 5, Bounds.Top + 5);
    Result[1] := Point(CenterX, Bounds.Bottom - 5);
    Result[2] := Point(Bounds.Right - 5, Bounds.Top + 5);
  end
  else
  begin
    SetLength(Result, 7);
    Result[0] := Point(Bounds.Left + 5, Bounds.Top + 5);
    Result[1] := Point(Bounds.Left + 5, Bounds.Bottom - 8);
    Result[2] := Point(Bounds.Left + 7, Bounds.Bottom - 5);
    Result[3] := Point(CenterX, Bounds.Bottom - 4);
    Result[4] := Point(Bounds.Right - 7, Bounds.Bottom - 5);
    Result[5] := Point(Bounds.Right - 5, Bounds.Bottom - 8);
    Result[6] := Point(Bounds.Right - 5, Bounds.Top + 5);
  end;
end;

function BuildDiamondPoints(const Bounds: TRect): TArray<TPoint>;
begin
  SetLength(Result, 4);
  Result[0] := Point((Bounds.Left + Bounds.Right) div 2, Bounds.Top);
  Result[1] := Point(Bounds.Right, (Bounds.Top + Bounds.Bottom) div 2);
  Result[2] := Point((Bounds.Left + Bounds.Right) div 2, Bounds.Bottom);
  Result[3] := Point(Bounds.Left, (Bounds.Top + Bounds.Bottom) div 2);
end;

procedure BuildRotationMarkPoints(const Bounds: TRect;
  out ArcPoints, ArrowPoints: TArray<TPoint>);
const
  ARC_POINT_COUNT = 10;
var
  Angle: Single;
  CenterX: Single;
  CenterY: Single;
  I: Integer;
  PerpendicularX: Single;
  PerpendicularY: Single;
  Radius: Single;
  TangentX: Single;
  TangentY: Single;
  Tip: TPoint;
begin
  CenterX := (Bounds.Left + Bounds.Right) * 0.5;
  CenterY := (Bounds.Top + Bounds.Bottom) * 0.5;
  Radius := Max(Min(Bounds.Width, Bounds.Height) * 0.5 - 4, 2);
  SetLength(ArcPoints, ARC_POINT_COUNT);
  for I := 0 to High(ArcPoints) do
  begin
    Angle := DegToRad(45 + 270 * I / High(ArcPoints));
    ArcPoints[I] := Point(Round(CenterX + Cos(Angle) * Radius),
      Round(CenterY - Sin(Angle) * Radius));
  end;
  Tip := ArcPoints[High(ArcPoints)];
  Angle := DegToRad(315);
  TangentX := -Sin(Angle);
  TangentY := -Cos(Angle);
  PerpendicularX := -TangentY;
  PerpendicularY := TangentX;
  SetLength(ArrowPoints, 3);
  ArrowPoints[0] := Tip;
  ArrowPoints[1] := Point(Round(Tip.X - TangentX * 4 +
    PerpendicularX * 2), Round(Tip.Y - TangentY * 4 +
    PerpendicularY * 2));
  ArrowPoints[2] := Point(Round(Tip.X - TangentX * 4 -
    PerpendicularX * 2), Round(Tip.Y - TangentY * 4 -
    PerpendicularY * 2));
end;

function BuildStyledPreviewSegments(const StartPoint, EndPoint: TPoint;
  Width: Single; Style: TVectArtMifStrokeStyle): TArray<TPreviewLineSegment>;
var
  CurrentDistance: Single;
  DashIndex: Integer;
  DrawSegment: Boolean;
  DX: Single;
  DY: Single;
  EndDistance: Single;
  Intervals: TArray<Single>;
  LineLength: Single;
  SegmentLength: Single;
  UnitX: Single;
  UnitY: Single;
begin
  Result := nil;
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  LineLength := Hypot(DX, DY);
  if LineLength <= 0 then
    Exit;
  Intervals := VectArtStrokeDashIntervals(Style, Max(Width, 1.0));
  if Length(Intervals) = 0 then
  begin
    SetLength(Result, 1);
    Result[0].StartPoint := StartPoint;
    Result[0].EndPoint := EndPoint;
    Exit;
  end;
  UnitX := DX / LineLength;
  UnitY := DY / LineLength;
  CurrentDistance := 0;
  DashIndex := 0;
  DrawSegment := True;
  while CurrentDistance < LineLength do
  begin
    SegmentLength := Max(Intervals[DashIndex], 1.0);
    EndDistance := Min(CurrentDistance + SegmentLength, LineLength);
    if DrawSegment then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].StartPoint := Point(
        StartPoint.X + Round(UnitX * CurrentDistance),
        StartPoint.Y + Round(UnitY * CurrentDistance));
      Result[High(Result)].EndPoint := Point(
        StartPoint.X + Round(UnitX * EndDistance),
        StartPoint.Y + Round(UnitY * EndDistance));
    end;
    CurrentDistance := EndDistance;
    DashIndex := (DashIndex + 1) mod Length(Intervals);
    DrawSegment := not DrawSegment;
  end;
end;

procedure DrawStyledPreviewLine(Target: TCanvas; const StartPoint,
  EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap); overload;
var
  DX: Single;
  DY: Single;
  EffectiveCap: TVectArtLineCap;
  I: Integer;
  LengthValue: Single;
  P1: TPoint;
  P2: TPoint;
  Points: array[0..2] of TPoint;
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  EffectiveCap := LineCap;
  Target.Pen.Color := Color;
  Target.Pen.Width := Max(Round(Width), 1);
  Target.Pen.Style := psSolid;
  for I := 0 to High(Segments) do
  begin
    P1 := Segments[I].StartPoint;
    P2 := Segments[I].EndPoint;
    if EffectiveCap = vlcSquare then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        P1.Offset(-Round(DX / LengthValue * Width * 0.5),
          -Round(DY / LengthValue * Width * 0.5));
        P2.Offset(Round(DX / LengthValue * Width * 0.5),
          Round(DY / LengthValue * Width * 0.5));
      end;
    end;
    Target.MoveTo(P1.X, P1.Y);
    Target.LineTo(P2.X, P2.Y);
    if EffectiveCap = vlcRound then
    begin
      Radius := Max(Round(Width * 0.5), 1);
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := Color;
      Target.Ellipse(P1.X - Radius, P1.Y - Radius, P1.X + Radius + 1,
        P1.Y + Radius + 1);
      Target.Ellipse(P2.X - Radius, P2.Y - Radius, P2.X + Radius + 1,
        P2.Y + Radius + 1);
      Target.Brush.Style := bsClear;
    end
    else if EffectiveCap = vlcTriangle then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        Radius := Max(Round(Width * 0.5), 1);
        DX := DX / LengthValue;
        DY := DY / LengthValue;
        Target.Brush.Style := bsSolid;
        Target.Brush.Color := Color;
        Points[0] := Point(P1.X - Round(DY * Radius),
          P1.Y + Round(DX * Radius));
        Points[1] := Point(P1.X - Round(DX * Radius),
          P1.Y - Round(DY * Radius));
        Points[2] := Point(P1.X + Round(DY * Radius),
          P1.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Points[0] := Point(P2.X - Round(DY * Radius),
          P2.Y + Round(DX * Radius));
        Points[1] := Point(P2.X + Round(DX * Radius),
          P2.Y + Round(DY * Radius));
        Points[2] := Point(P2.X + Round(DY * Radius),
          P2.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Target.Brush.Style := bsClear;
      end;
    end;
  end;
  Target.Pen.Width := 1;
end;

procedure DrawStyledPreviewLine(Target: TDirect2DCanvas;
  const StartPoint, EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap); overload;
var
  DX: Single;
  DY: Single;
  EffectiveCap: TVectArtLineCap;
  I: Integer;
  LengthValue: Single;
  P1: TPoint;
  P2: TPoint;
  Points: array[0..2] of TPoint;
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Target.RenderTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  EffectiveCap := LineCap;
  Target.Pen.Color := Color;
  Target.Pen.Width := Max(Round(Width), 1);
  Target.Pen.Style := psSolid;
  for I := 0 to High(Segments) do
  begin
    P1 := Segments[I].StartPoint;
    P2 := Segments[I].EndPoint;
    if EffectiveCap = vlcSquare then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        P1.Offset(-Round(DX / LengthValue * Width * 0.5),
          -Round(DY / LengthValue * Width * 0.5));
        P2.Offset(Round(DX / LengthValue * Width * 0.5),
          Round(DY / LengthValue * Width * 0.5));
      end;
    end;
    Target.MoveTo(P1.X, P1.Y);
    Target.LineTo(P2.X, P2.Y);
    if EffectiveCap = vlcRound then
    begin
      Radius := Max(Round(Width * 0.5), 1);
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := Color;
      Target.Ellipse(P1.X - Radius, P1.Y - Radius, P1.X + Radius + 1,
        P1.Y + Radius + 1);
      Target.Ellipse(P2.X - Radius, P2.Y - Radius, P2.X + Radius + 1,
        P2.Y + Radius + 1);
      Target.Brush.Style := bsClear;
    end
    else if EffectiveCap = vlcTriangle then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        Radius := Max(Round(Width * 0.5), 1);
        DX := DX / LengthValue;
        DY := DY / LengthValue;
        Target.Brush.Style := bsSolid;
        Target.Brush.Color := Color;
        Points[0] := Point(P1.X - Round(DY * Radius),
          P1.Y + Round(DX * Radius));
        Points[1] := Point(P1.X - Round(DX * Radius),
          P1.Y - Round(DY * Radius));
        Points[2] := Point(P1.X + Round(DY * Radius),
          P1.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Points[0] := Point(P2.X - Round(DY * Radius),
          P2.Y + Round(DX * Radius));
        Points[1] := Point(P2.X + Round(DX * Radius),
          P2.Y + Round(DY * Radius));
        Points[2] := Point(P2.X + Round(DY * Radius),
          P2.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Target.Brush.Style := bsClear;
      end;
    end;
  end;
  Target.Pen.Width := 1;
  Target.RenderTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
end;

constructor TVectArtCanvasControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_EDITOR_SURROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FDirect2DEnabled := TDirect2DCanvas.Supported;
  FInteraction := TVectArtCanvasInteraction.Create;
  FReferenceBackground := Vcl.Graphics.TBitmap.Create;
  FReferenceBackground.PixelFormat := pf32bit;
  FRenderedDocument := Vcl.Graphics.TBitmap.Create;
  FRenderedDocument.PixelFormat := pf32bit;
  FRenderBuffer := TVectArtRenderBuffer.Create;
  FRenderedPreviewStrokeWidth := -1.0;
  FRenderedRevision := -1;
  FShapeCreation := TVectArtShapeCreation.Create;
  FTextEditor := TMemo.Create(Self);
  FTextEditor.Parent := Self;
  FTextEditor.BorderStyle := bsNone;
  FTextEditor.Color := COLOR_EDITOR_SURROUND;
  FTextEditor.Ctl3D := False;
  FTextEditor.ScrollBars := ssNone;
  FTextEditor.TabStop := False;
  FTextEditor.Visible := False;
  FTextEditor.WantReturns := True;
  FTextEditor.WordWrap := False;
  FTextEditor.SetBounds(0, 0, 1, 1);
  FTextEditor.OnChange := TextEditorChange;
  FTextEditor.OnExit := TextEditorExit;
  FTextEditor.OnKeyDown := TextEditorKeyDown;
  FTextEditor.OnKeyUp := TextEditorKeyUp;
  FPanOffset := TPointF.Zero;
  FViewZoom := 1.0;
  CalculateCanvasBounds;
end;

destructor TVectArtCanvasControl.Destroy;
begin
  FTextEditor.Free;
  FRenderBuffer.Free;
  FRenderedDocument.Free;
  FReferenceBackground.Free;
  FShapeCreation.Free;
  FInteraction.Free;
  inherited Destroy;
end;

procedure TVectArtCanvasControl.BeginNewTextEdit(
  const GuideBounds: TRectF);
var
  Data: TScreenLayoutTextData;
begin
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) then
    Exit;
  FTextBeforeSelection := FDocument.GetSelectedLayerIndices;
  Data := Default(TScreenLayoutTextData);
  Data.Bounds := TRectF.Create(GuideBounds.Left, GuideBounds.Top,
    GuideBounds.Left + 1, GuideBounds.Top + DEFAULT_TEXT_FONT_SIZE);
  Data.FontFamily := DEFAULT_TEXT_FONT_FAMILY;
  Data.FontSize := DEFAULT_TEXT_FONT_SIZE;
  Data.Locked := False;
  Data.Name := NextScreenLayoutLayerName(FDocument, 'Text');
  Data.Opacity := 1.0;
  Data.RotationDegrees := 0.0;
  Data.Text := '';
  Data.TextColor := clWhite;
  Data.Visible := True;
  Data.WrapWidth := Max(GuideBounds.Width, 1.0);
  FTextLayerIndex := FDocument.InsertText(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([FTextLayerIndex]);
  FTextGuideBounds := GuideBounds;
  FTextNewLayer := True;
  FTextEditor.Text := '';
  FTextEditor.Font.Name := Data.FontFamily;
  FTextEditor.Font.Size := Round(Data.FontSize);
  FTextEditor.Font.Color := Data.TextColor;
  FTextEditing := True;
  UpdateTextLayerFromEditor;
  FTextEditor.Visible := True;
  FTextEditor.BringToFront;
  FTextEditor.SetFocus;
  FTextEditor.SelStart := 0;
  UpdateTextEditorPosition;
end;

procedure TVectArtCanvasControl.BeginExistingTextEdit(Index: Integer);
var
  Layer: TScreenLayoutTextLayer;
begin
  if (FDocument = nil) or (Index <= 0) or
    (Index >= FDocument.LayerCount) or
    not (FDocument[Index] is TScreenLayoutTextLayer) or
    FDocument[Index].Locked then
    Exit;
  if FTextEditing then
    FinishTextEdit(False);
  Layer := TScreenLayoutTextLayer(FDocument[Index]);
  FTextBeforeSelection := FDocument.GetSelectedLayerIndices;
  FTextLayerIndex := Index;
  FTextOriginalData := CaptureScreenLayoutTextData(Layer);
  FTextGuideBounds := TRectF.Create(Layer.Bounds.Left, Layer.Bounds.Top,
    Layer.Bounds.Left + Max(Layer.WrapWidth, Layer.Bounds.Width),
    Layer.Bounds.Bottom);
  FTextNewLayer := False;
  FTextEditor.Text := Layer.Text;
  FTextEditor.Font.Name := Layer.FontFamily;
  FTextEditor.Font.Size := Round(Layer.FontSize);
  FTextEditor.Font.Color := Layer.FillColor;
  FTextEditing := True;
  UpdateTextLayerFromEditor;
  FTextEditor.Visible := True;
  FTextEditor.BringToFront;
  FTextEditor.SetFocus;
  FTextEditor.SelStart := Length(FTextEditor.Text);
  UpdateTextEditorPosition;
end;

procedure TVectArtCanvasControl.DblClick;
begin
  if (FDocument <> nil) and (FDocument.SelectedIndex > 0) and
    (FDocument.SelectedIndex < FDocument.LayerCount) and
    (FDocument[FDocument.SelectedIndex] is TScreenLayoutTextLayer) then
  begin
    BeginExistingTextEdit(FDocument.SelectedIndex);
    Exit;
  end;
  inherited DblClick;
end;

procedure TVectArtCanvasControl.DrawTextEditingOverlay(
  ACanvas: TCanvas);
var
  CaretBottom: TPointF;
  CaretLayout: TScreenLayoutTextLayout;
  CaretTop: TPointF;
  GuideRect: TRect;
  LastLine: Integer;
  Layer: TScreenLayoutTextLayer;
  Prefix: string;
begin
  if FTextDragActive then
  begin
    GuideRect := TRect.Create(
      Min(FTextDragStart.X, FTextDragCurrent.X),
      Min(FTextDragStart.Y, FTextDragCurrent.Y),
      Max(FTextDragStart.X, FTextDragCurrent.X),
      Max(FTextDragStart.Y, FTextDragCurrent.Y));
    ACanvas.Pen.Color := COLOR_SELECTION;
    ACanvas.Pen.Style := psDot;
    ACanvas.Brush.Style := bsClear;
    ACanvas.FrameRect(GuideRect);
    ACanvas.Pen.Style := psSolid;
  end;
  if not FTextEditing or (FDocument = nil) or
    (FTextLayerIndex <= 0) or (FTextLayerIndex >= FDocument.LayerCount) or
    not (FDocument[FTextLayerIndex] is TScreenLayoutTextLayer) then
    Exit;
  Layer := TScreenLayoutTextLayer(FDocument[FTextLayerIndex]);
  GuideRect := Rect(ToScreenX(FTextGuideBounds.Left),
    ToScreenY(FTextGuideBounds.Top), ToScreenX(FTextGuideBounds.Right),
    ToScreenY(Max(FTextGuideBounds.Bottom,
      FTextGuideBounds.Top + Layer.Bounds.Height)));
  ACanvas.Pen.Color := TColor($00808080);
  ACanvas.Pen.Style := psDot;
  ACanvas.Brush.Style := bsClear;
  ACanvas.FrameRect(GuideRect);
  ACanvas.Pen.Style := psSolid;

  Prefix := Copy(FTextEditor.Text, 1, FTextEditor.SelStart);
  CaretLayout := BuildScreenLayoutTextLayout(Prefix, Layer.FontFamily,
    Layer.FontSize, Layer.WrapWidth);
  LastLine := Max(High(CaretLayout.Lines), 0);
  CaretTop := TPointF.Create(Layer.Bounds.Left,
    Layer.Bounds.Top + LastLine * CaretLayout.LineHeight);
  if Length(CaretLayout.Lines) > 0 then
    CaretTop.X := CaretTop.X + CreateScreenLayoutTextFont(Layer.FontFamily,
      Layer.FontSize).MeasureText(CaretLayout.Lines[LastLine]);
  CaretBottom := TPointF.Create(CaretTop.X,
    CaretTop.Y + CaretLayout.LineHeight);
  CaretTop := RotatePointAround(CaretTop, Layer.Bounds.CenterPoint,
    Layer.RotationDegrees);
  CaretBottom := RotatePointAround(CaretBottom, Layer.Bounds.CenterPoint,
    Layer.RotationDegrees);
  ACanvas.Pen.Color := clWhite;
  ACanvas.MoveTo(ToScreenX(CaretTop.X), ToScreenY(CaretTop.Y));
  ACanvas.LineTo(ToScreenX(CaretBottom.X), ToScreenY(CaretBottom.Y));
end;

procedure TVectArtCanvasControl.DrawTextEditingOverlayDirect2D(
  ACanvas: TDirect2DCanvas);
var
  CaretBottom: TPointF;
  CaretLayout: TScreenLayoutTextLayout;
  CaretTop: TPointF;
  GuideRect: TRect;
  LastLine: Integer;
  Layer: TScreenLayoutTextLayer;
  Prefix: string;
begin
  if FTextDragActive then
  begin
    GuideRect := TRect.Create(
      Min(FTextDragStart.X, FTextDragCurrent.X),
      Min(FTextDragStart.Y, FTextDragCurrent.Y),
      Max(FTextDragStart.X, FTextDragCurrent.X),
      Max(FTextDragStart.Y, FTextDragCurrent.Y));
    ACanvas.Pen.Color := COLOR_SELECTION;
    ACanvas.Pen.Style := psDot;
    ACanvas.Brush.Style := bsClear;
    ACanvas.FrameRect(GuideRect);
    ACanvas.Pen.Style := psSolid;
  end;
  if not FTextEditing or (FDocument = nil) or
    (FTextLayerIndex <= 0) or (FTextLayerIndex >= FDocument.LayerCount) or
    not (FDocument[FTextLayerIndex] is TScreenLayoutTextLayer) then
    Exit;
  Layer := TScreenLayoutTextLayer(FDocument[FTextLayerIndex]);
  GuideRect := Rect(ToScreenX(FTextGuideBounds.Left),
    ToScreenY(FTextGuideBounds.Top), ToScreenX(FTextGuideBounds.Right),
    ToScreenY(Max(FTextGuideBounds.Bottom,
      FTextGuideBounds.Top + Layer.Bounds.Height)));
  ACanvas.Pen.Color := TColor($00808080);
  ACanvas.Pen.Style := psDot;
  ACanvas.Brush.Style := bsClear;
  ACanvas.FrameRect(GuideRect);
  ACanvas.Pen.Style := psSolid;

  Prefix := Copy(FTextEditor.Text, 1, FTextEditor.SelStart);
  CaretLayout := BuildScreenLayoutTextLayout(Prefix, Layer.FontFamily,
    Layer.FontSize, Layer.WrapWidth);
  LastLine := Max(High(CaretLayout.Lines), 0);
  CaretTop := TPointF.Create(Layer.Bounds.Left,
    Layer.Bounds.Top + LastLine * CaretLayout.LineHeight);
  if Length(CaretLayout.Lines) > 0 then
    CaretTop.X := CaretTop.X + CreateScreenLayoutTextFont(Layer.FontFamily,
      Layer.FontSize).MeasureText(CaretLayout.Lines[LastLine]);
  CaretBottom := TPointF.Create(CaretTop.X,
    CaretTop.Y + CaretLayout.LineHeight);
  CaretTop := RotatePointAround(CaretTop, Layer.Bounds.CenterPoint,
    Layer.RotationDegrees);
  CaretBottom := RotatePointAround(CaretBottom, Layer.Bounds.CenterPoint,
    Layer.RotationDegrees);
  ACanvas.Pen.Color := clWhite;
  ACanvas.MoveTo(ToScreenX(CaretTop.X), ToScreenY(CaretTop.Y));
  ACanvas.LineTo(ToScreenX(CaretBottom.X), ToScreenY(CaretBottom.Y));
end;

procedure TVectArtCanvasControl.FinishTextEdit(Cancel,
  RestoreCanvasFocus: Boolean);
var
  AfterSelection: TArray<Integer>;
  CurrentData: TScreenLayoutTextData;
  RemovedData: TScreenLayoutTextData;
begin
  if not FTextEditing or FTextEnding then
    Exit;
  FTextEnding := True;
  try
    FTextEditor.Visible := False;
    if (FDocument <> nil) and (FTextLayerIndex > 0) and
      (FTextLayerIndex < FDocument.LayerCount) and
      (FDocument[FTextLayerIndex] is TScreenLayoutTextLayer) then
    begin
      CurrentData := CaptureScreenLayoutTextData(
        TScreenLayoutTextLayer(FDocument[FTextLayerIndex]));
      if FTextNewLayer then
      begin
        if Cancel or (CurrentData.Text = '') then
        begin
          FDocument.RemoveText(FTextLayerIndex, RemovedData);
          FDocument.SetSelectedLayers(FTextBeforeSelection);
        end
        else if EditHistory <> nil then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          EditHistory.AddApplied(TScreenLayoutInsertTextCommand.Create(
            FDocument, FTextLayerIndex, CurrentData, FTextBeforeSelection,
            AfterSelection));
        end;
      end
      else if Cancel then
        FDocument.SetTextData(FTextLayerIndex, FTextOriginalData)
      else if CurrentData.Text = '' then
      begin
        FDocument.RemoveText(FTextLayerIndex, RemovedData);
        AfterSelection := FDocument.GetSelectedLayerIndices;
        if EditHistory <> nil then
          EditHistory.AddApplied(TScreenLayoutDeleteTextCommand.Create(
            FDocument, FTextLayerIndex, FTextOriginalData,
            FTextBeforeSelection, AfterSelection));
      end
      else if EditHistory <> nil then
        EditHistory.AddApplied(TScreenLayoutTextDataCommand.Create(FDocument,
          FTextLayerIndex, FTextOriginalData, CurrentData));
    end;
    FTextEditing := False;
    FTextLayerIndex := -1;
    FTextNewLayer := False;
    if RestoreCanvasFocus and
      not (csDestroying in ComponentState) and
      (Parent <> nil) and not (csDestroying in Parent.ComponentState) and
      not Application.Terminated and CanFocus then
      SetFocus;
    Invalidate;
  finally
    FTextEnding := False;
  end;
end;

procedure TVectArtCanvasControl.TextEditorChange(Sender: TObject);
begin
  if FTextEditing and not FTextEnding then
    UpdateTextLayerFromEditor;
end;

procedure TVectArtCanvasControl.TextEditorExit(Sender: TObject);
begin
  if FTextEditing and not FTextEnding then
    FinishTextEdit(False);
end;

procedure TVectArtCanvasControl.TextEditorKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    FinishTextEdit(True);
  end;
end;

procedure TVectArtCanvasControl.TextEditorKeyUp(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if FTextEditing and not FTextEnding then
  begin
    UpdateTextEditorPosition;
    Invalidate;
  end;
end;

procedure TVectArtCanvasControl.UpdateTextEditorPosition;
var
  CandidateForm: TCandidateForm;
  CaretLayout: TScreenLayoutTextLayout;
  CaretPoint: TPointF;
  CompositionForm: TCompositionForm;
  InputContext: HIMC;
  LastLine: Integer;
  Layer: TScreenLayoutTextLayer;
  Prefix: string;
  ScreenPoint: TPoint;
begin
  if not FTextEditing or (FDocument = nil) or
    (FTextLayerIndex <= 0) or (FTextLayerIndex >= FDocument.LayerCount) or
    not (FDocument[FTextLayerIndex] is TScreenLayoutTextLayer) then
    Exit;
  Layer := TScreenLayoutTextLayer(FDocument[FTextLayerIndex]);
  Prefix := Copy(FTextEditor.Text, 1, FTextEditor.SelStart);
  CaretLayout := BuildScreenLayoutTextLayout(Prefix, Layer.FontFamily,
    Layer.FontSize, Layer.WrapWidth);
  LastLine := Max(High(CaretLayout.Lines), 0);
  CaretPoint := TPointF.Create(Layer.Bounds.Left,
    Layer.Bounds.Top + LastLine * CaretLayout.LineHeight);
  if Length(CaretLayout.Lines) > 0 then
    CaretPoint.X := CaretPoint.X + CreateScreenLayoutTextFont(
      Layer.FontFamily, Layer.FontSize).MeasureText(
      CaretLayout.Lines[LastLine]);
  CaretPoint := RotatePointAround(CaretPoint, Layer.Bounds.CenterPoint,
    Layer.RotationDegrees);
  ScreenPoint := Point(ToScreenX(CaretPoint.X), ToScreenY(CaretPoint.Y));
  // 入力コントロールを親の原点へ固定し、IMEへ渡す座標系を
  // キャンバスのクライアント座標と一致させる。
  FTextEditor.SetBounds(0, 0, 1, 1);
  if not FTextEditor.HandleAllocated then
    Exit;
  InputContext := ImmGetContext(FTextEditor.Handle);
  if InputContext = 0 then
    Exit;
  try
    CompositionForm := Default(TCompositionForm);
    CompositionForm.dwStyle := CFS_FORCE_POSITION;
    CompositionForm.ptCurrentPos := ScreenPoint;
    ImmSetCompositionWindow(InputContext, @CompositionForm);
    CandidateForm := Default(TCandidateForm);
    CandidateForm.dwIndex := 0;
    CandidateForm.dwStyle := CFS_CANDIDATEPOS;
    CandidateForm.ptCurrentPos := Point(ScreenPoint.X, ScreenPoint.Y +
      Max(Round(CaretLayout.LineHeight * FZoom), 1));
    ImmSetCandidateWindow(InputContext, @CandidateForm);
  finally
    ImmReleaseContext(FTextEditor.Handle, InputContext);
  end;
end;

procedure TVectArtCanvasControl.UpdateTextLayerFromEditor;
var
  Data: TScreenLayoutTextData;
  Layout: TScreenLayoutTextLayout;
begin
  if not FTextEditing or (FDocument = nil) or
    (FTextLayerIndex <= 0) or (FTextLayerIndex >= FDocument.LayerCount) or
    not (FDocument[FTextLayerIndex] is TScreenLayoutTextLayer) then
    Exit;
  Data := CaptureScreenLayoutTextData(
    TScreenLayoutTextLayer(FDocument[FTextLayerIndex]));
  Data.Text := FTextEditor.Text;
  Data.WrapWidth := Max(FTextGuideBounds.Width, 1.0);
  Layout := BuildScreenLayoutTextLayout(Data.Text, Data.FontFamily,
    Data.FontSize, Data.WrapWidth);
  Data.Bounds := TRectF.Create(FTextGuideBounds.Left, FTextGuideBounds.Top,
    FTextGuideBounds.Left + Max(Layout.Width, 1.0),
    FTextGuideBounds.Top + Max(Layout.Height, Data.FontSize));
  FDocument.SetTextData(FTextLayerIndex, Data);
  UpdateTextEditorPosition;
  Invalidate;
end;

function TVectArtCanvasControl.HasReferenceBackground: Boolean;
begin
  Result := (FReferenceBackground <> nil) and
    (FReferenceBackground.Width > 0) and
    (FReferenceBackground.Height > 0);
end;

procedure TVectArtCanvasControl.CalculateCanvasBounds;
var
  AvailableHeight: Integer;
  AvailableWidth: Integer;
  ControlHeight: Integer;
  ControlWidth: Integer;
  DisplayHeight: Integer;
  DisplayWidth: Integer;
  LogicalHeight: Integer;
  LogicalWidth: Integer;
begin
  // Create/Parent/Alignの途中ではまだWinControlのハンドルを作成できない。
  // ClientWidth/ClientHeightは暗黙にHandleNeededを呼ぶため、その期間は
  // ハンドルを必要としないWidth/Heightを使って初期値を計算する。
  if HandleAllocated then
  begin
    ControlWidth := ClientWidth;
    ControlHeight := ClientHeight;
  end
  else
  begin
    ControlWidth := Width;
    ControlHeight := Height;
  end;
  AvailableWidth := Max(ControlWidth - (CANVAS_MARGIN * 2), 1);
  AvailableHeight := Max(ControlHeight - (CANVAS_MARGIN * 2), 1);
  LogicalWidth := DESIGN_CANVAS_WIDTH;
  LogicalHeight := DESIGN_CANVAS_HEIGHT;
  if (FDocument <> nil) and (FDocument.CanvasLayer <> nil) then
  begin
    LogicalWidth := Max(FDocument.CanvasLayer.Width, 1);
    LogicalHeight := Max(FDocument.CanvasLayer.Height, 1);
  end;
  FZoom := Min(AvailableWidth / LogicalWidth,
    AvailableHeight / LogicalHeight);
  FZoom := Min(FZoom, 1.0);
  FZoom := FZoom * FViewZoom;
  DisplayWidth := Max(Round(LogicalWidth * FZoom), 1);
  DisplayHeight := Max(Round(LogicalHeight * FZoom), 1);
  FCanvasBounds := Rect(
    (ControlWidth - DisplayWidth) div 2 + Round(FPanOffset.X),
    (ControlHeight - DisplayHeight) div 2 + Round(FPanOffset.Y),
    (ControlWidth + DisplayWidth) div 2 + Round(FPanOffset.X),
    (ControlHeight + DisplayHeight) div 2 + Round(FPanOffset.Y));
end;

function TVectArtCanvasControl.ToScreenX(Value: Single): Integer;
begin
  Result := LogicalToScreenX(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Width);
end;

function TVectArtCanvasControl.ToScreenY(Value: Single): Integer;
begin
  Result := LogicalToScreenY(Value, FCanvasBounds, FZoom,
    FDocument.CanvasLayer.Height);
end;

function TVectArtCanvasControl.TryClientPointToLogical(
  const ClientPoint: TPoint; out LogicalPoint: TPointF): Boolean;
begin
  CalculateCanvasBounds;
  Result := (FDocument <> nil) and (FDocument.CanvasLayer <> nil) and
    PtInRect(FCanvasBounds, ClientPoint);
  if not Result then
  begin
    LogicalPoint := TPointF.Zero;
    Exit;
  end;
  LogicalPoint := TPointF.Create(ScreenToLogicalX(ClientPoint.X,
    FCanvasBounds, FZoom, FDocument.CanvasLayer.Width),
    ScreenToLogicalY(ClientPoint.Y, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height));
end;

function TVectArtCanvasControl.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  CanvasX: Single;
  CanvasY: Single;
  ClientPoint: TPoint;
  NewViewZoom: Single;
begin
  ClientPoint := ScreenToClient(MousePos);
  if not PtInRect(ClientRect, ClientPoint) then
    Exit(inherited DoMouseWheel(Shift, WheelDelta, MousePos));

  Result := True;
  if WheelDelta = 0 then
    Exit;
  CalculateCanvasBounds;
  if FZoom <= 0 then
    Exit;

  // カーソル直下の論理キャンバス座標を、新しい倍率でも同じ位置に保つ。
  CanvasX := (ClientPoint.X - FCanvasBounds.Left) / FZoom;
  CanvasY := (ClientPoint.Y - FCanvasBounds.Top) / FZoom;
  if WheelDelta > 0 then
    NewViewZoom := FViewZoom * VIEW_ZOOM_STEP
  else
    NewViewZoom := FViewZoom / VIEW_ZOOM_STEP;
  NewViewZoom := EnsureRange(NewViewZoom, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM);
  if SameValue(NewViewZoom, FViewZoom) then
    Exit;

  FViewZoom := NewViewZoom;
  FPanOffset := TPointF.Zero;
  CalculateCanvasBounds;
  FPanOffset.X := ClientPoint.X - CanvasX * FZoom - FCanvasBounds.Left;
  FPanOffset.Y := ClientPoint.Y - CanvasY * FZoom - FCanvasBounds.Top;
  CalculateCanvasBounds;
  Invalidate;
end;

procedure TVectArtCanvasControl.EndPan;
begin
  if not FPanning then
    Exit;
  FPanning := False;
  MouseCapture := False;
  Cursor := crDefault;
end;

procedure TVectArtCanvasControl.KeyDown(var Key: Word;
  Shift: TShiftState);
begin
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if FShapeCreation.KeyDown(Key, Shift) then
  begin
    Key := 0;
    Invalidate;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

function TVectArtCanvasControl.GetEditHistory: TVectArtEditHistory;
begin
  Result := FInteraction.EditHistory;
end;

procedure TVectArtCanvasControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if (Button = mbRight) and (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetPath, vetShape]) and
    FShapeCreation.Active then
  begin
    if not FShapeCreation.FinishPath(
      FEditorState.CurrentTool = vetShape) then
      FShapeCreation.CancelPath;
    Invalidate;
    Exit;
  end;
  if Button = mbRight then
  begin
    CalculateCanvasBounds;
    FInteraction.Configure(FDocument, FCanvasBounds, FZoom);
    if FInteraction.MouseDown(Button, Shift, X, Y) then
    begin
      Invalidate;
      Exit;
    end;
    FPanning := True;
    FPanStartMouse := Point(X, Y);
    FPanStartOffset := FPanOffset;
    MouseCapture := True;
    Cursor := crSizeAll;
    Exit;
  end;
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    if FTextEditing then
    begin
      FinishTextEdit(False);
      Exit;
    end;
    if CanFocus then
      SetFocus;
    CalculateCanvasBounds;
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetText) then
    begin
      if not PtInRect(FCanvasBounds, Point(X, Y)) then
        Exit;
      FTextDragActive := True;
      FTextDragStart := Point(X, Y);
      FTextDragCurrent := FTextDragStart;
      MouseCapture := True;
      Cursor := crIBeam;
      Invalidate;
      Exit;
    end;
    FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
      FCanvasBounds, FZoom);
    if FShapeCreation.MouseDown(Button, Shift, X, Y) then
    begin
      if (FEditorState <> nil) and
        not (FEditorState.CurrentTool in [vetPath, vetShape]) then
        MouseCapture := True;
      Cursor := crCross;
      Invalidate;
      Exit;
    end;
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetRectangleLine, vetRectangle,
        vetRoundedRectangleLine, vetRoundedRectangle,
        vetEllipseLine, vetEllipse, vetArc, vetArcShape, vetLine, vetPath,
        vetShape, vetText]) then
    begin
      if FEditorState.CurrentTool = vetText then
        Cursor := crIBeam
      else
        Cursor := crCross;
      Exit;
    end;
    FInteraction.Configure(FDocument, FCanvasBounds, FZoom);
    if FInteraction.MouseDown(Button, Shift, X, Y) then
    begin
      MouseCapture := True;
      Cursor := FInteraction.CursorAt(X, Y);
    end;
    Invalidate;
    Exit;
  end;
  // 左ドラッグは将来の範囲選択用として、この段階では開始しない。
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtCanvasControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
begin
  if FTextDragActive then
  begin
    FTextDragCurrent := Point(X, Y);
    Cursor := crIBeam;
    Invalidate;
    Exit;
  end;
  if FPanning then
  begin
    if not (ssRight in Shift) then
    begin
      EndPan;
      Exit;
    end;
    FPanOffset.X := FPanStartOffset.X + X - FPanStartMouse.X;
    FPanOffset.Y := FPanStartOffset.Y + Y - FPanStartMouse.Y;
    CalculateCanvasBounds;
    Invalidate;
    Exit;
  end;
  CalculateCanvasBounds;
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if FShapeCreation.MouseMove(Shift, X, Y) then
  begin
    if not FShapeCreation.Active then
      MouseCapture := False;
    Cursor := crCross;
    Invalidate;
    Exit;
  end;
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool in [vetRectangleLine, vetRectangle,
      vetRoundedRectangleLine, vetRoundedRectangle,
      vetEllipseLine, vetEllipse, vetArc, vetArcShape, vetLine, vetPath,
      vetShape, vetText]) then
  begin
    if FEditorState.CurrentTool = vetText then
      Cursor := crIBeam
    else
      Cursor := crCross;
    Exit;
  end;
  FInteraction.Configure(FDocument, FCanvasBounds, FZoom);
  if FInteraction.MouseMove(Shift, X, Y) then
  begin
    if not FInteraction.Dragging then
      MouseCapture := False;
    Cursor := FInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  Cursor := FInteraction.CursorAt(X, Y);
  inherited MouseMove(Shift, X, Y);
end;

procedure TVectArtCanvasControl.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Bottom: Single;
  GuideRect: TRect;
  Left: Single;
  Right: Single;
  Top: Single;
begin
  if (Button = mbLeft) and FTextDragActive then
  begin
    FTextDragActive := False;
    MouseCapture := False;
    FTextDragCurrent := Point(X, Y);
    GuideRect := TRect.Create(Min(FTextDragStart.X, X),
      Min(FTextDragStart.Y, Y), Max(FTextDragStart.X, X),
      Max(FTextDragStart.Y, Y));
    if (GuideRect.Width < 4) or (GuideRect.Height < 4) then
      GuideRect := TRect.Create(FTextDragStart.X, FTextDragStart.Y,
        FTextDragStart.X + Round(DEFAULT_TEXT_GUIDE_WIDTH * FZoom),
        FTextDragStart.Y + Round(DEFAULT_TEXT_GUIDE_HEIGHT * FZoom));
    GuideRect.Intersect(FCanvasBounds);
    Left := ScreenToLogicalX(GuideRect.Left, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width);
    Top := ScreenToLogicalY(GuideRect.Top, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height);
    Right := ScreenToLogicalX(GuideRect.Right, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Width);
    Bottom := ScreenToLogicalY(GuideRect.Bottom, FCanvasBounds, FZoom,
      FDocument.CanvasLayer.Height);
    BeginNewTextEdit(TRectF.Create(Left, Top, Right, Bottom));
    Cursor := crIBeam;
    Invalidate;
    Exit;
  end;
  if (Button = mbRight) and FPanning then
  begin
    EndPan;
    Exit;
  end;
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  if FShapeCreation.MouseUp(Button, Shift, X, Y) then
  begin
    MouseCapture := False;
    Cursor := crCross;
    Invalidate;
    Exit;
  end;
  if FInteraction.MouseUp(Button) then
  begin
    MouseCapture := False;
    FInteraction.Configure(FDocument, FCanvasBounds, FZoom);
    Cursor := FInteraction.CursorAt(X, Y);
    Invalidate;
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TVectArtCanvasControl.Paint;
begin
  CalculateCanvasBounds;
  FInteraction.Configure(FDocument, FCanvasBounds, FZoom);
  FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
    FCanvasBounds, FZoom);
  UpdateRenderedDocument;
  if FDirect2DEnabled then
    try
      PaintDirect2D;
      Exit;
    except
      FDirect2DEnabled := False;
    end;
  PaintGDI;
end;

procedure TVectArtCanvasControl.UpdateRenderedDocument;
var
  Alpha: Integer;
  Destination: PByte;
  Height: Integer;
  Source: PVectArtRgbaPixel;
  PreviewStrokeWidth: Single;
  Width: Integer;
  X: Integer;
  Y: Integer;
begin
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) then
  begin
    FRenderedDocument.SetSize(0, 0);
    FRenderedRevision := -1;
    Exit;
  end;
  Width := Max(FDocument.CanvasLayer.Width, 1);
  Height := Max(FDocument.CanvasLayer.Height, 1);
  PreviewStrokeWidth := 0.0;
  if ENABLE_THIN_STROKE_PREVIEW and (FZoom > 0) then
    PreviewStrokeWidth := MIN_PREVIEW_STROKE_WIDTH_PIXELS / FZoom;
  if (FRenderedRevision = FDocument.Revision) and
    SameValue(FRenderedPreviewStrokeWidth, PreviewStrokeWidth) and
    (FRenderedDocument.Width = Width) and
    (FRenderedDocument.Height = Height) then
    Exit;

  RenderVectArtDocument(FDocument, FRenderBuffer, Width, Height,
    PreviewStrokeWidth);
  FRenderedDocument.PixelFormat := pf32bit;
  FRenderedDocument.SetSize(Width, Height);
  FRenderedDocument.AlphaFormat := afPremultiplied;
  Source := FRenderBuffer.Data;
  for Y := 0 to Height - 1 do
  begin
    Destination := FRenderedDocument.ScanLine[Y];
    for X := 0 to Width - 1 do
    begin
      Alpha := Source^.A;
      Destination[0] := (Integer(Source^.B) * Alpha + 127) div 255;
      Destination[1] := (Integer(Source^.G) * Alpha + 127) div 255;
      Destination[2] := (Integer(Source^.R) * Alpha + 127) div 255;
      Destination[3] := Alpha;
      Inc(Destination, 4);
      Inc(Source);
    end;
  end;
  FRenderedRevision := FDocument.Revision;
  FRenderedPreviewStrokeWidth := PreviewStrokeWidth;
end;

procedure TVectArtCanvasControl.PaintDirect2D;
var
  ArcHandles: TScreenLayoutArcAngleHandles;
  ArcLayer: TScreenLayoutArcLayer;
  ArcPreview: TArray<TPoint>;
  BezierHandles: TScreenLayoutBezierHandles;
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  CreationRect: TRect;
  Column: Integer;
  ColumnEnd: Integer;
  ColumnStart: Integer;
  CornerHandle: TScreenLayoutRoundedCornerHandle;
  CornerHandles: TArray<TScreenLayoutRoundedCornerHandle>;
  Direct2DCanvas: TDirect2DCanvas;
  DocumentBitmap: ID2D1Bitmap;
  ReferenceBitmap: ID2D1Bitmap;
  ReferenceRect: TD2D1RectF;
  Handle: TVectArtSelectionHandle;
  RotationHandleIndex: Integer;
  RotationArcPoints: TArray<TPoint>;
  RotationArrowPoints: TArray<TPoint>;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Layer: TVectArtLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  LayerRect: TRect;
  LineEnd: TPoint;
  LineStart: TPoint;
  PathPreview: TArray<TPoint>;
  PathVertexRects: TArray<TRect>;
  PreviewRadius: Integer;
  SelectedShapeVertexRect: TRect;
  ShapeKindButtons: TArray<TScreenLayoutVertexKindButton>;
  ShapeKindIconPoints: TArray<TPoint>;
  ShapeVertexRects: TArray<TRect>;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  PathVertices: TArray<TScreenLayoutVertex>;
  RectangleLayer: TVectArtRectangleLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
  RotatedBounds: TRectF;
  RangeRect: TRect;
  RadiusHandlePoints: TArray<TPoint>;
  RadiusHandleRect: TRect;
  Row: Integer;
  RowEnd: Integer;
  RowStart: Integer;
  SelectionGeometry: TVectArtSelectionGeometry;
  SelectionFrameOffsetPixels: Integer;
  SelectionLayerRect: TRect;
  SelectionLocked: Boolean;
  ScreenQuad: TVectArtScreenQuad;
  ShadowBounds: TRect;
  VisibleCanvasBounds: TRect;
begin
  Direct2DCanvas := TDirect2DCanvas.Create(Canvas, ClientRect);
  try
    Direct2DCanvas.BeginDraw;
    try
      SelectionLayerRect := TRect.Empty;
      SelectionFrameOffsetPixels := SelectionFrameOffset(0, FZoom);
      SelectionLocked := False;
      Direct2DCanvas.Brush.Color := COLOR_EDITOR_SURROUND;
      Direct2DCanvas.FillRect(ClientRect);
      ShadowBounds := FCanvasBounds;
      OffsetRect(ShadowBounds, CANVAS_SHADOW_OFFSET, CANVAS_SHADOW_OFFSET);
      Direct2DCanvas.Brush.Color := COLOR_CANVAS_SHADOW;
      Direct2DCanvas.FillRect(ShadowBounds);

      CanvasLayer := nil;
      if FDocument <> nil then
        CanvasLayer := FDocument.CanvasLayer;
      if HasReferenceBackground then
      begin
        ReferenceBitmap := Direct2DCanvas.CreateBitmap(FReferenceBackground);
        if ReferenceBitmap = nil then
          raise EInvalidOp.Create('Direct2D reference background creation failed');
        ReferenceRect := D2D1RectF(FCanvasBounds.Left, FCanvasBounds.Top,
          FCanvasBounds.Right, FCanvasBounds.Bottom);
        Direct2DCanvas.RenderTarget.DrawBitmap(ReferenceBitmap,
          @ReferenceRect);
        ReferenceBitmap := nil;
      end
      else if (CanvasLayer <> nil) and CanvasLayer.Visible and
        not CanvasLayer.Transparent then
      begin
        Direct2DCanvas.Brush.Color := CanvasLayer.BackgroundColor;
        Direct2DCanvas.FillRect(FCanvasBounds);
      end
      else
      begin
        if IntersectRect(VisibleCanvasBounds, FCanvasBounds, ClientRect) then
        begin
          ColumnStart := (VisibleCanvasBounds.Left - FCanvasBounds.Left) div
            TRANSPARENCY_CELL;
          ColumnEnd := (VisibleCanvasBounds.Right - 1 - FCanvasBounds.Left) div
            TRANSPARENCY_CELL;
          RowStart := (VisibleCanvasBounds.Top - FCanvasBounds.Top) div
            TRANSPARENCY_CELL;
          RowEnd := (VisibleCanvasBounds.Bottom - 1 - FCanvasBounds.Top) div
            TRANSPARENCY_CELL;
          for Row := RowStart to RowEnd do
            for Column := ColumnStart to ColumnEnd do
            begin
              CellRect := Rect(
                FCanvasBounds.Left + Column * TRANSPARENCY_CELL,
                FCanvasBounds.Top + Row * TRANSPARENCY_CELL,
                Min(FCanvasBounds.Left + (Column + 1) * TRANSPARENCY_CELL,
                  FCanvasBounds.Right),
                Min(FCanvasBounds.Top + (Row + 1) * TRANSPARENCY_CELL,
                  FCanvasBounds.Bottom));
              if Odd(Row + Column) then
                Direct2DCanvas.Brush.Color := COLOR_TRANSPARENT_A
              else
                Direct2DCanvas.Brush.Color := COLOR_TRANSPARENT_B;
              Direct2DCanvas.FillRect(CellRect);
            end;
        end;
      end;

      if (FRenderedDocument.Width > 0) and
        (FRenderedDocument.Height > 0) then
      begin
        DocumentBitmap := Direct2DCanvas.CreateBitmap(FRenderedDocument);
        if DocumentBitmap = nil then
          raise EInvalidOp.Create('Direct2D document bitmap creation failed');
        ReferenceRect := D2D1RectF(FCanvasBounds.Left, FCanvasBounds.Top,
          FCanvasBounds.Right, FCanvasBounds.Bottom);
        Direct2DCanvas.RenderTarget.DrawBitmap(DocumentBitmap,
          @ReferenceRect);
        DocumentBitmap := nil;
      end;

      if FDocument <> nil then
        for I := 1 to FDocument.LayerCount - 1 do
        begin
          Layer := FDocument[I];
          if not Layer.Visible or
            not ((Layer is TScreenLayoutRectangleLineLayer) or
              (Layer is TVectArtRectangleLayer) or
              (Layer is TScreenLayoutArcLayer) or
              (Layer is TVectArtPathLayer) or
              (Layer is TScreenLayoutShapeLayer) or
              (Layer is TVectArtImageLayer)) then
            Continue;
          if Layer is TScreenLayoutRectangleLineLayer then
          begin
            RectangleLine := TScreenLayoutRectangleLineLayer(Layer);
            RotatedBounds := QuadBounds(RectangleCorners(
              RectangleLine.Bounds, RectangleLine.RotationDegrees));
            SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
              SelectionFrameOffset(RectangleLine.StrokeWidth, FZoom));
          end
          else if Layer is TScreenLayoutArcLayer then
          begin
            ArcLayer := TScreenLayoutArcLayer(Layer);
            RotatedBounds := ScreenLayoutEllipseBounds(ArcLayer.Bounds,
              ArcLayer.RotationDegrees);
            SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
              SelectionFrameOffset(ArcLayer.StrokeWidth, FZoom));
          end
          else if Layer is TVectArtRectangleLayer then
          begin
            RectangleLayer := TVectArtRectangleLayer(Layer);
            RotatedBounds := QuadBounds(RectangleCorners(
              RectangleLayer.Bounds, RectangleLayer.RotationDegrees));
          end
          else if Layer is TVectArtPathLayer then
          begin
            PathLayer := TVectArtPathLayer(Layer);
            RotatedBounds := ScreenLayoutPathVerticesBounds(
              PathLayer.Vertices);
            if not PathLayer.Closed then
              SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
                SelectionFrameOffset(PathLayer.StrokeWidth, FZoom));
          end
          else if Layer is TScreenLayoutShapeLayer then
          begin
            ShapeLayer := TScreenLayoutShapeLayer(Layer);
            RotatedBounds := ScreenLayoutShapeContoursBounds(
              ShapeLayer.Contours);
            SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
              SelectionFrameOffset(ShapeLayer.StrokeWidth, FZoom));
          end
          else
          begin
            ImageLayer := TVectArtImageLayer(Layer);
            RotatedBounds := TRectF.Create(ImageLayer.Points[0],
              ImageLayer.Points[0]);
            for RotationHandleIndex := 1 to High(ImageLayer.Points) do
            begin
              RotatedBounds.Left := Min(RotatedBounds.Left,
                ImageLayer.Points[RotationHandleIndex].X);
              RotatedBounds.Top := Min(RotatedBounds.Top,
                ImageLayer.Points[RotationHandleIndex].Y);
              RotatedBounds.Right := Max(RotatedBounds.Right,
                ImageLayer.Points[RotationHandleIndex].X);
              RotatedBounds.Bottom := Max(RotatedBounds.Bottom,
                ImageLayer.Points[RotationHandleIndex].Y);
            end;
          end;
          LayerRect := Rect(ToScreenX(RotatedBounds.Left),
            ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
            ToScreenY(RotatedBounds.Bottom));
          if LayerRect.Width = 0 then
            Inc(LayerRect.Right);
          if LayerRect.Height = 0 then
            Inc(LayerRect.Bottom);
          if FDocument.IsLayerSelected(I) then
          begin
            SelectionLocked := SelectionLocked or Layer.Locked;
            if SelectionLayerRect.IsEmpty then
              SelectionLayerRect := LayerRect
            else
              SelectionLayerRect := Rect(
                Min(SelectionLayerRect.Left, LayerRect.Left),
                Min(SelectionLayerRect.Top, LayerRect.Top),
                Max(SelectionLayerRect.Right, LayerRect.Right),
                Max(SelectionLayerRect.Bottom, LayerRect.Bottom));
          end;
        end;
      if (SelectionLayerRect.Width > 0) and
        (SelectionLayerRect.Height > 0) then
      begin
        if (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
        begin
          PathLayer := TVectArtPathLayer(
            FDocument[FDocument.SelectedIndex]);
          PathVertices := PathLayer.Vertices;
          if not PathLayer.Closed and
            ScreenLayoutPathIsStraightLine(PathVertices) then
            SelectionGeometry := BuildLineSelectionGeometry(
              Point(ToScreenX(PathVertices[0].Position.X),
                ToScreenY(PathVertices[0].Position.Y)),
              Point(ToScreenX(PathVertices[1].Position.X),
                ToScreenY(PathVertices[1].Position.Y)))
          else
            SelectionGeometry := BuildPathSelectionGeometry(
              SelectionLayerRect, SelectionFrameOffsetPixels);
        end
        else if (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is
            TScreenLayoutShapeLayer) then
          SelectionGeometry := BuildPathSelectionGeometry(
            SelectionLayerRect, SelectionFrameOffsetPixels)
        else if (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) then
        begin
          ImageLayer := TVectArtImageLayer(
            FDocument[FDocument.SelectedIndex]);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(ImageLayer.Points[I].X),
              ToScreenY(ImageLayer.Points[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else if not FInteraction.AxisAlignedSelection and
          (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is
            TScreenLayoutRectangleLineLayer) then
        begin
          RectangleLine := TScreenLayoutRectangleLineLayer(
            FDocument[FDocument.SelectedIndex]);
          LogicalQuad := RectangleCorners(RectangleLine.Bounds,
            RectangleLine.RotationDegrees);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
              ToScreenY(LogicalQuad[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else if not FInteraction.AxisAlignedSelection and
          (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) then
        begin
          ArcLayer := TScreenLayoutArcLayer(
            FDocument[FDocument.SelectedIndex]);
          LogicalQuad := RectangleCorners(ArcLayer.Bounds,
            ArcLayer.RotationDegrees);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
              ToScreenY(LogicalQuad[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else if not FInteraction.AxisAlignedSelection and
          (FDocument.SelectionCount = 1) and
          (FDocument.SelectedIndex > 0) and
          (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) then
        begin
          RectangleLayer := TVectArtRectangleLayer(
            FDocument[FDocument.SelectedIndex]);
          LogicalQuad := RectangleCorners(RectangleLayer.Bounds,
            RectangleLayer.RotationDegrees);
          for I := 0 to High(ScreenQuad) do
            ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
              ToScreenY(LogicalQuad[I].Y));
          SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
            SelectionFrameOffsetPixels);
        end
        else
          SelectionGeometry := BuildSelectionGeometry(SelectionLayerRect,
            SelectionFrameOffsetPixels);
        Direct2DCanvas.Brush.Style := bsSolid;
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.Pen.Color := COLOR_SELECTION;
        if SelectionGeometry.DrawFrame then
          Direct2DCanvas.Polyline(SelectionGeometry.FramePoints);
        if not SelectionLocked then
        begin
          for Handle := vshTopLeft to vshLeft do
            if not SelectionGeometry.Handles[Handle].IsEmpty then
            begin
              Direct2DCanvas.Brush.Color := clWhite;
              Direct2DCanvas.FillRect(SelectionGeometry.Handles[Handle]);
              Direct2DCanvas.Brush.Color := COLOR_SELECTION;
              Direct2DCanvas.FrameRect(SelectionGeometry.Handles[Handle]);
            end;
          if (FDocument.SelectionCount = 1) and
            ((FDocument[FDocument.SelectedIndex] is TScreenLayoutRectangleLineLayer) or
             (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
             (FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) or
             (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) or
             (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) or
             (FDocument[FDocument.SelectedIndex] is
               TScreenLayoutShapeLayer)) and
            not FInteraction.AxisAlignedSelection then
          begin
            Direct2DCanvas.Pen.Color := COLOR_SELECTION;
            Direct2DCanvas.MoveTo(SelectionGeometry.RotationStem[0].X,
              SelectionGeometry.RotationStem[0].Y);
            Direct2DCanvas.LineTo(SelectionGeometry.RotationStem[1].X,
              SelectionGeometry.RotationStem[1].Y);
            Direct2DCanvas.Brush.Color := clWhite;
            Direct2DCanvas.Pen.Color := COLOR_ROTATION_MARK;
            Direct2DCanvas.Ellipse(
              SelectionGeometry.PrimaryRotationHandle.Left,
              SelectionGeometry.PrimaryRotationHandle.Top,
              SelectionGeometry.PrimaryRotationHandle.Right,
              SelectionGeometry.PrimaryRotationHandle.Bottom);
            BuildRotationMarkPoints(
              SelectionGeometry.PrimaryRotationHandle,
              RotationArcPoints, RotationArrowPoints);
            Direct2DCanvas.Polyline(RotationArcPoints);
            Direct2DCanvas.Brush.Color := COLOR_ROTATION_MARK;
            Direct2DCanvas.Polygon(RotationArrowPoints);
          end;
          CornerHandles := FInteraction.RoundedRectangleCornerHandles;
          for CornerHandle in CornerHandles do
          begin
            if CornerHandle.Selected then
              Direct2DCanvas.Brush.Color := TColor($0048A8F8)
            else
              Direct2DCanvas.Brush.Color := clWhite;
            Direct2DCanvas.Pen.Color := COLOR_SELECTION;
            Direct2DCanvas.Ellipse(CornerHandle.Bounds.Left,
              CornerHandle.Bounds.Top, CornerHandle.Bounds.Right,
              CornerHandle.Bounds.Bottom);
          end;
          if FInteraction.RoundedRectangleRadiusHandle(RadiusHandleRect) then
          begin
            RadiusHandlePoints := BuildDiamondPoints(RadiusHandleRect);
            Direct2DCanvas.Brush.Color := TColor($0048A8F8);
            Direct2DCanvas.Pen.Color := COLOR_SELECTION;
            Direct2DCanvas.Polygon(RadiusHandlePoints);
          end;
          if FInteraction.SelectedArcAngleHandles(ArcHandles) then
          begin
            Direct2DCanvas.Pen.Color := COLOR_SELECTION;
            Direct2DCanvas.Brush.Color := TColor($0060C060);
            Direct2DCanvas.Ellipse(ArcHandles.StartHandle.Left,
              ArcHandles.StartHandle.Top, ArcHandles.StartHandle.Right,
              ArcHandles.StartHandle.Bottom);
            Direct2DCanvas.Brush.Color := TColor($0048A8F8);
            Direct2DCanvas.Ellipse(ArcHandles.EndHandle.Left,
              ArcHandles.EndHandle.Top, ArcHandles.EndHandle.Right,
              ArcHandles.EndHandle.Bottom);
          end;
        end;
      end;
      PathVertexRects := FInteraction.SelectedPathVertexRects;
      for I := 0 to High(PathVertexRects) do
      begin
        Direct2DCanvas.Brush.Color := TColor($00F0C060);
        Direct2DCanvas.FillRect(PathVertexRects[I]);
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.FrameRect(PathVertexRects[I]);
      end;
      ShapeVertexRects := FInteraction.SelectedShapeVertexRects;
      for I := 0 to High(ShapeVertexRects) do
      begin
        Direct2DCanvas.Brush.Color := TColor($00F0C060);
        Direct2DCanvas.FillRect(ShapeVertexRects[I]);
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.FrameRect(ShapeVertexRects[I]);
      end;
      if FInteraction.SelectedShapeVertexRect(SelectedShapeVertexRect) then
      begin
        Direct2DCanvas.Brush.Color := clWhite;
        Direct2DCanvas.FillRect(SelectedShapeVertexRect);
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.FrameRect(SelectedShapeVertexRect);
      end;
      if FInteraction.SelectedShapeBezierHandles(BezierHandles) then
      begin
        SetLength(ShapeKindIconPoints, 2);
        ShapeKindIconPoints[0] := BezierHandles.IncomingPoint;
        ShapeKindIconPoints[1] := BezierHandles.OutgoingPoint;
        Direct2DCanvas.Pen.Color := COLOR_SELECTION;
        Direct2DCanvas.Pen.Style := psDot;
        Direct2DCanvas.Polyline(ShapeKindIconPoints);
        Direct2DCanvas.Pen.Style := psSolid;
        Direct2DCanvas.Brush.Color := clWhite;
        Direct2DCanvas.FillRect(BezierHandles.IncomingRect);
        Direct2DCanvas.FillRect(BezierHandles.OutgoingRect);
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.FrameRect(BezierHandles.IncomingRect);
        Direct2DCanvas.FrameRect(BezierHandles.OutgoingRect);
      end;
      ShapeKindButtons := FInteraction.SelectedShapeVertexKindButtons;
      for I := 0 to High(ShapeKindButtons) do
      begin
        if ShapeKindButtons[I].Selected then
          Direct2DCanvas.Brush.Color := TColor($00F0C060)
        else
          Direct2DCanvas.Brush.Color := clWhite;
        Direct2DCanvas.FillRect(ShapeKindButtons[I].Bounds);
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.FrameRect(ShapeKindButtons[I].Bounds);
        ShapeKindIconPoints := BuildVertexKindIconPoints(
          ShapeKindButtons[I].Bounds, ShapeKindButtons[I].Kind);
        Direct2DCanvas.Polyline(ShapeKindIconPoints);
      end;
      if FInteraction.RangeSelecting then
      begin
        RangeRect := FInteraction.RangeSelectionRect;
        Direct2DCanvas.Brush.Style := bsSolid;
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.FrameRect(RangeRect);
      end;
      CreationRect := FShapeCreation.PreviewRect;
      if not CreationRect.IsEmpty then
      begin
        if (FEditorState <> nil) and
          (FEditorState.CurrentTool = vetArcShape) then
        begin
          Direct2DCanvas.Brush.Style := bsSolid;
          Direct2DCanvas.Brush.Color := COLOR_SELECTION;
          Direct2DCanvas.Pie(CreationRect.Left, CreationRect.Top,
            CreationRect.Right, CreationRect.Bottom, CreationRect.Right,
            (CreationRect.Top + CreationRect.Bottom) div 2,
            CreationRect.Left,
            (CreationRect.Top + CreationRect.Bottom) div 2);
        end
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool = vetArc) then
          Direct2DCanvas.Brush.Style := bsClear
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool = vetRectangleLine) then
        begin
          Direct2DCanvas.Brush.Style := bsClear;
          Direct2DCanvas.Pen.Color := FEditorState.LineStrokeColor;
          Direct2DCanvas.Pen.Width := Max(
            Round(FEditorState.LineStrokeWidth * FZoom), 1);
          Direct2DCanvas.Rectangle(CreationRect);
          Direct2DCanvas.Pen.Width := 1;
        end
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool in [vetEllipseLine, vetEllipse]) then
        begin
          Direct2DCanvas.Brush.Style := bsClear;
          if FEditorState.CurrentTool = vetEllipseLine then
          begin
            Direct2DCanvas.Pen.Color := FEditorState.LineStrokeColor;
            Direct2DCanvas.Pen.Width := Max(
              Round(FEditorState.LineStrokeWidth * FZoom), 1);
          end
          else
            Direct2DCanvas.Pen.Color := COLOR_SELECTION;
          Direct2DCanvas.Ellipse(CreationRect);
          Direct2DCanvas.Pen.Width := 1;
        end
        else if (FEditorState <> nil) and
          (FEditorState.CurrentTool in [vetRoundedRectangleLine,
            vetRoundedRectangle]) then
        begin
          PreviewRadius := Round(Min(CreationRect.Width,
            CreationRect.Height) * 0.2);
          Direct2DCanvas.Brush.Style := bsClear;
          if FEditorState.CurrentTool = vetRoundedRectangleLine then
          begin
            Direct2DCanvas.Pen.Color := FEditorState.LineStrokeColor;
            Direct2DCanvas.Pen.Width := Max(
              Round(FEditorState.LineStrokeWidth * FZoom), 1);
          end
          else
            Direct2DCanvas.Pen.Color := COLOR_SELECTION;
          Direct2DCanvas.RoundRect(CreationRect.Left, CreationRect.Top,
            CreationRect.Right, CreationRect.Bottom, PreviewRadius * 2,
            PreviewRadius * 2);
          Direct2DCanvas.Pen.Width := 1;
        end
        else
        begin
          Direct2DCanvas.Brush.Style := bsSolid;
          Direct2DCanvas.Brush.Color := COLOR_SELECTION;
          Direct2DCanvas.FrameRect(CreationRect);
        end;
      end;
      if FShapeCreation.PreviewArc(ArcPreview) then
      begin
        Direct2DCanvas.Brush.Style := bsClear;
        Direct2DCanvas.Pen.Color := FEditorState.LineStrokeColor;
        Direct2DCanvas.Pen.Width := Max(
          Round(FEditorState.LineStrokeWidth * FZoom), 1);
        Direct2DCanvas.Polyline(ArcPreview);
        Direct2DCanvas.Pen.Width := 1;
      end;
      if FShapeCreation.PreviewLine(LineStart, LineEnd) then
        DrawStyledPreviewLine(Direct2DCanvas, LineStart, LineEnd,
          FEditorState.LineStrokeColor,
          FEditorState.LineStrokeWidth * FZoom,
          FEditorState.LineMifStrokeStyle, FEditorState.LineCap);
      if FShapeCreation.PreviewPath(PathPreview) then
      begin
        Direct2DCanvas.Pen.Color := COLOR_SELECTION;
        Direct2DCanvas.Polyline(PathPreview);
      end;
      DrawTextEditingOverlayDirect2D(Direct2DCanvas);
    finally
      Direct2DCanvas.EndDraw;
    end;
  finally
    Direct2DCanvas.Free;
  end;
end;

procedure TVectArtCanvasControl.PaintGDI;
var
  ArcHandles: TScreenLayoutArcAngleHandles;
  ArcLayer: TScreenLayoutArcLayer;
  ArcPreview: TArray<TPoint>;
  BezierHandles: TScreenLayoutBezierHandles;
  CanvasLayer: TVectArtCanvasLayer;
  CreationRect: TRect;
  CellRect: TRect;
  Column: Integer;
  ColumnEnd: Integer;
  ColumnStart: Integer;
  CornerHandle: TScreenLayoutRoundedCornerHandle;
  CornerHandles: TArray<TScreenLayoutRoundedCornerHandle>;
  Handle: TVectArtSelectionHandle;
  RotationHandleIndex: Integer;
  RotationArcPoints: TArray<TPoint>;
  RotationArrowPoints: TArray<TPoint>;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Layer: TVectArtLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  LayerRect: TRect;
  LineEnd: TPoint;
  LineStart: TPoint;
  PathPreview: TArray<TPoint>;
  PathVertexRects: TArray<TRect>;
  PreviewRadius: Integer;
  SelectedShapeVertexRect: TRect;
  ShapeKindButtons: TArray<TScreenLayoutVertexKindButton>;
  ShapeKindIconPoints: TArray<TPoint>;
  ShapeVertexRects: TArray<TRect>;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  PathVertices: TArray<TScreenLayoutVertex>;
  RectangleLayer: TVectArtRectangleLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
  RotatedBounds: TRectF;
  RangeRect: TRect;
  RadiusHandlePoints: TArray<TPoint>;
  RadiusHandleRect: TRect;
  Row: Integer;
  RowEnd: Integer;
  RowStart: Integer;
  SelectionGeometry: TVectArtSelectionGeometry;
  SelectionFrameOffsetPixels: Integer;
  SelectionLayerRect: TRect;
  SelectionLocked: Boolean;
  ScreenQuad: TVectArtScreenQuad;
  ShadowBounds: TRect;
  VisibleCanvasBounds: TRect;
begin
  SelectionLayerRect := TRect.Empty;
  SelectionFrameOffsetPixels := SelectionFrameOffset(0, FZoom);
  SelectionLocked := False;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := COLOR_EDITOR_SURROUND;
  Canvas.FillRect(ClientRect);
  ShadowBounds := FCanvasBounds;
  OffsetRect(ShadowBounds, CANVAS_SHADOW_OFFSET, CANVAS_SHADOW_OFFSET);
  Canvas.Brush.Color := COLOR_CANVAS_SHADOW;
  Canvas.FillRect(ShadowBounds);

  CanvasLayer := nil;
  if FDocument <> nil then
    CanvasLayer := FDocument.CanvasLayer;
  if HasReferenceBackground then
  begin
    Canvas.StretchDraw(FCanvasBounds, FReferenceBackground);
  end
  else if (CanvasLayer <> nil) and CanvasLayer.Visible and
    not CanvasLayer.Transparent then
  begin
    Canvas.Brush.Color := CanvasLayer.BackgroundColor;
    Canvas.FillRect(FCanvasBounds);
  end
  else
  begin
    if IntersectRect(VisibleCanvasBounds, FCanvasBounds, ClientRect) then
    begin
      ColumnStart := (VisibleCanvasBounds.Left - FCanvasBounds.Left) div
        TRANSPARENCY_CELL;
      ColumnEnd := (VisibleCanvasBounds.Right - 1 - FCanvasBounds.Left) div
        TRANSPARENCY_CELL;
      RowStart := (VisibleCanvasBounds.Top - FCanvasBounds.Top) div
        TRANSPARENCY_CELL;
      RowEnd := (VisibleCanvasBounds.Bottom - 1 - FCanvasBounds.Top) div
        TRANSPARENCY_CELL;
      for Row := RowStart to RowEnd do
        for Column := ColumnStart to ColumnEnd do
        begin
          CellRect := Rect(
            FCanvasBounds.Left + Column * TRANSPARENCY_CELL,
            FCanvasBounds.Top + Row * TRANSPARENCY_CELL,
            Min(FCanvasBounds.Left + (Column + 1) * TRANSPARENCY_CELL,
              FCanvasBounds.Right),
            Min(FCanvasBounds.Top + (Row + 1) * TRANSPARENCY_CELL,
              FCanvasBounds.Bottom));
          if Odd(Row + Column) then
            Canvas.Brush.Color := COLOR_TRANSPARENT_A
          else
            Canvas.Brush.Color := COLOR_TRANSPARENT_B;
          Canvas.FillRect(CellRect);
        end;
    end;
  end;

  DrawPremultipliedBitmap(Canvas, FCanvasBounds, FRenderedDocument);

  if FDocument <> nil then
    for I := 1 to FDocument.LayerCount - 1 do
    begin
      Layer := FDocument[I];
      if not Layer.Visible or
        not ((Layer is TScreenLayoutRectangleLineLayer) or
          (Layer is TVectArtRectangleLayer) or
          (Layer is TScreenLayoutArcLayer) or
          (Layer is TVectArtPathLayer) or
          (Layer is TScreenLayoutShapeLayer) or
          (Layer is TVectArtImageLayer)) then
        Continue;
      if Layer is TScreenLayoutRectangleLineLayer then
      begin
        RectangleLine := TScreenLayoutRectangleLineLayer(Layer);
        RotatedBounds := QuadBounds(RectangleCorners(RectangleLine.Bounds,
          RectangleLine.RotationDegrees));
        SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
          SelectionFrameOffset(RectangleLine.StrokeWidth, FZoom));
      end
      else if Layer is TScreenLayoutArcLayer then
      begin
        ArcLayer := TScreenLayoutArcLayer(Layer);
        RotatedBounds := ScreenLayoutEllipseBounds(ArcLayer.Bounds,
          ArcLayer.RotationDegrees);
        SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
          SelectionFrameOffset(ArcLayer.StrokeWidth, FZoom));
      end
      else if Layer is TVectArtRectangleLayer then
      begin
        RectangleLayer := TVectArtRectangleLayer(Layer);
        RotatedBounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
          RectangleLayer.RotationDegrees));
      end
      else if Layer is TVectArtPathLayer then
      begin
        PathLayer := TVectArtPathLayer(Layer);
        RotatedBounds := ScreenLayoutPathVerticesBounds(PathLayer.Vertices);
        if not PathLayer.Closed then
          SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
            SelectionFrameOffset(PathLayer.StrokeWidth, FZoom));
      end
      else if Layer is TScreenLayoutShapeLayer then
      begin
        ShapeLayer := TScreenLayoutShapeLayer(Layer);
        RotatedBounds := ScreenLayoutShapeContoursBounds(
          ShapeLayer.Contours);
        SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
          SelectionFrameOffset(ShapeLayer.StrokeWidth, FZoom));
      end
      else
      begin
        ImageLayer := TVectArtImageLayer(Layer);
        RotatedBounds := TRectF.Create(ImageLayer.Points[0],
          ImageLayer.Points[0]);
        for RotationHandleIndex := 1 to High(ImageLayer.Points) do
        begin
          RotatedBounds.Left := Min(RotatedBounds.Left,
            ImageLayer.Points[RotationHandleIndex].X);
          RotatedBounds.Top := Min(RotatedBounds.Top,
            ImageLayer.Points[RotationHandleIndex].Y);
          RotatedBounds.Right := Max(RotatedBounds.Right,
            ImageLayer.Points[RotationHandleIndex].X);
          RotatedBounds.Bottom := Max(RotatedBounds.Bottom,
            ImageLayer.Points[RotationHandleIndex].Y);
        end;
      end;
      LayerRect := Rect(ToScreenX(RotatedBounds.Left),
        ToScreenY(RotatedBounds.Top), ToScreenX(RotatedBounds.Right),
        ToScreenY(RotatedBounds.Bottom));
      if LayerRect.Width = 0 then
        Inc(LayerRect.Right);
      if LayerRect.Height = 0 then
        Inc(LayerRect.Bottom);
      if FDocument.IsLayerSelected(I) then
      begin
        SelectionLocked := SelectionLocked or Layer.Locked;
        if SelectionLayerRect.IsEmpty then
          SelectionLayerRect := LayerRect
        else
          SelectionLayerRect := Rect(
            Min(SelectionLayerRect.Left, LayerRect.Left),
            Min(SelectionLayerRect.Top, LayerRect.Top),
            Max(SelectionLayerRect.Right, LayerRect.Right),
            Max(SelectionLayerRect.Bottom, LayerRect.Bottom));
      end;
    end;
  if (SelectionLayerRect.Width > 0) and (SelectionLayerRect.Height > 0) then
  begin
    if (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) then
    begin
      PathLayer := TVectArtPathLayer(FDocument[FDocument.SelectedIndex]);
      PathVertices := PathLayer.Vertices;
      if not PathLayer.Closed and
        ScreenLayoutPathIsStraightLine(PathVertices) then
        SelectionGeometry := BuildLineSelectionGeometry(
          Point(ToScreenX(PathVertices[0].Position.X),
            ToScreenY(PathVertices[0].Position.Y)),
          Point(ToScreenX(PathVertices[1].Position.X),
            ToScreenY(PathVertices[1].Position.Y)))
      else
        SelectionGeometry := BuildPathSelectionGeometry(SelectionLayerRect,
          SelectionFrameOffsetPixels);
    end
    else if (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TScreenLayoutShapeLayer) then
      SelectionGeometry := BuildPathSelectionGeometry(SelectionLayerRect,
        SelectionFrameOffsetPixels)
    else if (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) then
    begin
      ImageLayer := TVectArtImageLayer(FDocument[FDocument.SelectedIndex]);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(ImageLayer.Points[I].X),
          ToScreenY(ImageLayer.Points[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else if not FInteraction.AxisAlignedSelection and
      (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is
        TScreenLayoutRectangleLineLayer) then
    begin
      RectangleLine := TScreenLayoutRectangleLineLayer(
        FDocument[FDocument.SelectedIndex]);
      LogicalQuad := RectangleCorners(RectangleLine.Bounds,
        RectangleLine.RotationDegrees);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
          ToScreenY(LogicalQuad[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else if not FInteraction.AxisAlignedSelection and
      (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) then
    begin
      ArcLayer := TScreenLayoutArcLayer(FDocument[FDocument.SelectedIndex]);
      LogicalQuad := RectangleCorners(ArcLayer.Bounds,
        ArcLayer.RotationDegrees);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
          ToScreenY(LogicalQuad[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else if not FInteraction.AxisAlignedSelection and
      (FDocument.SelectionCount = 1) and
      (FDocument.SelectedIndex > 0) and
      (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) then
    begin
      RectangleLayer := TVectArtRectangleLayer(
        FDocument[FDocument.SelectedIndex]);
      LogicalQuad := RectangleCorners(RectangleLayer.Bounds,
        RectangleLayer.RotationDegrees);
      for I := 0 to High(ScreenQuad) do
        ScreenQuad[I] := Point(ToScreenX(LogicalQuad[I].X),
          ToScreenY(LogicalQuad[I].Y));
      SelectionGeometry := BuildRotatedSelectionGeometry(ScreenQuad,
        SelectionFrameOffsetPixels);
    end
    else
      SelectionGeometry := BuildSelectionGeometry(SelectionLayerRect,
        SelectionFrameOffsetPixels);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.Pen.Color := COLOR_SELECTION;
    if SelectionGeometry.DrawFrame then
      Canvas.Polyline(SelectionGeometry.FramePoints);
    if not SelectionLocked then
    begin
      for Handle := vshTopLeft to vshLeft do
        if not SelectionGeometry.Handles[Handle].IsEmpty then
        begin
          Canvas.Brush.Color := clWhite;
          Canvas.FillRect(SelectionGeometry.Handles[Handle]);
          Canvas.Brush.Color := COLOR_SELECTION;
          Canvas.FrameRect(SelectionGeometry.Handles[Handle]);
        end;
      if (FDocument.SelectionCount = 1) and
        ((FDocument[FDocument.SelectedIndex] is TScreenLayoutRectangleLineLayer) or
         (FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
         (FDocument[FDocument.SelectedIndex] is TScreenLayoutArcLayer) or
         (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer) or
         (FDocument[FDocument.SelectedIndex] is TVectArtPathLayer) or
         (FDocument[FDocument.SelectedIndex] is
           TScreenLayoutShapeLayer)) and
        not FInteraction.AxisAlignedSelection then
      begin
        Canvas.Pen.Color := COLOR_SELECTION;
        Canvas.MoveTo(SelectionGeometry.RotationStem[0].X,
          SelectionGeometry.RotationStem[0].Y);
        Canvas.LineTo(SelectionGeometry.RotationStem[1].X,
          SelectionGeometry.RotationStem[1].Y);
        Canvas.Brush.Color := clWhite;
        Canvas.Pen.Color := COLOR_ROTATION_MARK;
        Canvas.Ellipse(SelectionGeometry.PrimaryRotationHandle);
        BuildRotationMarkPoints(SelectionGeometry.PrimaryRotationHandle,
          RotationArcPoints, RotationArrowPoints);
        Canvas.Polyline(RotationArcPoints);
        Canvas.Brush.Color := COLOR_ROTATION_MARK;
        Canvas.Polygon(RotationArrowPoints);
      end;
      CornerHandles := FInteraction.RoundedRectangleCornerHandles;
      for CornerHandle in CornerHandles do
      begin
        if CornerHandle.Selected then
          Canvas.Brush.Color := TColor($0048A8F8)
        else
          Canvas.Brush.Color := clWhite;
        Canvas.Pen.Color := COLOR_SELECTION;
        Canvas.Ellipse(CornerHandle.Bounds);
      end;
      if FInteraction.RoundedRectangleRadiusHandle(RadiusHandleRect) then
      begin
        RadiusHandlePoints := BuildDiamondPoints(RadiusHandleRect);
        Canvas.Brush.Color := TColor($0048A8F8);
        Canvas.Pen.Color := COLOR_SELECTION;
        Canvas.Polygon(RadiusHandlePoints);
      end;
      if FInteraction.SelectedArcAngleHandles(ArcHandles) then
      begin
        Canvas.Pen.Color := COLOR_SELECTION;
        Canvas.Brush.Color := TColor($0060C060);
        Canvas.Ellipse(ArcHandles.StartHandle);
        Canvas.Brush.Color := TColor($0048A8F8);
        Canvas.Ellipse(ArcHandles.EndHandle);
      end;
    end;
  end;
  PathVertexRects := FInteraction.SelectedPathVertexRects;
  for I := 0 to High(PathVertexRects) do
  begin
    Canvas.Brush.Color := TColor($00F0C060);
    Canvas.FillRect(PathVertexRects[I]);
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.FrameRect(PathVertexRects[I]);
  end;
  ShapeVertexRects := FInteraction.SelectedShapeVertexRects;
  for I := 0 to High(ShapeVertexRects) do
  begin
    Canvas.Brush.Color := TColor($00F0C060);
    Canvas.FillRect(ShapeVertexRects[I]);
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.FrameRect(ShapeVertexRects[I]);
  end;
  if FInteraction.SelectedShapeVertexRect(SelectedShapeVertexRect) then
  begin
    Canvas.Brush.Color := clWhite;
    Canvas.FillRect(SelectedShapeVertexRect);
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.FrameRect(SelectedShapeVertexRect);
  end;
  if FInteraction.SelectedShapeBezierHandles(BezierHandles) then
  begin
    SetLength(ShapeKindIconPoints, 2);
    ShapeKindIconPoints[0] := BezierHandles.IncomingPoint;
    ShapeKindIconPoints[1] := BezierHandles.OutgoingPoint;
    Canvas.Pen.Color := COLOR_SELECTION;
    Canvas.Pen.Style := psDot;
    Canvas.Polyline(ShapeKindIconPoints);
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Color := clWhite;
    Canvas.FillRect(BezierHandles.IncomingRect);
    Canvas.FillRect(BezierHandles.OutgoingRect);
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.FrameRect(BezierHandles.IncomingRect);
    Canvas.FrameRect(BezierHandles.OutgoingRect);
  end;
  ShapeKindButtons := FInteraction.SelectedShapeVertexKindButtons;
  for I := 0 to High(ShapeKindButtons) do
  begin
    if ShapeKindButtons[I].Selected then
      Canvas.Brush.Color := TColor($00F0C060)
    else
      Canvas.Brush.Color := clWhite;
    Canvas.FillRect(ShapeKindButtons[I].Bounds);
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.FrameRect(ShapeKindButtons[I].Bounds);
    ShapeKindIconPoints := BuildVertexKindIconPoints(
      ShapeKindButtons[I].Bounds, ShapeKindButtons[I].Kind);
    Canvas.Polyline(ShapeKindIconPoints);
  end;
  if FInteraction.RangeSelecting then
  begin
    RangeRect := FInteraction.RangeSelectionRect;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.FrameRect(RangeRect);
  end;
  CreationRect := FShapeCreation.PreviewRect;
  if not CreationRect.IsEmpty then
  begin
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetArcShape) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := COLOR_SELECTION;
      Canvas.Pie(CreationRect.Left, CreationRect.Top,
        CreationRect.Right, CreationRect.Bottom, CreationRect.Right,
        (CreationRect.Top + CreationRect.Bottom) div 2,
        CreationRect.Left, (CreationRect.Top + CreationRect.Bottom) div 2);
    end
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetArc) then
      Canvas.Brush.Style := bsClear
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool = vetRectangleLine) then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Pen.Color := FEditorState.LineStrokeColor;
      Canvas.Pen.Width := Max(Round(FEditorState.LineStrokeWidth * FZoom), 1);
      Canvas.Rectangle(CreationRect);
      Canvas.Pen.Width := 1;
    end
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetEllipseLine, vetEllipse]) then
    begin
      Canvas.Brush.Style := bsClear;
      if FEditorState.CurrentTool = vetEllipseLine then
      begin
        Canvas.Pen.Color := FEditorState.LineStrokeColor;
        Canvas.Pen.Width := Max(
          Round(FEditorState.LineStrokeWidth * FZoom), 1);
      end
      else
        Canvas.Pen.Color := COLOR_SELECTION;
      Canvas.Ellipse(CreationRect);
      Canvas.Pen.Width := 1;
    end
    else if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetRoundedRectangleLine,
        vetRoundedRectangle]) then
    begin
      PreviewRadius := Round(Min(CreationRect.Width,
        CreationRect.Height) * 0.2);
      Canvas.Brush.Style := bsClear;
      if FEditorState.CurrentTool = vetRoundedRectangleLine then
      begin
        Canvas.Pen.Color := FEditorState.LineStrokeColor;
        Canvas.Pen.Width := Max(
          Round(FEditorState.LineStrokeWidth * FZoom), 1);
      end
      else
        Canvas.Pen.Color := COLOR_SELECTION;
      Canvas.RoundRect(CreationRect.Left, CreationRect.Top,
        CreationRect.Right, CreationRect.Bottom, PreviewRadius * 2,
        PreviewRadius * 2);
      Canvas.Pen.Width := 1;
    end
    else
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := COLOR_SELECTION;
      Canvas.FrameRect(CreationRect);
    end;
  end;
  if FShapeCreation.PreviewArc(ArcPreview) then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := FEditorState.LineStrokeColor;
    Canvas.Pen.Width := Max(Round(FEditorState.LineStrokeWidth * FZoom), 1);
    Canvas.Polyline(ArcPreview);
    Canvas.Pen.Width := 1;
  end;
  if FShapeCreation.PreviewLine(LineStart, LineEnd) then
    DrawStyledPreviewLine(Canvas, LineStart, LineEnd,
      FEditorState.LineStrokeColor, FEditorState.LineStrokeWidth * FZoom,
      FEditorState.LineMifStrokeStyle, FEditorState.LineCap);
  if FShapeCreation.PreviewPath(PathPreview) then
  begin
    Canvas.Pen.Color := COLOR_SELECTION;
    Canvas.Polyline(PathPreview);
  end;
  DrawTextEditingOverlay(Canvas);
end;

procedure TVectArtCanvasControl.SetReferenceBackgroundRgba(
  const Pixels: TBytes; Width, Height: Integer);
var
  Destination: PByte;
  Source: PByte;
  X: Integer;
  Y: Integer;
begin
  FReferenceBackground.SetSize(0, 0);
  if (Width <= 0) or (Height <= 0) or
    (Length(Pixels) <> NativeInt(Width) * Height * 4) then
  begin
    Invalidate;
    Exit;
  end;
  FReferenceBackground.PixelFormat := pf32bit;
  FReferenceBackground.SetSize(Width, Height);
  FReferenceBackground.AlphaFormat := afIgnored;
  Source := @Pixels[0];
  for Y := 0 to Height - 1 do
  begin
    Destination := FReferenceBackground.ScanLine[Y];
    for X := 0 to Width - 1 do
    begin
      Destination[0] := Source[2];
      Destination[1] := Source[1];
      Destination[2] := Source[0];
      Destination[3] := 255;
      Inc(Destination, 4);
      Inc(Source, 4);
    end;
  end;
  Invalidate;
end;

procedure TVectArtCanvasControl.Resize;
begin
  inherited Resize;
  CalculateCanvasBounds;
  Invalidate;
end;

procedure TVectArtCanvasControl.SetDocument(const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  if FTextEditing then
    FinishTextEdit(True, False);
  FDocument := Value;
  FRenderedRevision := -1;
  FRenderedPreviewStrokeWidth := -1.0;
  FPanOffset := TPointF.Zero;
  FViewZoom := 1.0;
  CalculateCanvasBounds;
  Invalidate;
end;

procedure TVectArtCanvasControl.SetEditHistory(
  const Value: TVectArtEditHistory);
begin
  FInteraction.EditHistory := Value;
end;

procedure TVectArtCanvasControl.SetEditorState(
  const Value: TVectArtEditorState);
begin
  FEditorState := Value;
  Invalidate;
end;

end.
