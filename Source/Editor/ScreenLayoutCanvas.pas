// 中央編集領域のキャンバス表示を担当する。
// 論理サイズと画面上の拡大率を分離し、描画にはDirect2Dを優先して使用する。
unit ScreenLayoutCanvas;

interface

uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls, Vcl.Graphics,
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
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
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
  System.Math, Winapi.D2D1, Winapi.Windows, Vcl.Direct2D,
  ScreenLayoutGeometry;

const
  CANVAS_MARGIN         = 32;
  CANVAS_SHADOW_OFFSET  = 6;
  COLOR_EDITOR_SURROUND = TColor($00121212);
  COLOR_CANVAS_SHADOW   = TColor($00070707);
  COLOR_SELECTION       = clBlack;
  COLOR_TRANSPARENT_A   = TColor($00D8D8D8);
  COLOR_TRANSPARENT_B   = TColor($00FFFFFF);
  TRANSPARENCY_CELL     = 16;
  MAX_VIEW_ZOOM         = 8.0;
  MIN_VIEW_ZOOM         = 0.25;
  VIEW_ZOOM_STEP        = 1.2;
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
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  EffectiveCap := LineCap;
  if VectArtStrokeUsesRoundCaps(Style) then
    EffectiveCap := vlcRound;
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
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Target.RenderTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  EffectiveCap := LineCap;
  if VectArtStrokeUsesRoundCaps(Style) then
    EffectiveCap := vlcRound;
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
  FPanOffset := TPointF.Zero;
  FViewZoom := 1.0;
  CalculateCanvasBounds;
end;

destructor TVectArtCanvasControl.Destroy;
begin
  FRenderBuffer.Free;
  FRenderedDocument.Free;
  FReferenceBackground.Free;
  FShapeCreation.Free;
  FInteraction.Free;
  inherited Destroy;
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
    (FEditorState.CurrentTool = vetPath) and FShapeCreation.Active then
  begin
    if not FShapeCreation.FinishPath(False) then
      FShapeCreation.CancelPath;
    Invalidate;
    Exit;
  end;
  if Button = mbRight then
  begin
    FPanning := True;
    FPanStartMouse := Point(X, Y);
    FPanStartOffset := FPanOffset;
    MouseCapture := True;
    Cursor := crSizeAll;
    Exit;
  end;
  if (Button = mbLeft) and (FDocument <> nil) then
  begin
    if CanFocus then
      SetFocus;
    CalculateCanvasBounds;
    FShapeCreation.Configure(FDocument, EditHistory, FEditorState,
      FCanvasBounds, FZoom);
    if FShapeCreation.MouseDown(Button, Shift, X, Y) then
    begin
      if (FEditorState <> nil) and
        (FEditorState.CurrentTool <> vetPath) then
        MouseCapture := True;
      Cursor := crCross;
      Invalidate;
      Exit;
    end;
    if (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetRectangle, vetLine, vetPath]) then
    begin
      Cursor := crCross;
      Exit;
    end;
    FInteraction.Configure(FDocument, FCanvasBounds, FZoom);
    if FInteraction.MouseDown(Button, Shift, X, Y) then
    begin
      MouseCapture := True;
      Cursor := FInteraction.CursorAt(X, Y);
    end;
    Exit;
  end;
  // 左ドラッグは将来の範囲選択用として、この段階では開始しない。
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtCanvasControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
begin
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
    (FEditorState.CurrentTool in [vetRectangle, vetLine, vetPath]) then
  begin
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
begin
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
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  CreationRect: TRect;
  Column: Integer;
  ColumnEnd: Integer;
  ColumnStart: Integer;
  Direct2DCanvas: TDirect2DCanvas;
  DocumentBitmap: ID2D1Bitmap;
  ReferenceBitmap: ID2D1Bitmap;
  ReferenceRect: TD2D1RectF;
  Handle: TVectArtSelectionHandle;
  RotationHandleIndex: Integer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Layer: TVectArtLayer;
  LayerRect: TRect;
  LineEnd: TPoint;
  LineStart: TPoint;
  PathPreview: TArray<TPoint>;
  PathVertexRects: TArray<TRect>;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  RectangleLayer: TVectArtRectangleLayer;
  RotatedBounds: TRectF;
  RangeRect: TRect;
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
            not ((Layer is TVectArtRectangleLayer) or
              (Layer is TVectArtPathLayer) or
              (Layer is TVectArtImageLayer)) then
            Continue;
          if Layer is TVectArtRectangleLayer then
          begin
            RectangleLayer := TVectArtRectangleLayer(Layer);
            RotatedBounds := QuadBounds(RectangleCorners(
              RectangleLayer.Bounds, RectangleLayer.RotationDegrees));
          end
          else if Layer is TVectArtPathLayer then
          begin
            PathLayer := TVectArtPathLayer(Layer);
            RotatedBounds := PointsBounds(PathLayer.Points);
            if not PathLayer.Closed then
              SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
                SelectionFrameOffset(PathLayer.StrokeWidth, FZoom));
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
          if not PathLayer.Closed and (Length(PathLayer.Points) = 2) then
            SelectionGeometry := BuildLineSelectionGeometry(
              Point(ToScreenX(PathLayer.Points[0].X),
                ToScreenY(PathLayer.Points[0].Y)),
              Point(ToScreenX(PathLayer.Points[1].X),
                ToScreenY(PathLayer.Points[1].Y)))
          else
            SelectionGeometry := BuildPathSelectionGeometry(
              SelectionLayerRect, SelectionFrameOffsetPixels);
        end
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
            ((FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
             (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer)) and
            not FInteraction.AxisAlignedSelection then
            for RotationHandleIndex := 0 to 3 do
            begin
              Direct2DCanvas.Brush.Color := TColor($00F0C060);
              Direct2DCanvas.FillRect(
                SelectionGeometry.RotationHandles[RotationHandleIndex]);
              Direct2DCanvas.Brush.Color := COLOR_SELECTION;
              Direct2DCanvas.FrameRect(
                SelectionGeometry.RotationHandles[RotationHandleIndex]);
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
        Direct2DCanvas.Brush.Style := bsSolid;
        Direct2DCanvas.Brush.Color := COLOR_SELECTION;
        Direct2DCanvas.FrameRect(CreationRect);
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
    finally
      Direct2DCanvas.EndDraw;
    end;
  finally
    Direct2DCanvas.Free;
  end;
end;

procedure TVectArtCanvasControl.PaintGDI;
var
  CanvasLayer: TVectArtCanvasLayer;
  CreationRect: TRect;
  CellRect: TRect;
  Column: Integer;
  ColumnEnd: Integer;
  ColumnStart: Integer;
  Handle: TVectArtSelectionHandle;
  RotationHandleIndex: Integer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Layer: TVectArtLayer;
  LayerRect: TRect;
  LineEnd: TPoint;
  LineStart: TPoint;
  PathPreview: TArray<TPoint>;
  PathVertexRects: TArray<TRect>;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  RectangleLayer: TVectArtRectangleLayer;
  RotatedBounds: TRectF;
  RangeRect: TRect;
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
        not ((Layer is TVectArtRectangleLayer) or
          (Layer is TVectArtPathLayer) or
          (Layer is TVectArtImageLayer)) then
        Continue;
      if Layer is TVectArtRectangleLayer then
      begin
        RectangleLayer := TVectArtRectangleLayer(Layer);
        RotatedBounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
          RectangleLayer.RotationDegrees));
      end
      else if Layer is TVectArtPathLayer then
      begin
        PathLayer := TVectArtPathLayer(Layer);
        RotatedBounds := PointsBounds(PathLayer.Points);
        if not PathLayer.Closed then
          SelectionFrameOffsetPixels := Max(SelectionFrameOffsetPixels,
            SelectionFrameOffset(PathLayer.StrokeWidth, FZoom));
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
      if not PathLayer.Closed and (Length(PathLayer.Points) = 2) then
        SelectionGeometry := BuildLineSelectionGeometry(
          Point(ToScreenX(PathLayer.Points[0].X),
            ToScreenY(PathLayer.Points[0].Y)),
          Point(ToScreenX(PathLayer.Points[1].X),
            ToScreenY(PathLayer.Points[1].Y)))
      else
        SelectionGeometry := BuildPathSelectionGeometry(SelectionLayerRect,
          SelectionFrameOffsetPixels);
    end
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
        ((FDocument[FDocument.SelectedIndex] is TVectArtRectangleLayer) or
         (FDocument[FDocument.SelectedIndex] is TVectArtImageLayer)) and
        not FInteraction.AxisAlignedSelection then
        for RotationHandleIndex := 0 to 3 do
        begin
          Canvas.Brush.Color := TColor($00F0C060);
          Canvas.FillRect(SelectionGeometry.RotationHandles[
            RotationHandleIndex]);
          Canvas.Brush.Color := COLOR_SELECTION;
          Canvas.FrameRect(SelectionGeometry.RotationHandles[
            RotationHandleIndex]);
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
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := COLOR_SELECTION;
    Canvas.FrameRect(CreationRect);
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
