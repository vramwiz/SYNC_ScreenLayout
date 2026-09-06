// 内蔵6種の周期描画、保存の事前検証、複製の独立性、倍率とグループの一致を確認する。
program ScreenLayoutPatternTest;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Types, System.Math, System.Skia, System.UITypes, System.JSON,
  Vcl.Graphics, ScreenLayoutDocument, ScreenLayoutDocumentJson, ScreenLayoutPatternJson,
  ScreenLayoutPatternStyle, ScreenLayoutPaintStyles, ScreenLayoutPatternRenderer,
  ScreenLayoutRenderer, ScreenLayoutGroupCommands, TextRendererSkiaRuntime;

procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;

procedure Reject(Json: TJSONObject; const Text: string);
var Rejected: Boolean;
begin
  Rejected := False;
  try
    try ReadScreenLayoutPattern(Json); except on E: EConvertError do Rejected := True; end;
    Check(Rejected, Text);
  finally
    Json.Free;
  end;
end;

procedure Run;
var
  Doc, Loaded: TVectArtDocument;
  Layer: TVectArtRectangleLayer;
  Group: TScreenLayoutGroupLayer;
  Clone: TVectArtLayer;
  Buffer, Other: TVectArtRenderBuffer;
  Kind: TScreenLayoutPatternKind;
  Pattern, OldPattern, Restored: TScreenLayoutPatternStyle;
  Slot: TScreenLayoutPatternColor;
  Values: TArray<TScreenLayoutPatternValue>;
  Colors: TArray<TScreenLayoutPatternColor>;
  Style: TScreenLayoutPaintStyle;
  Json, Params: TJSONObject;
  Saved, Before, ErrorText: string;
  Count, Transparent, X, Y, I: Integer;
  Image: ISkImage;
  Size: TSizeF;
  Scope: IInterface;
  Sheet: ISkSurface;
  Paint: ISkPaint;
  P: TScreenLayoutPatternParameter;
begin
  Doc := TVectArtDocument.Create;
  Loaded := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  Other := TVectArtRenderBuffer.Create;
  try
    Sheet := TSkSurface.MakeRaster(600, 400);
    Sheet.Canvas.Clear(TAlphaColorRec.White);
    Paint := TSkPaint.Create;
    Doc.SetCanvasSize(200, 200);
    Layer := TVectArtRectangleLayer.Create('Pattern', TRectF.Create(-100, -100, 100, 100), clBlack);
    Doc.InsertLayer(1, Layer);
    for Kind := Low(Kind) to High(Kind) do
    begin
      Pattern := TScreenLayoutPatternStyle.Create(Kind, clBlue);
      OldPattern := Pattern;
      Values := Pattern.Values;
      Values[0].Value := 17;
      Colors := Pattern.Colors;
      Colors[0].Opacity := 0;
      Check(Pattern.SameAs(OldPattern), 'array getters alias the model');
      Pattern.SetNumber('angle', 13);
      Check(OldPattern.Number('angle') <> 13, 'parameter setter changed snapshot');
      Slot := Pattern.Slot('foreground');
      Slot.Opacity := 0.7;
      Pattern.SetSlot(Slot);
      Check(OldPattern.Slot('foreground').Opacity = 1, 'color setter changed snapshot');
      Json := WriteScreenLayoutPattern(Pattern);
      try Restored := ReadScreenLayoutPattern(Json); finally Json.Free; end;
      Check(Pattern.SameAs(Restored), 'pattern JSON lost values');
      Style := TScreenLayoutPaintStyle.Solid(clBlack);
      Style.Kind := slpkPattern;
      Style.Pattern := Pattern;
      Layer.PaintStyle := Style;
      RenderVectArtDocument(Doc, Buffer, 200, 200);
      Count := 0;
      Transparent := 0;
      for I := 0 to Buffer.PixelCount - 1 do
      begin
        if Buffer.Pixels[I].A > 50 then Inc(Count);
        if Buffer.Pixels[I].A = 0 then Inc(Transparent);
      end;
      Check((Count > 100) and (Transparent > 100), 'empty or fully covered default ' + PATTERN_IDS[Kind]);
      Saved := SerializeVectArtDocument(Doc);
      Check((Pos('"data"', Saved) = 0) and (Pos('"patternId"', Saved) > 0), 'pattern saved image data');
      Check(TryDeserializeVectArtDocument(Saved, Loaded, ErrorText), ErrorText);
      RenderVectArtDocument(Loaded, Other, 200, 200);
      Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * 4), 'round-trip pixel difference');
      Clone := CloneScreenLayoutLayer(Layer, 'Copy');
      try
        Check(Clone.PaintStyle.Pattern.SameAs(Pattern), 'clone lost pattern');
        Pattern.SetNumber('angle', 0);
        Style.Pattern := Pattern;
        Clone.PaintStyle := Style;
        Check(Layer.PaintStyle.Pattern.Number('angle') = 13, 'clone changed source');
      finally Clone.Free; end;
      Layer.PaintStyle := Style;
      // 既定の模様を3列2行へ出力し、目視確認用に保存する。
      X := (Ord(Kind) mod 3) * 200;
      Y := (Ord(Kind) div 3) * 200;
      Sheet.Canvas.Save;
      Sheet.Canvas.Translate(X, Y);
      ApplyScreenLayoutPattern(Paint, Pattern, TRectF.Create(0, 0, 200, 200), 0, 1);
      Sheet.Canvas.DrawRect(TRectF.Create(0, 0, 200, 200), Paint);
      Sheet.Canvas.Restore;
      Image := MakeScreenLayoutPatternTile(Pattern, 0.25, Size);
      I := Image.Width;
      Image := MakeScreenLayoutPatternTile(Pattern, 4, Size);
      Check(Image.Width > I, 'resolution does not follow zoom');
      Scope := BeginScreenLayoutPatternRender(1);
      ApplyScreenLayoutPattern(Paint, Pattern, TRectF.Create(0, 0, 200, 200), 0, 1);
      Scope := nil;
      // スコープ終了後もPaintのシェーダーが画像を安全に保持できることを確認する。
      Sheet.Canvas.DrawRect(TRectF.Create(0, 0, 1, 1), Paint);
      for P in ScreenLayoutPatternParameters(Kind) do
      begin
        Restored := Pattern;
        Restored.SetNumber(P.Id, P.Minimum);
        Image := MakeScreenLayoutPatternTile(Restored, 1, Size);
        Check(Image <> nil, 'minimum parameter render failed');
        Restored.SetNumber(P.Id, P.Maximum);
        Image := MakeScreenLayoutPatternTile(Restored, 1, Size);
        Check((Image.Width <= 1024) and (Image.Height <= 1024), 'tile budget exceeded');
      end;
    end;
    Sheet.MakeImageSnapshot.EncodeToFile(ExtractFilePath(ParamStr(0)) + 'patterns.png');
    Pattern := TScreenLayoutPatternStyle.Create(slptChecker, clRed);
    Pattern.SetNumber('size', 16);
    Style.Pattern := Pattern;
    Layer.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    Check((Buffer.Pixels[101*200+101].R = 255) and (Buffer.Pixels[101*200+117].A = 0),
      'checker cell size or transparency incorrect');
    RenderVectArtDocument(Doc, Other, 400, 400);
    Check((Other.Pixels[203*400+203].R = 255) and (Other.Pixels[203*400+235].A = 0),
      'logical pattern size changed at double zoom');
    Slot := Pattern.Slot('background');
    Slot.Color := clBlue;
    Slot.Opacity := 0.5;
    Pattern.SetSlot(Slot);
    Style.Pattern := Pattern;
    Layer.PaintStyle := Style;
    Layer.Opacity := 0.5;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    Check(Abs(Buffer.Pixels[101*200+117].A - 64) <= 1, 'slot and layer alpha not multiplied');
    Doc.ExtractLayer(1);
    Group := TScreenLayoutGroupLayer.Create('Group');
    Group.AddChild(Layer);
    Doc.InsertLayer(1, Group);
    RenderVectArtDocument(Doc, Other, 200, 200);
    Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * 4), 'group changed pattern pixels');
    RenderVectArtLayerThumbnail(Group, Buffer, 160, 160);
    RenderVectArtLayerThumbnail(Layer, Other, 160, 160);
    Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * 4), 'group thumbnail mismatch');
    Before := SerializeVectArtDocument(Loaded);
    Saved := StringReplace(Before, '"patternId":"honeycomb"', '"patternId":"unknown"', []);
    Check(Saved <> Before, 'invalid fixture replacement failed');
    Check(not TryDeserializeVectArtDocument(Saved, Loaded, ErrorText), 'unknown ID accepted');
    Check(SerializeVectArtDocument(Loaded) = Before, 'bad pattern destroyed document');
    Json := WriteScreenLayoutPattern(Pattern);
    Params := TJSONObject(Json.GetValue('parameters'));
    Params.AddPair('size', TJSONNumber.Create(16));
    Reject(Json, 'duplicate parameter accepted');
    Json := WriteScreenLayoutPattern(Pattern);
    Params := TJSONObject(Json.GetValue('parameters'));
    Params.RemovePair('size').Free;
    Reject(Json, 'missing parameter accepted');
    Json := WriteScreenLayoutPattern(Pattern);
    Params := TJSONObject(Json.GetValue('parameters'));
    Params.RemovePair('size').Free;
    Params.AddPair('size', TJSONNumber.Create(0));
    Reject(Json, 'zero cell size accepted');
    Json := WriteScreenLayoutPattern(Pattern);
    TJSONObject(Json.GetValue('colors')).AddPair('foreground', TJSONObject.Create);
    Reject(Json, 'duplicate color accepted');
    Json := WriteScreenLayoutPattern(Pattern);
    Json.AddPair('patternId', 'dots');
    Reject(Json, 'duplicate definition accepted');
    Json := WriteScreenLayoutPattern(Pattern);
    Params := TJSONObject(Json.GetValue('parameters'));
    Params.RemovePair('size').Free;
    Params.AddPair('size', 'large');
    Reject(Json, 'string parameter accepted');
    Json := WriteScreenLayoutPattern(Pattern);
    Params := TJSONObject(Json.GetValue('parameters'));
    Params.RemovePair('size').Free;
    Params.AddPair('unknown', TJSONNumber.Create(16));
    Reject(Json, 'unknown parameter ID accepted');
    Json := WriteScreenLayoutPattern(Pattern);
    Params := TJSONObject(TJSONObject(Json.GetValue('colors')).GetValue('background'));
    Params.RemovePair('opacity').Free;
    Params.AddPair('opacity', TJSONNumber.Create(2));
    Reject(Json, 'out of range opacity accepted');
    Saved := StringReplace(Before, '"angle":13', '"angle":1e999', []);
    Check(Saved <> Before, 'infinite angle fixture replacement failed');
    Check(not TryDeserializeVectArtDocument(Saved, Loaded, ErrorText), 'infinite angle accepted');
    Check(SerializeVectArtDocument(Loaded) = Before, 'infinite angle replaced document');
  finally
    Other.Free;
    Buffer.Free;
    Loaded.Free;
    Doc.Free;
  end;
end;

begin
  try
    TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try Run; finally TTextRendererSkiaRuntime.Release; end;
    Writeln('PASS pattern definitions, rendering, JSON, clone, scale, group and bounds');
  except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); ExitCode := 1; end; end;
end.
