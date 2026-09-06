// グラデーション種別、点別不透明度、JSON往復と共通描画の契約を検証する。
program ScreenLayoutGradientExtensionTest;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Math, System.Types, Vcl.Graphics,
  ScreenLayoutDocument, ScreenLayoutDocumentJson, ScreenLayoutPaintStyles, ScreenLayoutGroupCommands,
  ScreenLayoutRenderer, TextRendererSkiaRuntime;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Doc, Loaded: TVectArtDocument;
  Buffer, Other: TVectArtRenderBuffer;
  Layer: TVectArtRectangleLayer;
  Path: TVectArtPathLayer;
  Clone: TVectArtLayer;
  Group, Inner: TScreenLayoutGroupLayer;
  Vertices: TArray<TScreenLayoutVertex>;
  Style, CopyStyle: TScreenLayoutPaintStyle;
  Kind: TScreenLayoutGradientKind;
  StopId, I: Integer;
  Opacity: Single;
  Text, ErrorText, BeforeText: string;
  A, B: TVectArtRgbaPixel;
begin
  Doc := TVectArtDocument.Create;
  Loaded := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  Other := TVectArtRenderBuffer.Create;
  try
    Doc.SetCanvasSize(200, 200);
    Layer := TVectArtRectangleLayer.Create('Gradient', TRectF.Create(-80, -80, 80, 80), clRed);
    Doc.InsertLayer(1, Layer);
    Style := TScreenLayoutPaintStyle.Solid(clRed);
    Style.PrepareLinearGradient(clRed);
    Style.Kind := slpkGradient;
    Style.GradientEndColor := clBlue;
    Style.LinearStart := TPointF.Create(0.5, 0.5);
    Style.LinearEnd := TPointF.Create(0.875, 0.5);
    Style.SetGradientStopOpacity(SCREEN_LAYOUT_GRADIENT_START_STOP_ID, 0.2);
    Style.SetGradientStopOpacity(SCREEN_LAYOUT_GRADIENT_END_STOP_ID, 0.8);
    StopId := Style.AddGradientStop(0.5);
    Check(Style.GetGradientStopOpacity(StopId, Opacity) and SameValue(Opacity, 0.5, 0.001),
      'new stop changed the alpha ramp');
    CopyStyle := Style;
    Style.SetGradientStopOpacity(StopId, 0.3);
    Check(CopyStyle.GetGradientStopOpacity(StopId, Opacity) and SameValue(Opacity, 0.5, 0.001),
      'stop alpha mutated an Undo snapshot');
    Check(not CopyStyle.SameAs(Style), 'alpha missing from equality');
    Style.RemoveGradientStop(StopId);
    for Kind := Low(TScreenLayoutGradientKind) to High(TScreenLayoutGradientKind) do
    begin
      Style.GradientKind := Kind;
      Style.GradientAspect := 0.7;
      Layer.PaintStyle := Style;
      Text := SerializeVectArtDocument(Doc);
      Check(TryDeserializeVectArtDocument(Text, Loaded, ErrorText), 'JSON: ' + ErrorText);
      CopyStyle := Loaded[1].PaintStyle;
      Check((CopyStyle.GradientKind = Kind) and
        SameValue(CopyStyle.GradientStartOpacity, 0.2, 0.001) and
        SameValue(CopyStyle.GradientEndOpacity, 0.8, 0.001) and
        SameValue(CopyStyle.GradientAspect, 0.7, 0.001), 'JSON lost gradient parameters');
      RenderVectArtDocument(Doc, Buffer, 200, 200);
      RenderVectArtDocument(Loaded, Other, 200, 200);
      Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * SizeOf(TVectArtRgbaPixel)),
        'JSON changed rendered pixels');
      A := Buffer.Pixels[100 * 200 + 102];
      if Kind = slgkSweep then
        B := Buffer.Pixels[60 * 200 + 100]
      else
        B := Buffer.Pixels[100 * 200 + 157];
      Check((A.A < B.A) and (A.R > A.B) and (B.B > B.R),
        Format('gradient %d has wrong distribution A=%d,%d,%d B=%d,%d,%d',
        [Ord(Kind), A.R, A.B, A.A, B.R, B.B, B.A]));
    end;
    BeforeText := SerializeVectArtDocument(Loaded);
    Text := StringReplace(BeforeText, 'acrossStrokeGradient', 'unsupportedGradient', [rfReplaceAll]);
    Check(not TryDeserializeVectArtDocument(Text, Loaded, ErrorText), 'unknown gradient was accepted');
    Check(SerializeVectArtDocument(Loaded) = BeforeText, 'invalid paint destroyed existing document');
    Layer.PaintStyle := TScreenLayoutPaintStyle.Solid(clRed);
    Check(TryDeserializeVectArtDocument(SerializeVectArtDocument(Doc), Loaded, ErrorText), ErrorText);
    CopyStyle := Loaded[1].PaintStyle;
    CopyStyle.PrepareLinearGradient(clRed);
    Check(SameValue(CopyStyle.GradientStartOpacity, 1.0) and
      SameValue(CopyStyle.GradientEndOpacity, 1.0) and SameValue(CopyStyle.GradientAspect, 1.0),
      'loaded solid became an invisible gradient');
    // グループの再帰描画とサムネイルが同一の塗りを使うことを確認する。
    Style.GradientKind := slgkRectangle;
    Layer.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    Doc.ExtractLayer(1);
    Inner := TScreenLayoutGroupLayer.Create('Inner');
    Inner.AddChild(Layer);
    Group := TScreenLayoutGroupLayer.Create('Outer');
    Group.AddChild(Inner);
    Doc.InsertLayer(1, Group);
    RenderVectArtDocument(Doc, Other, 200, 200);
    Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * SizeOf(TVectArtRgbaPixel)),
      'nested grouping changed gradient rendering');
    RenderVectArtLayerThumbnail(Layer, Buffer, 96, 96);
    RenderVectArtLayerThumbnail(Group, Other, 96, 96);
    Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * SizeOf(TVectArtRgbaPixel)),
      'nested thumbnail gradient differs');
    Clone := CloneScreenLayoutLayer(Layer, 'Copy');
    try
      Check(Clone.PaintStyle.SameAs(Layer.PaintStyle), 'clone lost gradient properties');
      CopyStyle := Clone.PaintStyle;
      CopyStyle.GradientStartOpacity := 0.9;
      Clone.PaintStyle := CopyStyle;
      Check(not Clone.PaintStyle.SameAs(Layer.PaintStyle), 'clone shares mutable paint');
    finally
      Clone.Free;
    end;
    Group.Visible := False;
    SetLength(Vertices, 3);
    Vertices[0].Position := TPointF.Create(-60, -30);
    Vertices[1].Position := TPointF.Create(60, -30);
    Vertices[2].Position := TPointF.Create(60, 60);
    for I := 0 to 2 do
      Vertices[I].OutgoingSegment := slskLine;
    Path := TVectArtPathLayer.Create('Bent line', Vertices, False);
    Path.StrokeWidth := 20;
    Doc.InsertLayer(2, Path);
    Style.GradientStartOpacity := 1;
    Style.GradientEndOpacity := 1;
    Style.GradientKind := slgkAlongStroke;
    Path.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    A := Buffer.Pixels[70 * 200 + 45];
    B := Buffer.Pixels[150 * 200 + 160];
    Check((A.R > A.B) and (B.B > B.R) and (A.A > 240) and (B.A > 240),
      'along-stroke gradient did not follow the bent path');
    Style.GradientKind := slgkAcrossStroke;
    Path.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    A := Buffer.Pixels[63 * 200 + 100];
    B := Buffer.Pixels[77 * 200 + 100];
    Check((A.R > A.B) and (B.B > B.R), 'across-stroke horizontal colors failed');
    A := Buffer.Pixels[120 * 200 + 167];
    B := Buffer.Pixels[120 * 200 + 153];
    Check((A.R > A.B) and (B.B > B.R), 'across-stroke colors did not turn with the path');
    SetLength(Vertices, 2);
    Vertices[0].Position := TPointF.Create(-60, 0);
    Vertices[0].OutgoingSegment := slskCubicBezier;
    Vertices[0].OutgoingControl := TPointF.Create(0, -60);
    Vertices[1].Position := TPointF.Create(60, 0);
    Vertices[1].IncomingControl := TPointF.Create(0, -60);
    Path.Vertices := Vertices;
    Style.GradientKind := slgkAlongStroke;
    Path.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    A := Buffer.Pixels[84 * 200 + 44];
    B := Buffer.Pixels[84 * 200 + 156];
    Check((A.A > 240) and (B.A > 240) and (A.R > A.B) and (B.B > B.R),
      'along gradient did not follow cubic curve');
    Style.GradientKind := slgkAcrossStroke;
    Path.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    A := Buffer.Pixels[49 * 200 + 100];
    B := Buffer.Pixels[61 * 200 + 100];
    Check((A.A > 240) and (B.A > 240) and (A.R > A.B) and (B.B > B.R),
      'across gradient failed on curved stroke');
    Style.LinearEnd := Style.LinearStart;
    Layer.PaintStyle := Style;
    Group.Visible := True;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    // 半径0でも例外や不正なシェーダーを作らない。
    Text := SerializeVectArtDocument(Doc);
    Check(TryDeserializeVectArtDocument(Text, Loaded, ErrorText), ErrorText);
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
    try
      Run;
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
