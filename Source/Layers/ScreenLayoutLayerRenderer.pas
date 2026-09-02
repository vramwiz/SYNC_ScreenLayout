// 共通Skia描画結果をサムネイルへ合成し、レイヤー一覧の行と状態アイコンを描画する。
unit ScreenLayoutLayerRenderer;

interface

uses
  System.Generics.Collections, System.SysUtils, System.Types, Vcl.Direct2D,
  Vcl.Graphics, ScreenLayoutDocument, ScreenLayoutRenderer;

type
  TVectArtLayerRenderer = class
  private
    FDocument: TVectArtDocument;
    FOpenGroup: TScreenLayoutGroupLayer;
    FLastSelectedIndex: Integer;
    FScrollOffset: Integer;
    FRenderedThumbnails: TObjectDictionary<TVectArtLayer, TBitmap>;
    FThumbnailBitmap: TBitmap;
    FThumbnailBuffer: TVectArtRenderBuffer;
    FThumbnailRevision: Int64;
    procedure EnsureSelectionVisible(const Bounds: TRect);
    procedure ClampScrollOffset(const Bounds: TRect);
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SyncThumbnailCache;
    procedure DrawRenderedLayerThumbnail(ACanvas: TCustomCanvas;
      const ThumbnailRect: TRect; Layer: TVectArtLayer);
    procedure DrawLayerItem(ACanvas: TCanvas; const ItemRect: TRect;
      Layer: TVectArtLayer; Selected, Active: Boolean); overload;
    procedure DrawLayerItem(ACanvas: TDirect2DCanvas;
      const ItemRect: TRect; Layer: TVectArtLayer;
      Selected, Active: Boolean); overload;
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
    function MaximumScrollOffset(const Bounds: TRect): Integer;
    function ScrollStep: Integer;
    procedure SetScrollOffset(Value: Integer);
    function LockButtonRect(const ItemRect: TRect): TRect;
    function VisibilityButtonRect(const ItemRect: TRect): TRect;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property OpenGroup: TScreenLayoutGroupLayer read FOpenGroup
      write FOpenGroup;
    property ScrollOffset: Integer read FScrollOffset write SetScrollOffset;
  end;

implementation

uses
  System.Math, Winapi.Windows, ScreenLayoutPathOperations;

const
  COLOR_LIST_BACKGROUND   = TColor($001A1A1A);
  COLOR_ROW_BACKGROUND    = TColor($00272727);
  COLOR_ROW_BORDER        = TColor($00424242);
  COLOR_ROW_SELECTED      = TColor($003D352A);
  COLOR_ROW_ACTIVE        = TColor($00D69C4A); // 減算の左辺にもなるアクティブ行の識別色。
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
function GroupLayerDetailText(GroupLayer: TScreenLayoutGroupLayer): string;
var
  I: Integer;
  NameList: string;
begin
  NameList := '';
  for I := 0 to Min(GroupLayer.ChildCount - 1, 2) do
  begin
    if NameList <> '' then
      NameList := NameList + ' / ';
    NameList := NameList + GroupLayer[I].Name;
  end;
  if GroupLayer.ChildCount > 3 then
    NameList := NameList + ' / ...';
  Result := Format('Group  %d layers', [GroupLayer.ChildCount]);
  if NameList <> '' then
    Result := Result + '  ' + NameList;
end;

constructor TVectArtLayerRenderer.Create;
begin
  inherited Create;
  FRenderedThumbnails := TObjectDictionary<TVectArtLayer,
    Vcl.Graphics.TBitmap>.Create([doOwnsValues]);
  FThumbnailBitmap := Vcl.Graphics.TBitmap.Create;
  FThumbnailBuffer := TVectArtRenderBuffer.Create;
  FThumbnailRevision := -1;
  FLastSelectedIndex := -2;
end;

destructor TVectArtLayerRenderer.Destroy;
begin
  FThumbnailBuffer.Free;
  FThumbnailBitmap.Free;
  FRenderedThumbnails.Free;
  inherited Destroy;
end;

procedure TVectArtLayerRenderer.EnsureSelectionVisible(
  const Bounds: TRect);
var
  ContentBottom: Integer;
  ContentTop: Integer;
  ItemRect: TRect;
  MaximumOffset: Integer;
  SelectedIndex: Integer;
begin
  if (FDocument = nil) or (FDocument.LayerCount <= 1) then
  begin
    FScrollOffset := 0;
    Exit;
  end;
  ContentTop := Bounds.Top + LAYER_LIST_PADDING;
  ContentBottom := Bounds.Bottom - LAYER_LIST_PADDING;
  MaximumOffset := MaximumScrollOffset(Bounds);
  FScrollOffset := EnsureRange(FScrollOffset, 0, MaximumOffset);
  SelectedIndex := FDocument.SelectedIndex;
  if SelectedIndex <= 0 then
    Exit;
  ItemRect := LayerItemRect(Bounds, SelectedIndex);
  if ItemRect.Top < ContentTop then
    Inc(FScrollOffset, ContentTop - ItemRect.Top)
  else if ItemRect.Bottom > ContentBottom then
    Dec(FScrollOffset, ItemRect.Bottom - ContentBottom);
  FScrollOffset := EnsureRange(FScrollOffset, 0, MaximumOffset);
end;

procedure TVectArtLayerRenderer.ClampScrollOffset(const Bounds: TRect);
begin
  FScrollOffset := EnsureRange(FScrollOffset, 0,
    MaximumScrollOffset(Bounds));
end;

procedure TVectArtLayerRenderer.DrawRenderedLayerThumbnail(
  ACanvas: TCustomCanvas; const ThumbnailRect: TRect;
  Layer: TVectArtLayer);
var
  Alpha: Cardinal;
  BackgroundColor: TColor;
  BackgroundValue: Cardinal;
  CachedBitmap: Vcl.Graphics.TBitmap;
  Destination: PByte;
  Source: PVectArtRgbaPixel;
  X: Integer;
  Y: Integer;
begin
  if (ACanvas = nil) or (Layer = nil) or
    (ThumbnailRect.Width <= 0) or (ThumbnailRect.Height <= 0) then
    Exit;
  if FRenderedThumbnails.TryGetValue(Layer, CachedBitmap) and
    (CachedBitmap.Width = ThumbnailRect.Width) and
    (CachedBitmap.Height = ThumbnailRect.Height) then
  begin
    ACanvas.Draw(ThumbnailRect.Left, ThumbnailRect.Top, CachedBitmap);
    Exit;
  end;
  FRenderedThumbnails.Remove(Layer);
  RenderVectArtLayerThumbnail(Layer, FThumbnailBuffer,
    ThumbnailRect.Width, ThumbnailRect.Height);
  FThumbnailBitmap.PixelFormat := pf32bit;
  FThumbnailBitmap.SetSize(ThumbnailRect.Width, ThumbnailRect.Height);
  Source := FThumbnailBuffer.Data;
  for Y := 0 to ThumbnailRect.Height - 1 do
  begin
    Destination := FThumbnailBitmap.ScanLine[Y];
    for X := 0 to ThumbnailRect.Width - 1 do
    begin
      if Odd((X div THUMBNAIL_CHECKER_SIZE) +
        (Y div THUMBNAIL_CHECKER_SIZE)) then
        BackgroundColor := TColor($00B8B8B8)
      else
        BackgroundColor := clWhite;
      BackgroundValue := ColorToRGB(BackgroundColor);
      Alpha := Source^.A;
      Destination[0] := (Cardinal(Source^.B) * Alpha +
        Cardinal(GetBValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
      Destination[1] := (Cardinal(Source^.G) * Alpha +
        Cardinal(GetGValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
      Destination[2] := (Cardinal(Source^.R) * Alpha +
        Cardinal(GetRValue(BackgroundValue)) * (255 - Alpha) + 127) div 255;
      Destination[3] := 255;
      Inc(Destination, 4);
      Inc(Source);
    end;
  end;
  CachedBitmap := Vcl.Graphics.TBitmap.Create;
  CachedBitmap.Assign(FThumbnailBitmap);
  FRenderedThumbnails.Add(Layer, CachedBitmap);
  ACanvas.Draw(ThumbnailRect.Left, ThumbnailRect.Top, CachedBitmap);
end;

procedure TVectArtLayerRenderer.DrawLayerItem(ACanvas: TCanvas;
  const ItemRect: TRect; Layer: TVectArtLayer; Selected, Active: Boolean);
var
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  Column: Integer;
  DetailText: string;
  LockRect: TRect;
  PathLayer: TVectArtPathLayer;
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
  if Layer = FOpenGroup then
  begin
    ACanvas.Pen.Color := TColor($00D6A04A);
    ACanvas.FrameRect(Rect(ItemRect.Left + 2, ItemRect.Top + 2,
      ItemRect.Right - 2, ItemRect.Bottom - 2));
  end;
  if Active then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_ROW_ACTIVE;
    ACanvas.FillRect(Rect(ItemRect.Left, ItemRect.Top,
      ItemRect.Left + 3, ItemRect.Bottom));
    ACanvas.Brush.Style := bsClear;
  end;

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
  if not (Layer is TVectArtCanvasLayer) then
    DrawRenderedLayerThumbnail(ACanvas, ThumbnailRect, Layer);
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
  else if Layer is TScreenLayoutGroupLayer then
    DetailText := GroupLayerDetailText(TScreenLayoutGroupLayer(Layer))
  else if Layer is TScreenLayoutTextLayer then
    DetailText := Format('Text  %spt  %d%%',
      [FormatFloat('0.##', TScreenLayoutTextLayer(Layer).FontSize),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutEllipseArcShapeLayer then
    DetailText := Format('Arc Shape  %d%%', [Round(Layer.Opacity * 100)])
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
  else if Layer is TScreenLayoutEllipseLineLayer then
    DetailText := Format('Ellipse Line  %spx  %d%%',
      [FormatFloat('0.##', TScreenLayoutEllipseLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutRoundedRectangleLineLayer then
    DetailText := Format('Rounded Rectangle Line  %spx  %d%%',
      [FormatFloat('0.##',
       TScreenLayoutRoundedRectangleLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutRectangleLineLayer then
    DetailText := Format('Rectangle Line  %spx  %d%%',
      [FormatFloat('0.##',
       TScreenLayoutRectangleLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutArcLayer then
    DetailText := Format('Arc  %spx  %d%%',
      [FormatFloat('0.##', TScreenLayoutArcLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TVectArtPathLayer then
  begin
    PathLayer := TVectArtPathLayer(Layer);
    if not PathLayer.Closed and
      ScreenLayoutPathIsStraightLine(PathLayer.Vertices) then
      DetailText := Format('Line  %spx  %d%%',
        [FormatFloat('0.##', PathLayer.StrokeWidth),
         Round(Layer.Opacity * 100)])
    else
      DetailText := Format('Path  %d%%', [Round(Layer.Opacity * 100)]);
  end
  else if Layer is TScreenLayoutShapeLayer then
    DetailText := Format('Shape  %d contours  %d%%',
      [TScreenLayoutShapeLayer(Layer).ContourCount,
       Round(Layer.Opacity * 100)])
  else
    DetailText := '';
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
  const ItemRect: TRect; Layer: TVectArtLayer; Selected, Active: Boolean);
var
  CanvasLayer: TVectArtCanvasLayer;
  CellRect: TRect;
  Column: Integer;
  DetailText: string;
  LockRect: TRect;
  PathLayer: TVectArtPathLayer;
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
  if Layer = FOpenGroup then
  begin
    ACanvas.Pen.Color := TColor($00D6A04A);
    ACanvas.FrameRect(Rect(ItemRect.Left + 2, ItemRect.Top + 2,
      ItemRect.Right - 2, ItemRect.Bottom - 2));
  end;
  if Active then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_ROW_ACTIVE;
    ACanvas.FillRect(Rect(ItemRect.Left, ItemRect.Top,
      ItemRect.Left + 3, ItemRect.Bottom));
    ACanvas.Brush.Style := bsClear;
  end;

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
  if not (Layer is TVectArtCanvasLayer) then
    DrawRenderedLayerThumbnail(ACanvas, ThumbnailRect, Layer);
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
  else if Layer is TScreenLayoutGroupLayer then
    DetailText := GroupLayerDetailText(TScreenLayoutGroupLayer(Layer))
  else if Layer is TScreenLayoutTextLayer then
    DetailText := Format('Text  %spt  %d%%',
      [FormatFloat('0.##', TScreenLayoutTextLayer(Layer).FontSize),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutEllipseArcShapeLayer then
    DetailText := Format('Arc Shape  %d%%', [Round(Layer.Opacity * 100)])
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
  else if Layer is TScreenLayoutEllipseLineLayer then
    DetailText := Format('Ellipse Line  %spx  %d%%',
      [FormatFloat('0.##', TScreenLayoutEllipseLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutRoundedRectangleLineLayer then
    DetailText := Format('Rounded Rectangle Line  %spx  %d%%',
      [FormatFloat('0.##',
       TScreenLayoutRoundedRectangleLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutRectangleLineLayer then
    DetailText := Format('Rectangle Line  %spx  %d%%',
      [FormatFloat('0.##',
       TScreenLayoutRectangleLineLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TScreenLayoutArcLayer then
    DetailText := Format('Arc  %spx  %d%%',
      [FormatFloat('0.##', TScreenLayoutArcLayer(Layer).StrokeWidth),
       Round(Layer.Opacity * 100)])
  else if Layer is TVectArtPathLayer then
  begin
    PathLayer := TVectArtPathLayer(Layer);
    if not PathLayer.Closed and
      ScreenLayoutPathIsStraightLine(PathLayer.Vertices) then
      DetailText := Format('Line  %spx  %d%%',
        [FormatFloat('0.##', PathLayer.StrokeWidth),
         Round(Layer.Opacity * 100)])
    else
      DetailText := Format('Path  %d%%', [Round(Layer.Opacity * 100)]);
  end
  else if Layer is TScreenLayoutShapeLayer then
    DetailText := Format('Shape  %d contours  %d%%',
      [TScreenLayoutShapeLayer(Layer).ContourCount,
       Round(Layer.Opacity * 100)])
  else
    DetailText := '';
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
  FRenderedThumbnails.Clear;
  FScrollOffset := 0;
  FLastSelectedIndex := -2;
  FThumbnailRevision := -1;
end;

procedure TVectArtLayerRenderer.SyncThumbnailCache;
begin
  if FDocument = nil then
  begin
    FRenderedThumbnails.Clear;
    FThumbnailRevision := -1;
    Exit;
  end;
  if FThumbnailRevision = FDocument.Revision then
    Exit;
  FRenderedThumbnails.Clear;
  FThumbnailRevision := FDocument.Revision;
end;

procedure TVectArtLayerRenderer.DrawLayers(ACanvas: TCanvas;
  const Bounds: TRect);
var
  I: Integer;
  ItemRect: TRect;
begin
  SyncThumbnailCache;
  ClampScrollOffset(Bounds);
  if (FDocument <> nil) and
    (FLastSelectedIndex <> FDocument.SelectedIndex) then
  begin
    EnsureSelectionVisible(Bounds);
    FLastSelectedIndex := FDocument.SelectedIndex;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Top >= Bounds.Bottom then
      Continue;
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    DrawLayerItem(ACanvas, ItemRect, FDocument[I],
      FDocument.IsLayerSelected(I), FDocument.SelectedIndex = I);
  end;
end;

procedure TVectArtLayerRenderer.DrawLayers(ACanvas: TDirect2DCanvas;
  const Bounds: TRect);
var
  I: Integer;
  ItemRect: TRect;
begin
  SyncThumbnailCache;
  ClampScrollOffset(Bounds);
  if (FDocument <> nil) and
    (FLastSelectedIndex <> FDocument.SelectedIndex) then
  begin
    EnsureSelectionVisible(Bounds);
    FLastSelectedIndex := FDocument.SelectedIndex;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to FDocument.LayerCount - 1 do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Top >= Bounds.Bottom then
      Continue;
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    DrawLayerItem(ACanvas, ItemRect, FDocument[I],
      FDocument.IsLayerSelected(I), FDocument.SelectedIndex = I);
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
    (Index - 1) * (LAYER_ROW_HEIGHT + LAYER_GAP) + FScrollOffset;
  Result := Rect(Bounds.Left + LAYER_LIST_PADDING,
    ItemBottom - LAYER_ROW_HEIGHT,
    Bounds.Right - LAYER_LIST_PADDING, ItemBottom);
end;

function TVectArtLayerRenderer.MaximumScrollOffset(
  const Bounds: TRect): Integer;
var
  ContentHeight: Integer;
  ItemCount: Integer;
begin
  if FDocument = nil then
    Exit(0);
  ItemCount := Max(FDocument.LayerCount - 1, 0);
  if ItemCount = 0 then
    Exit(0);
  ContentHeight := ItemCount * LAYER_ROW_HEIGHT +
    Max(ItemCount - 1, 0) * LAYER_GAP + 2 * LAYER_LIST_PADDING;
  Result := Max(ContentHeight - Bounds.Height, 0);
end;

function TVectArtLayerRenderer.ScrollStep: Integer;
begin
  Result := LAYER_ROW_HEIGHT + LAYER_GAP;
end;

procedure TVectArtLayerRenderer.SetScrollOffset(Value: Integer);
begin
  FScrollOffset := Max(Value, 0);
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
