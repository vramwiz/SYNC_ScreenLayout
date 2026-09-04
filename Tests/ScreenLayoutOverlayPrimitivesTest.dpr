program ScreenLayoutOverlayPrimitivesTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  Vcl.Graphics,
  ScreenLayoutOverlayPrimitives in
    '..\Source\Rendering\ScreenLayoutOverlayPrimitives.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure FillBitmap(Bitmap: TBitmap; Color: TColor);
begin
  Bitmap.Canvas.Brush.Color := Color;
  Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
end;

procedure TestLineContrast(BackgroundColor: TColor);
var
  Bitmap: TBitmap;
  Points: array[0..1] of TPoint;
begin
  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(32, 24);
    FillBitmap(Bitmap, BackgroundColor);
    Points[0] := Point(4, 12);
    Points[1] := Point(27, 12);
    DrawOverlayPolyline(Bitmap.Canvas, Points);
    Check(ColorToRGB(Bitmap.Canvas.Pixels[12, 12]) = ColorToRGB(clBlack),
      'overlay core must remain black');
    Check(ColorToRGB(Bitmap.Canvas.Pixels[12, 11]) = ColorToRGB(clWhite),
      'overlay halo must remain white');
  finally
    Bitmap.Free;
  end;
end;

procedure TestCanvasStateIsRestored;
var
  Bitmap: TBitmap;
begin
  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(24, 24);
    Bitmap.Canvas.Pen.Color := clRed;
    Bitmap.Canvas.Pen.Style := psDash;
    Bitmap.Canvas.Pen.Width := 2;
    Bitmap.Canvas.Brush.Color := clLime;
    Bitmap.Canvas.Brush.Style := bsSolid;
    DrawOverlayLine(Bitmap.Canvas, Point(2, 2), Point(20, 2));
    Check(Bitmap.Canvas.Pen.Color = clRed, 'pen color was not restored');
    Check(Bitmap.Canvas.Pen.Style = psDash, 'pen style was not restored');
    Check(Bitmap.Canvas.Pen.Width = 2, 'pen width was not restored');
    DrawOverlayHandleRect(Bitmap.Canvas, Rect(6, 6, 14, 14));
    Check(Bitmap.Canvas.Brush.Color = clLime,
      'brush color was not restored');
    Check(Bitmap.Canvas.Brush.Style = bsSolid,
      'brush style was not restored');
  finally
    Bitmap.Free;
  end;
end;

procedure TestFramesAndHandlesUseCommonContrast;
var
  Bitmap: TBitmap;
begin
  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(32, 24);
    FillBitmap(Bitmap, clBlack);
    DrawOverlayFrameRect(Bitmap.Canvas, Rect(5, 5, 27, 19), clRed);
    Check(ColorToRGB(Bitmap.Canvas.Pixels[12, 5]) = ColorToRGB(clRed),
      'frame must preserve its semantic core color');
    Check(ColorToRGB(Bitmap.Canvas.Pixels[12, 4]) = ColorToRGB(clWhite),
      'frame must have a white halo');
    DrawOverlayHandleRect(Bitmap.Canvas, Rect(10, 8, 20, 18), clYellow,
      clBlack);
    Check(ColorToRGB(Bitmap.Canvas.Pixels[15, 13]) = ColorToRGB(clYellow),
      'handle fill color was not preserved');
    Check(ColorToRGB(Bitmap.Canvas.Pixels[15, 8]) = ColorToRGB(clBlack),
      'handle border must remain visible on a light fill');
    Check(ColorToRGB(Bitmap.Canvas.Pixels[15, 7]) = ColorToRGB(clWhite),
      'handle border must have a white halo');
  finally
    Bitmap.Free;
  end;
end;

begin
  try
    TestLineContrast(clBlack);
    TestLineContrast(clWhite);
    TestCanvasStateIsRestored;
    TestFramesAndHandlesUseCommonContrast;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.Message);
      Halt(1);
    end;
  end;
end.
