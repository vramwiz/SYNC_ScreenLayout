// 文字情報を持たないレイヤー行へ、共通Skiaサムネイルと操作用状態アイコンを描画する。
unit ScreenLayoutLayerRenderer;

interface

uses
  System.Generics.Collections, System.Types, Vcl.Direct2D,
  Vcl.Graphics, ScreenLayoutDocument, ScreenLayoutEditorState,
  ScreenLayoutRenderer;

type
  TScreenLayoutLayerListEntry = record
    Depth: Integer;                  // 範囲線のX位置に使う表示上の階層深度。
    GroupRangeStart: Integer;        // 展開子の先頭。子を持たない行は0。
    Layer: TVectArtLayer;            // この表示行が参照する非所有Layer。
    Parent: TScreenLayoutGroupLayer; // 最上位行はnil、子行は直接の親Group。
    SourceIndex: Integer;            // Parent内またはDocument内での積層位置。
  end;

  TVectArtLayerRenderer = class
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FEntries: TArray<TScreenLayoutLayerListEntry>;
    FLastSelectedIndex: Integer;
    FScrollOffset: Integer;
    FRenderedThumbnails: TObjectDictionary<TVectArtLayer, TBitmap>;
    FThumbnailBitmap: TBitmap;
    FThumbnailBuffer: TVectArtRenderBuffer;
    FThumbnailRevision: Int64;
    procedure EnsureSelectionVisible(const Bounds: TRect);
    procedure ClampScrollOffset(const Bounds: TRect);
    function DisplayedLayerCount: Integer;
    function DisplayedSelectedIndex: Integer;
    procedure AppendGroupChildren(Group: TScreenLayoutGroupLayer;
      Depth: Integer; Entries: TList<TScreenLayoutLayerListEntry>);
    procedure AppendLayerEntry(Layer: TVectArtLayer;
      Parent: TScreenLayoutGroupLayer; SourceIndex, Depth: Integer;
      Entries: TList<TScreenLayoutLayerListEntry>);
    procedure DrawGroupRanges(ACanvas: TCanvas;
      const Bounds: TRect); overload;
    procedure DrawGroupRanges(ACanvas: TDirect2DCanvas;
      const Bounds: TRect); overload;
    procedure PreserveExpandedGroupPosition(
      const NewEntries: TArray<TScreenLayoutLayerListEntry>);
    procedure RebuildEntries;
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
    // サムネイル用バッファとRevision単位のキャッシュを生成する。
    constructor Create;
    // 非所有参照を破棄する前に、内部で所有する描画資源を解放する。
    destructor Destroy; override;
    // 表示中の行をGDI Canvasへ下層から上層の順で描画する。
    procedure DrawLayers(ACanvas: TCanvas;
      const Bounds: TRect); overload;
    // 表示中の行をDirect2D CanvasへGDI経路と同じ配置で描画する。
    procedure DrawLayers(ACanvas: TDirect2DCanvas;
      const Bounds: TRect); overload;
    // Y座標にある表示行の1基点Indexを返し、行外では-1を返す。
    function LayerIndexAt(const Bounds: TRect; Y: Integer): Integer;
    // 表示行Indexに対応する非所有Layerを返し、範囲外ではnilを返す。
    function LayerAt(Index: Integer): TVectArtLayer;
    // 表示行のグループ深度を返す。
    function LayerDepthAt(Index: Integer): Integer;
    // 表示行の直接の親Groupを返し、最上位行ではnilを返す。
    function LayerParentAt(Index: Integer): TScreenLayoutGroupLayer;
    // 表示行が属するDocumentまたは親Group内の積層Indexを返す。
    function LayerSourceIndexAt(Index: Integer): Integer;
    // スクロール量を反映した表示行の描画・当たり判定矩形を返す。
    function LayerItemRect(const Bounds: TRect; Index: Integer): TRect;
    // 現在の行数と表示高から有効な最大スクロール量を返す。
    function MaximumScrollOffset(const Bounds: TRect): Integer;
    // 1行と行間を合わせたホイール・ドラッグ用の移動量を返す。
    function ScrollStep: Integer;
    // 負値を0へ丸めてスクロール量を設定する。
    procedure SetScrollOffset(Value: Integer);
    // 各状態操作とグループ開閉で共有する当たり判定矩形を返す。
    function LockButtonRect(const ItemRect: TRect): TRect;
    function ExpandButtonRect(const ItemRect: TRect): TRect;
    function VisibilityButtonRect(const ItemRect: TRect): TRect;
    // DocumentとEditorStateは非所有参照。Document交換時はサムネイルキャッシュを破棄する。
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditorState: TVectArtEditorState read FEditorState
      write FEditorState;
    // 現在の先頭側へのスクロール量。
    property ScrollOffset: Integer read FScrollOffset write SetScrollOffset;
  end;

implementation

uses
  System.Math, Winapi.Windows;

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

function TVectArtLayerRenderer.DisplayedLayerCount: Integer;
begin
  Result := Length(FEntries);
end;

function TVectArtLayerRenderer.DisplayedSelectedIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  if FDocument = nil then
    Exit;
  for I := 0 to High(FEntries) do
    if ((FEntries[I].Parent = nil) and
        FDocument.IsLayerSelected(FEntries[I].SourceIndex)) or
       ((FEditorState <> nil) and
        (FEntries[I].Parent = FEditorState.OpenGroup) and
        FEditorState.IsOpenGroupChildSelected(FEntries[I].Layer)) then
      if ((FEntries[I].Parent = nil) and
          (FDocument.SelectedIndex = FEntries[I].SourceIndex)) or
         ((FEditorState <> nil) and
          (FEditorState.OpenGroupChild = FEntries[I].Layer)) then
        Exit(I + 1);
end;

procedure TVectArtLayerRenderer.AppendGroupChildren(
  Group: TScreenLayoutGroupLayer; Depth: Integer;
  Entries: TList<TScreenLayoutLayerListEntry>);
var
  I: Integer;
begin
  for I := 0 to Group.ChildCount - 1 do
    AppendLayerEntry(Group[I], Group, I, Depth, Entries);
end;

procedure TVectArtLayerRenderer.AppendLayerEntry(Layer: TVectArtLayer;
  Parent: TScreenLayoutGroupLayer; SourceIndex, Depth: Integer;
  Entries: TList<TScreenLayoutLayerListEntry>);
var
  Entry: TScreenLayoutLayerListEntry;
  Group: TScreenLayoutGroupLayer;
begin
  Entry.GroupRangeStart := 0;
  if (Layer is TScreenLayoutGroupLayer) and (FEditorState <> nil) and
    FEditorState.IsGroupInOpenPath(TScreenLayoutGroupLayer(Layer)) then
  begin
    Group := TScreenLayoutGroupLayer(Layer);
    Entry.GroupRangeStart := Entries.Count + 1;
    AppendGroupChildren(Group, Depth + 1, Entries);
  end;
  Entry.Depth := Depth;
  Entry.Layer := Layer;
  Entry.Parent := Parent;
  Entry.SourceIndex := SourceIndex;
  Entries.Add(Entry);
end;

procedure TVectArtLayerRenderer.RebuildEntries;
var
  Entries: TList<TScreenLayoutLayerListEntry>;
  I: Integer;
  NewEntries: TArray<TScreenLayoutLayerListEntry>;
begin
  Entries := TList<TScreenLayoutLayerListEntry>.Create;
  try
    if FDocument <> nil then
      for I := 1 to FDocument.LayerCount - 1 do
        AppendLayerEntry(FDocument[I], nil, I, 0, Entries);
    NewEntries := Entries.ToArray;
    PreserveExpandedGroupPosition(NewEntries);
    FEntries := NewEntries;
  finally
    Entries.Free;
  end;
end;

procedure TVectArtLayerRenderer.PreserveExpandedGroupPosition(
  const NewEntries: TArray<TScreenLayoutLayerListEntry>);
var
  I: Integer;
  J: Integer;
  OldIndex: Integer;
  NewIndex: Integer;
begin
  if (Length(FEntries) = 0) or (Length(NewEntries) = 0) then
    Exit;
  OldIndex := -1;
  NewIndex := -1;
  // 展開時は新しく開いたグループ、折り畳み時は閉じたグループを基準行にする。
  for J := 0 to High(NewEntries) do
    if NewEntries[J].GroupRangeStart > 0 then
      for I := 0 to High(FEntries) do
        if (FEntries[I].Layer = NewEntries[J].Layer) and
          (FEntries[I].GroupRangeStart = 0) then
        begin
          OldIndex := I;
          NewIndex := J;
          Break;
        end;
  if OldIndex < 0 then
    for I := 0 to High(FEntries) do
      if FEntries[I].GroupRangeStart > 0 then
        for J := 0 to High(NewEntries) do
          if (NewEntries[J].Layer = FEntries[I].Layer) and
            (NewEntries[J].GroupRangeStart = 0) then
          begin
            OldIndex := I;
            NewIndex := J;
            Break;
          end;
  if (OldIndex >= 0) and (NewIndex >= 0) then
  begin
    Inc(FScrollOffset, (NewIndex - OldIndex) *
      (LAYER_ROW_HEIGHT + LAYER_GAP));
    FLastSelectedIndex := -2;
  end;
end;

procedure TVectArtLayerRenderer.DrawGroupRanges(ACanvas: TCanvas;
  const Bounds: TRect);
var
  GroupRect: TRect;
  I: Integer;
  RangeRect: TRect;
  X: Integer;
begin
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := TColor($00806A48);
  for I := 1 to DisplayedLayerCount do
    if FEntries[I - 1].GroupRangeStart > 0 then
    begin
      GroupRect := LayerItemRect(Bounds, I);
      RangeRect := LayerItemRect(Bounds,
        FEntries[I - 1].GroupRangeStart);
      X := Bounds.Left + 3 + FEntries[I - 1].Depth * 3;
      ACanvas.MoveTo(GroupRect.Left, GroupRect.Top);
      ACanvas.LineTo(X, GroupRect.Top);
      ACanvas.LineTo(X, RangeRect.Bottom);
      ACanvas.LineTo(RangeRect.Left, RangeRect.Bottom);
    end;
end;

procedure TVectArtLayerRenderer.DrawGroupRanges(
  ACanvas: TDirect2DCanvas; const Bounds: TRect);
var
  GroupRect: TRect;
  I: Integer;
  RangeRect: TRect;
  X: Integer;
begin
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := TColor($00806A48);
  for I := 1 to DisplayedLayerCount do
    if FEntries[I - 1].GroupRangeStart > 0 then
    begin
      GroupRect := LayerItemRect(Bounds, I);
      RangeRect := LayerItemRect(Bounds,
        FEntries[I - 1].GroupRangeStart);
      X := Bounds.Left + 3 + FEntries[I - 1].Depth * 3;
      ACanvas.MoveTo(GroupRect.Left, GroupRect.Top);
      ACanvas.LineTo(X, GroupRect.Top);
      ACanvas.LineTo(X, RangeRect.Bottom);
      ACanvas.LineTo(RangeRect.Left, RangeRect.Bottom);
    end;
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
  if DisplayedLayerCount = 0 then
  begin
    FScrollOffset := 0;
    Exit;
  end;
  ContentTop := Bounds.Top + LAYER_LIST_PADDING;
  ContentBottom := Bounds.Bottom - LAYER_LIST_PADDING;
  MaximumOffset := MaximumScrollOffset(Bounds);
  FScrollOffset := EnsureRange(FScrollOffset, 0, MaximumOffset);
  SelectedIndex := DisplayedSelectedIndex;
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
  ExpandPoints: array[0..2] of TPoint;
  ExpandRect: TRect;
  LockRect: TRect;
  Row: Integer;
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

  if Layer is TScreenLayoutGroupLayer then
  begin
    // 名称列を省いても開閉操作を失わないよう、三角だけを状態列へ残す。
    ExpandRect := ExpandButtonRect(ItemRect);
    if (FEditorState <> nil) and FEditorState.IsGroupInOpenPath(
      TScreenLayoutGroupLayer(Layer)) then
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + 5, ExpandRect.Top + 4);
      ExpandPoints[1] := Point(ExpandRect.Right - 5, ExpandRect.Top + 4);
      ExpandPoints[2] := Point((ExpandRect.Left + ExpandRect.Right) div 2,
        ExpandRect.Bottom - 3);
    end
    else
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + 6, ExpandRect.Top + 2);
      ExpandPoints[1] := Point(ExpandRect.Left + 6, ExpandRect.Bottom - 2);
      ExpandPoints[2] := Point(ExpandRect.Right - 4,
        (ExpandRect.Top + ExpandRect.Bottom) div 2);
    end;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_SECONDARY;
    ACanvas.Polygon(ExpandPoints);
  end;

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
  ExpandPoints: array[0..2] of TPoint;
  ExpandRect: TRect;
  LockRect: TRect;
  Row: Integer;
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

  if Layer is TScreenLayoutGroupLayer then
  begin
    // GDI経路と同じ当たり判定矩形を使い、描画方式で操作位置を変えない。
    ExpandRect := ExpandButtonRect(ItemRect);
    if (FEditorState <> nil) and FEditorState.IsGroupInOpenPath(
      TScreenLayoutGroupLayer(Layer)) then
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + 5, ExpandRect.Top + 4);
      ExpandPoints[1] := Point(ExpandRect.Right - 5, ExpandRect.Top + 4);
      ExpandPoints[2] := Point((ExpandRect.Left + ExpandRect.Right) div 2,
        ExpandRect.Bottom - 3);
    end
    else
    begin
      ExpandPoints[0] := Point(ExpandRect.Left + 6, ExpandRect.Top + 2);
      ExpandPoints[1] := Point(ExpandRect.Left + 6, ExpandRect.Bottom - 2);
      ExpandPoints[2] := Point(ExpandRect.Right - 4,
        (ExpandRect.Top + ExpandRect.Bottom) div 2);
    end;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := COLOR_TEXT_SECONDARY;
    ACanvas.Polygon(ExpandPoints);
  end;

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
  Layer: TVectArtLayer;
  SelectedIndex: Integer;
begin
  RebuildEntries;
  SyncThumbnailCache;
  ClampScrollOffset(Bounds);
  SelectedIndex := DisplayedSelectedIndex;
  if FLastSelectedIndex <> SelectedIndex then
  begin
    EnsureSelectionVisible(Bounds);
    FLastSelectedIndex := SelectedIndex;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to DisplayedLayerCount do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Top >= Bounds.Bottom then
      Continue;
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    Layer := LayerAt(I);
    if LayerParentAt(I) <> nil then
      DrawLayerItem(ACanvas, ItemRect, Layer,
        (FEditorState <> nil) and
          (LayerParentAt(I) = FEditorState.OpenGroup) and
          FEditorState.IsOpenGroupChildSelected(Layer),
        (FEditorState <> nil) and
          ((FEditorState.OpenGroupChild = Layer) or
           (FEditorState.OpenGroup = Layer)))
    else
      DrawLayerItem(ACanvas, ItemRect, Layer,
        FDocument.IsLayerSelected(LayerSourceIndexAt(I)),
        (FDocument.SelectedIndex = LayerSourceIndexAt(I)) or
          ((FEditorState <> nil) and (FEditorState.OpenGroup = Layer)));
  end;
  DrawGroupRanges(ACanvas, Bounds);
end;

procedure TVectArtLayerRenderer.DrawLayers(ACanvas: TDirect2DCanvas;
  const Bounds: TRect);
var
  I: Integer;
  ItemRect: TRect;
  Layer: TVectArtLayer;
  SelectedIndex: Integer;
begin
  RebuildEntries;
  SyncThumbnailCache;
  ClampScrollOffset(Bounds);
  SelectedIndex := DisplayedSelectedIndex;
  if FLastSelectedIndex <> SelectedIndex then
  begin
    EnsureSelectionVisible(Bounds);
    FLastSelectedIndex := SelectedIndex;
  end;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := COLOR_LIST_BACKGROUND;
  ACanvas.FillRect(Bounds);
  if FDocument = nil then
    Exit;
  for I := 1 to DisplayedLayerCount do
  begin
    ItemRect := LayerItemRect(Bounds, I);
    if ItemRect.Top >= Bounds.Bottom then
      Continue;
    if ItemRect.Bottom <= Bounds.Top then
      Break;
    Layer := LayerAt(I);
    if LayerParentAt(I) <> nil then
      DrawLayerItem(ACanvas, ItemRect, Layer,
        (FEditorState <> nil) and
          (LayerParentAt(I) = FEditorState.OpenGroup) and
          FEditorState.IsOpenGroupChildSelected(Layer),
        (FEditorState <> nil) and
          ((FEditorState.OpenGroupChild = Layer) or
           (FEditorState.OpenGroup = Layer)))
    else
      DrawLayerItem(ACanvas, ItemRect, Layer,
        FDocument.IsLayerSelected(LayerSourceIndexAt(I)),
        (FDocument.SelectedIndex = LayerSourceIndexAt(I)) or
          ((FEditorState <> nil) and (FEditorState.OpenGroup = Layer)));
  end;
  DrawGroupRanges(ACanvas, Bounds);
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
  RebuildEntries;
  for I := 1 to DisplayedLayerCount do
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

function TVectArtLayerRenderer.LayerAt(Index: Integer): TVectArtLayer;
begin
  Result := nil;
  if (Index <= 0) or (Index > DisplayedLayerCount) then
    Exit;
  Result := FEntries[Index - 1].Layer;
end;

function TVectArtLayerRenderer.LayerDepthAt(Index: Integer): Integer;
begin
  Result := 0;
  if (Index > 0) and (Index <= DisplayedLayerCount) then
    Result := FEntries[Index - 1].Depth;
end;

function TVectArtLayerRenderer.LayerParentAt(
  Index: Integer): TScreenLayoutGroupLayer;
begin
  Result := nil;
  if (Index > 0) and (Index <= DisplayedLayerCount) then
    Result := FEntries[Index - 1].Parent;
end;

function TVectArtLayerRenderer.LayerSourceIndexAt(Index: Integer): Integer;
begin
  Result := -1;
  if (Index > 0) and (Index <= DisplayedLayerCount) then
    Result := FEntries[Index - 1].SourceIndex;
end;

function TVectArtLayerRenderer.MaximumScrollOffset(
  const Bounds: TRect): Integer;
var
  ContentHeight: Integer;
  ItemCount: Integer;
begin
  RebuildEntries;
  ItemCount := DisplayedLayerCount;
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

function TVectArtLayerRenderer.ExpandButtonRect(
  const ItemRect: TRect): TRect;
begin
  Result := Rect(ItemRect.Left + STATE_COLUMN_LEFT, ItemRect.Top + 1,
    ItemRect.Left + STATE_COLUMN_LEFT + STATE_BUTTON_SIZE,
    ItemRect.Top + 15);
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
