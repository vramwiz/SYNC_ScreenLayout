program ScreenLayoutFilterRenderTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function CountVisiblePixels(const Buffer: TVectArtRenderBuffer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Buffer.PixelCount - 1 do
    if Buffer.Pixels[I].A <> 0 then
      Inc(Result);
end;

procedure Run;
var
  BaselineCount: Integer;
  Blur: TScreenLayoutBlurFilter;
  Buffer: TVectArtRenderBuffer;
  Document: TVectArtDocument;
  FilteredCount: Integer;
  Group: TScreenLayoutGroupLayer;
  Layer: TVectArtLayer;
  Outline: TScreenLayoutOutlineFilter;
  Shadow: TScreenLayoutShadowFilter;
begin
  Document := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  try
    Document.SetCanvasSize(200, 200);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Rectangle',
        TRectF.Create(-20, -20, 20, 20), clWhite));
    Layer := Document[1];

    RenderVectArtDocument(Document, Buffer, 200, 200);
    BaselineCount := CountVisiblePixels(Buffer);
    Check(BaselineCount > 0, 'baseline rectangle was not rendered');

    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Width := 8;
    Layer.AddFilter(Outline);
    RenderVectArtDocument(Document, Buffer, 200, 200);
    FilteredCount := CountVisiblePixels(Buffer);
    Check(FilteredCount > BaselineCount,
      'outline did not expand the rendered alpha');

    Layer.ClearFilters;
    Shadow := TScreenLayoutShadowFilter.Create;
    Shadow.OffsetX := 12;
    Shadow.OffsetY := 12;
    Shadow.BlurRadius := 4;
    Layer.AddFilter(Shadow);
    RenderVectArtDocument(Document, Buffer, 200, 200);
    FilteredCount := CountVisiblePixels(Buffer);
    Check(FilteredCount > BaselineCount,
      'shadow did not expand the rendered alpha');

    Layer.ClearFilters;
    Blur := TScreenLayoutBlurFilter.Create;
    Blur.Radius := 5;
    Layer.AddFilter(Blur);
    RenderVectArtDocument(Document, Buffer, 200, 200);
    FilteredCount := CountVisiblePixels(Buffer);
    Check(FilteredCount > BaselineCount,
      'blur did not expand the rendered alpha');

    Layer.ClearFilters;
    Layer := Document.ExtractLayer(1);
    Group := TScreenLayoutGroupLayer.Create('Group');
    Group.AddChild(Layer);
    Document.InsertLayer(1, Group);
    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Width := 8;
    Group.AddFilter(Outline);
    RenderVectArtDocument(Document, Buffer, 200, 200);
    FilteredCount := CountVisiblePixels(Buffer);
    Check(FilteredCount > BaselineCount,
      'group outline did not expand the rendered alpha');
  finally
    Buffer.Free;
    Document.Free;
  end;
end;

begin
  try
    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
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
