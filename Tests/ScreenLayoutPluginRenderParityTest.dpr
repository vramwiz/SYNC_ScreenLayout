program ScreenLayoutPluginRenderParityTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Lib\AviUtl2\AviUtl2FilterTypes.pas',
  PluginFilterContextManager in
    '..\Lib\AviUtl2\PluginFilterContextManager.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutDocumentJson in
    '..\Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutDocumentJsonReader in
    '..\Source\Persistence\ScreenLayoutDocumentJsonReader.pas',
  ScreenLayoutDocumentJsonWriter in
    '..\Source\Persistence\ScreenLayoutDocumentJsonWriter.pas',
  ScreenLayoutFrameCapture in
    '..\Source\PlacementPlugin\ScreenLayoutFrameCapture.pas',
  ScreenLayoutFilterContext in
    '..\Source\PlacementPlugin\ScreenLayoutFilterContext.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

const
  OUTPUT_WIDTH = 320;
  OUTPUT_HEIGHT = 180;

var
  ReturnedHeight: Integer;
  ReturnedPixels: TBytes;
  ReturnedWidth: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure FillTestBackground(Buffer: PPIXEL_RGBA);
var
  I: Integer;
begin
  for I := 0 to OUTPUT_WIDTH * OUTPUT_HEIGHT - 1 do
  begin
    Buffer^.R := 17;
    Buffer^.G := 31;
    Buffer^.B := 47;
    Buffer^.A := 255;
    Inc(Buffer);
  end;
end;

procedure GetTestImage(Buffer: PPIXEL_RGBA); cdecl;
begin
  FillTestBackground(Buffer);
end;

procedure SetReturnedImage(Buffer: PPIXEL_RGBA;
  Width, Height: Integer); cdecl;
begin
  ReturnedWidth := Width;
  ReturnedHeight := Height;
  SetLength(ReturnedPixels, Width * Height * SizeOf(TPIXEL_RGBA));
  if Length(ReturnedPixels) > 0 then
    Move(Buffer^, ReturnedPixels[0], Length(ReturnedPixels));
end;

function CreateTestPng: TBytes;
var
  Bitmap: TBitmap;
  Png: TPngImage;
  Stream: TMemoryStream;
begin
  Bitmap := TBitmap.Create;
  Png := TPngImage.Create;
  Stream := TMemoryStream.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(2, 2);
    Bitmap.Canvas.Brush.Color := clFuchsia;
    Bitmap.Canvas.FillRect(Rect(0, 0, 2, 2));
    Png.Assign(Bitmap);
    Png.SaveToStream(Stream);
    SetLength(Result, Stream.Size);
    Stream.Position := 0;
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[0], Length(Result));
  finally
    Stream.Free;
    Png.Free;
    Bitmap.Free;
  end;
end;

procedure AddCurrentLayerTypes(Document: TVectArtDocument);
var
  Attachment: TScreenLayoutTextPathAttachment;
  Arc: TScreenLayoutArcLayer;
  ArcShape: TScreenLayoutEllipseArcShapeLayer;
  Contours: TArray<TScreenLayoutContour>;
  EllipseLine: TScreenLayoutEllipseLineLayer;
  Group: TScreenLayoutGroupLayer;
  ImagePoints: TVectArtImagePoints;
  Path: TVectArtPathLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RoundedLine: TScreenLayoutRoundedRectangleLineLayer;
  Shape: TScreenLayoutShapeLayer;
  TextPath: TScreenLayoutTextPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document.InsertLayer(Document.LayerCount,
    TVectArtRectangleLayer.Create('Rectangle',
      TRectF.Create(-150, -80, -110, -50), clRed));
  Document.InsertLayer(Document.LayerCount,
    TScreenLayoutRoundedRectangleLayer.Create('Rounded rectangle',
      TRectF.Create(-100, -80, -50, -45), clGreen,
      UniformScreenLayoutCornerRadii(8)));
  Document.InsertLayer(Document.LayerCount,
    TScreenLayoutEllipseLayer.Create('Ellipse',
      TRectF.Create(-40, -80, 10, -45), clBlue));

  RectangleLine := TScreenLayoutRectangleLineLayer.Create('Rectangle line',
    TRectF.Create(20, -80, 65, -45));
  RectangleLine.StrokeColor := clYellow;
  RectangleLine.StrokeWidth := 3;
  Document.InsertLayer(Document.LayerCount, RectangleLine);
  RoundedLine := TScreenLayoutRoundedRectangleLineLayer.Create(
    'Rounded line', TRectF.Create(75, -80, 125, -45),
    UniformScreenLayoutCornerRadii(7));
  RoundedLine.StrokeColor := clAqua;
  RoundedLine.StrokeWidth := 3;
  Document.InsertLayer(Document.LayerCount, RoundedLine);
  EllipseLine := TScreenLayoutEllipseLineLayer.Create('Ellipse line',
    TRectF.Create(135, -80, 155, -45));
  EllipseLine.StrokeColor := clWhite;
  EllipseLine.StrokeWidth := 2;
  Document.InsertLayer(Document.LayerCount, EllipseLine);

  Arc := TScreenLayoutArcLayer.Create('Arc',
    TRectF.Create(-150, -30, -90, 20));
  Arc.StrokeColor := clLime;
  Arc.StrokeWidth := 4;
  Arc.StartAngleDegrees := 15;
  Arc.SweepAngleDegrees := 240;
  Document.InsertLayer(Document.LayerCount, Arc);
  ArcShape := TScreenLayoutEllipseArcShapeLayer.Create('Arc shape',
    TRectF.Create(-80, -30, -20, 20), clPurple);
  ArcShape.StartAngleDegrees := 30;
  ArcShape.SweepAngleDegrees := 210;
  Document.InsertLayer(Document.LayerCount, ArcShape);

  SetLength(Vertices, 3);
  Vertices[0].Position := TPointF.Create(-10, -20);
  Vertices[0].OutgoingControl := TPointF.Create(15, -15);
  Vertices[0].OutgoingSegment := slskCubicBezier;
  Vertices[0].Kind := slvkBezier;
  Vertices[1].Position := TPointF.Create(40, 15);
  Vertices[1].IncomingControl := TPointF.Create(-15, -15);
  Vertices[1].OutgoingSegment := slskLine;
  Vertices[1].Kind := slvkBezier;
  Vertices[2].Position := TPointF.Create(75, -15);
  Vertices[2].OutgoingSegment := slskLine;
  Vertices[2].Kind := slvkSharp;
  Path := TVectArtPathLayer.Create('Path', Vertices, False);
  Path.StrokeColor := clSilver;
  Path.StrokeWidth := 5;
  Path.LineCap := vlcRound;
  Document.InsertLayer(Document.LayerCount, Path);

  for Attachment := Low(TScreenLayoutTextPathAttachment) to
    High(TScreenLayoutTextPathAttachment) do
  begin
    SetLength(Vertices, 2);
    Vertices[0].Position := TPointF.Create(-150,
      30 + Ord(Attachment) * 14);
    Vertices[0].Kind := slvkSharp;
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].Position := TPointF.Create(-75,
      30 + Ord(Attachment) * 14);
    Vertices[1].Kind := slvkSharp;
    Vertices[1].OutgoingSegment := slskLine;
    TextPath := TScreenLayoutTextPathLayer.Create('Text path',
      TRectF.Create(-150, 10 + Ord(Attachment) * 14, -75,
        30 + Ord(Attachment) * 14), 'Path', 'Segoe UI', 14, 0,
      clWhite, Vertices);
    TextPath.Attachment := Attachment;
    Document.InsertLayer(Document.LayerCount, TextPath);
  end;

  SetLength(Contours, 1);
  SetLength(Contours[0].Vertices, 3);
  Contours[0].Vertices[0].Position := TPointF.Create(90, -25);
  Contours[0].Vertices[1].Position := TPointF.Create(145, 15);
  Contours[0].Vertices[2].Position := TPointF.Create(100, 25);
  Contours[0].Vertices[0].OutgoingSegment := slskLine;
  Contours[0].Vertices[1].OutgoingSegment := slskLine;
  Contours[0].Vertices[2].OutgoingSegment := slskLine;
  Shape := TScreenLayoutShapeLayer.Create('Shape', Contours);
  Shape.FillColor := clOlive;
  Shape.StrokeColor := clWhite;
  Shape.StrokeWidth := 2;
  Document.InsertLayer(Document.LayerCount, Shape);

  Group := TScreenLayoutGroupLayer.Create('Group');
  Group.Opacity := 0.65;
  Group.AddChild(TScreenLayoutTextLayer.Create('Text',
    TRectF.Create(-140, 40, -20, 75), 'Center', 'Segoe UI', 24, 120,
    clWhite));
  TScreenLayoutTextLayer(Group[Group.ChildCount - 1]).FontStyle :=
    [fsBold, fsItalic, fsUnderline, fsStrikeOut];
  TScreenLayoutTextLayer(Group[Group.ChildCount - 1]).Alignment :=
    sltaMiddleCenter;
  TScreenLayoutTextLayer(Group[Group.ChildCount - 1]).LetterSpacingRatio :=
    0.2;
  TScreenLayoutTextLayer(Group[Group.ChildCount - 1]).LineSpacingRatio := 0.3;
  Group.AddChild(TVectArtRectangleLayer.Create('Grouped rectangle',
    TRectF.Create(0, 45, 55, 80), clTeal));
  Document.InsertLayer(Document.LayerCount, Group);

  ImagePoints[0] := TPointF.Create(75, 45);
  ImagePoints[1] := TPointF.Create(115, 45);
  ImagePoints[2] := TPointF.Create(115, 80);
  ImagePoints[3] := TPointF.Create(75, 80);
  Document.InsertLayer(Document.LayerCount,
    TVectArtImageLayer.Create('Image', CreateTestPng, ImagePoints,
      visImage));
end;

var
  Attachment: TScreenLayoutTextPathAttachment;
  AttachmentSeen: array[TScreenLayoutTextPathAttachment] of Boolean;
  DirectBuffer: TVectArtRenderBuffer;
  Document: TVectArtDocument;
  ExpectedBuffer: TVectArtRenderBuffer;
  ExpectedDocument: TVectArtDocument;
  FilterContext: TScreenLayoutFilterContext;
  I: Integer;
  ObjectInfo: TOBJECT_INFO;
  ReadError: string;
  Serialized: string;
  Video: TFILTER_PROC_VIDEO;
begin
  Document := TVectArtDocument.Create;
  ExpectedDocument := TVectArtDocument.Create;
  DirectBuffer := TVectArtRenderBuffer.Create;
  ExpectedBuffer := TVectArtRenderBuffer.Create;
  FilterContext := nil;
  try
    Document.SetCanvasSize(OUTPUT_WIDTH, OUTPUT_HEIGHT);
    Document.CanvasLayer.Transparent := True;
    AddCurrentLayerTypes(Document);
    Serialized := SerializeVectArtDocument(Document);
    Check(TryDeserializeVectArtDocument(Serialized, ExpectedDocument,
      ReadError), 'Expected document load failed: ' + ReadError);
    FillChar(AttachmentSeen, SizeOf(AttachmentSeen), 0);
    for I := 1 to ExpectedDocument.LayerCount - 1 do
      if ExpectedDocument[I] is TScreenLayoutTextPathLayer then
        AttachmentSeen[TScreenLayoutTextPathLayer(
          ExpectedDocument[I]).Attachment] := True;
    for Attachment := Low(TScreenLayoutTextPathAttachment) to
      High(TScreenLayoutTextPathAttachment) do
      Check(AttachmentSeen[Attachment],
        Format('Text path attachment %d was not restored for plugin input',
          [Ord(Attachment)]));

    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      RenderVectArtDocument(ExpectedDocument, DirectBuffer,
        OUTPUT_WIDTH, OUTPUT_HEIGHT);
      ExpectedBuffer.SetSize(OUTPUT_WIDTH, OUTPUT_HEIGHT);
      FillTestBackground(PPIXEL_RGBA(ExpectedBuffer.Data));
      CompositeVectArtRgba(DirectBuffer, ExpectedBuffer.Data,
        OUTPUT_WIDTH, OUTPUT_HEIGHT);
      FilterContext := TScreenLayoutFilterContext.Create;
      Check(FilterContext.UpdateSerializedData(Serialized),
        'Plugin rejected the current serialized document');
      FillChar(ObjectInfo, SizeOf(ObjectInfo), 0);
      FillChar(Video, SizeOf(Video), 0);
      ObjectInfo.Width := OUTPUT_WIDTH;
      ObjectInfo.Height := OUTPUT_HEIGHT;
      Video.Object_ := @ObjectInfo;
      Video.GetImageData := GetTestImage;
      Video.SetImageData := SetReturnedImage;
      Check(FilterContext.RenderVideo(@Video), 'Plugin render failed');
      Check((ReturnedWidth = OUTPUT_WIDTH) and
        (ReturnedHeight = OUTPUT_HEIGHT),
        'Plugin returned unexpected dimensions');
      Check(Length(ReturnedPixels) = ExpectedBuffer.PixelCount *
        SizeOf(TVectArtRgbaPixel), 'Plugin returned unexpected byte count');
      Check(CompareMem(ExpectedBuffer.Data, @ReturnedPixels[0],
        Length(ReturnedPixels)),
        'Plugin RGBA differs from the shared renderer output');
    finally
      FilterContext.Free;
      TTextRendererSkiaRuntime.Release;
    end;
  finally
    ExpectedBuffer.Free;
    DirectBuffer.Free;
    ExpectedDocument.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
