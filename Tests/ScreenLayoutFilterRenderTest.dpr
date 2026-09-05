program ScreenLayoutFilterRenderTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Math,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutPaintStyles in
    '..\Source\Core\Model\ScreenLayoutPaintStyles.pas',
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

function TryGetVisibleBounds(const Buffer: TVectArtRenderBuffer;
  out Bounds: TRect): Boolean;
var
  X: Integer;
  Y: Integer;
begin
  Result := False;
  Bounds := Rect(Buffer.Width, Buffer.Height, 0, 0);
  for Y := 0 to Buffer.Height - 1 do
    for X := 0 to Buffer.Width - 1 do
      if Buffer.Pixels[Y * Buffer.Width + X].A <> 0 then
      begin
        Bounds.Left := Min(Bounds.Left, X);
        Bounds.Top := Min(Bounds.Top, Y);
        Bounds.Right := Max(Bounds.Right, X + 1);
        Bounds.Bottom := Max(Bounds.Bottom, Y + 1);
        Result := True;
      end;
end;

procedure CheckSharpPathOutlineBounds;
const
  OUTLINE_WIDTH = 12;
var
  BaselineBounds: TRect;
  Buffer: TVectArtRenderBuffer;
  Document: TVectArtDocument;
  FilteredBounds: TRect;
  Outline: TScreenLayoutOutlineFilter;
  Path: TVectArtPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  try
    Document.SetCanvasSize(300, 200);
    SetLength(Vertices, 3);
    Vertices[0].Position := TPointF.Create(-70, 50);
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].Position := TPointF.Create(0, 0);
    Vertices[1].OutgoingSegment := slskLine;
    Vertices[2].Position := TPointF.Create(-70, -50);
    Vertices[2].OutgoingSegment := slskLine;
    Path := TVectArtPathLayer.Create('Sharp path', Vertices, False);
    Path.LineCap := vlcRound;
    Path.StrokeColor := clRed;
    Path.StrokeWidth := 40;
    Document.InsertLayer(1, Path);

    RenderVectArtDocument(Document, Buffer, 300, 200);
    Check(TryGetVisibleBounds(Buffer, BaselineBounds),
      'sharp path baseline was not rendered');

    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Color := clBlack;
    Outline.Width := OUTLINE_WIDTH;
    Path.AddFilter(Outline);
    RenderVectArtDocument(Document, Buffer, 300, 200);
    Check(TryGetVisibleBounds(Buffer, FilteredBounds),
      'sharp path outline was not rendered');
    Check((FilteredBounds.Left <= BaselineBounds.Left - OUTLINE_WIDTH + 2) and
      (FilteredBounds.Top <= BaselineBounds.Top - OUTLINE_WIDTH + 2) and
      (FilteredBounds.Right >= BaselineBounds.Right + OUTLINE_WIDTH - 2) and
      (FilteredBounds.Bottom >= BaselineBounds.Bottom + OUTLINE_WIDTH - 2),
      'outline clipped the sharp path miter');
  finally
    Buffer.Free;
    Document.Free;
  end;
end;

procedure CheckLinearGradientRendering;
var
  BottomPixel: TVectArtRgbaPixel;
  Buffer: TVectArtRenderBuffer;
  Document: TVectArtDocument;
  Layer: TVectArtRectangleLayer;
  LeftPixel: TVectArtRgbaPixel;
  RightPixel: TVectArtRgbaPixel;
  Style: TScreenLayoutPaintStyle;
  Stops: TArray<TScreenLayoutGradientStop>;
  MiddlePixel: TVectArtRgbaPixel;
  TopPixel: TVectArtRgbaPixel;
begin
  Document := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  try
    Document.SetCanvasSize(200, 200);
    Layer := TVectArtRectangleLayer.Create('Gradient',
      TRectF.Create(-60, -30, 60, 30), clRed);
    Style := TScreenLayoutPaintStyle.Solid(clRed);
    Style.Kind := slpkGradient;
    Style.GradientStartColor := clRed;
    Style.GradientEndColor := clBlue;
    Style.AddGradientStop(0.5);
    Stops := Style.GetGradientStops;
    Stops[0].Color := clLime;
    Style.SetGradientStops(Stops);
    Layer.PaintStyle := Style;
    Document.InsertLayer(1, Layer);
    RenderVectArtDocument(Document, Buffer, 200, 200);
    LeftPixel := Buffer.Pixels[100 * Buffer.Width + 45];
    MiddlePixel := Buffer.Pixels[100 * Buffer.Width + 100];
    RightPixel := Buffer.Pixels[100 * Buffer.Width + 155];
    Check((LeftPixel.A > 240) and (RightPixel.A > 240) and
      (MiddlePixel.A > 240) and
      (LeftPixel.R > LeftPixel.B) and
      (MiddlePixel.G > MiddlePixel.R) and
      (MiddlePixel.G > MiddlePixel.B) and
      (RightPixel.B > RightPixel.R),
      'linear gradient endpoints were not rendered in the requested direction');
    Layer.RotationDegrees := 90.0;
    RenderVectArtDocument(Document, Buffer, 200, 200);
    TopPixel := Buffer.Pixels[45 * Buffer.Width + 100];
    MiddlePixel := Buffer.Pixels[100 * Buffer.Width + 100];
    BottomPixel := Buffer.Pixels[155 * Buffer.Width + 100];
    Check((TopPixel.A > 240) and (BottomPixel.A > 240) and
      (TopPixel.R > TopPixel.B) and
      (MiddlePixel.G > MiddlePixel.R) and
      (MiddlePixel.G > MiddlePixel.B) and
      (BottomPixel.B > BottomPixel.R),
      'rotated gradient rendering did not follow the layer-local direction');
  finally
    Buffer.Free;
    Document.Free;
  end;
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
      CheckSharpPathOutlineBounds;
      CheckLinearGradientRendering;
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
