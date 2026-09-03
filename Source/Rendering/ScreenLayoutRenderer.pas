// Documentの表示オブジェクトを、各ホストで共有できる透明RGBA8画像へ描画する。
// 線種と四角・丸・三角の線端をSkia描画へ反映する。
unit ScreenLayoutRenderer;

interface

uses
  System.SysUtils, System.Types, ScreenLayoutDocument;

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
// 単体レイヤーまたはグループ子孫を、通常描画と同じ処理でサムネイルへ収める。
procedure RenderVectArtLayerThumbnail(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
// ストレートアルファRGBA8同士をSource-overで合成する。
procedure CompositeVectArtRgba(const Source: TVectArtRenderBuffer;
  Destination: PVectArtRgbaPixel; Width, Height: Integer);

implementation

uses
  System.Generics.Collections, System.Math, System.Skia, System.UITypes,
  TextRendererSkiaRuntime, Vcl.Graphics, Winapi.Windows,
  ScreenLayoutEllipseGeometry, ScreenLayoutGeometry,
  ScreenLayoutFilters, ScreenLayoutLayerGeometry, ScreenLayoutShapePath,
  ScreenLayoutTextGeometry;

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

function BuildScreenLayoutImageFilter(
  Filter: TScreenLayoutFilter; ScaleX: Single = 1.0;
  ScaleY: Single = 1.0): ISkImageFilter;
var
  ColorizedOutline: ISkImageFilter;
  DilatedOutline: ISkImageFilter;
  OutlineFilter: TScreenLayoutOutlineFilter;
  ShadowFilter: TScreenLayoutShadowFilter;
begin
  Result := nil;
  if (Filter = nil) or not Filter.Enabled then
    Exit;
  ScaleX := Max(Abs(ScaleX), 0.0);
  ScaleY := Max(Abs(ScaleY), 0.0);
  case Filter.Kind of
    slfkOutline:
    begin
      OutlineFilter := TScreenLayoutOutlineFilter(Filter);
      if OutlineFilter.Width <= 0 then
        Exit;
      DilatedOutline := TSkImageFilter.MakeDilate(
        OutlineFilter.Width * ScaleX, OutlineFilter.Width * ScaleY);
      ColorizedOutline := TSkImageFilter.MakeColorFilter(
        TSkColorFilter.MakeBlend(
          VclColorToAlphaColor(OutlineFilter.Color, 1.0),
          TSkBlendMode.SrcIn), DilatedOutline);
      // Paint the original input over the expanded, colorized alpha mask.
      Result := TSkImageFilter.MakeBlend(TSkBlendMode.SrcOver,
        ColorizedOutline);
    end;
    slfkShadow:
    begin
      ShadowFilter := TScreenLayoutShadowFilter(Filter);
      Result := TSkImageFilter.MakeDropShadow(
        ShadowFilter.OffsetX * ScaleX, ShadowFilter.OffsetY * ScaleY,
        Max(ShadowFilter.BlurRadius * ScaleX, 0.0),
        Max(ShadowFilter.BlurRadius * ScaleY, 0.0),
        VclColorToAlphaColor(ShadowFilter.Color,
          EnsureRange(ShadowFilter.Opacity, 0.0, 1.0)));
    end;
    slfkBlur:
      if TScreenLayoutBlurFilter(Filter).Radius > 0 then
        Result := TSkImageFilter.MakeBlur(
          TScreenLayoutBlurFilter(Filter).Radius * ScaleX,
          TScreenLayoutBlurFilter(Filter).Radius * ScaleY);
  end;
end;

procedure InflateScreenLayoutBounds(var Bounds: TRectF; X, Y: Single);
begin
  Bounds.Left := Bounds.Left - Max(X, 0.0);
  Bounds.Top := Bounds.Top - Max(Y, 0.0);
  Bounds.Right := Bounds.Right + Max(X, 0.0);
  Bounds.Bottom := Bounds.Bottom + Max(Y, 0.0);
end;

procedure ExpandScreenLayoutFilterBounds(Layer: TVectArtLayer;
  var Bounds: TRectF);
var
  Blur: Single;
  EffectBounds: TRectF;
  Filter: TScreenLayoutFilter;
  I: Integer;
  Shadow: TScreenLayoutShadowFilter;
begin
  for I := 0 to Layer.FilterCount - 1 do
  begin
    Filter := Layer.Filters[I];
    if not Filter.Enabled then
      Continue;
    case Filter.Kind of
      slfkOutline:
        InflateScreenLayoutBounds(Bounds,
          TScreenLayoutOutlineFilter(Filter).Width,
          TScreenLayoutOutlineFilter(Filter).Width);
      slfkShadow:
      begin
        Shadow := TScreenLayoutShadowFilter(Filter);
        EffectBounds := Bounds;
        EffectBounds.Offset(Shadow.OffsetX, Shadow.OffsetY);
        Blur := Max(Shadow.BlurRadius, 0.0) * 3.0;
        InflateScreenLayoutBounds(EffectBounds, Blur, Blur);
        Bounds.Left := Min(Bounds.Left, EffectBounds.Left);
        Bounds.Top := Min(Bounds.Top, EffectBounds.Top);
        Bounds.Right := Max(Bounds.Right, EffectBounds.Right);
        Bounds.Bottom := Max(Bounds.Bottom, EffectBounds.Bottom);
      end;
      slfkBlur:
      begin
        Blur := Max(TScreenLayoutBlurFilter(Filter).Radius, 0.0) * 3.0;
        InflateScreenLayoutBounds(Bounds, Blur, Blur);
      end;
    end;
  end;
end;

function TryGetScreenLayoutPaintBounds(Layer: TVectArtLayer;
  MinimumStrokeWidth: Single; out Bounds: TRectF): Boolean;
var
  StrokeMargin: Single;
begin
  Result := TryGetScreenLayoutLayerBounds(Layer, Bounds);
  if not Result then
    Exit;
  StrokeMargin := 0.0;
  if Layer is TScreenLayoutShapeLayer then
    StrokeMargin := Max(TScreenLayoutShapeLayer(Layer).StrokeWidth,
      MinimumStrokeWidth) * 0.5
  else if Layer is TScreenLayoutRectangleLineLayer then
    StrokeMargin := Max(TScreenLayoutRectangleLineLayer(Layer).StrokeWidth,
      MinimumStrokeWidth) * 0.5
  else if Layer is TScreenLayoutArcLayer then
    StrokeMargin := Max(TScreenLayoutArcLayer(Layer).StrokeWidth,
      MinimumStrokeWidth) * 0.5
  else if Layer is TVectArtPathLayer then
    StrokeMargin := Max(TVectArtPathLayer(Layer).StrokeWidth,
      MinimumStrokeWidth) * 0.5;
  InflateScreenLayoutBounds(Bounds, StrokeMargin, StrokeMargin);
  ExpandScreenLayoutFilterBounds(Layer, Bounds);
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

procedure RenderVectArtLayers(const RenderLayers: TArray<TVectArtLayer>;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single); forward;

procedure RenderVectArtLayerTree(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single); forward;

procedure ApplyScreenLayoutLayerFilters(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; ScaleX, ScaleY: Single);
var
  Canvas: ISkCanvas;
  FilterImage: ISkImageFilter;
  FilterPaint: ISkPaint;
  I: Integer;
  ImageInfo: TSkImageInfo;
  InputImage: ISkImage;
  InputSurface: ISkSurface;
  OutputSurface: ISkSurface;
  Scratch: TVectArtRenderBuffer;
begin
  if (Layer = nil) or (Target = nil) or (Target.PixelCount = 0) then
    Exit;
  Scratch := TVectArtRenderBuffer.Create;
  try
    Scratch.SetSize(Target.Width, Target.Height);
    ImageInfo := TSkImageInfo.Create(Target.Width, Target.Height,
      TSkColorType.RGBA8888, TSkAlphaType.Unpremul);
    for I := 0 to Layer.FilterCount - 1 do
    begin
      FilterImage := BuildScreenLayoutImageFilter(Layer.Filters[I],
        ScaleX, ScaleY);
      if FilterImage = nil then
        Continue;
      InputSurface := TSkSurface.MakeRasterDirect(ImageInfo, Target.Data,
        Target.Stride);
      if InputSurface = nil then
        raise EInvalidOp.Create('Cannot create filter input surface');
      InputSurface.Flush;
      InputImage := InputSurface.MakeImageSnapshot;
      Scratch.Clear;
      OutputSurface := TSkSurface.MakeRasterDirect(ImageInfo, Scratch.Data,
        Scratch.Stride);
      if OutputSurface = nil then
        raise EInvalidOp.Create('Cannot create filter output surface');
      Canvas := OutputSurface.Canvas;
      Canvas.Clear(TAlphaColorRec.Null);
      FilterPaint := TSkPaint.Create;
      FilterPaint.ImageFilter := FilterImage;
      Canvas.DrawImage(InputImage, 0, 0, FilterPaint);
      OutputSurface.Flush;
      Canvas := nil;
      OutputSurface := nil;
      InputImage := nil;
      InputSurface := nil;
      Move(Scratch.Data^, Target.Data^,
        Target.PixelCount * SizeOf(TVectArtRgbaPixel));
    end;
  finally
    Scratch.Free;
  end;
end;

procedure MultiplyScreenLayoutBufferOpacity(Target: TVectArtRenderBuffer;
  Opacity: Single);
var
  I: Integer;
begin
  if Target = nil then
    Exit;
  Opacity := EnsureRange(Opacity, 0.0, 1.0);
  if Opacity >= 1.0 then
    Exit;
  for I := 0 to Target.PixelCount - 1 do
    Target.Pixels[I].A := EnsureRange(
      Round(Target.Pixels[I].A * Opacity), 0, 255);
end;

procedure RenderVectArtDocument(Document: TVectArtDocument;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  MinimumStrokeWidth: Single);
var
  CanvasLayer: TVectArtCanvasLayer;
  FlatLayers: TList<TVectArtLayer>;
  HasVisibleGroup: Boolean;
  I: Integer;
  LogicalBounds: TRectF;
  LayerBuffer: TVectArtRenderBuffer;
begin
  if Document = nil then
    raise EArgumentNilException.Create('Document');
  CanvasLayer := Document.CanvasLayer;
  if CanvasLayer = nil then
    raise EInvalidOp.Create('Document canvas is missing');
  LogicalBounds := TRectF.Create(-CanvasLayer.Width * 0.5,
    -CanvasLayer.Height * 0.5, CanvasLayer.Width * 0.5,
    CanvasLayer.Height * 0.5);
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  HasVisibleGroup := False;
  FlatLayers := TList<TVectArtLayer>.Create;
  try
    for I := 1 to Document.LayerCount - 1 do
      if Document[I].Visible then
      begin
        FlatLayers.Add(Document[I]);
        HasVisibleGroup := HasVisibleGroup or
          (Document[I] is TScreenLayoutGroupLayer);
      end;
    // The common, non-group case can render directly into the destination.
    // This avoids a full-canvas temporary buffer and source-over pass on
    // every mouse movement.
    if not HasVisibleGroup then
    begin
      RenderVectArtLayers(FlatLayers.ToArray, Target, Width, Height,
        LogicalBounds, MinimumStrokeWidth, 1.0);
      Exit;
    end;
  finally
    FlatLayers.Free;
  end;
  Target.SetSize(Width, Height);
  Target.Clear;
  LayerBuffer := TVectArtRenderBuffer.Create;
  try
    for I := 1 to Document.LayerCount - 1 do
      if Document[I].Visible then
      begin
        RenderVectArtLayerTree(Document[I], LayerBuffer, Width, Height,
          LogicalBounds, MinimumStrokeWidth, 1.0);
        CompositeVectArtRgba(LayerBuffer, Target.Data, Width, Height);
      end;
  finally
    LayerBuffer.Free;
  end;
end;

function FitScreenLayoutThumbnailBounds(const ContentBounds: TRectF;
  Width, Height: Integer; Margin: Integer; out LogicalBounds: TRectF;
  out Scale: Single): Boolean;
var
  AvailableHeight: Integer;
  AvailableWidth: Integer;
  Center: TPointF;
  ContentHeight: Single;
  ContentWidth: Single;
  LogicalHeight: Single;
  LogicalWidth: Single;
begin
  Result := False;
  AvailableWidth := Width - Margin * 2;
  AvailableHeight := Height - Margin * 2;
  if (AvailableWidth <= 0) or (AvailableHeight <= 0) then
    Exit;
  ContentWidth := Max(ContentBounds.Width, 1.0);
  ContentHeight := Max(ContentBounds.Height, 1.0);
  Scale := Min(AvailableWidth / ContentWidth,
    AvailableHeight / ContentHeight);
  if Scale <= 0 then
    Exit;
  LogicalWidth := Width / Scale;
  LogicalHeight := Height / Scale;
  Center := ContentBounds.CenterPoint;
  LogicalBounds := TRectF.Create(Center.X - LogicalWidth * 0.5,
    Center.Y - LogicalHeight * 0.5, Center.X + LogicalWidth * 0.5,
    Center.Y + LogicalHeight * 0.5);
  Result := True;
end;

procedure RenderVectArtLayerThumbnail(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer);
const
  THUMBNAIL_MARGIN = 5;
  THUMBNAIL_MINIMUM_STROKE_WIDTH = 1.0;
var
  ContentBounds: TRectF;
  LogicalBounds: TRectF;
  OpacityMultiplier: Single;
  Scale: Single;
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  Target.SetSize(Width, Height);
  Target.Clear;
  if not TryGetScreenLayoutLayerBounds(Layer, ContentBounds) or
    not FitScreenLayoutThumbnailBounds(ContentBounds, Width, Height,
      THUMBNAIL_MARGIN, LogicalBounds, Scale) then
    Exit;
  if Layer.Visible then
    OpacityMultiplier := 1.0
  else
    OpacityMultiplier := 0.35;
  RenderVectArtLayerTree(Layer, Target, Width, Height, LogicalBounds,
    THUMBNAIL_MINIMUM_STROKE_WIDTH / Scale, OpacityMultiplier);
end;

procedure RenderVectArtLayers(const RenderLayers: TArray<TVectArtLayer>;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single);
var
  ArcEndPoint: TPointF;
  ArcEndTangent: TPointF;
  ArcLayer: TScreenLayoutArcLayer;
  ArcStartPoint: TPointF;
  ArcStartTangent: TPointF;
  Canvas: ISkCanvas;
  DashIntervals: TArray<Single>;
  EllipseLayer: TScreenLayoutEllipseLayer;
  EllipseLine: TScreenLayoutEllipseLineLayer;
  EllipseArcShape: TScreenLayoutEllipseArcShapeLayer;
  I: Integer;
  J: Integer;
  ImageInfo: TSkImageInfo;
  ImageLayer: TVectArtImageLayer;
  ImagePaint: ISkPaint;
  Font: ISkFont;
  FilterImage: ISkImageFilter;
  FilterPaint: ISkPaint;
  FilterSaveCount: Integer;
  FilterBounds: TRectF;
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
  TextLayer: TScreenLayoutTextLayer;
  TextLayout: TScreenLayoutTextLayout;

begin
  if Target = nil then
    raise EArgumentNilException.Create('Target');
  if not TTextRendererSkiaRuntime.IsAcquired then
    raise EInvalidOp.Create('Skia runtime is not acquired');
  if (Width <= 0) or (Height <= 0) then
    raise EArgumentOutOfRangeException.Create('Render dimensions must be positive');
  if (LogicalBounds.Width <= 0) or (LogicalBounds.Height <= 0) then
    raise EArgumentOutOfRangeException.Create('Logical bounds must be positive');

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
  ScaleX := Width / LogicalBounds.Width;
  ScaleY := Height / LogicalBounds.Height;
  MinimumStrokeWidth := Max(MinimumStrokeWidth, 0.0);
  OpacityMultiplier := EnsureRange(OpacityMultiplier, 0.0, 1.0);
  Paint := TSkPaint.Create(TSkPaintStyle.Fill);
  Paint.AntiAlias := True;
  StrokePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  StrokePaint.AntiAlias := True;
  ImagePaint := TSkPaint.Create;
  ImagePaint.AntiAlias := True;
  Canvas.Scale(ScaleX, ScaleY);
  Canvas.Translate(-LogicalBounds.Left, -LogicalBounds.Top);
  for I := 0 to High(RenderLayers) do
  begin
    Layer := RenderLayers[I];
    FilterSaveCount := 0;
    if not TryGetScreenLayoutPaintBounds(Layer, MinimumStrokeWidth,
      FilterBounds) then
      FilterBounds := LogicalBounds;
    // Save in reverse so Restore applies the stack in list order.
    for J := Layer.FilterCount - 1 downto 0 do
    begin
      FilterImage := BuildScreenLayoutImageFilter(Layer.Filters[J]);
      if FilterImage = nil then
        Continue;
      FilterPaint := TSkPaint.Create;
      FilterPaint.ImageFilter := FilterImage;
      Canvas.SaveLayer(FilterBounds, FilterPaint);
      Inc(FilterSaveCount);
    end;
    try
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
      ImagePaint.AlphaF := EnsureRange(ImageLayer.Opacity *
        OpacityMultiplier, 0.0, 1.0);
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
    if Layer is TScreenLayoutTextLayer then
    begin
      TextLayer := TScreenLayoutTextLayer(Layer);
      if TextLayer.Text = '' then
        Continue;
      TextLayout := BuildScreenLayoutTextLayout(TextLayer.Text,
        TextLayer.FontFamily, TextLayer.FontSize, TextLayer.WrapWidth);
      if (TextLayout.Width <= 0) or (TextLayout.Height <= 0) then
        Continue;
      Font := CreateScreenLayoutTextFont(TextLayer.FontFamily,
        TextLayer.FontSize);
      Paint.Color := VclColorToAlphaColor(TextLayer.FillColor,
        TextLayer.Opacity * OpacityMultiplier);
      Paint.Style := TSkPaintStyle.Fill;
      Canvas.Save;
      try
        Canvas.Rotate(TextLayer.RotationDegrees,
          (TextLayer.Bounds.Left + TextLayer.Bounds.Right) * 0.5,
          (TextLayer.Bounds.Top + TextLayer.Bounds.Bottom) * 0.5);
        Canvas.Translate(TextLayer.Bounds.Left, TextLayer.Bounds.Top);
        Canvas.Scale(TextLayer.Bounds.Width / TextLayout.Width,
          TextLayer.Bounds.Height / TextLayout.Height);
        for J := 0 to High(TextLayout.Lines) do
          Canvas.DrawSimpleText(TextLayout.Lines[J], 0,
            TextLayout.Ascent + J * TextLayout.LineHeight, Font, Paint);
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
        ShapeLayer.Opacity * OpacityMultiplier);
      Canvas.DrawPath(Path, Paint);
      if ShapeLayer.StrokeWidth > 0 then
      begin
        StrokeWidth := Max(ShapeLayer.StrokeWidth, MinimumStrokeWidth);
        StrokePaint.AntiAlias := True;
        StrokePaint.Color := VclColorToAlphaColor(ShapeLayer.StrokeColor,
          ShapeLayer.Opacity * OpacityMultiplier);
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
        RectangleLine.Opacity * OpacityMultiplier);
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
        ArcLayer.Opacity * OpacityMultiplier);
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
        PathLayer.Opacity * OpacityMultiplier);
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
        EllipseArcShape.Opacity * OpacityMultiplier);
      Canvas.DrawPath(BuildScreenLayoutEllipseArcShapePath(EllipseArcShape),
        Paint);
      Continue;
    end;
    if Layer is TScreenLayoutEllipseLayer then
    begin
      EllipseLayer := TScreenLayoutEllipseLayer(Layer);
      Paint.AntiAlias := True;
      Paint.Color := VclColorToAlphaColor(EllipseLayer.FillColor,
        EllipseLayer.Opacity * OpacityMultiplier);
      Canvas.DrawPath(BuildScreenLayoutEllipsePath(EllipseLayer), Paint);
      Continue;
    end;
    if Layer is TScreenLayoutRoundedRectangleLayer then
    begin
      RoundedRectangleLayer := TScreenLayoutRoundedRectangleLayer(Layer);
      Paint.AntiAlias := True;
      Paint.Color := VclColorToAlphaColor(RoundedRectangleLayer.FillColor,
        RoundedRectangleLayer.Opacity * OpacityMultiplier);
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
      RectangleLayer.Opacity * OpacityMultiplier);
    Canvas.Save;
    try
      Canvas.Rotate(RectangleLayer.RotationDegrees,
        (RectangleLayer.Bounds.Left + RectangleLayer.Bounds.Right) * 0.5,
        (RectangleLayer.Bounds.Top + RectangleLayer.Bounds.Bottom) * 0.5);
      Canvas.DrawRect(RectangleLayer.Bounds, Paint);
    finally
      Canvas.Restore;
    end;
    finally
      while FilterSaveCount > 0 do
      begin
        Canvas.Restore;
        Dec(FilterSaveCount);
      end;
    end;
  end;
  Surface.Flush;
end;

procedure RenderVectArtLayerTree(Layer: TVectArtLayer;
  Target: TVectArtRenderBuffer; Width, Height: Integer;
  const LogicalBounds: TRectF; MinimumStrokeWidth,
  OpacityMultiplier: Single);
var
  ChildBuffer: TVectArtRenderBuffer;
  GroupLayer: TScreenLayoutGroupLayer;
  I: Integer;
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if not (Layer is TScreenLayoutGroupLayer) then
  begin
    RenderVectArtLayers([Layer], Target, Width, Height, LogicalBounds,
      MinimumStrokeWidth, OpacityMultiplier);
    Exit;
  end;

  Target.SetSize(Width, Height);
  Target.Clear;
  GroupLayer := TScreenLayoutGroupLayer(Layer);
  ChildBuffer := TVectArtRenderBuffer.Create;
  try
    for I := 0 to GroupLayer.ChildCount - 1 do
      if GroupLayer[I].Visible then
      begin
        RenderVectArtLayerTree(GroupLayer[I], ChildBuffer, Width, Height,
          LogicalBounds, MinimumStrokeWidth, 1.0);
        CompositeVectArtRgba(ChildBuffer, Target.Data, Width, Height);
      end;
  finally
    ChildBuffer.Free;
  end;
  ApplyScreenLayoutLayerFilters(Layer, Target,
    Width / LogicalBounds.Width, Height / LogicalBounds.Height);
  MultiplyScreenLayoutBufferOpacity(Target,
    Layer.Opacity * OpacityMultiplier);
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
