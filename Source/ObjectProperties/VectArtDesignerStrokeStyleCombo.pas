// 線種を文字ではなく実際の線パターンで選択する共通コンボボックス。
// 現在の線パターンとマーカー一覧はWebArt DesignerのMIF値に対応する。
unit VectArtDesignerStrokeStyleCombo;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.StdCtrls,
  VectArtDesignerDocument;

type
  // Parent未接続のFrame内でItemsへ触れるとTComboBoxがHandleを要求するため、
  // 選択肢の生成を実際のCreateWndまで遅延する。
  TVectArtMifStrokeStyleCombo = class(TComboBox)
  private
    FPendingItemIndex: Integer;
  protected
    procedure CreateWnd; override;
    procedure DrawItem(Index: Integer; Rect: TRect;
      State: TOwnerDrawState); override;
  public
    // 線種項目をウィンドウハンドル生成時に構築するコンボボックスを生成する。
    constructor Create(AOwner: TComponent); override;
    // Handle未生成時にも選択予定値を保持し、生成済みなら表示へ直ちに反映する。
    procedure SetPendingItemIndex(Value: Integer);
    property PendingItemIndex: Integer read FPendingItemIndex;
  end;

  TVectArtMifLineMarkerCombo = class(TComboBox)
  private
    FPendingMarker: TVectArtMifLineMarker;
    FPendingCommon: Boolean;
    function IndexForMarker(Value: TVectArtMifLineMarker): Integer;
    function MarkerForIndex(Index: Integer): TVectArtMifLineMarker;
  protected
    procedure CreateWnd; override;
    procedure DrawItem(Index: Integer; Rect: TRect;
      State: TOwnerDrawState); override;
  public
    // MIF互換順の線端マーカー一覧を遅延構築するコンボボックスを生成する。
    constructor Create(AOwner: TComponent); override;
    // 現在選択されたマーカーを返す。混在表示中または未選択時はvlmNoneを返す。
    function SelectedMarker: TVectArtMifLineMarker;
    // 表示予定マーカーと、複数選択で値が共通かどうかを同時に更新する。
    procedure SetPendingMarker(Value: TVectArtMifLineMarker; Common: Boolean);
    property PendingMarker: TVectArtMifLineMarker read FPendingMarker;
    property PendingCommon: Boolean read FPendingCommon;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, Vcl.Graphics,
  VectArtDesignerGeometry;

const
  COLOR_EDIT = TColor($00303030);
  COLOR_TEXT = TColor($00EEEEEE);

constructor TVectArtMifStrokeStyleCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPendingItemIndex := 0;
end;

procedure TVectArtMifStrokeStyleCombo.CreateWnd;
var
  ChangeEvent: TNotifyEvent;
begin
  inherited CreateWnd;
  ChangeEvent := OnChange;
  OnChange := nil;
  try
    Items.BeginUpdate;
    try
      Items.Clear;
      Items.Add('Solid');
      Items.Add('Dotted');
      Items.Add('Short dash');
      Items.Add('Dash-dot');
      Items.Add('Dash-dot-dot');
      Items.Add('Sparse dotted');
      Items.Add('Medium dash');
      Items.Add('Long dash-dot');
      Items.Add('Long dash');
      ItemIndex := FPendingItemIndex;
    finally
      Items.EndUpdate;
    end;
  finally
    OnChange := ChangeEvent;
  end;
end;

procedure TVectArtMifStrokeStyleCombo.DrawItem(Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  DashIndex: Integer;
  DrawSegment: Boolean;
  Intervals: TArray<Single>;
  SegmentLength: Integer;
  StyleValue: TVectArtMifStrokeStyle;
  X: Integer;
  Y: Integer;
begin
  if odSelected in State then
    Canvas.Brush.Color := TColor($00D77800)
  else
    Canvas.Brush.Color := COLOR_EDIT;
  Canvas.FillRect(Rect);
  if not InRange(Index, Ord(Low(TVectArtMifStrokeStyle)),
    Ord(High(TVectArtMifStrokeStyle))) then
    Exit;
  StyleValue := TVectArtMifStrokeStyle(Index);
  Canvas.Pen.Color := COLOR_TEXT;
  Canvas.Pen.Width := 2;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Color := COLOR_TEXT;
  Y := (Rect.Top + Rect.Bottom) div 2;
  X := Rect.Left + 5;
  Intervals := VectArtStrokeDashIntervals(StyleValue, 2.0);
  if Length(Intervals) = 0 then
  begin
    Canvas.MoveTo(X, Y);
    Canvas.LineTo(Rect.Right - 5, Y);
    Exit;
  end;
  DashIndex := 0;
  DrawSegment := True;
  while X < Rect.Right - 5 do
  begin
    SegmentLength := Max(Round(Intervals[DashIndex]), 1);
    if DrawSegment then
      if VectArtStrokeUsesRoundCaps(StyleValue) and
        (SegmentLength <= 2) then
        Canvas.Ellipse(X - 1, Y - 1, X + 2, Y + 2)
      else
      begin
        Canvas.MoveTo(X, Y);
        Canvas.LineTo(Min(X + SegmentLength, Rect.Right - 5), Y);
      end;
    Inc(X, SegmentLength);
    DashIndex := (DashIndex + 1) mod Length(Intervals);
    DrawSegment := not DrawSegment;
  end;
end;

procedure TVectArtMifStrokeStyleCombo.SetPendingItemIndex(Value: Integer);
begin
  FPendingItemIndex := Value;
  if HandleAllocated then
    ItemIndex := Value;
end;

{ TVectArtMifLineMarkerCombo }

constructor TVectArtMifLineMarkerCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPendingMarker := vlmNone;
  FPendingCommon := True;
end;

function TVectArtMifLineMarkerCombo.IndexForMarker(
  Value: TVectArtMifLineMarker): Integer;
begin
  case Value of
    vlmNone: Result := 0;
    vlmOpenArrow: Result := 1;
    vlmArrow: Result := 2;
    vlmWideArrow: Result := 3;
    vlmCircle: Result := 4;
    vlmDiamond: Result := 5;
    vlmConcaveArrow: Result := 6;
    vlmSmallArrow: Result := 7;
    vlmSlash: Result := 8;
    vlmStar: Result := 9;
  else
    Result := 0;
  end;
end;

function TVectArtMifLineMarkerCombo.MarkerForIndex(
  Index: Integer): TVectArtMifLineMarker;
begin
  case Index of
    1: Result := vlmOpenArrow;
    2: Result := vlmArrow;
    3: Result := vlmWideArrow;
    4: Result := vlmCircle;
    5: Result := vlmDiamond;
    6: Result := vlmConcaveArrow;
    7: Result := vlmSmallArrow;
    8: Result := vlmSlash;
    9: Result := vlmStar;
  else
    Result := vlmNone;
  end;
end;

procedure TVectArtMifLineMarkerCombo.CreateWnd;
var
  ChangeEvent: TNotifyEvent;
  I: Integer;
begin
  inherited CreateWnd;
  ChangeEvent := OnChange;
  OnChange := nil;
  try
    Items.BeginUpdate;
    try
      Items.Clear;
      for I := 0 to 9 do Items.Add(IntToStr(I));
      if FPendingCommon then ItemIndex := IndexForMarker(FPendingMarker)
      else ItemIndex := -1;
    finally
      Items.EndUpdate;
    end;
  finally
    OnChange := ChangeEvent;
  end;
end;

procedure TVectArtMifLineMarkerCombo.DrawItem(Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  Geometry: TVectArtMarkerGeometry;
  I: Integer;
  Marker: TVectArtMifLineMarker;
  Points: TArray<TPoint>;
  Y: Integer;
begin
  if odSelected in State then Canvas.Brush.Color := TColor($00D77800)
  else Canvas.Brush.Color := COLOR_EDIT;
  Canvas.FillRect(Rect);
  if not InRange(Index, 0, 9) then Exit;
  Marker := MarkerForIndex(Index);
  Y := (Rect.Top + Rect.Bottom) div 2;
  Canvas.Pen.Color := COLOR_TEXT;
  Canvas.Pen.Width := 1;
  Canvas.MoveTo(Rect.Left + 8, Y);
  Canvas.LineTo(Rect.Right - 8, Y);
  Geometry := BuildMifLineMarkerGeometry(Ord(Marker),
    TPointF.Create(Rect.Right - 8, Y), TPointF.Create(Rect.Left + 8, Y),
    1.5, 6.0);
  SetLength(Points, Length(Geometry.PrimaryPoints));
  for I := 0 to High(Points) do
    Points[I] := Point(Round(Geometry.PrimaryPoints[I].X),
      Round(Geometry.PrimaryPoints[I].Y));
  if Length(Points) < 2 then Exit;
  Canvas.Pen.Width := 2;
  if Geometry.Filled then
  begin
    Canvas.Brush.Color := COLOR_TEXT;
    Canvas.Polygon(Points);
  end
  else
    Canvas.Polyline(Points);
end;

function TVectArtMifLineMarkerCombo.SelectedMarker: TVectArtMifLineMarker;
begin
  Result := MarkerForIndex(ItemIndex);
end;

procedure TVectArtMifLineMarkerCombo.SetPendingMarker(
  Value: TVectArtMifLineMarker; Common: Boolean);
begin
  FPendingMarker := Value;
  FPendingCommon := Common;
  if HandleAllocated then
    if Common then ItemIndex := IndexForMarker(Value)
    else ItemIndex := -1;
end;

end.
