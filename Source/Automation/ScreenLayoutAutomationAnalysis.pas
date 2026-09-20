// 通常レンダラーのアルファから効果込み範囲を測り、余白・保護矩形との関係を報告する。
unit ScreenLayoutAutomationAnalysis;

interface

uses System.JSON, ScreenLayoutDocument;

// 文書直下のレイヤーを個別描画する。グループは子孫と親フィルターを合成した1対象。
// 検査は有限領域・有限解像度の標本であり、正確なベクター境界や被写体検出ではない。
function AnalyzeAutomationLayout(Document: TVectArtDocument; Request: TJSONObject): TJSONObject;

implementation

uses System.SysUtils, System.Types, System.Math, System.Generics.Collections, ScreenLayoutRenderer,
  ScreenLayoutAutomationArguments;

function ContainsRect(const Outer, Inner: TRectF): Boolean;
begin
  Result := (Inner.Left >= Outer.Left) and (Inner.Top >= Outer.Top) and
    (Inner.Right <= Outer.Right) and (Inner.Bottom <= Outer.Bottom);
end;

function IntersectsRect(const A, B: TRectF): Boolean;
begin
  Result := (A.Left < B.Right) and (A.Right > B.Left) and
    (A.Top < B.Bottom) and (A.Bottom > B.Top);
end;

function ScanBounds(Buffer: TVectArtRenderBuffer; const View: TRectF;
  Threshold: Integer; out Bounds: TRectF; out TouchesEdge: Boolean): Boolean;
var
  Pixel: PVectArtRgbaPixel;
  X, Y, Left, Top, Right, Bottom: Integer;
begin
  Left := Buffer.Width;
  Top := Buffer.Height;
  Right := -1;
  Bottom := -1;
  Pixel := Buffer.Data;
  for Y := 0 to Buffer.Height - 1 do
    for X := 0 to Buffer.Width - 1 do
    begin
      if Pixel.A >= Threshold then
      begin
        Left := Min(Left, X);
        Top := Min(Top, Y);
        Right := Max(Right, X);
        Bottom := Max(Bottom, Y);
      end;
      Inc(Pixel);
    end;
  Result := Right >= 0;
  TouchesEdge := Result and ((Left = 0) or (Top = 0) or
    (Right = Buffer.Width - 1) or (Bottom = Buffer.Height - 1));
  Bounds := TRectF.Empty;
  if Result then
    Bounds := TRectF.Create(View.Left + Left * View.Width / Buffer.Width,
      View.Top + Top * View.Height / Buffer.Height,
      View.Left + (Right + 1) * View.Width / Buffer.Width,
      View.Top + (Bottom + 1) * View.Height / Buffer.Height);
end;

function AnalyzeAutomationLayout(Document: TVectArtDocument; Request: TJSONObject): TJSONObject;
var
  CanvasBounds, View, Safe, Bounds: TRectF;
  Regions: TArray<TRectF>;
  Indices: TArray<Integer>;
  RegionValues, Paths, Entries, Hits: TJSONArray;
  Entry: TJSONObject;
  Value: TJSONValue;
  Layer: TVectArtLayer;
  Buffer: TVectArtRenderBuffer;
  Visible, Locked, Found, Touches: Boolean;
  Margin, Padding, Scale, N: Double;
  W, H, Edge, Threshold, I, J, K: Integer;
  Path: string;
begin
  N := AutomationNumber(Request, 'max_edge', 1280, 64, 2048);
  if N <> Trunc(N) then raise EArgumentException.Create('max_edge must be an integer.');
  Edge := Trunc(N);
  N := AutomationNumber(Request, 'alpha_threshold', 1, 1, 255);
  if N <> Trunc(N) then raise EArgumentException.Create('alpha_threshold must be an integer.');
  Threshold := Trunc(N);
  Margin := AutomationNumber(Request, 'safe_margin', 0, 0, 10000);
  Padding := AutomationNumber(Request, 'analysis_padding', 128, 0, 4096);
  CanvasBounds := TRectF.Create(-Document.CanvasLayer.Width / 2, -Document.CanvasLayer.Height / 2,
    Document.CanvasLayer.Width / 2, Document.CanvasLayer.Height / 2);
  Safe := CanvasBounds;
  Safe.Inflate(-Margin, -Margin);
  if (Safe.Width <= 0) or (Safe.Height <= 0) then
    raise EArgumentException.Create('safe_margin consumes the canvas.');
  View := CanvasBounds;
  View.Inflate(Padding, Padding);
  Scale := Min(1.0, Edge / Max(View.Width, View.Height));
  W := Max(1, Round(View.Width * Scale));
  H := Max(1, Round(View.Height * Scale));
  Value := Request.GetValue('protected_regions');
  if Value <> nil then
  begin
    if not (Value is TJSONArray) then
      raise EArgumentException.Create('protected_regions must be an array of rectangles.');
    RegionValues := TJSONArray(Value);
    if RegionValues.Count > 32 then
      raise EArgumentException.Create('At most 32 protected_regions are supported.');
    SetLength(Regions, RegionValues.Count);
    for I := 0 to High(Regions) do Regions[I] := AutomationRect(RegionValues[I]);
  end;
  Value := Request.GetValue('layer_paths');
  if Value = nil then
  begin
    if Document.LayerCount > 33 then
      raise EArgumentException.Create('Specify at most 32 top-level layer_paths per analysis.');
    SetLength(Indices, Document.LayerCount - 1);
    for I := 0 to High(Indices) do Indices[I] := I + 1;
  end
  else
  begin
    if not (Value is TJSONArray) then
      raise EArgumentException.Create('layer_paths must be an array.');
    Paths := TJSONArray(Value);
    if Paths.Count > 32 then raise EArgumentException.Create('At most 32 layer_paths are supported.');
    SetLength(Indices, Paths.Count);
    for I := 0 to Paths.Count - 1 do
    begin
      if not (Paths[I] is TJSONString) then
        raise EArgumentException.Create('Each layer_path must be a string.');
      Path := Paths[I].Value;
      Layer := AutomationLayer(Document, Path, Visible, Locked);
      if Length(Path.Split(['/'])) <> 3 then
        raise EArgumentException.Create('Analyze the top-level parent to include group effects.');
      Indices[I] := -1;
      for J := 1 to Document.LayerCount - 1 do
        if Document[J] = Layer then Indices[I] := J;
      for J := 0 to I - 1 do
        if Indices[J] = Indices[I] then
          raise EArgumentException.Create('Duplicate layer_path.');
    end;
  end;
  Buffer := TVectArtRenderBuffer.Create;
  Result := TJSONObject.Create;
  try
    try
      Result.AddPair('bounds_kind', 'sampled_alpha_bounds');
      Result.AddPair('effects_included', TJSONBool.Create(True));
      Result.AddPair('overlap_kind', 'conservative_bounds_intersection');
      Result.AddPair('occlusion_by_other_layers_included', TJSONBool.Create(False));
      Result.AddPair('analysis_bounds', AutomationRectJson(View));
      Result.AddPair('safe_bounds', AutomationRectJson(Safe));
      Result.AddPair('pixel_width', TJSONNumber.Create(W));
      Result.AddPair('pixel_height', TJSONNumber.Create(H));
      Result.AddPair('document_x_per_pixel', TJSONNumber.Create(View.Width / W));
      Result.AddPair('document_y_per_pixel', TJSONNumber.Create(View.Height / H));
      Result.AddPair('alpha_threshold', TJSONNumber.Create(Threshold));
      Entries := TJSONArray.Create;
      Result.AddPair('layers', Entries);
      for I := 0 to High(Indices) do
      begin
        K := Indices[I];
        Layer := Document[K];
        RenderVectArtLayerRegion(Layer, Buffer, W, H, View);
        Found := ScanBounds(Buffer, View, Threshold, Bounds, Touches);
        Entry := TJSONObject.Create;
        Entries.AddElement(Entry);
        Entry.AddPair('layer_path', '/layers/' + IntToStr(K - 1));
        Entry.AddPair('name', Layer.Name);
        Entry.AddPair('has_sampled_pixels', TJSONBool.Create(Found));
        Entry.AddPair('touches_analysis_edge', TJSONBool.Create(Touches));
        Hits := TJSONArray.Create;
        Entry.AddPair('protected_region_indices', Hits);
        if Found then
        begin
          Entry.AddPair('bounds', AutomationRectJson(Bounds));
          Entry.AddPair('outside_canvas', TJSONBool.Create(not ContainsRect(CanvasBounds, Bounds)));
          Entry.AddPair('outside_safe_area', TJSONBool.Create(not ContainsRect(Safe, Bounds)));
          for J := 0 to High(Regions) do
            if IntersectsRect(Bounds, Regions[J]) then Hits.Add(J);
        end
        else
        begin
          Entry.AddPair('bounds', TJSONNull.Create);
          // 透明と検査領域外を区別できないので安全と断定しない。
          Entry.AddPair('outside_canvas', TJSONNull.Create);
          Entry.AddPair('outside_safe_area', TJSONNull.Create);
        end;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Buffer.Free;
  end;
end;

end.
