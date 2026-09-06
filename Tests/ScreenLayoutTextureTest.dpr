// テクスチャの画素分布、保存の安全性、複製と直接操作の履歴を検証する。
program ScreenLayoutTextureTest;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.Skia, System.UITypes,
  System.NetEncoding, System.RegularExpressions, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Imaging.pngimage,
  ScreenLayoutDocument, ScreenLayoutDocumentJson, ScreenLayoutPaintStyles, ScreenLayoutTextureStyle,
  ScreenLayoutTextureRenderer, ScreenLayoutRenderer, ScreenLayoutGroupCommands,
  ScreenLayoutEditHistory, ScreenLayoutEditorState, ScreenLayoutTextureInteraction,
  ScreenLayoutColorPickerFrame, ScreenLayoutTextureControl, TextRendererSkiaRuntime;

procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;

function Fixture: string;
var
  Surface: ISkSurface;
  Paint: ISkPaint;
  Stream: TBytesStream;
begin
  Surface := TSkSurface.MakeRaster(8, 4);
  Surface.Canvas.Clear(TAlphaColorRec.Red);
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColorRec.Blue;
  Surface.Canvas.DrawRect(TRectF.Create(4, 0, 8, 4), Paint);
  Stream := TBytesStream.Create;
  try
    Surface.MakeImageSnapshot.EncodeToStream(Stream);
    Result := TNetEncoding.Base64.EncodeBytesToString(Copy(Stream.Bytes, 0, Stream.Size));
  finally
    Stream.Free;
  end;
end;

procedure Run;
var
  Doc, Loaded: TVectArtDocument;
  Layer: TVectArtRectangleLayer;
  Group: TScreenLayoutGroupLayer;
  Clone: TVectArtLayer;
  Style, BeforeStyle: TScreenLayoutPaintStyle;
  Texture: TScreenLayoutTextureStyle;
  Fit: TScreenLayoutTextureFit;
  Rep: TScreenLayoutTextureRepeat;
  Buffer, Other: TVectArtRenderBuffer;
  Json, BeforeJson, ErrorText: string;
  State: TVectArtEditorState;
  History: TVectArtEditHistory;
  Interaction: TScreenLayoutTextureInteraction;
  Center, Edge: TPoint;
  Frame: TScreenLayoutColorPickerFrame;
  Control: TScreenLayoutTextureControl;
  Form: TForm;
  I: Integer;
  Bitmap: TBitmap;
  Png: TPngImage;
begin
  Doc := TVectArtDocument.Create;
  Loaded := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  Other := TVectArtRenderBuffer.Create;
  State := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TScreenLayoutTextureInteraction.Create;
  Form := TForm.Create(nil);
  Frame := TScreenLayoutColorPickerFrame.Create(nil);
  try
    Doc.SetCanvasSize(200, 200);
    Layer := TVectArtRectangleLayer.Create('Texture', TRectF.Create(-80, -80, 80, 80), clWhite);
    Doc.InsertLayer(1, Layer);
    Style := TScreenLayoutPaintStyle.Solid(clWhite);
    Style.Kind := slpkTexture;
    Texture := TScreenLayoutTextureStyle.DefaultStyle;
    Texture.Data := Fixture;
    Texture.FileName := 'embedded.png';
    Style.Texture := Texture;
    Layer.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    Check((Buffer.Pixels[100*200+50].R > 240) and (Buffer.Pixels[100*200+150].B > 240),
      'cover texture colors or centering are wrong');
    Texture.Fit := sltfContain;
    Style.Texture := Texture;
    Layer.PaintStyle := Style;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    Check((Buffer.Pixels[30*200+100].A = 0) and (Buffer.Pixels[100*200+50].A = 255),
      'contain must leave transparent margins');
    for Fit := Low(Fit) to High(Fit) do
      for Rep := Low(Rep) to High(Rep) do
      begin
        Texture.Fit := Fit;
        Texture.RepeatMode := Rep;
        Texture.Scale := 0.7;
        Texture.OffsetX := 0.13;
        Texture.OffsetY := -0.2;
        Texture.Angle := 35;
        Style.Texture := Texture;
        Layer.PaintStyle := Style;
        Layer.Opacity := 0.6;
        Json := SerializeVectArtDocument(Doc);
        Check(TryDeserializeVectArtDocument(Json, Loaded, ErrorText), 'texture JSON: ' + ErrorText);
        Check(Loaded[1].PaintStyle.Texture.SameAs(Texture), 'JSON lost texture parameters');
        RenderVectArtDocument(Doc, Buffer, 200, 200);
        RenderVectArtDocument(Loaded, Other, 200, 200);
        Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * SizeOf(TVectArtRgbaPixel)),
          'round trip changed texture rendering');
      end;
    BeforeJson := SerializeVectArtDocument(Loaded);
    Json := TRegEx.Replace(BeforeJson, '"scale":\s*[0-9.]+', '"scale":0');
    Check(Json <> BeforeJson, 'invalid fixture replacement failed');
    Check(not TryDeserializeVectArtDocument(Json, Loaded, ErrorText), 'zero scale accepted');
    Check(SerializeVectArtDocument(Loaded) = BeforeJson, 'bad input destroyed document');
    Json := TRegEx.Replace(BeforeJson, '"data":\s*"[^"]*"', '"data":"AAAA"');
    Check(Json <> BeforeJson, 'bad image fixture replacement failed');
    Check(not TryDeserializeVectArtDocument(Json, Loaded, ErrorText), 'invalid image accepted');
    Check(SerializeVectArtDocument(Loaded) = BeforeJson, 'bad image destroyed document');
    Clone := CloneScreenLayoutLayer(Layer, 'Copy');
    try
      Check(Clone.PaintStyle.Texture.SameAs(Texture), 'clone lost image');
      BeforeStyle := Clone.PaintStyle;
      Texture.Data := '';
      Style.Texture := Texture;
      Clone.PaintStyle := Style;
      Check(Layer.PaintStyle.Texture.Data <> '', 'clone changed original image');
    finally
      Clone.Free;
    end;
    Doc.SetSelectedLayers([1]);
    State.CurrentTool := vetSelect;
    Texture := TScreenLayoutTextureStyle.DefaultStyle;
    Texture.Data := Fixture;
    Style.Texture := Texture;
    Layer.PaintStyle := Style;
    Interaction.Configure(Doc, History, State, Rect(0, 0, 200, 200), 1);
    Check(Interaction.GuidePoints(Center, Edge), 'missing texture guide');
    Check((Center.X = 100) and (Center.Y = 100), 'texture center not at object center');
    BeforeStyle := Layer.PaintStyle;
    Check(Interaction.MouseDown(mbLeft, Center.X, Center.Y), 'center was not draggable');
    Interaction.MouseMove([], Center.X + 16, Center.Y - 32);
    Interaction.MouseMove([], Center.X + 32, Center.Y - 32);
    Interaction.MouseUp(Center.X + 32, Center.Y - 32);
    Check(SameValue(Layer.PaintStyle.Texture.OffsetX, 0.2, 0.001), 'move did not normalize position');
    Check(not Doc.IsInteractiveUpdate, 'interactive notification left open');
    History.Undo;
    Check(Layer.PaintStyle.SameAs(BeforeStyle) and not History.CanUndo, 'drag was not one undo step');
    History.Redo;
    Check(SameValue(Layer.PaintStyle.Texture.OffsetY, -0.2, 0.001), 'redo lost position');
    Interaction.GuidePoints(Center, Edge);
    Check(Interaction.MouseDown(mbLeft, Edge.X, Edge.Y), 'scale handle was not draggable');
    Interaction.MouseMove([], Center.X, Center.Y + (Edge.X-Center.X)*2);
    Interaction.MouseUp(Center.X, Center.Y + (Edge.X-Center.X)*2);
    Check(SameValue(Layer.PaintStyle.Texture.Scale, 2, 0.02) and
      SameValue(Layer.PaintStyle.Texture.Angle, 90, 0.02), 'scale/rotation gesture failed');
    Layer.Locked := True;
    Check(not Interaction.GuidePoints(Center, Edge), 'locked texture can be edited');
    Layer.Locked := False;
    RenderVectArtDocument(Doc, Buffer, 200, 200);
    Doc.ExtractLayer(1);
    Group := TScreenLayoutGroupLayer.Create('Group');
    Group.AddChild(Layer);
    Doc.InsertLayer(1, Group);
    RenderVectArtDocument(Doc, Other, 200, 200);
    Check(CompareMem(Buffer.Data, Other.Data, Buffer.PixelCount * SizeOf(TVectArtRgbaPixel)),
      'group changed texture pixels');
    Frame.Parent := Form;
    Frame.SelectPaintKind(slpkTexture);
    Check(Frame.PaintStyle.Kind = slpkTexture, 'texture selector disabled');
    Frame.PaintStyle := Style;
    Control := nil;
    for I := 0 to Frame.ComponentCount - 1 do
      if Frame.Components[I] is TScreenLayoutTextureControl then
        Control := TScreenLayoutTextureControl(Frame.Components[I]);
    Check((Control <> nil) and Control.Visible, 'texture UI not visible');
    Control.LoadFile('missing-texture-test.png');
    Check(Control.Texture.SameAs(Style.Texture), 'failed replacement lost original');
    Frame.SelectPaintKind(slpkSolid);
    Check(not Control.Visible, 'texture UI visible in solid mode');
    Frame.SelectPaintKind(slpkTexture);
    Check(Frame.PaintStyle.Texture.SameAs(Style.Texture), 'mode switch lost texture');
    Frame.Width := 160;
    Control.Texture := Texture;
    Form.SetBounds(-32000, -32000, 200, 480);
    Form.Show;
    Application.ProcessMessages;
    Bitmap := TBitmap.Create;
    Png := TPngImage.Create;
    try
      Bitmap.SetSize(Frame.Width, Frame.Height);
      Bitmap.Canvas.Brush.Color := Frame.Color;
      Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
      Frame.PaintTo(Bitmap.Canvas.Handle, 0, 0);
      Png.Assign(Bitmap);
      Png.SaveToFile(ExtractFilePath(ParamStr(0)) + 'texture-ui.png');
    finally
      Png.Free;
      Bitmap.Free;
    end;
  finally
    Frame.Free;
    Form.Free;
    Interaction.Free;
    History.Free;
    State.Free;
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
    Writeln('PASS texture rendering, JSON validation, clone, history and UI');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
