// 編集対象となる用紙とオブジェクトレイヤーを一元管理する。
// レイヤー配列の先頭を最背面、末尾を最前面とする。
unit ScreenLayoutDocument;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  Vcl.Graphics;

type
  TVectArtLayerKind = (vlkCanvas, vlkRectangle, vlkPath, vlkImage);
  TVectArtImageSourceKind = (visImage, visLogo);
  TVectArtImagePoints = array[0..3] of TPointF;
  // WebArt Designerの線種コンボとMIF vector stroke style 0..8を同順で保持する。
  TVectArtMifStrokeStyle = (vssSolid, vssDotted, vssShortDash, vssDashDot,
    vssDashDotDot, vssSparseDotted, vssMediumDash, vssLongDashDot,
    vssLongDash);
  // MIFのvector stroke cap 0..2と同じ順序で保持する。
  TVectArtLineCap = (vlcButt, vlcSquare, vlcRound);
  // MIFのvector stroke join 0..2と同じ順序で保持する。
  TVectArtLineJoin = (vljMiter, vljBevel, vljRound);
  TVectArtLayer = class
  private
    FKind: TVectArtLayerKind;
    FLocked: Boolean;
    FName: string;
    FOpacity: Single;
    FVisible: Boolean;
  protected
    constructor Create(AKind: TVectArtLayerKind; const AName: string);
  public
    property Kind: TVectArtLayerKind read FKind;
    property Locked: Boolean read FLocked write FLocked;
    property Name: string read FName write FName;
    property Opacity: Single read FOpacity write FOpacity;
    property Visible: Boolean read FVisible write FVisible;
  end;

  TVectArtCanvasLayer = class(TVectArtLayer)
  private
    FBackgroundColor: TColor;
    FHeight: Integer;
    FTransparent: Boolean;
    FWidth: Integer;
  public
    constructor Create(AWidth, AHeight: Integer; AColor: TColor);
    property BackgroundColor: TColor read FBackgroundColor
      write FBackgroundColor;
    property Height: Integer read FHeight write FHeight;
    property Transparent: Boolean read FTransparent write FTransparent;
    property Width: Integer read FWidth write FWidth;
  end;

  TVectArtRectangleLayer = class(TVectArtLayer)
  private
    FBounds: TRectF;
    FFillColor: TColor;
    FRotationDegrees: Single;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor);
    property Bounds: TRectF read FBounds write FBounds;
    property FillColor: TColor read FFillColor write FFillColor;
    property RotationDegrees: Single read FRotationDegrees
      write FRotationDegrees;
  end;

  TVectArtRectangleData = record
    Bounds: TRectF;                         // 回転前の基本矩形。
    FillColor: TColor;                      // 内部の塗り色。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single;                // 中心回りの時計回り角度。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TVectArtPathLayer = class(TVectArtLayer)
  private
    FClosed: Boolean;
    FFillColor: TColor;
    FLineCap: TVectArtLineCap;
    FLineJoin: TVectArtLineJoin;
    FMifAntiAlias: Boolean;
    FPoints: TArray<TPointF>;
    FStrokeColor: TColor;
    FMifStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
  public
    constructor Create(const AName: string; const APoints: TArray<TPointF>;
      AClosed: Boolean);
    property Closed: Boolean read FClosed write FClosed;
    property FillColor: TColor read FFillColor write FFillColor;
    property LineCap: TVectArtLineCap read FLineCap write FLineCap;
    property LineJoin: TVectArtLineJoin read FLineJoin write FLineJoin;
    property MifAntiAlias: Boolean read FMifAntiAlias write FMifAntiAlias;
    property Points: TArray<TPointF> read FPoints write FPoints;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property MifStrokeStyle: TVectArtMifStrokeStyle read FMifStrokeStyle
      write FMifStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
  end;

  TVectArtPathData = record
    Closed: Boolean;                        // 終点と始点を閉じる状態。
    FillColor: TColor;                      // 閉領域の塗り色。
    LineCap: TVectArtLineCap;               // 開いたPathの線端形状。
    LineJoin: TVectArtLineJoin;             // 頂点間の線結合形状。
    MifAntiAlias: Boolean;                  // MIF vector qualityに対応する品質値。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    Points: TArray<TPointF>;                // 描画順に並ぶ頂点列。
    StrokeColor: TColor;                    // 開いたPathの線色。
    MifStrokeStyle: TVectArtMifStrokeStyle; // 開いたPathの線パターン。
    StrokeWidth: Single;                    // 開いたPathの線幅。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TVectArtImageLayer = class(TVectArtLayer)
  private
    FPngData: TBytes;
    FPoints: TVectArtImagePoints;
    FSourceFileName: string;
    FSourceKind: TVectArtImageSourceKind;
  public
    constructor Create(const AName: string; const APngData: TBytes;
      const APoints: TVectArtImagePoints; ASourceKind: TVectArtImageSourceKind;
      const ASourceFileName: string = '');
    property PngData: TBytes read FPngData;
    property Points: TVectArtImagePoints read FPoints write FPoints;
    property SourceFileName: string read FSourceFileName;
    property SourceKind: TVectArtImageSourceKind read FSourceKind;
  end;

  TVectArtImageData = record
    Locked: Boolean;                     // 編集を禁止する状態。
    Name: string;                        // レイヤー一覧の表示名。
    Opacity: Single;                     // 0.0..1.0のレイヤー不透明度。
    PngData: TBytes;                     // 埋め込みPNGの全バイト。
    Points: TVectArtImagePoints;         // 左上から時計回りの配置4頂点。
    SourceFileName: string;              // JSONから参照する画像ファイルパス。
    SourceKind: TVectArtImageSourceKind; // MIF由来のimage／logo区分。
    Visible: Boolean;                    // 描画対象に含める状態。
  end;

  TVectArtDocument = class
  private
    FLayers: TObjectList<TVectArtLayer>;
    FChangePending: Boolean;
    FInteractiveChanged: Boolean;
    FInteractiveUpdateCount: Integer;
    FOnChanged: TNotifyEvent;
    FRevision: Int64;
    FSelectedIndex: Integer;
    FSelectedLayers: TList<Integer>;
    FUpdateCount: Integer;
    function GetCanvasLayer: TVectArtCanvasLayer;
    function GetLayer(Index: Integer): TVectArtLayer;
    function GetLayerCount: Integer;
    function GetIsInteractiveUpdate: Boolean;
    function GetSelectionCount: Integer;
    procedure SelectionChanged;
    procedure SetSelectedLayersCore(const Indices: array of Integer;
      Notify: Boolean);
    procedure SetSelectedIndex(const Value: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginInteractiveUpdate;
    procedure BeginUpdate;
    procedure Changed;
    procedure EndInteractiveUpdate;
    procedure EndUpdate;
    function GetSelectedLayerIndices: TArray<Integer>;
    function InsertRectangle(Index: Integer;
      const Data: TVectArtRectangleData): Integer;
    function InsertPath(Index: Integer; const Data: TVectArtPathData): Integer;
    function InsertImage(Index: Integer; const Data: TVectArtImageData): Integer;
    function IsLayerSelected(Index: Integer): Boolean;
    procedure SetCanvasSize(AWidth, AHeight: Integer);
    procedure SetRectangleBounds(Index: Integer; const Value: TRectF);
    procedure SetRectangleFillColor(Index: Integer; Value: TColor);
    procedure SetRectangleRotation(Index: Integer; Value: Single);
    procedure SetImagePoints(Index: Integer;
      const Points: TVectArtImagePoints);
    procedure SetPathFill(Index: Integer; Color: TColor);
    procedure SetPathLineCap(Index: Integer; Value: TVectArtLineCap);
    procedure SetPathLineJoin(Index: Integer; Value: TVectArtLineJoin);
    procedure SetPathMifAntiAlias(Index: Integer; Value: Boolean);
    procedure SetLayerLocked(Index: Integer; Value: Boolean);
    procedure SetLayerOpacity(Index: Integer; Value: Single);
    procedure SetLayerVisible(Index: Integer; Value: Boolean);
    procedure MoveLayer(FromIndex, ToIndex: Integer);
    function RemoveRectangle(Index: Integer;
      out Data: TVectArtRectangleData): Boolean;
    function RemovePath(Index: Integer; out Data: TVectArtPathData): Boolean;
    function RemoveImage(Index: Integer; out Data: TVectArtImageData): Boolean;
    procedure SetPathPoints(Index: Integer; const Points: TArray<TPointF>);
    procedure SetPathStroke(Index: Integer; Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
    procedure SelectLayerRange(AnchorIndex, TargetIndex: Integer;
      Additive: Boolean);
    procedure SetSelectedLayers(const Indices: array of Integer);
    procedure ToggleSelectedLayer(Index: Integer);
    property CanvasLayer: TVectArtCanvasLayer read GetCanvasLayer;
    property LayerCount: Integer read GetLayerCount;
    property Layers[Index: Integer]: TVectArtLayer read GetLayer; default;
    property IsInteractiveUpdate: Boolean read GetIsInteractiveUpdate;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property Revision: Int64 read FRevision;
    property SelectedIndex: Integer read FSelectedIndex write SetSelectedIndex;
    property SelectionCount: Integer read GetSelectionCount;
  end;

const
  DEFAULT_CANVAS_WIDTH = 1920;
  DEFAULT_CANVAS_HEIGHT = 1080;
  // 旧実装名はMIF style 3（ダッシュ・ドット）として互換維持する。
  vssDashed: TVectArtMifStrokeStyle = vssDashDot;

function VectArtStrokeDashIntervals(Style: TVectArtMifStrokeStyle;
  Width: Single): TArray<Single>;
function VectArtStrokeUsesRoundCaps(Style: TVectArtMifStrokeStyle): Boolean;

implementation

uses
  System.Math, ScreenLayoutGeometry;

function VectArtStrokeDashIntervals(Style: TVectArtMifStrokeStyle;
  Width: Single): TArray<Single>;
begin
  Width := Max(Width, 0.1);
  case Style of
    vssDotted:
      Result := [Width, Width * 2];
    vssShortDash:
      Result := [Width * 3, Width * 3];
    vssDashDot:
      Result := [Width * 6, Width * 2, Width, Width * 2];
    vssDashDotDot:
      Result := [Width * 6, Width * 2, Width, Width * 2,
        Width, Width * 2];
    vssSparseDotted:
      Result := [Width, Width * 4];
    vssMediumDash:
      Result := [Width * 5, Width * 2];
    vssLongDashDot:
      Result := [Width * 9, Width * 2, Width, Width * 2];
    vssLongDash:
      Result := [Width * 9, Width * 3];
  else
    Result := nil;
  end;
end;

function VectArtStrokeUsesRoundCaps(Style: TVectArtMifStrokeStyle): Boolean;
begin
  Result := Style in [vssDotted, vssDashDot, vssDashDotDot,
    vssSparseDotted, vssLongDashDot];
end;

{ TVectArtLayer }

constructor TVectArtLayer.Create(AKind: TVectArtLayerKind;
  const AName: string);
begin
  inherited Create;
  FKind := AKind;
  FLocked := False;
  FName := AName;
  FOpacity := 1.0;
  FVisible := True;
end;

{ TVectArtCanvasLayer }

constructor TVectArtCanvasLayer.Create(AWidth, AHeight: Integer;
  AColor: TColor);
begin
  inherited Create(vlkCanvas, 'Canvas');
  FWidth := Max(AWidth, 1);
  FHeight := Max(AHeight, 1);
  FBackgroundColor := AColor;
  FTransparent := False;
end;

{ TVectArtRectangleLayer }

constructor TVectArtRectangleLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor);
begin
  inherited Create(vlkRectangle, AName);
  FBounds := ABounds;
  FFillColor := AFillColor;
  FRotationDegrees := 0.0;
end;

{ TVectArtPathLayer }

constructor TVectArtPathLayer.Create(const AName: string;
  const APoints: TArray<TPointF>; AClosed: Boolean);
begin
  inherited Create(vlkPath, AName);
  FPoints := Copy(APoints);
  FClosed := AClosed;
  FFillColor := clWhite;
  FLineCap := vlcButt;
  FLineJoin := vljMiter;
  FMifAntiAlias := True;
  FStrokeColor := clBlack;
  FMifStrokeStyle := vssSolid;
  FStrokeWidth := 1.0;
end;

{ TVectArtImageLayer }

constructor TVectArtImageLayer.Create(const AName: string;
  const APngData: TBytes; const APoints: TVectArtImagePoints;
  ASourceKind: TVectArtImageSourceKind; const ASourceFileName: string);
begin
  inherited Create(vlkImage, AName);
  FPngData := Copy(APngData);
  FPoints := APoints;
  FSourceFileName := ASourceFileName;
  FSourceKind := ASourceKind;
end;

{ TVectArtDocument }

constructor TVectArtDocument.Create;
begin
  inherited Create;
  FLayers := TObjectList<TVectArtLayer>.Create(True);
  FSelectedLayers := TList<Integer>.Create;
  FLayers.Add(TVectArtCanvasLayer.Create(DEFAULT_CANVAS_WIDTH,
    DEFAULT_CANVAS_HEIGHT, clWhite));
  FSelectedIndex := -1;
end;

destructor TVectArtDocument.Destroy;
begin
  FSelectedLayers.Free;
  FLayers.Free;
  inherited Destroy;
end;

procedure TVectArtDocument.Changed;
begin
  if FUpdateCount > 0 then
  begin
    FChangePending := True;
    Exit;
  end;
  Inc(FRevision);
  if FInteractiveUpdateCount > 0 then
    FInteractiveChanged := True;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtDocument.BeginInteractiveUpdate;
begin
  Inc(FInteractiveUpdateCount);
end;

procedure TVectArtDocument.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TVectArtDocument.EndInteractiveUpdate;
begin
  if FInteractiveUpdateCount <= 0 then
    Exit;
  Dec(FInteractiveUpdateCount);
  if (FInteractiveUpdateCount = 0) and FInteractiveChanged then
  begin
    FInteractiveChanged := False;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
  end;
end;

procedure TVectArtDocument.EndUpdate;
begin
  if FUpdateCount <= 0 then
    Exit;
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FChangePending then
  begin
    FChangePending := False;
    Changed;
  end;
end;

procedure TVectArtDocument.SelectionChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TVectArtDocument.GetSelectedLayerIndices: TArray<Integer>;
begin
  Result := FSelectedLayers.ToArray;
end;

function TVectArtDocument.GetIsInteractiveUpdate: Boolean;
begin
  Result := FInteractiveUpdateCount > 0;
end;

function TVectArtDocument.InsertRectangle(Index: Integer;
  const Data: TVectArtRectangleData): Integer;
var
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  RectangleLayer := TVectArtRectangleLayer.Create(Data.Name, Data.Bounds,
    Data.FillColor);
  RectangleLayer.Locked := Data.Locked;
  RectangleLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  RectangleLayer.RotationDegrees := NormalizeAngleDegrees(
    Data.RotationDegrees);
  RectangleLayer.Visible := Data.Visible;
  FLayers.Insert(Result, RectangleLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertPath(Index: Integer;
  const Data: TVectArtPathData): Integer;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  PathLayer := TVectArtPathLayer.Create(Data.Name, Data.Points, Data.Closed);
  PathLayer.FillColor := Data.FillColor;
  PathLayer.LineCap := Data.LineCap;
  PathLayer.LineJoin := Data.LineJoin;
  PathLayer.MifAntiAlias := Data.MifAntiAlias;
  PathLayer.Locked := Data.Locked;
  PathLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  PathLayer.StrokeColor := Data.StrokeColor;
  PathLayer.MifStrokeStyle := Data.MifStrokeStyle;
  PathLayer.StrokeWidth := Max(Data.StrokeWidth, 0.0);
  PathLayer.Visible := Data.Visible;
  FLayers.Insert(Result, PathLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertImage(Index: Integer;
  const Data: TVectArtImageData): Integer;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ImageLayer := TVectArtImageLayer.Create(Data.Name, Data.PngData,
    Data.Points, Data.SourceKind, Data.SourceFileName);
  ImageLayer.Locked := Data.Locked;
  ImageLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ImageLayer.Visible := Data.Visible;
  FLayers.Insert(Result, ImageLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

procedure TVectArtDocument.MoveLayer(FromIndex, ToIndex: Integer);
var
  I: Integer;
  Layer: TVectArtLayer;
  Selection: TArray<Integer>;
begin
  if (FromIndex <= 0) or (FromIndex >= FLayers.Count) then
    Exit;
  ToIndex := EnsureRange(ToIndex, 1, FLayers.Count - 1);
  if FromIndex = ToIndex then
    Exit;
  Selection := GetSelectedLayerIndices;
  Layer := FLayers.Extract(FLayers[FromIndex]);
  FLayers.Insert(ToIndex, Layer);
  for I := 0 to High(Selection) do
    if Selection[I] = FromIndex then
      Selection[I] := ToIndex
    else if (FromIndex < ToIndex) and (Selection[I] > FromIndex) and
      (Selection[I] <= ToIndex) then
      Dec(Selection[I])
    else if (FromIndex > ToIndex) and (Selection[I] >= ToIndex) and
      (Selection[I] < FromIndex) then
      Inc(Selection[I]);
  SetSelectedLayersCore(Selection, False);
  Changed;
end;

function TVectArtDocument.RemoveRectangle(Index: Integer;
  out Data: TVectArtRectangleData): Boolean;
var
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TVectArtRectangleLayer);
  if not Result then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  Data.Bounds := RectangleLayer.Bounds;
  Data.FillColor := RectangleLayer.FillColor;
  Data.Locked := RectangleLayer.Locked;
  Data.Name := RectangleLayer.Name;
  Data.Opacity := RectangleLayer.Opacity;
  Data.RotationDegrees := RectangleLayer.RotationDegrees;
  Data.Visible := RectangleLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemovePath(Index: Integer;
  out Data: TVectArtPathData): Boolean;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TVectArtPathLayer);
  if not Result then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  Data.Closed := PathLayer.Closed;
  Data.FillColor := PathLayer.FillColor;
  Data.LineCap := PathLayer.LineCap;
  Data.LineJoin := PathLayer.LineJoin;
  Data.MifAntiAlias := PathLayer.MifAntiAlias;
  Data.Locked := PathLayer.Locked;
  Data.Name := PathLayer.Name;
  Data.Opacity := PathLayer.Opacity;
  Data.Points := Copy(PathLayer.Points);
  Data.StrokeColor := PathLayer.StrokeColor;
  Data.MifStrokeStyle := PathLayer.MifStrokeStyle;
  Data.StrokeWidth := PathLayer.StrokeWidth;
  Data.Visible := PathLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveImage(Index: Integer;
  out Data: TVectArtImageData): Boolean;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TVectArtImageLayer);
  if not Result then
    Exit;
  ImageLayer := TVectArtImageLayer(FLayers[Index]);
  Data.Locked := ImageLayer.Locked;
  Data.Name := ImageLayer.Name;
  Data.Opacity := ImageLayer.Opacity;
  Data.PngData := Copy(ImageLayer.PngData);
  Data.Points := ImageLayer.Points;
  Data.SourceFileName := ImageLayer.SourceFileName;
  Data.SourceKind := ImageLayer.SourceKind;
  Data.Visible := ImageLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.GetCanvasLayer: TVectArtCanvasLayer;
begin
  if (FLayers.Count > 0) and (FLayers[0] is TVectArtCanvasLayer) then
    Result := TVectArtCanvasLayer(FLayers[0])
  else
    Result := nil;
end;

function TVectArtDocument.GetLayer(Index: Integer): TVectArtLayer;
begin
  Result := FLayers[Index];
end;

function TVectArtDocument.GetLayerCount: Integer;
begin
  Result := FLayers.Count;
end;

function TVectArtDocument.GetSelectionCount: Integer;
begin
  Result := FSelectedLayers.Count;
end;

function TVectArtDocument.IsLayerSelected(Index: Integer): Boolean;
begin
  Result := FSelectedLayers.Contains(Index);
end;

procedure TVectArtDocument.SetCanvasSize(AWidth, AHeight: Integer);
var
  Canvas: TVectArtCanvasLayer;
begin
  Canvas := GetCanvasLayer;
  if Canvas = nil then
    Exit;
  AWidth := Max(AWidth, 1);
  AHeight := Max(AHeight, 1);
  if (Canvas.Width = AWidth) and (Canvas.Height = AHeight) then
    Exit;
  Canvas.Width := AWidth;
  Canvas.Height := AHeight;
  Changed;
end;

procedure TVectArtDocument.SetSelectedIndex(const Value: Integer);
var
  NewValue: Integer;
begin
  NewValue := EnsureRange(Value, -1, FLayers.Count - 1);
  if (FSelectedIndex = NewValue) and
    (((NewValue < 0) and (FSelectedLayers.Count = 0)) or
     ((FSelectedLayers.Count = 1) and (FSelectedLayers[0] = NewValue))) then
    Exit;
  FSelectedLayers.Clear;
  if NewValue >= 0 then
    FSelectedLayers.Add(NewValue);
  FSelectedIndex := NewValue;
  SelectionChanged;
end;

procedure TVectArtDocument.SetSelectedLayers(const Indices: array of Integer);
begin
  SetSelectedLayersCore(Indices, True);
end;

procedure TVectArtDocument.SelectLayerRange(AnchorIndex,
  TargetIndex: Integer; Additive: Boolean);
var
  FirstIndex: Integer;
  I: Integer;
  LastIndex: Integer;
  Selection: TList<Integer>;
begin
  if FLayers.Count <= 1 then
    Exit;
  AnchorIndex := EnsureRange(AnchorIndex, 1, FLayers.Count - 1);
  TargetIndex := EnsureRange(TargetIndex, 1, FLayers.Count - 1);
  FirstIndex := Min(AnchorIndex, TargetIndex);
  LastIndex := Max(AnchorIndex, TargetIndex);
  Selection := TList<Integer>.Create;
  try
    if Additive then
      Selection.AddRange(FSelectedLayers);
    for I := FirstIndex to LastIndex do
      if not Selection.Contains(I) then
        Selection.Add(I);
    Selection.Sort;
    SetSelectedLayers(Selection.ToArray);
  finally
    Selection.Free;
  end;
end;

procedure TVectArtDocument.SetSelectedLayersCore(
  const Indices: array of Integer; Notify: Boolean);
var
  I: Integer;
  Index: Integer;
  HasSelectionChanged: Boolean;
  ValidIndices: TList<Integer>;
begin
  ValidIndices := TList<Integer>.Create;
  try
    for Index in Indices do
      if (Index > 0) and (Index < FLayers.Count) and
        not ValidIndices.Contains(Index) then
        ValidIndices.Add(Index);
    HasSelectionChanged := ValidIndices.Count <> FSelectedLayers.Count;
    if not HasSelectionChanged then
      for I := 0 to ValidIndices.Count - 1 do
        if ValidIndices[I] <> FSelectedLayers[I] then
        begin
          HasSelectionChanged := True;
          Break;
        end;
    if not HasSelectionChanged then
      Exit;
    FSelectedLayers.Clear;
    FSelectedLayers.AddRange(ValidIndices);
    if FSelectedLayers.Count > 0 then
      FSelectedIndex := FSelectedLayers[FSelectedLayers.Count - 1]
    else
      FSelectedIndex := -1;
  finally
    ValidIndices.Free;
  end;
  if Notify then
    SelectionChanged;
end;

procedure TVectArtDocument.ToggleSelectedLayer(Index: Integer);
var
  Selection: TList<Integer>;
begin
  if (Index <= 0) or (Index >= FLayers.Count) then
    Exit;
  Selection := TList<Integer>.Create;
  try
    Selection.AddRange(FSelectedLayers);
    if Selection.Contains(Index) then
      Selection.Remove(Index)
    else
      Selection.Add(Index);
    Selection.Sort;
    SetSelectedLayers(Selection.ToArray);
  finally
    Selection.Free;
  end;
end;

procedure TVectArtDocument.SetRectangleBounds(Index: Integer;
  const Value: TRectF);
var
  CurrentBounds: TRectF;
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  CurrentBounds := RectangleLayer.Bounds;
  if SameValue(CurrentBounds.Left, Value.Left) and
    SameValue(CurrentBounds.Top, Value.Top) and
    SameValue(CurrentBounds.Right, Value.Right) and
    SameValue(CurrentBounds.Bottom, Value.Bottom) then
    Exit;
  RectangleLayer.Bounds := Value;
  Changed;
end;

procedure TVectArtDocument.SetRectangleFillColor(Index: Integer;
  Value: TColor);
var
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  if RectangleLayer.FillColor = Value then
    Exit;
  RectangleLayer.FillColor := Value;
  Changed;
end;

procedure TVectArtDocument.SetRectangleRotation(Index: Integer;
  Value: Single);
var
  NewValue: Single;
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  NewValue := NormalizeAngleDegrees(Value);
  if SameValue(RectangleLayer.RotationDegrees, NewValue) then
    Exit;
  RectangleLayer.RotationDegrees := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetImagePoints(Index: Integer;
  const Points: TVectArtImagePoints);
var
  ImageLayer: TVectArtImageLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtImageLayer) then
    Exit;
  ImageLayer := TVectArtImageLayer(FLayers[Index]);
  ImageLayer.Points := Points;
  Changed;
end;

procedure TVectArtDocument.SetPathPoints(Index: Integer;
  const Points: TArray<TPointF>);
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if Length(PathLayer.Points) = Length(Points) then
  begin
    if Length(Points) = 0 then
      Exit;
    for I := 0 to High(Points) do
      if not SameValue(PathLayer.Points[I].X, Points[I].X) or
        not SameValue(PathLayer.Points[I].Y, Points[I].Y) then
        Break;
    if I > High(Points) then
      Exit;
  end;
  PathLayer.Points := Copy(Points);
  Changed;
end;

procedure TVectArtDocument.SetPathFill(Index: Integer; Color: TColor);
var
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if not PathLayer.Closed or (PathLayer.FillColor = Color) then
    Exit;
  PathLayer.FillColor := Color;
  Changed;
end;

procedure TVectArtDocument.SetPathLineCap(Index: Integer;
  Value: TVectArtLineCap);
var
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  if PathLayer.LineCap = Value then
    Exit;
  PathLayer.LineCap := Value;
  Changed;
end;

procedure TVectArtDocument.SetPathLineJoin(Index: Integer;
  Value: TVectArtLineJoin);
var
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  if PathLayer.LineJoin = Value then
    Exit;
  PathLayer.LineJoin := Value;
  Changed;
end;

procedure TVectArtDocument.SetPathMifAntiAlias(Index: Integer;
  Value: Boolean);
var
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  if PathLayer.MifAntiAlias = Value then
    Exit;
  PathLayer.MifAntiAlias := Value;
  Changed;
end;

procedure TVectArtDocument.SetPathStroke(Index: Integer; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  NewWidth: Single;
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  NewWidth := Max(Width, 0.0);
  if (PathLayer.StrokeColor = Color) and
    SameValue(PathLayer.StrokeWidth, NewWidth) and
    (PathLayer.MifStrokeStyle = Style) then
    Exit;
  PathLayer.StrokeColor := Color;
  PathLayer.StrokeWidth := NewWidth;
  PathLayer.MifStrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetLayerLocked(Index: Integer; Value: Boolean);
begin
  if (Index < 0) or (Index >= FLayers.Count) or
    (FLayers[Index].Locked = Value) then
    Exit;
  FLayers[Index].Locked := Value;
  Changed;
end;

procedure TVectArtDocument.SetLayerOpacity(Index: Integer; Value: Single);
var
  NewValue: Single;
begin
  if (Index < 0) or (Index >= FLayers.Count) then
    Exit;
  NewValue := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FLayers[Index].Opacity, NewValue) then
    Exit;
  FLayers[Index].Opacity := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetLayerVisible(Index: Integer; Value: Boolean);
begin
  if (Index < 0) or (Index >= FLayers.Count) or
    (FLayers[Index].Visible = Value) then
    Exit;
  FLayers[Index].Visible := Value;
  Changed;
end;

end.
