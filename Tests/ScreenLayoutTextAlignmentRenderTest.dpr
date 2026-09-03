program ScreenLayoutTextAlignmentRenderTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function RenderAlignment(Document: TVectArtDocument;
  Buffer: TVectArtRenderBuffer; Alignment: TScreenLayoutTextAlignment):
  TBytes;
var
  Data: TScreenLayoutTextData;
begin
  Data := Default(TScreenLayoutTextData);
  Data.Alignment := Alignment;
  Data.Bounds := TRectF.Create(-80, -35, 80, 35);
  Data.FontFamily := 'Segoe UI';
  Data.FontSize := 28;
  Data.Name := 'Text';
  Data.Opacity := 1;
  Data.Text := 'MMMM' + sLineBreak + 'I';
  Data.TextColor := clWhite;
  Data.Visible := True;
  Data.WrapWidth := 160;
  if Document.LayerCount = 1 then
    Document.InsertText(1, Data)
  else
    Document.SetTextData(1, Data);
  RenderVectArtDocument(Document, Buffer, 240, 120);
  SetLength(Result, Buffer.PixelCount * SizeOf(TVectArtRgbaPixel));
  if Length(Result) > 0 then
    Move(Buffer.Data^, Result[0], Length(Result));
end;

procedure Run;
var
  Buffer: TVectArtRenderBuffer;
  CenterPixels: TBytes;
  Document: TVectArtDocument;
  LeftPixels: TBytes;
  RightPixels: TBytes;
begin
  Document := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  try
    Document.SetCanvasSize(240, 120);
    Document.CanvasLayer.Transparent := True;
    LeftPixels := RenderAlignment(Document, Buffer, sltaMiddleLeft);
    CenterPixels := RenderAlignment(Document, Buffer, sltaMiddleCenter);
    RightPixels := RenderAlignment(Document, Buffer, sltaMiddleRight);
    Check(not CompareMem(@LeftPixels[0], @CenterPixels[0],
      Length(LeftPixels)), 'center alignment did not change rendering');
    Check(not CompareMem(@CenterPixels[0], @RightPixels[0],
      Length(CenterPixels)), 'right alignment did not change rendering');
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
