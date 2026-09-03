program ScreenLayoutPluginCoordinateTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  AviUtl2FilterTypes in '..\Lib\AviUtl2\AviUtl2FilterTypes.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutDocumentJson in
    '..\Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutDocumentJsonReader in
    '..\Source\Persistence\ScreenLayoutDocumentJsonReader.pas',
  ScreenLayoutDocumentJsonWriter in
    '..\Source\Persistence\ScreenLayoutDocumentJsonWriter.pas',
  ScreenLayoutPluginDocument in
    '..\Source\PlacementPlugin\ScreenLayoutPluginDocument.pas',
  ScreenLayoutFrameCapture in
    '..\Source\PlacementPlugin\ScreenLayoutFrameCapture.pas',
  ScreenLayoutFilterContext in
    '..\Source\PlacementPlugin\ScreenLayoutFilterContext.pas',
  PluginFilterContextManager in
    '..\Lib\AviUtl2\PluginFilterContextManager.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

var
  LastSetHeight: Integer;
  LastSetWidth: Integer;

procedure SetTestImageData(Buffer: PPIXEL_RGBA;
  Width, Height: Integer); cdecl;
begin
  LastSetWidth := Width;
  LastSetHeight := Height;
end;

var
  Document: TVectArtDocument;
  ErrorMessage: string;
  FilterContext: TScreenLayoutFilterContext;
  ObjectInfo: TOBJECT_INFO;
  OutputHeight: Integer;
  OutputWidth: Integer;
  Saved: TVectArtDocument;
  SceneInfo: TSCENE_INFO;
  Serialized: string;
  Video: TFILTER_PROC_VIDEO;
begin
  Document := TVectArtDocument.Create;
  Saved := TVectArtDocument.Create;
  try
    Check(InitializeScreenLayoutPluginDocument(Document, '', 1280, 720,
      ErrorMessage), 'New plugin document initialization failed');
    Check((Document.CanvasLayer.Width = 1280) and
      (Document.CanvasLayer.Height = 720),
      'New plugin document did not use the captured frame size');

    Saved.SetCanvasSize(640, 360);
    Serialized := SerializeVectArtDocument(Saved);
    Check(InitializeScreenLayoutPluginDocument(Document, Serialized,
      1920, 1080, ErrorMessage), 'Saved plugin document was not loaded');
    Check((Document.CanvasLayer.Width = 640) and
      (Document.CanvasLayer.Height = 360),
      'Captured frame size replaced saved canvas dimensions');

    Document.SetCanvasSize(800, 600);
    Check(InitializeScreenLayoutPluginDocument(Document, '', 0, 0,
      ErrorMessage), 'Missing frame fallback failed');
    Check((Document.CanvasLayer.Width = 800) and
      (Document.CanvasLayer.Height = 600),
      'Missing frame size changed the current canvas dimensions');

    FillChar(ObjectInfo, SizeOf(ObjectInfo), 0);
    FillChar(SceneInfo, SizeOf(SceneInfo), 0);
    FillChar(Video, SizeOf(Video), 0);
    ObjectInfo.Width := 320;
    ObjectInfo.Height := 180;
    SceneInfo.Width := 1920;
    SceneInfo.Height := 1080;
    Video.Object_ := @ObjectInfo;
    Video.Scene := @SceneInfo;
    Video.SetImageData := SetTestImageData;
    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      FilterContext := TScreenLayoutFilterContext.Create;
      try
        Check(FilterContext.RenderVideo(@Video),
          'Plugin object-size render failed');
        Check(FilterContext.CopyOutputSize(OutputWidth, OutputHeight) and
          (OutputWidth = 320) and (OutputHeight = 180),
          'Plugin did not retain the object output size');
        Check((LastSetWidth = 320) and (LastSetHeight = 180),
          'Plugin returned an unexpected object output size');

        ObjectInfo.Width := 0;
        ObjectInfo.Height := 0;
        Check(FilterContext.RenderVideo(@Video),
          'Plugin scene-size fallback render failed');
        Check(FilterContext.CopyOutputSize(OutputWidth, OutputHeight) and
          (OutputWidth = 1920) and (OutputHeight = 1080),
          'Plugin did not retain the scene fallback size');
      finally
        FilterContext.Free;
      end;
    finally
      TTextRendererSkiaRuntime.Release;
    end;
  finally
    Saved.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
