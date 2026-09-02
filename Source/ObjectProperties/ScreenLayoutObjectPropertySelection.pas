// Object Propertiesが扱う現在選択を、属性別の編集対象へ分類する。
unit ScreenLayoutObjectPropertySelection;

interface

uses
  Vcl.Graphics, ScreenLayoutContext, ScreenLayoutDocument,
  ScreenLayoutObjectPropertyCommands;

// 塗り色または線色を持つ選択レイヤーだけを、現在の編集階層を保って返す。
function ScreenLayoutSelectedColorLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
// 不透明度を変更できる全選択レイヤーを、トップレベルとグループ内の双方から返す。
function ScreenLayoutSelectedOpacityLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
// 線幅、線種、線端を持つ選択レイヤーだけを返す。
function ScreenLayoutSelectedLineLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
// Layerの主要色と、ピッカーが塗り・線のどちらを変更すべきかを返す。
function TryGetScreenLayoutLayerColor(Layer: TVectArtLayer;
  out Value: TColor; out Target: TScreenLayoutLayerColorTarget): Boolean;
// 線編集GUIへ表示する共通属性を読み、線端を持たない閉じた線も区別する。
function TryReadScreenLayoutLineLayer(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap; out HasLineCap: Boolean): Boolean;
// 旧属性領域に残した円弧角度UIが現在選択に必要かを返す。
function ScreenLayoutSelectionNeedsArcProperties(
  const Context: IVectArtDesignerContext): Boolean;

implementation

uses
  System.Generics.Collections;

function SelectedLayers(const Context: IVectArtDesignerContext):
  TArray<TVectArtLayer>;
var
  Count: Integer;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
begin
  SetLength(Result, 0);
  if (Context = nil) or (Context.Document = nil) then
    Exit;
  Count := 0;
  // 子選択リストは編集終了直後の通知中にも残り得るため、開いているGroupも確認する。
  if (Context.EditorState <> nil) and
    (Context.EditorState.OpenGroup <> nil) and
    (Context.EditorState.OpenGroupChildCount > 0) then
  begin
    Result := Context.EditorState.GetOpenGroupChildren;
    for Layer in Result do
      if Layer <> nil then
        Inc(Count);
    if Count <> Length(Result) then
    begin
      SetLength(Result, Count);
      Count := 0;
      for Layer in Context.EditorState.GetOpenGroupChildren do
        if Layer <> nil then
        begin
          Result[Count] := Layer;
          Inc(Count);
        end;
    end;
    Exit;
  end;

  Indices := Context.Document.GetSelectedLayerIndices;
  SetLength(Result, Length(Indices));
  for I := 0 to High(Indices) do
    if (Indices[I] > 0) and (Indices[I] < Context.Document.LayerCount) then
    begin
      Result[Count] := Context.Document[Indices[I]];
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

function ScreenLayoutSelectedColorLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
var
  Layer: TVectArtLayer;
  Layers: TList<TVectArtLayer>;
  Target: TScreenLayoutLayerColorTarget;
  Value: TColor;
begin
  Layers := TList<TVectArtLayer>.Create;
  try
    for Layer in SelectedLayers(Context) do
      if TryGetScreenLayoutLayerColor(Layer, Value, Target) then
        Layers.Add(Layer);
    Result := Layers.ToArray;
  finally
    Layers.Free;
  end;
end;

function ScreenLayoutSelectedOpacityLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
begin
  Result := SelectedLayers(Context);
end;

function ScreenLayoutSelectedLineLayers(
  const Context: IVectArtDesignerContext): TArray<TVectArtLayer>;
var
  HasLineCap: Boolean;
  Layer: TVectArtLayer;
  Layers: TList<TVectArtLayer>;
  LineCap: TVectArtLineCap;
  Color: TColor;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  Layers := TList<TVectArtLayer>.Create;
  try
    for Layer in SelectedLayers(Context) do
      if TryReadScreenLayoutLineLayer(Layer, Color, Width, Style, LineCap,
        HasLineCap) then
        Layers.Add(Layer);
    Result := Layers.ToArray;
  finally
    Layers.Free;
  end;
end;

function TryGetScreenLayoutLayerColor(Layer: TVectArtLayer;
  out Value: TColor; out Target: TScreenLayoutLayerColorTarget): Boolean;
begin
  Result := True;
  if Layer is TVectArtRectangleLayer then
  begin
    Target := slctFill;
    Value := TVectArtRectangleLayer(Layer).FillColor;
  end
  else if Layer is TScreenLayoutShapeLayer then
  begin
    Target := slctFill;
    Value := TScreenLayoutShapeLayer(Layer).FillColor;
  end
  else
  begin
    Target := slctStroke;
    if Layer is TScreenLayoutRectangleLineLayer then
      Value := TScreenLayoutRectangleLineLayer(Layer).StrokeColor
    else if Layer is TScreenLayoutArcLayer then
      Value := TScreenLayoutArcLayer(Layer).StrokeColor
    else if Layer is TVectArtPathLayer then
      Value := TVectArtPathLayer(Layer).StrokeColor
    else
      Result := False;
  end;
end;

function TryReadScreenLayoutLineLayer(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap; out HasLineCap: Boolean): Boolean;
begin
  Result := True;
  HasLineCap := False;
  LineCap := vlcSquare;
  if Layer is TScreenLayoutRectangleLineLayer then
  begin
    Color := TScreenLayoutRectangleLineLayer(Layer).StrokeColor;
    Width := TScreenLayoutRectangleLineLayer(Layer).StrokeWidth;
    Style := TScreenLayoutRectangleLineLayer(Layer).StrokeStyle;
  end
  else if Layer is TScreenLayoutArcLayer then
  begin
    Color := TScreenLayoutArcLayer(Layer).StrokeColor;
    Width := TScreenLayoutArcLayer(Layer).StrokeWidth;
    Style := TScreenLayoutArcLayer(Layer).StrokeStyle;
    LineCap := TScreenLayoutArcLayer(Layer).LineCap;
    HasLineCap := True;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Color := TVectArtPathLayer(Layer).StrokeColor;
    Width := TVectArtPathLayer(Layer).StrokeWidth;
    Style := TVectArtPathLayer(Layer).MifStrokeStyle;
    LineCap := TVectArtPathLayer(Layer).LineCap;
    HasLineCap := not TVectArtPathLayer(Layer).Closed;
  end
  else
    Result := False;
end;

function ScreenLayoutSelectionNeedsArcProperties(
  const Context: IVectArtDesignerContext): Boolean;
var
  Layer: TVectArtLayer;
begin
  Result := False;
  if (Context = nil) or (Context.Document = nil) then
    Exit;
  Layer := nil;
  if (Context.EditorState <> nil) and
    (Context.EditorState.OpenGroupChildCount = 1) then
    Layer := Context.EditorState.OpenGroupChild
  else if Context.Document.SelectionCount = 1 then
    Layer := Context.Document[Context.Document.SelectedIndex];
  Result := (Layer is TScreenLayoutArcLayer) or
    (Layer is TScreenLayoutEllipseArcShapeLayer);
end;

end.
