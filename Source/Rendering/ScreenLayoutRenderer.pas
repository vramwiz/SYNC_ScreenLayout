// Documentの表示オブジェクトを、各ホストで共有できる透明RGBA8画像へ描画する。
// 線種と四角・丸・三角の線端をSkia描画へ反映する。
unit ScreenLayoutRenderer;

interface

uses
  System.SysUtils, ScreenLayoutDocument;

type
  TVectArtRgbaPixel = packed record
    R: Byte;
    G: Byte;
    B: Byte;
    A: Byte;
  end;
  PVectArtRgbaPixel = ^TVectArtRgbaPixel;

  TVectArtRenderBuffer = class
  private
    FHeight: Integer;
    FPixels: TArray<TVectArtRgbaPixel>;
    FWidth: Integer;
    function GetData: PVectArtRgbaPixel;
    function GetPixelCount: NativeInt;
    function GetStride: NativeInt;
  public
    procedure Clear;
    procedure SetSize(AWidth, AHeight: Integer);
    property Data: PVectArtRgbaPixel read GetData;
    property Height: Integer read FHeight;
    property PixelCount: NativeInt read GetPixelCount;
    property Pixels: TArray<TVectArtRgbaPixel> read FPixels;
    property Stride: NativeInt read GetStride;
    property Width: Integer read FWidth;
  end;

// Canvas背景を含めず、図形だけを透明RGBA8へ描画する。
// MinimumStrokeWidthは編集補助用の論理座標幅で、0ならDocumentの線幅を変更しない。
procedure RenderVectArtDocument(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  MinimumStrokeWidth: Single = 0.0);
// ストレートアルファRGBA8同士をSource-overで合成する。
procedure CompositeVectArtRgba(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height: Integer);

implementation

uses
  System.Math, System.Skia, System.Types, System.UITypes,
  TextRendererSkiaRuntime, Vcl.Graphics, Winapi.Windows,
  ScreenLayoutEllipseGeometry, ScreenLayoutGeometry,
  ScreenLayoutShapePath;

const
  MAX_RENDER_DIMENSION = 16384;

function VclColorToAlphaColor(Color: TColor; Opacity: Single): TAlphaColor;
var
  RGBColor: TColor;
begin
  RGBColor := ColorToRGB(Color);
  Result := TAlphaColor(
    (Cardinal(EnsureRange(Round(Opacity * 255), 0, 255)) shl 24) or
    (Cardinal(GetRValue(RGBColor)) shl 16) or
    (Cardinal(GetGValue(RGBColor)) shl 8) or
    Cardinal(GetBValue(RGBColor)));
end;

procedure DrawTriangleLineCap(const Canvas: ISkCanvas; const Position: TPointF;
  OutwardDirection: TPointF; HalfWidth: Single; const Paint: ISkPaint);
var
  DirectionLength: Single;
  Normal: TPointF;
  PathBuilder: ISkPathBuilder;
  Tip: TPointF;
begin
  DirectionLength := Hypot(OutwardDirection.X, OutwardDirection.Y);
  if DirectionLength <= 0.0001 then
    Exit;
  OutwardDirection := TPointF.Create(OutwardDirection.X / DirectionLength,
    OutwardDirection.Y / DirectionLength);
  Normal := TPointF.Create(-OutwardDirection.Y * HalfWidth,
    OutwardDirection.X * HalfWidth);
  Tip := TPointF.Create(Position.X + OutwardDirection.X * HalfWidth,
    Position.Y + OutwardDirection.Y * HalfWidth);
  PathBuilder := TSkPathBuilder.Create;
  PathBuilder.MoveTo(TPointF.Create(Position.X + Normal.X,
    Position.Y + Normal.Y));
  PathBuilder.LineTo(Tip);
  PathBuilder.LineTo(TPointF.Create(Position.X - Normal.X,
    Position.Y - Normal.Y));
  PathBuilder.Close;
  Canvas.DrawPath(PathBuilder.Detach, Paint);
end;

procedure DrawPathTriangleCaps(const Canvas: ISkCanvas;
  const Vertices: TArray<TScreenLayoutVertex>; StrokeWidth: Single;
  const Paint: ISkPaint);
var
  Direction: TPointF;
  LastIndex: Integer;
begin
  if Length(Vertices) < 2 then
    Exit;
  LastIndex := High(Vertices);
  if (Vertices[0].OutgoingSegment = slskCubicBezier) and
    not IsZero(Hypot(Vertices[0].OutgoingControl.X,
      Vertices[0].OutgoingControl.Y)) then
    Direction := Vertices[0].OutgoingControl
  else
    Direction := TPointF.Create(Vertices[1].Position.X -
      Vertices[0].Position.X, Vertices[1].Position.Y -
      Vertices[0].Position.Y);
  DrawTriangleLineCap(Canvas, Vertices[0].Position,
    TPointF.Create(-Direction.X, -Direction.Y), StrokeWidth * 0.5, Paint);

  if (Vertices[LastIndex - 1].OutgoingSegment = slskCubicBezier) and
    not IsZero(Hypot(Vertices[LastIndex].IncomingControl.X,
      Vertices[LastIndex].IncomingControl.Y)) then
    Direction := TPointF.Create(-Vertices[LastIndex].IncomingControl.X,
      -Vertices[LastIndex].IncomingControl.Y)
  else
    Direction := TPointF.Create(Vertices[LastIndex].Position.X -
      Vertices[LastIndex - 1].Position.X,
      Vertices[LastIndex].Position.Y -
      Vertices[LastIndex - 1].Position.Y);
  DrawTriangleLineCap(Canvas, Vertices[LastIndex].Position, Direction,
    StrokeWidth * 0.5, Paint);
end;

function BuildRoundedRectanglePath(const Bounds: TRectF;
  const SourceRadii: TScreenLayoutCornerRadii): ISkPath;
const
  KAPPA = 0.5522847498;
var
  Builder: ISkPathBuilder;
  Radii: TScreenLayoutCornerRadii;
begin
  Radii := ClampScreenLayoutCornerRadii(Bounds, SourceRadii);
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(Bounds.Left + Radii.TopLeft, Bounds.Top);
  Builder.LineTo(Bounds.Right - Radii.TopRight, Bounds.Top);
  if Radii.TopRight > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Right - Radii.TopRight * (1 - KAPPA),
        Bounds.Top),
      TPointF.Create(Bounds.Right,
        Bounds.Top + Radii.TopRight * (1 - KAPPA)),
      TPointF.Create(Bounds.Right, Bounds.Top + Radii.TopRight));
  Builder.LineTo(Bounds.Right, Bounds.Bottom - Radii.BottomRight);
  if Radii.BottomRight > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Right,
        Bounds.Bottom - Radii.BottomRight * (1 - KAPPA)),
      TPointF.Create(Bounds.Right - Radii.BottomRight * (1 - KAPPA),
        Bounds.Bottom),
      TPointF.Create(Bounds.Right - Radii.BottomRight, Bounds.Bottom));
  Builder.LineTo(Bounds.Left + Radii.BottomLeft, Bounds.Bottom);
  if Radii.BottomLeft > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Left + Radii.BottomLeft * (1 - KAPPA),
        Bounds.Bottom),
      TPointF.Create(Bounds.Left,
        Bounds.Bottom - Radii.BottomLeft * (1 - KAPPA)),
      TPointF.Create(Bounds.Left, Bounds.Bottom - Radii.BottomLeft));
  Builder.LineTo(Bounds.Left, Bounds.Top + Radii.TopLeft);
  if Radii.TopLeft > 0 then
    Builder.CubicTo(
      TPointF.Create(Bounds.Left,
        Bounds.Top + Radii.TopLeft * (1 - KAPPA)),
      TPointF.Create(Bounds.Left + Radii.TopLeft * (1 - KAPPA),
        Bounds.Top),
      TPointF.Create(Bounds.Left + Radii.TopLeft, Bounds.Top));
  Builder.Close;
  Result := Builder.Detach;
end;

{ TVectArtRenderBuffer }

procedure TVectArtRenderBuffer.Clear;
begin
  if Length(FPixels) > 0 then
    FillChar(FPixels[0], Length(FPixels) * SizeOf(TVectArtRgbaPixel), 0);
end;

function TVectArtRenderBuffer.GetData: PVectArtRgbaPixel;
begin
  if Length(FPixels) = 0 then
    Result := nil
  else
    Result := @FPixels[0];
end;

function TVectArtRenderBuffer.GetPixelCount: NativeInt;
begin
  Result := Length(FPixels);
end;

function TVectArtRenderBuffer.GetStride: NativeInt;
begin
  Result := NativeInt(FWidth) * SizeOf(TVectArtRgbaPixel);
end;

procedure TVectArtRenderBuffer.SetSize(AWidth, AHeight: Integer);
var
  Count: Int64;
begin
  if (AWidth < 0) or (AHeight < 0) or
    (AWidth > MAX_RENDER_DIMENSION) or (AHeight > MAX_RENDER_DIMENSION) then
    raise EArgumentOutOfRangeException.Create('Invalid render dimensions');
  Count := Int64(AWidth) * AHeight;
  if Count > MaxInt then
    raise EArgumentOutOfRangeException.Create('Render buffer is too large');
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FPixels, NativeInt(Count));
end;

procedure RenderVectArtDocument(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  MinimumStrokeWidth: Single);
var
  ArcEndPoint: TPointF;
  ArcEndTangent: TPointF;
  ArcLayer: TScreenLayoutArcLayer;
  ArcStartPoint: TPointF;
  ArcStartTangent: TPointF;
  Canvas: ISkCanvas;
  CanvasLayer: TVectArtCanvasLayer;
  DashIntervals: TArray<Single>;
  EllipseLayer: TScreenLayoutEllipseLayer;
  EllipseLine: TScreenLayoutEllipseLineLayer;
  EllipseArcShape: TScreenLayoutEllipseArcShapeLayer;
  I: Integer;
  J: Integer;
  ImageInfo: TSkImageInfo;
  ImageLayer: TVectArtImageLayer;
  ImagePaint: ISkPaint;
  RasterImage: ISkImage;
  EdgeWidth: Single;
  SignedHeight: Single;
  RotationDegrees: Single;
  Layer: TVectArtLayer;
  Paint: ISkPaint;
  Path: ISkPath;
  PathBuilder: ISkPathBuilder;
  PathLayer: TVectArtPathLayer;
  PathSegmentCount: Integer;
  PathVertices: TArray<TScreenLayoutVertex>;
  RectangleLayer: TVectArtRectangleLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLineCorners: TVectArtQuad;
  RoundedRectangleLayer: TScreenLayoutRoundedRectangleLayer;
  RoundedRectangleLine: TScreenLayoutRoundedRectangleLineLayer;
  ScaleX: Single;
  ScaleY: Single;
  StrokeWidth: Single;
  StrokePaint: ISkPaint;
  Surface: ISkSurface;
  ShapeLayer: TScreenLayoutShapeLayer;

begin
  if Document = nil then
    raise EArgumentNilException.Create('Document');
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  if not TTextRendererSkiaRuntime.IsAcquired then
    raise EInvalidOp.Create('Skia runtime is not acquired');
  CanvasLayer := Document.CanvasLayer;
  if CanvasLayer = nil then
    raise EInvalidOp.Create('Document canvas is missing');
  if (Width <= 0) or (Height <= 0) then
    raise EArgumentOutOfRangeException.Create('Render dimensions must be positive');

  Target.SetSize(Width, Height);
  Target.Clear;
  ImageInfo := TSkImageInfo.Create(Width, Height, TSkColorType.RGBA8888,
    TSkAlphaType.Unpremul);
  Surface := TSkSurface.MakeRasterDirect(ImageInfo, Target.Data,
    Target.Stride);
  if Surface = nil then
    raise EInvalidOp.Create('Cannot create VectArt raster surface');
  Canvas := Surface.Canvas;
  Canvas.Clear(TAlphaColorRec.Null);
  ScaleX := Width / Max(CanvasLayer.Width, 1);
  ScaleY := Height / Max(CanvasLayer.Height, 1);
  MinimumStrokeWidth := Max(MinimumStrokeWidth, 0.0);
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  StrokePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  StrokePaint.AntiAlias := True;
  ImagePaint := TSkPaint.Create;
  ImagePaint.AntiAlias := True;
  Canvas.Scale(ScaleX, ScaleY);
  Canvas.Translate(CanvasLayer.Width * 0.5, CanvasLayer.Height * 0.5);
  for I := 1 to Document.LayerCount - 1 do
  begin
    Layer := Document[I];
    if not Layer.Visible then
      Continue;
    if Layer is TVectArtImageLayer then
    begin
      ImageLayer := TVectArtImageLayer(Layer);
      RasterImage := TSkImage.MakeFromEncoded(ImageLayer.PngData);
      if (RasterImage = nil) or (RasterImage.Width <= 0) or
        (RasterImage.Height <= 0) then
        Continue;
      EdgeWidth := Hypot(
        ImageLayer.Points[1].X - ImageLayer.Points[0].X,
        ImageLayer.Points[1].Y - ImageLayer.Points[0].Y);
      if EdgeWidth <= 0 then
        Continue;
      SignedHeight := (
        (ImageLayer.Points[1].X - ImageLayer.Points[0].X) *
          (ImageLayer.Points[3].Y - ImageLayer.Points[0].Y) -
        (ImageLayer.Points[1].Y - ImageLayer.Points[0].Y) *
          (ImageLayer.Points[3].X - ImageLayer.Points[0].X)) / EdgeWidth;
      if Abs(SignedHeight) <= 0 then
        Continue;
      RotationDegrees := RadToDeg(ArcTan2(
        ImageLayer.Points[1].Y - ImageLayer.Points[0].Y,
        ImageLayer.Points[1].X - ImageLayer.Points[0].X));
      ImagePaint.AlphaF := EnsureRange(ImageLayer.Opacity, 0.0, 1.0);
      Canvas.Save;
      try
        Canvas.Translate(ImageLayer.Points[0].X, ImageLayer.Points[0].Y);
        Canvas.Rotate(RotationDegrees);
        Canvas.Scale(EdgeWidth / RasterImage.Width,
          SignedHeight / RasterImage.Height);
        Canvas.DrawImage(RasterImage, 0, 0, TSkSamplingOptions.Medium,
          ImagePaint);
      finally
        Canvas.Restore;
      end;
      Continue;
    end;
    if Layer is TScreenLayoutShapeLayer then
    begin
      ShapeLayer := TScreenLayoutShapeLayer(Layer);
      Path := BuildScreenLayoutShapePath(ShapeLayer);
      Paint.AntiAlias := True;
      Paint.Color := VclColorToAlphaColor(ShapeLayer.FillColor,
        ShapeLayer.Opacity);
      Canvas.DrawPath(Path, Paint);
      if ShapeLayer.StrokeWidth > 0 then
      begin
        StrokeWidth := Max(ShapeLayer.StrokeWidth, MinimumStrokeWidth);
        StrokePaint.AntiAlias := True;
        StrokePaint.Color := VclColorToAlphaColor(ShapeLayer.StrokeColor,
          ShapeLayer.Opacity);
        StrokePaint.StrokeWidth := StrokeWidth;
        DashIntervals := VectArtStrokeDashIntervals(ShapeLayer.StrokeStyle,
          StrokeWidth);
        if Length(DashIntervals) > 0 then
          StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
        else
          StrokePaint.PathEffect := nil;
        Canvas.DrawPath(Path, StrokePaint);
      end;
      Continue;
    end;
    if Layer is TScreenLayoutRectangleLineLayer then
    begin
      RectangleLine := TScreenLayoutRectangleLineLayer(Layer);
      if Layer is TScreenLayoutEllipseLineLayer then
      begin
        EllipseLine := TScreenLayoutEllipseLineLayer(Layer);
        Path := BuildScreenLayoutEllipseLinePath(EllipseLine);
      end
      else if Layer is TScreenLayoutRoundedRectangleLineLayer then
      begin
        RoundedRectangleLine := TScreenLayoutRoundedRectangleLineLayer(Layer);
        Path := BuildRoundedRectanglePath(RoundedRectangleLine.Bounds,
          RoundedRectangleLine.CornerRadii);
      end
      else
      begin
        RectangleLineCorners := RectangleCorners(RectangleLine.Bounds,
          RectangleLine.RotationDegrees);
        PathBuilder := TSkPathBuilder.Create;
        PathBuilder.MoveTo(RectangleLineCorners[0].X,
          RectangleLineCorners[0].Y);
        for J := 1 to High(RectangleLineCorners) do
          PathBuilder.LineTo(RectangleLineCorners[J].X,
            RectangleLineCorners[J].Y);
        PathBuilder.Close;
        Path := PathBuilder.Detach;
      end;
      StrokeWidth := Max(RectangleLine.StrokeWidth, MinimumStrokeWidth);
      StrokePaint.Color := VclColorToAlphaColor(RectangleLine.StrokeColor,
        RectangleLine.Opacity);
      StrokePaint.StrokeWidth := StrokeWidth;
      StrokePaint.StrokeCap := TSkStrokeCap.Butt;
      DashIntervals := VectArtStrokeDashIntervals(RectangleLine.StrokeStyle,
        StrokeWidth);
      if Length(DashIntervals) > 0 then
        StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
      else
        StrokePaint.PathEffect := nil;
      if Layer is TScreenLayoutRoundedRectangleLineLayer then
      begin
        Canvas.Save;
        try
          Canvas.Rotate(RectangleLine.RotationDegrees,
            (RectangleLine.Bounds.Left + RectangleLine.Bounds.Right) * 0.5,
            (RectangleLine.Bounds.Top + RectangleLine.Bounds.Bottom) * 0.5);
          Canvas.DrawPath(Path, StrokePaint);
        finally
          Canvas.Restore;
        end;
      end
      else
        Canvas.DrawPath(Path, StrokePaint);
      Continue;
    end;
    if Layer is TScreenLayoutArcLayer then
    begin
      ArcLayer := TScreenLayoutArcLayer(Layer);
      Path := BuildScreenLayoutArcPath(ArcLayer);
      StrokeWidth := Max(ArcLayer.StrokeWidth, MinimumStrokeWidth);
      StrokePaint.Color := VclColorToAlphaColor(ArcLayer.StrokeColor,
        ArcLayer.Opacity);
      StrokePaint.StrokeWidth := StrokeWidth;
      DashIntervals := VectArtStrokeDashIntervals(ArcLayer.StrokeStyle,
        StrokeWidth);
      if Length(DashIntervals) > 0 then
        StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
      else
        StrokePaint.PathEffect := nil;
      case ArcLayer.LineCap of
        vlcRound: StrokePaint.StrokeCap := TSkStrokeCap.Round;
        vlcTriangle: StrokePaint.StrokeCap := TSkStrokeCap.Butt;
      else
        StrokePaint.StrokeCap := TSkStrokeCap.Square;
      end;
      Canvas.DrawPath(Path, StrokePaint);
      if ArcLayer.LineCap = vlcTriangle then
      begin
        ArcStartPoint := ScreenLayoutEllipsePoint(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees);
        ArcEndPoint := ScreenLayoutArcEndPoint(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees,
          ArcLayer.SweepAngleDegrees);
        ArcStartTangent := ScreenLayoutEllipseTangent(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees);
        ArcEndTangent := ScreenLayoutEllipseTangent(ArcLayer.Bounds,
          ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees +
          ArcLayer.SweepAngleDegrees);
        Paint.Color := StrokePaint.Color;
        Paint.Style := TSkPaintStyle.Fill;
        DrawTriangleLineCap(Canvas, ArcStartPoint,
          TPointF.Create(-ArcStartTangent.X, -ArcStartTangent.Y),
          StrokeWidth * 0.5, Paint);
        DrawTriangleLineCap(Canvas, ArcEndPoint, ArcEndTangent,
          StrokeWidth * 0.5, Paint);
      end;
      Continue;
    end;
    if Layer is TVectArtPathLayer then
    begin
      PathLayer := TVectArtPathLayer(Layer);
      Paint.AntiAlias := True;
      StrokePaint.AntiAlias := True;
      PathVertices := PathLayer.Vertices;
      if Length(PathVertices) < 2 then
        Continue;
      PathBuilder := TSkPathBuilder.Create;
      PathBuilder.MoveTo(PathVertices[0].Position);
      if PathLayer.Closed then
        PathSegmentCount := Length(PathVertices)
      else
        PathSegmentCount := Length(PathVertices) - 1;
      for J := 0 to PathSegmentCount - 1 do
        if PathVertices[J].OutgoingSegment = slskCubicBezier then
          PathBuilder.CubicTo(TPointF.Create(
            PathVertices[J].Position.X +
              PathVertices[J].OutgoingControl.X,
            PathVertices[J].Position.Y +
              PathVertices[J].OutgoingControl.Y),
            TPointF.Create(
              PathVertices[(J + 1) mod Length(PathVertices)].Position.X +
                PathVertices[(J + 1) mod Length(PathVertices)].IncomingControl.X,
              PathVertices[(J + 1) mod Length(PathVertices)].Position.Y +
                PathVertices[(J + 1) mod Length(PathVertices)].IncomingControl.Y),
            PathVertices[(J + 1) mod Length(PathVertices)].Position)
        else
          PathBuilder.LineTo(
            PathVertices[(J + 1) mod Length(PathVertices)].Position);
      if PathLayer.Closed then
        PathBuilder.Close;
      Path := PathBuilder.Detach;
      StrokeWidth := Max(PathLayer.StrokeWidth, MinimumStrokeWidth);
      StrokePaint.Color := VclColorToAlphaColor(PathLayer.StrokeColor,
        PathLayer.Opacity);
      StrokePaint.StrokeWidth := StrokeWidth;
      DashIntervals := VectArtStrokeDashIntervals(PathLayer.MifStrokeStyle,
        StrokeWidth);
      if Length(DashIntervals) > 0 then
        StrokePaint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0)
      else
        StrokePaint.PathEffect := nil;
      case PathLayer.LineCap of
        vlcRound: StrokePaint.StrokeCap := TSkStrokeCap.Round;
        vlcTriangle: StrokePaint.StrokeCap := TSkStrokeCap.Butt;
      else
        StrokePaint.StrokeCap := TSkStrokeCap.Square;
      end;
      Canvas.DrawPath(Path, StrokePaint);
      if not PathLayer.Closed and (PathLayer.LineCap = vlcTriangle) then
      begin
        Paint.Color := StrokePaint.Color;
        Paint.Style := TSkPaintStyle.Fill;
        DrawPathTriangleCaps(Canvas, PathVertices, StrokeWidth, Paint);
      end;
      Continue;
    end;
    if Layer is TScreenLayoutEllipseArcShapeLayer then
    begin
      EllipseArcShape := TScreenLayoutEllipseArcShapeLayer(Layer);
      Paint.AntiAlias := True;
      Paint.Color := VclColorToAlphaColor(EllipseArcShape.FillColor,
        EllipseArcShape.Opacity);
      Canvas.DrawPath(BuildScreenLayoutEllipseArcShapePath(EllipseArcShape),
        Paint);
      Continue;
    end;
    if Layer is TScreenLayoutEllipseLayer then
    begin
      EllipseLayer := TScreenLayoutEllipseLayer(Layer);
      Paint.AntiAlias := True;
      Paint.Color := VclColorToAlphaColor(EllipseLayer.FillColor,
        EllipseLayer.Opacity);
      Canvas.DrawPath(BuildScreenLayoutEllipsePath(EllipseLayer), Paint);
      Continue;
    end;
    if Layer is TScreenLayoutRoundedRectangleLayer then
    begin
      RoundedRectangleLayer := TScreenLayoutRoundedRectangleLayer(Layer);
      Paint.AntiAlias := True;
      Paint.Color := VclColorToAlphaColor(RoundedRectangleLayer.FillColor,
        RoundedRectangleLayer.Opacity);
      Canvas.Save;
      try
        Canvas.Rotate(RoundedRectangleLayer.RotationDegrees,
          (RoundedRectangleLayer.Bounds.Left +
            RoundedRectangleLayer.Bounds.Right) * 0.5,
          (RoundedRectangleLayer.Bounds.Top +
            RoundedRectangleLayer.Bounds.Bottom) * 0.5);
        Canvas.DrawPath(BuildRoundedRectanglePath(RoundedRectangleLayer.Bounds,
          RoundedRectangleLayer.CornerRadii), Paint);
      finally
        Canvas.Restore;
      end;
      Continue;
    end;
    if not (Layer is TVectArtRectangleLayer) then
      Continue;
    RectangleLayer := TVectArtRectangleLayer(Layer);
    Paint.AntiAlias := True;
    Paint.Color := VclColorToAlphaColor(RectangleLayer.FillColor,
      RectangleLayer.Opacity);
    Canvas.Save;
    try
      Canvas.Rotate(RectangleLayer.RotationDegrees,
        (RectangleLayer.Bounds.Left + RectangleLayer.Bounds.Right) * 0.5,
        (RectangleLayer.Bounds.Top + RectangleLayer.Bounds.Bottom) * 0.5);
      Canvas.DrawRect(RectangleLayer.Bounds, Paint);
    finally
      Canvas.Restore;
    end;
  end;
  Surface.Flush;
end;

procedure CompositeVectArtRgba(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height: Integer);
var
  AlphaDenominator: Cardinal;
  DestinationAlpha: Cardinal;
  DestinationPixel: PVectArtRgbaPixel;
  I: NativeInt;
  PixelCount: NativeInt;
  SourceAlpha: Cardinal;
  SourcePixel: PVectArtRgbaPixel;
begin
  if (Source = nil) or (Destination = nil) or
    (Source.Width <> Width) or (Source.Height <> Height) then
    Exit;
  PixelCount := NativeInt(Width) * Height;
  SourcePixel := Source.Data;
  DestinationPixel := Destination;
  for I := 0 to PixelCount - 1 do
  begin
    SourceAlpha := SourcePixel^.A;
    if SourceAlpha = 255 then
      DestinationPixel^ := SourcePixel^
    else if SourceAlpha <> 0 then
    begin
      DestinationAlpha := DestinationPixel^.A;
      AlphaDenominator := SourceAlpha * 255 +
        DestinationAlpha * (255 - SourceAlpha);
      if AlphaDenominator <> 0 then
      begin
        DestinationPixel^.R :=
          (Cardinal(SourcePixel^.R) * SourceAlpha * 255 +
           Cardinal(DestinationPixel^.R) * DestinationAlpha *
             (255 - SourceAlpha) + AlphaDenominator div 2) div
          AlphaDenominator;
        DestinationPixel^.G :=
          (Cardinal(SourcePixel^.G) * SourceAlpha * 255 +
           Cardinal(DestinationPixel^.G) * DestinationAlpha *
             (255 - SourceAlpha) + AlphaDenominator div 2) div
          AlphaDenominator;
        DestinationPixel^.B :=
          (Cardinal(SourcePixel^.B) * SourceAlpha * 255 +
           Cardinal(DestinationPixel^.B) * DestinationAlpha *
             (255 - SourceAlpha) + AlphaDenominator div 2) div
          AlphaDenominator;
        DestinationPixel^.A := (AlphaDenominator + 127) div 255;
      end;
    end;
    Inc(SourcePixel);
    Inc(DestinationPixel);
  end;
end;

end.
