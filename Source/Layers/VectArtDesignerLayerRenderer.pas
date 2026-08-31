// レイヤー一覧の行配置、サムネイル、状態アイコンをGDI／Direct2Dで描画する。
unit VectArtDesignerLayerRenderer;

interface

uses
  System.Generics.Collections, System.SysUtils, System.Types, Vcl.Direct2D,
  Vcl.Graphics, Vcl.Imaging.pngimage, VectArtDesignerDocument;

type
  TVectArtImageThumbnailCacheEntry = class
  public
    Image: TPngImage;
    Signature: UInt64;
    destructor Destroy; override;
  end;

  TVectArtLayerRenderer = class
  private
    FDocument: TVectArtDocument;
    FImageThumbnails: TObjectDictionary<TVectArtImageLayer,
      TVectArtImageThumbnailCacheEntry>;
    FThumbnailRevision: Int64;
    function ImageDataSignature(const Data: TBytes): UInt64;
    function ImageThumbnail(ImageLayer: TVectArtImageLayer): TPngImage;
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SyncThumbnailCache;
    procedure DrawImageThumbnail(ACanvas: TCustomCanvas;
      const ThumbnailRect: TRect; ImageLayer: TVectArtImageLayer);
    procedure DrawLayerItem(ACanvas: TCanvas; const ItemRect: TRect;
      Layer: TVectArtLayer; Selected: Boolean); overload;
    procedure DrawLayerItem(ACanvas: TDirect2DCanvas;
      const ItemRect: TRect; Layer: TVectArtLayer;
      Selected: Boolean); overload;
    function FitThumbnailRect(const AvailableRect: TRect;
      LogicalWidth, LogicalHeight: Integer): TRect;
  public
    constructor Create;
    destructor Destroy; override;
    procedure DrawLayers(ACanvas: TCanvas;
      const Bounds: TRect); overload;
    procedure DrawLayers(ACanvas: TDirect2DCanvas;
      const Bounds: TRect); overload;
    function LayerIndexAt(const Bounds: TRect; Y: Integer): Integer;
    function LayerItemRect(const Bounds: TRect; Index: Integer): TRect;
    function LockButtonRect(const ItemRect: TRect): TRect;
    function VisibilityButtonRect(const ItemRect: TRect): TRect;
    property Document: TVectArtDocument read FDocument write SetDocument;
  end;

function VectArtLineThumbnailStrokeWidth(StrokeWidth: Single): Integer;
procedure VectArtLineThumbnailPoints(const ThumbnailRect: TRect;
  PreviewStrokeWidth: Integer; out StartPoint, EndPoint: TPoint);
// Path全体を縦横比を保ってサムネイル内へ収めた画面座標を返す。
function VectArtPathThumbnailPoints(const SourcePoints: TArray<TPointF>;
  const ThumbnailRect: TRect; PreviewStrokeWidth: Integer): TArray<TPoint>;

implementation

uses
  System.Classes, System.Math, Winapi.D2D1, Winapi.Windows;

const
  COLOR_LIST_BACKGROUND   = TColor($001A1A1A);
  COLOR_ROW_BACKGROUND    = TColor($00272727);
  COLOR_ROW_BORDER        = TColor($00424242);
  COLOR_ROW_SELECTED      = TColor($003D352A);
  COLOR_TEXT_PRIMARY      = TColor($00E6E6E6);
  COLOR_TEXT_SECONDARY    = TColor($00A8A8A8);
  COLOR_THUMB_BORDER      = TColor($00606060);
  LAYER_GAP               = 6;
  LAYER_LIST_PADDING      = 8;
  LAYER_ROW_HEIGHT        = 82;
  LOCK_BUTTON_TOP         = 45;
  STATE_BUTTON_SIZE       = 20;
  STATE_COLUMN_LEFT       = 4;
  THUMBNAIL_CHECKER_SIZE  = 6;
  THUMBNAIL_HEIGHT        = 54;
  THUMBNAIL_WIDTH         = 96;
  VISIBILITY_BUTTON_TOP   = 17;
  LINE_THUMBNAIL_MAX_STROKE = 10;
  LINE_THUMBNAIL_MIN_MARGIN = 8;

constructor TVectArtLayerRenderer.Create;
begin
  inherited Create;
  FImageThumbnails := TObjectDictionary<TVectArtImageLayer,
    TVectArtImageThumbnailCacheEntry>.Create([doOwnsValues]);
  FThumbnailRevision := -1;
end;

destructor TVectArtLayerRenderer.Destroy;
begin
  FImageThumbnails.Free;
  inherited Destroy;
end;

destructor TVectArtImageThumbnailCacheEntry.Destroy;
begin
  Image.Free;
  inherited Destroy;
end;

function TVectArtLayerRenderer.ImageDataSignature(
  const Data: TBytes): UInt64;
var
  I: Integer;
  Index: Integer;
begin
  Result := UInt64(Length(Data)) * UInt64($100000001B3);
  if Length(Data) = 0 then
    Exit;
  for I := 0 to 15 do
  begin
    Index := (Int64(I) * (Length(Data) - 1)) div 15;
    Result := (Result xor Data[Index]) * UInt64($100000001B3);
  end;
end;

function TVectArtLayerRenderer.ImageThumbnail(
  ImageLayer: TVectArtImageLayer): TPngImage;
var
  Entry: TVectArtImageThumbnailCacheEntry;
  Signature: UInt64;
  Stream: TBytesStream;
begin
  Result := nil;
  if (ImageLayer = nil) or (Length(ImageLayer.PngData) = 0) then
    Exit;
  Signature := ImageDataSignature(ImageLayer.PngData);
  if FImageThumbnails.TryGetValue(ImageLayer, Entry) and
    (Entry.Signature = Signature) then
    Exit(Entry.Image);
  FImageThumbnails.Remove(ImageLayer);
  Entry := TVectArtImageThumbnailCacheEntry.Create;
  Entry.Image := TPngImage.Create;
  Entry.Signature := Signature;
  Stream := TBytesStream.Create(ImageLayer.PngData);
  try
    try
      Entry.Image.LoadFromStream(Stream);
      if (Entry.Image.Width <= 0) or (Entry.Image.Height <= 0) then
        Exit;
      FImageThumbnails.Add(ImageLayer, Entry);
      Result := Entry.Image;
      Entry := nil;
    except
      on EInvalidGraphic do
        Exit;
      on EReadError do
        Exit;
    end;
  finally
    Stream.Free;
    Entry.Free;
  end;
end;

function BlendThumbnailColor(Foreground: TColor; Opacity: Single): TColor;
var
  ColorValue: TColor;
begin
  ColorValue := ColorToRGB(Foreground);
  Opacity := EnsureRange(Opacity, 0.0, 1.0);
  Result := RGB(
    Round(GetRValue(ColorValue) * Opacity + $FF * (1 - Opacity)),
    Round(GetGValue(ColorValue) * Opacity + $FF * (1 - Opacity)),
    Round(GetBValue(ColorValue) * Opacity + $FF * (1 - Opacity)));
end;

function VectArtLineThumbnailStrokeWidth(StrokeWidth: Single): Integer;
begin
  if StrokeWidth <= 1.0 then
    Exit(1);
  Result := EnsureRange(Round(1 + 2 * Ln(StrokeWidth)), 1,
    LINE_THUMBNAIL_MAX_STROKE);
end;

procedure VectArtLineThumbnailPoints(const ThumbnailRect: TRect;
  PreviewStrokeWidth: Integer; out StartPoint, EndPoint: TPoint);
var
  Margin: Integer;
begin
  PreviewStrokeWidth := EnsureRange(PreviewStrokeWidth, 1,
    LINE_THUMBNAIL_MAX_STROKE);
  Margin := Max(LINE_THUMBNAIL_MIN_MARGIN,
    ((PreviewStrokeWidth + 1) div 2) + 3);
  Margin := Min(Margin, Max(Min(ThumbnailRect.Width,
    ThumbnailRect.Height) div 2, 0));
  StartPoint := Point(ThumbnailRect.Left + Margin,
    ThumbnailRect.Bottom - Margin);
  EndPoint := Point(ThumbnailRect.Right - Margin,
    ThumbnailRect.Top + Margin);
end;

function VectArtPathThumbnailPoints(const SourcePoints: TArray<TPointF>;
  const ThumbnailRect: TRect; PreviewStrokeWidth: Integer): TArray<TPoint>;
var
  AvailableHeight: Integer;
  AvailableWidth: Integer;
  I: Integer;
  InnerLeft: Single;
  InnerTop: Single;
  Margin: Integer;
  MaximumX: Single;
  MaximumY: Single;
  MinimumX: Single;
  MinimumY: Single;
  OffsetX: Single;
  OffsetY: Single;
  Scale: Single;
  SourceHeight: Single;
  SourceWidth: Single;
begin
  SetLength(Result, Length(SourcePoints));
  if Length(SourcePoints) = 0 then
    Exit;
  PreviewStrokeWidth := EnsureRange(PreviewStrokeWidth, 1,
    LINE_THUMBNAIL_MAX_STROKE);
  Margin := Max(LINE_THUMBNAIL_MIN_MARGIN,
    ((PreviewStrokeWidth + 1) div 2) + 3);
  Margin := Min(Margin, Max(Min(ThumbnailRect.Width,
    ThumbnailRect.Height) div 2, 0));
  AvailableWidth := Max(ThumbnailRect.Width - 2 * Margin, 0);
  AvailableHeight := Max(ThumbnailRect.Height - 2 * Margin, 0);

  MinimumX := SourcePoints[0].X;
  MaximumX := MinimumX;
  MinimumY := SourcePoints[0].Y;
  MaximumY := MinimumY;
  for I := 1 to High(SourcePoints) do
  begin
    MinimumX := Min(MinimumX, SourcePoints[I].X);
    MaximumX := Max(MaximumX, SourcePoints[I].X);
    MinimumY := Min(MinimumY, SourcePoints[I].Y);
    MaximumY := Max(MaximumY, SourcePoints[I].Y);
  end;
  SourceWidth := MaximumX - MinimumX;
  SourceHeight := MaximumY - MinimumY;
  if (SourceWidth > 0) and (SourceHeight > 0) then
    Scale := Min(AvailableWidth / SourceWidth,
      AvailableHeight / SourceHeight)
  else if SourceWidth > 0 then
    Scale := AvailableWidth / SourceWidth
  else if SourceHeight > 0 then
    Scale := AvailableHeight / SourceHeight
  else
    Scale := 0;
  InnerLeft := ThumbnailRect.Left + Margin;
  InnerTop := ThumbnailRect.Top + Margin;
  OffsetX := InnerLeft + (AvailableWidth - SourceWidth * Scale) * 0.5;
  OffsetY := InnerTop + (AvailableHeight - SourceHeight * Scale) * 0.5;
  for I := 0 to High(SourcePoints) do
    Result[I] := Point(
      Round(OffsetX + (SourcePoints[I].X - MinimumX) * Scale),
      Round(OffsetY + (SourcePoints[I].Y - MinimumY) * Scale));
end;

procedure TVectArtLayerRenderer.DrawImageThumbnail(ACanvas: TCustomCanvas;
  const ThumbnailRect: TRect; ImageLayer: TVectArtImageLayer);
var
  ImageRect: TRect;
  PngImage: TPngImage;
begin
  if (ACanvas = nil) or (ImageLayer = nil) or
    (Length(ImageLayer.PngData) = 0) then
    Exit;
  PngImage := ImageThumbnail(ImageLayer);
  if PngImage = nil then
    Exit;
  ImageRect := FitThumbnailRect(ThumbnailRect, PngImage.Width,
    PngImage.Height);
  ACanvas.StretchDraw(ImageRect, PngImage);
end;

procedure TVectArtLayerRenderer.DrawLayerItem(ACanvas: TCanvas;
  const ItemRect: TRect; Layer: TVectArtLayer; Selected: Boolean);
var
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  Column: Integer;
  DetailText: string;
  LockRect: TRect;
  LineLayer: TVectArtLineLayer;
  LineEnd: TPoint;
  LineStart: TPoint;
  LineStrokeWidth: Integer;
  PathDrawPoints: TArray<TPoint>;
  PathLayer: TVectArtPathLayer;
  PathPoints: TArray<TPoint>;
  RectangleLayer: TVectArtRectangleLayer;
  RectangleRect: TRect;
  Row: Integer;
  SavedDC: Integer;
  TextX: Integer;
  ThumbnailArea: TRect;
  ThumbnailRect: TRect;
  VisibilityRect: TRect;
begin
  ACanvas.Brush.Style := bsSolid;
  if Selected then
    ACanvas.Brush.Color := COLOR_ROW_SELECTED
  else
    ACanvas.Brush.Color := COLOR_ROW_BACKGROUND;
  ACanvas.FillRect(ItemRect);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := COLOR_ROW_BORDER;
  ACanvas.FrameRect(ItemRect);

  ThumbnailArea := Rect(ItemRect.Left + 30,
    ItemRect.Top + (ItemRect.Height - THUMBNAIL_HEIGHT) div 2,
    Min(ItemRect.Left + 30 + THUMBNAIL_WIDTH, ItemRect.Right - 8),
    ItemRect.Top + (ItemRect.Height + THUMBNAIL_HEIGHT) div 2);
  CanvasLayer := nil;
  if FDocument <> nil then
    CanvasLayer := FDocument.CanvasLayer;
  if (Layer is TVectArtCanvasLayer) and (CanvasLayer <> nil) then
    ThumbnailRect := FitThumbnailRect(ThumbnailArea, CanvasLayer.Width,
      CanvasLayer.Height)
  else
    ThumbnailRect := ThumbnailArea;

  ACanvas.Brush.Style := bsSolid;
  if (Layer is TVectArtCanvasLayer) and
    not TVectArtCanvasLayer(Layer).Transparent then
  begin
    ACanvas.Brush.Color := TVectArtCanvasLayer(Layer).BackgroundColor;
    ACanvas.FillRect(ThumbnailRect);
  end
  else
  begin
    Row := 0;
    while ThumbnailRect.Top + Row * THUMBNAIL_CHECKER_SIZE <
      ThumbnailRect.Bottom do
    begin
      Column := 0;
      while ThumbnailRect.Left + Column * THUMBNAIL_CHECKER_SIZE <
        ThumbnailRect.Right do
      begin
        CellRect := Rect(
          ThumbnailRect.Left + Column * THUMBNAIL_CHECKER_SIZE,
          ThumbnailRect.Top + Row * THUMBNAIL_CHECKER_SIZE,
          Min(ThumbnailRect.Left + (Column + 1) * THUMBNAIL_CHECKER_SIZE,
            ThumbnailRect.Right),
          Min(ThumbnailRect.Top + (Row + 1) * THUMBNAIL_CHECKER_SIZE,
            ThumbnailRect.Bottom));
        if Odd(Row + Column) then
          ACanvas.Brush.Color := TColor($00B8B8B8)
        else
          ACanvas.Brush.Color := clWhite;
        ACanvas.FillRect(CellRect);
        Inc(Column);
      end;
      Inc(Row);
    end;
  end;
  if Layer is TVectArtRectangleLayer then
  begin
    RectangleLayer := TVectArtRectangleLayer(Layer);
    RectangleRect := FitThumbnailRect(ThumbnailRect,
      Max(Round(RectangleLayer.Bounds.Width), 1),
      Max(Round(RectangleLayer.Bounds.Height), 1));
    if Layer.Visible then
      ACanvas.Brush.Color := BlendThumbnailColor(RectangleLayer.FillColor,
        RectangleLayer.Opacity)
    else
      ACanvas.Brush.Color := BlendThumbnailColor(RectangleLayer.FillColor,
        RectangleLayer.Opacity * 0.35);
    ACanvas.FillRect(RectangleRect);
    if RectangleLayer.StrokeWidth > 0 then
    begin
      ACanvas.Pen.Color := BlendThumbnailColor(RectangleLayer.StrokeColor,
        RectangleLayer.Opacity);
      ACanvas.Pen.Width := Max(Round(RectangleLayer.StrokeWidth), 1);
      if RectangleLayer.MifStrokeStyle <> vssSolid then
        ACanvas.Pen.Style := psDash
      else
        ACanvas.Pen.Style := psSolid;
    end
    else
      ACanvas.Pen.Color := TColor($00707070);
    ACanvas.FrameRect(RectangleRect);
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
  end;
  if Layer is TVectArtLineLayer then
  begin
    LineLayer := TVectArtLineLayer(Layer);
    LineStrokeWidth := VectArtLineThumbnailStrokeWidth(
      LineLayer.StrokeWidth);
    VectArtLineThumbnailPoints(ThumbnailRect, LineStrokeWidth,
      LineStart, LineEnd);
    ACanvas.Pen.Color := BlendThumbnailColor(LineLayer.StrokeColor,
      LineLayer.Opacity);
    ACanvas.Pen.Width := LineStrokeWidth;
    if LineLayer.MifStrokeStyle <> vssSolid then
      ACanvas.Pen.Style := psDash
    else
      ACanvas.Pen.Style := psSolid;
    SavedDC := SaveDC(ACanvas.Handle);
    try
      IntersectClipRect(ACanvas.Handle, ThumbnailRect.Left,
        ThumbnailRect.Top, ThumbnailRect.Right, ThumbnailRect.Bottom);
      ACanvas.MoveTo(LineStart.X, LineStart.Y);
      ACanvas.LineTo(LineEnd.X, LineEnd.Y);
    finally
      RestoreDC(ACanvas.Handle, SavedDC);
    end;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
  end;
  if Layer is TVectArtPathLayer then
  begin
    PathLayer := TVectArtPathLayer(Layer);
    LineStrokeWidth := VectArtLineThumbnailStrokeWidth(
      PathLayer.StrokeWidth);
    PathPoints := VectArtPathThumbnailPoints(PathLayer.Points,
      ThumbnailRect, LineStrokeWidth);
    SavedDC := SaveDC(ACanvas.Handle);
    try
      IntersectClipRect(ACanvas.Handle, ThumbnailRect.Left,
        ThumbnailRect.Top, ThumbnailRect.Right, ThumbnailRect.Bottom);
      if PathLayer.Closed and PathLayer.Filled and
        (Length(PathPoints) >= 3) then
      begin
        ACanvas.Pen.Style := psClear;
        ACanvas.Brush.Style := bsSolid;
        if Layer.Visible then
          ACanvas.Brush.Color := BlendThumbnailColor(PathLayer.FillColor,
            PathLayer.Opacity)
        else
          ACanvas.Brush.Color := BlendThumbnailColor(PathLayer.FillColor,
            PathLayer.Opacity * 0.35);
        ACanvas.Polygon(PathPoints);
      end;
      if (PathLayer.StrokeWidth > 0) and (Length(PathPoints) >= 2) then
      begin
        PathDrawPoints := Copy(PathPoints);
        if PathLayer.Closed then
        begin
          SetLength(PathDrawPoints, Length(PathDrawPoints) + 1);
          PathDrawPoints[High(PathDrawPoints)] := PathDrawPoints[0];
        end;
        ACanvas.Brush.Style := bsClear;
        if Layer.Visible then
          ACanvas.Pen.Color := BlendThumbnailColor(PathLayer.StrokeColor,
            PathLayer.Opacity)
        else
          ACanvas.Pen.Color := BlendThumbnailColor(PathLayer.StrokeColor,
            PathLayer.Opacity * 0.35);
        ACanvas.Pen.Width := LineStrokeWidth;
        if PathLayer.MifStrokeStyle <> vssSolid then
          ACanvas.Pen.Style := psDash
        else
          ACanvas.Pen.Style := psSolid;
        ACanvas.Polyline(PathDrawPoints);
      end;
    finally
      RestoreDC(ACanvas.Handle, SavedDC);
    end;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
  end;
  if Layer is TVectArtImageLayer then
    DrawImageThumbnail(ACanvas, ThumbnailRect,
      TVectArtImageLayer(Layer));
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := COLOR_THUMB_BORDER;
  ACanvas.FrameRect(ThumbnailRect);

  TextX := ThumbnailArea.Right + 8;
  ACanvas.Font.Name := 'Segoe UI';
  ACanvas.Font.Height := -13;
  ACanvas.Font.Color := COLOR_TEXT_PRIMARY;
  ACanvas.TextOut(TextX, ItemRect.Top + 20, Layer.Name);
  if Layer is TVectArtCanvasLayer then
    DetailText := Format('%d x %d  %d%%', [TVectArtCanvasLayer(Layer).Width,
      TVectArtCanvasLayer(Layer).Height, Round(Layer.Opacity * 100)])
  else if Layer is TVectArtRectangleLayer then
    DetailText := Format('%d x %d  %d%%',
      [Round(TVectArtRectangleLayer(Layer).Bounds.Width),
       Round(TVectArtRectangleLayer(Layer).Bounds.Height),
       Round(Layer.Opacity * 100)])
  else if Layer is TVectArtImageLayer then
    if TVectArtImageLayer(Layer).SourceKind = visLogo then
      DetailText := Format('Logo  %d%%', [Round(Layer.Opacity * 100)])
    else
      DetailText := Format('Image  %d%%', [Round(Layer.Opacity * 100)])
  else if Layer is TVectArtPathLayer then
    DetailText := Format('Path  %d%%', [Round(Layer.Opacity * 100)])
  else
    DetailText := Format('Line  %spx  %d%%',
      [FormatFloat('0.##', TVectArtLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)]);
  ACanvas.Font.Height := -11;
  ACanvas.Font.Color := COLOR_TEXT_SECONDARY;
  ACanvas.TextOut(TextX, ItemRect.Top + 43, DetailText);

  VisibilityRect := VisibilityButtonRect(ItemRect);
  LockRect := LockButtonRect(ItemRect);
  ACanvas.Pen.Color := COLOR_TEXT_SECONDARY;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Ellipse(VisibilityRect.Left + 2, VisibilityRect.Top + 5,
    VisibilityRect.Right - 2, VisibilityRect.Bottom - 5);
  if Layer.Visible then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_PRIMARY;
    ACanvas.Ellipse(VisibilityRect.Left + 8, VisibilityRect.Top + 8,
      VisibilityRect.Left + 12, VisibilityRect.Top + 12);
  end;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Rectangle(LockRect.Left + 3, LockRect.Top + 8,
    LockRect.Right - 3, LockRect.Bottom - 2);
  ACanvas.MoveTo(LockRect.Left + 6, LockRect.Top + 8);
  ACanvas.LineTo(LockRect.Left + 6, LockRect.Top + 3);
  ACanvas.LineTo(LockRect.Right - 6, LockRect.Top + 3);
  if Layer.Locked then
    ACanvas.LineTo(LockRect.Right - 6, LockRect.Top + 8);
end;

procedure TVectArtLayerRenderer.DrawLayerItem(ACanvas: TDirect2DCanvas;
  const ItemRect: TRect; Layer: TVectArtLayer; Selected: Boolean);
var
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  Column: Integer;
  DetailText: string;
  LockRect: TRect;
  LineLayer: TVectArtLineLayer;
  LineEnd: TPoint;
  LineStart: TPoint;
  LineStrokeWidth: Integer;
  PathDrawPoints: TArray<TPoint>;
  PathLayer: TVectArtPathLayer;
  PathPoints: TArray<TPoint>;
  RectangleLayer: TVectArtRectangleLayer;
  RectangleRect: TRect;
  Row: Integer;
  TextX: Integer;
  ThumbnailArea: TRect;
  ThumbnailRect: TRect;
  VisibilityRect: TRect;
begin
  ACanvas.Brush.Style := bsSolid;
  if Selected then
    ACanvas.Brush.Color := COLOR_ROW_SELECTED
  else
    ACanvas.Brush.Color := COLOR_ROW_BACKGROUND;
  ACanvas.FillRect(ItemRect);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := COLOR_ROW_BORDER;
  ACanvas.FrameRect(ItemRect);

  ThumbnailArea := Rect(ItemRect.Left + 30,
    ItemRect.Top + (ItemRect.Height - THUMBNAIL_HEIGHT) div 2,
    Min(ItemRect.Left + 30 + THUMBNAIL_WIDTH, ItemRect.Right - 8),
    ItemRect.Top + (ItemRect.Height + THUMBNAIL_HEIGHT) div 2);
  CanvasLayer := nil;
  if FDocument <> nil then
    CanvasLayer := FDocument.CanvasLayer;
  if (Layer is TVectArtCanvasLayer) and (CanvasLayer <> nil) then
    ThumbnailRect := FitThumbnailRect(ThumbnailArea, CanvasLayer.Width,
      CanvasLayer.Height)
  else
    ThumbnailRect := ThumbnailArea;

  ACanvas.Brush.Style := bsSolid;
  if (Layer is TVectArtCanvasLayer) and
    not TVectArtCanvasLayer(Layer).Transparent then
  begin
    ACanvas.Brush.Color := TVectArtCanvasLayer(Layer).BackgroundColor;
    ACanvas.FillRect(ThumbnailRect);
  end
  else
  begin
    Row := 0;
    while ThumbnailRect.Top + Row * THUMBNAIL_CHECKER_SIZE <
      ThumbnailRect.Bottom do
    begin
      Column := 0;
      while ThumbnailRect.Left + Column * THUMBNAIL_CHECKER_SIZE <
        ThumbnailRect.Right do
      begin
        CellRect := Rect(
          ThumbnailRect.Left + Column * THUMBNAIL_CHECKER_SIZE,
          ThumbnailRect.Top + Row * THUMBNAIL_CHECKER_SIZE,
          Min(ThumbnailRect.Left + (Column + 1) * THUMBNAIL_CHECKER_SIZE,
            ThumbnailRect.Right),
          Min(ThumbnailRect.Top + (Row + 1) * THUMBNAIL_CHECKER_SIZE,
            ThumbnailRect.Bottom));
        if Odd(Row + Column) then
          ACanvas.Brush.Color := TColor($00B8B8B8)
        else
          ACanvas.Brush.Color := clWhite;
        ACanvas.FillRect(CellRect);
        Inc(Column);
      end;
      Inc(Row);
    end;
  end;
  if Layer is TVectArtRectangleLayer then
  begin
    RectangleLayer := TVectArtRectangleLayer(Layer);
    RectangleRect := FitThumbnailRect(ThumbnailRect,
      Max(Round(RectangleLayer.Bounds.Width), 1),
      Max(Round(RectangleLayer.Bounds.Height), 1));
    ACanvas.Brush.Color := RectangleLayer.FillColor;
    if Layer.Visible then
      ACanvas.Brush.Handle.SetOpacity(RectangleLayer.Opacity)
    else
      ACanvas.Brush.Handle.SetOpacity(RectangleLayer.Opacity * 0.35);
    ACanvas.FillRect(RectangleRect);
    ACanvas.Brush.Handle.SetOpacity(1.0);
    if RectangleLayer.StrokeWidth > 0 then
    begin
      if Layer.Visible then
        ACanvas.Pen.Color := BlendThumbnailColor(RectangleLayer.StrokeColor,
          RectangleLayer.Opacity)
      else
        ACanvas.Pen.Color := BlendThumbnailColor(RectangleLayer.StrokeColor,
          RectangleLayer.Opacity * 0.35);
      ACanvas.Pen.Width := Max(Round(RectangleLayer.StrokeWidth), 1);
      if RectangleLayer.MifStrokeStyle <> vssSolid then
        ACanvas.Pen.Style := psDash
      else
        ACanvas.Pen.Style := psSolid;
    end
    else
      ACanvas.Pen.Color := TColor($00707070);
    ACanvas.FrameRect(RectangleRect);
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
  end;
  if Layer is TVectArtLineLayer then
  begin
    LineLayer := TVectArtLineLayer(Layer);
    LineStrokeWidth := VectArtLineThumbnailStrokeWidth(
      LineLayer.StrokeWidth);
    VectArtLineThumbnailPoints(ThumbnailRect, LineStrokeWidth,
      LineStart, LineEnd);
    ACanvas.Pen.Color := BlendThumbnailColor(LineLayer.StrokeColor,
      LineLayer.Opacity);
    ACanvas.Pen.Width := LineStrokeWidth;
    if LineLayer.MifStrokeStyle <> vssSolid then
      ACanvas.Pen.Style := psDash
    else
      ACanvas.Pen.Style := psSolid;
    ACanvas.RenderTarget.PushAxisAlignedClip(ThumbnailRect,
      D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    try
      ACanvas.MoveTo(LineStart.X, LineStart.Y);
      ACanvas.LineTo(LineEnd.X, LineEnd.Y);
    finally
      ACanvas.RenderTarget.PopAxisAlignedClip;
    end;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
  end;
  if Layer is TVectArtPathLayer then
  begin
    PathLayer := TVectArtPathLayer(Layer);
    LineStrokeWidth := VectArtLineThumbnailStrokeWidth(
      PathLayer.StrokeWidth);
    PathPoints := VectArtPathThumbnailPoints(PathLayer.Points,
      ThumbnailRect, LineStrokeWidth);
    ACanvas.RenderTarget.PushAxisAlignedClip(ThumbnailRect,
      D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    try
      if PathLayer.Closed and PathLayer.Filled and
        (Length(PathPoints) >= 3) then
      begin
        ACanvas.Pen.Style := psClear;
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := PathLayer.FillColor;
        if Layer.Visible then
          ACanvas.Brush.Handle.SetOpacity(PathLayer.Opacity)
        else
          ACanvas.Brush.Handle.SetOpacity(PathLayer.Opacity * 0.35);
        ACanvas.Polygon(PathPoints);
        ACanvas.Brush.Handle.SetOpacity(1.0);
      end;
      if (PathLayer.StrokeWidth > 0) and (Length(PathPoints) >= 2) then
      begin
        PathDrawPoints := Copy(PathPoints);
        if PathLayer.Closed then
        begin
          SetLength(PathDrawPoints, Length(PathDrawPoints) + 1);
          PathDrawPoints[High(PathDrawPoints)] := PathDrawPoints[0];
        end;
        ACanvas.Brush.Style := bsClear;
        if Layer.Visible then
          ACanvas.Pen.Color := BlendThumbnailColor(PathLayer.StrokeColor,
            PathLayer.Opacity)
        else
          ACanvas.Pen.Color := BlendThumbnailColor(PathLayer.StrokeColor,
            PathLayer.Opacity * 0.35);
        ACanvas.Pen.Width := LineStrokeWidth;
        if PathLayer.MifStrokeStyle <> vssSolid then
          ACanvas.Pen.Style := psDash
        else
          ACanvas.Pen.Style := psSolid;
        ACanvas.Polyline(PathDrawPoints);
      end;
    finally
      ACanvas.Brush.Handle.SetOpacity(1.0);
      ACanvas.RenderTarget.PopAxisAlignedClip;
    end;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
  end;
  if Layer is TVectArtImageLayer then
    DrawImageThumbnail(ACanvas, ThumbnailRect,
      TVectArtImageLayer(Layer));
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := COLOR_THUMB_BORDER;
  ACanvas.FrameRect(ThumbnailRect);

  TextX := ThumbnailArea.Right + 8;
  ACanvas.Font.Name := 'Segoe UI';
  ACanvas.Font.Height := -13;
  ACanvas.Font.Color := COLOR_TEXT_PRIMARY;
  ACanvas.TextOut(TextX, ItemRect.Top + 20, Layer.Name);
  if Layer is TVectArtCanvasLayer then
    DetailText := Format('%d x %d  %d%%', [TVectArtCanvasLayer(Layer).Width,
      TVectArtCanvasLayer(Layer).Height, Round(Layer.Opacity * 100)])
  else if Layer is TVectArtRectangleLayer then
    DetailText := Format('%d x %d  %d%%',
      [Round(TVectArtRectangleLayer(Layer).Bounds.Width),
       Round(TVectArtRectangleLayer(Layer).Bounds.Height),
       Round(Layer.Opacity * 100)])
  else if Layer is TVectArtImageLayer then
    if TVectArtImageLayer(Layer).SourceKind = visLogo then
      DetailText := Format('Logo  %d%%', [Round(Layer.Opacity * 100)])
    else
      DetailText := Format('Image  %d%%', [Round(Layer.Opacity * 100)])
  else if Layer is TVectArtPathLayer then
    DetailText := Format('Path  %d%%', [Round(Layer.Opacity * 100)])
  else
    DetailText := Format('Line  %spx  %d%%',
      [FormatFloat('0.##', TVectArtLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)]);
  ACanvas.Font.Height := -11;
  ACanvas.Font.Color := COLOR_TEXT_SECONDARY;
  ACanvas.TextOut(TextX, ItemRect.Top + 43, DetailText);

  VisibilityRect := VisibilityButtonRect(ItemRect);
  LockRect := LockButtonRect(ItemRect);
  ACanvas.Pen.Color := COLOR_TEXT_SECONDARY;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Ellipse(VisibilityRect.Left + 2, VisibilityRect.Top + 5,
    VisibilityRect.Right - 2, VisibilityRect.Bottom - 5);
  if Layer.Visible then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_PRIMARY;
    ACanvas.Ellipse(VisibilityRect.Left + 8, VisibilityRect.Top + 8,
      VisibilityRect.Left + 12, VisibilityRect.Top + 12);
  end;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Rectangle(LockRect.Left + 3, LockRect.Top + 8,
    LockRect.Right - 3, LockRect.Bottom - 2);
  ACanvas.MoveTo(LockRect.Left + 6, LockRect.Top + 8);
  ACanvas.LineTo(LockRect.Left + 6, LockRect.Top + 3);
  ACanvas.LineTo(LockRect.Right - 6, LockRect.Top + 3);
  if Layer.Locked then
    ACanvas.LineTo(LockRect.Right - 6, LockRect.Top + 8);
end;

procedure TVectArtLayerRenderer.SetDocument(const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  FDocument := Value;
  FImageThumbnails.Clear;
  FThumbnailRevision := -1;
end;

procedure TVectArtLayerRenderer.SyncThumbnailCache;
var
  CachedLayer: TVectArtImageLayer;
  CurrentLayer: TVectArtLayer;
  I: Integer;
  IsCurrent: Boolean;
  Keys: TArray<TVectArtImageLayer>;
begin
  if FDocument = nil then
  begin
    FImageThumbnails.Clear;
    FThumbnailRevision := -1;
    Exit;
  end;
  if FThumbnailRevision = FDocument.Revision then
    Exit;
  Keys := FImageThumbnails.Keys.ToArray;
  for CachedLayer in Keys do
  begin
    IsCurrent := False;
    for I := 1 to FDocument.LayerCount - 1 do
    begin
      CurrentLayer := FDocument[I];
      if CurrentLayer = CachedLayer then
      begin
        IsCurrent := True;
        Break;
      end;
    end;
    if not IsCurrent then
      FImageThumbnails.Remove(CachedLayer);
  end;
  FThumbnailRevision := FDocument.Revision;
end;

procedure TVectArtLayerRenderer.DrawLayers(ACanvas: TCanvas;
  const Bounds: TRect);
var
  I: Integer;
  ItemRect: TRect;
begin
  SyncThumbnailCache;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    DrawLayerItem(ACanvas, ItemRect, FDocument[I],
      FDocument.IsLayerSelected(I));
  end;
end;

procedure TVectArtLayerRenderer.DrawLayers(ACanvas: TDirect2DCanvas;
  const Bounds: TRect);
var
  I: Integer;
  ItemRect: TRect;
begin
  SyncThumbnailCache;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    DrawLayerItem(ACanvas, ItemRect, FDocument[I],
      FDocument.IsLayerSelected(I));
  end;
end;

function TVectArtLayerRenderer.FitThumbnailRect(
  const AvailableRect: TRect; LogicalWidth, LogicalHeight: Integer): TRect;
var
  DrawHeight: Integer;
  DrawWidth: Integer;
  Scale: Double;
begin
  if (AvailableRect.Width <= 0) or (AvailableRect.Height <= 0) then
    Exit(TRect.Empty);
  Scale := Min(AvailableRect.Width / Max(LogicalWidth, 1),
    AvailableRect.Height / Max(LogicalHeight, 1));
  DrawWidth := Max(Round(LogicalWidth * Scale), 1);
  DrawHeight := Max(Round(LogicalHeight * Scale), 1);
  Result.Left := AvailableRect.Left + (AvailableRect.Width - DrawWidth) div 2;
  Result.Top := AvailableRect.Top + (AvailableRect.Height - DrawHeight) div 2;
  Result.Right := Result.Left + DrawWidth;
  Result.Bottom := Result.Top + DrawHeight;
end;

function TVectArtLayerRenderer.LayerIndexAt(const Bounds: TRect;
  Y: Integer): Integer;
var
  I: Integer;
  ItemRect: TRect;
begin
  Result := -1;
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if (Y >= ItemRect.Top) and (Y < ItemRect.Bottom) then
      Exit(I);
  end;
end;

function TVectArtLayerRenderer.LayerItemRect(const Bounds: TRect;
  Index: Integer): TRect;
var
  ItemBottom: Integer;
begin
  if Index <= 0 then
    Exit(TRect.Empty);
  ItemBottom := Bounds.Bottom - LAYER_LIST_PADDING -
    (Index - 1) * (LAYER_ROW_HEIGHT + LAYER_GAP);
  Result := Rect(Bounds.Left + LAYER_LIST_PADDING,
    ItemBottom - LAYER_ROW_HEIGHT,
    Bounds.Right - LAYER_LIST_PADDING, ItemBottom);
end;

function TVectArtLayerRenderer.LockButtonRect(
  const ItemRect: TRect): TRect;
begin
  Result := Rect(ItemRect.Left + STATE_COLUMN_LEFT,
    ItemRect.Top + LOCK_BUTTON_TOP,
    ItemRect.Left + STATE_COLUMN_LEFT + STATE_BUTTON_SIZE,
    ItemRect.Top + LOCK_BUTTON_TOP + STATE_BUTTON_SIZE);
end;

function TVectArtLayerRenderer.VisibilityButtonRect(
  const ItemRect: TRect): TRect;
begin
  Result := Rect(ItemRect.Left + STATE_COLUMN_LEFT,
    ItemRect.Top + VISIBILITY_BUTTON_TOP,
    ItemRect.Left + STATE_COLUMN_LEFT + STATE_BUTTON_SIZE,
    ItemRect.Top + VISIBILITY_BUTTON_TOP + STATE_BUTTON_SIZE);
end;

end.
