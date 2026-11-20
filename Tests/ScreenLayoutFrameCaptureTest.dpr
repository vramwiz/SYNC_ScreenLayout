program ScreenLayoutFrameCaptureTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  AviUtl2FilterTypes in '..\Lib\AviUtl2\AviUtl2FilterTypes.pas',
  ScreenLayoutFrameCapture in '..\Source\PlacementPlugin\ScreenLayoutFrameCapture.pas';

var
  Capture: TScreenLayoutFrameCapture;
  Reads: Integer;
  Target: TScreenLayoutCaptureTarget;
  ReplaceRequestDuringRead: Boolean;

procedure Check(Condition: Boolean; const Detail: string);
begin
  if not Condition then
    raise Exception.Create(Detail);
end;

procedure ReadInput(Buffer: PPIXEL_RGBA); cdecl;
begin
  Inc(Reads);
  Buffer^.R := 16;
  Buffer^.G := 192;
  Buffer^.B := 32;
  Buffer^.A := 255;
  Inc(Buffer);
  Buffer^.R := 220;
  Buffer^.G := 24;
  Buffer^.B := 80;
  Buffer^.A := 128;
  if ReplaceRequestDuringRead then
  begin
    ReplaceRequestDuringRead := False;
    Capture.Arm(Target, 6);
  end;
end;

procedure RunCaptureTests;
var
  Frame: TScreenLayoutCapturedFrame;
  Obj: TOBJECT_INFO;
  Pixels: TBytes;
  Scene: TSCENE_INFO;
  Video: TFILTER_PROC_VIDEO;
begin
  Target.SceneID := 3;
  Target.Frame := 15;
  Target.ObjectLayer := 2;
  Target.ObjectID := 24;
  Target.EffectID := 84;
  Scene := Default(TSCENE_INFO);
  Scene.ID := Target.SceneID;
  Scene.OriginID := Target.SceneID;
  Obj := Default(TOBJECT_INFO);
  Obj.Width := 1;
  Obj.Height := 2;
  Obj.Layer := 1;
  Obj.EffectLayer := Target.ObjectLayer;
  Obj.OriginFrame := Target.Frame;
  Obj.ID := Target.ObjectID;
  Obj.EffectID := Target.EffectID;
  Video := Default(TFILTER_PROC_VIDEO);
  Video.Scene := @Scene;
  Video.Object_ := @Obj;
  Video.GetImageData := ReadInput;

  Check((Capture.Capture(@Video, Pixels) = 0) and (Reads = 0),
    'An ordinary frame must not read a background');
  Capture.Arm(Target, 1);
  Inc(Scene.ID);
  Check(Capture.Capture(@Video, Pixels) = 0, 'Wrong scene accepted');
  Dec(Scene.ID);
  Inc(Scene.OriginID);
  Check(Capture.Capture(@Video, Pixels) = 0, 'Wrong origin scene accepted');
  Dec(Scene.OriginID);
  Scene.Flag := SCENE_FLAG_REFERENCE_FRAME;
  Check(Capture.Capture(@Video, Pixels) = 0, 'Reference frame accepted');
  Scene.Flag := 0;
  Inc(Obj.OriginFrame);
  Check(Capture.Capture(@Video, Pixels) = 0, 'Wrong frame accepted');
  Dec(Obj.OriginFrame);
  Inc(Obj.EffectLayer);
  Check(Capture.Capture(@Video, Pixels) = 0, 'Wrong owner layer accepted');
  Dec(Obj.EffectLayer);
  Inc(Obj.ID);
  Check(Capture.Capture(@Video, Pixels) = 0, 'Wrong object accepted');
  Dec(Obj.ID);
  Inc(Obj.EffectID);
  Check(Capture.Capture(@Video, Pixels) = 0, 'Wrong effect accepted');
  Dec(Obj.EffectID);
  Check(Reads = 0, 'Unrelated frames must not read a background');
  Check(Capture.Capture(@Video, Pixels) = 1, 'Matching frame was not captured');
  Check((Length(Pixels) = 8) and (Pixels[0] = 16) and (Pixels[4] = 220),
    'Acquired pixels were not returned for compositing');
  Check((Capture.Capture(@Video, Pixels) = 0) and (Reads = 1),
    'A request must read one image only');
  Capture.Take(1, Frame);
  Check((Frame.Width = 1) and (Frame.Height = 2) and (Length(Frame.Pixels) = 8),
    'Captured dimensions or buffer are invalid');
  Check((Frame.Pixels[0] = 16) and (Frame.Pixels[1] = 192) and
    (Frame.Pixels[2] = 32) and (Frame.Pixels[3] = 255) and
    (Frame.Pixels[4] = 220) and (Frame.Pixels[5] = 24) and
    (Frame.Pixels[6] = 80) and (Frame.Pixels[7] = 128), 'RGBA order changed');

  Capture.Arm(Target, 2);
  Capture.Take(1, Frame);
  Check(Length(Frame.Pixels) = 0, 'An old request was delivered again');
  Capture.Take(2, Frame);
  Check((Capture.Capture(@Video, Pixels) = 0) and (Reads = 1),
    'A cancelled request must not read a background');

  Capture.Arm(Target, 3);
  Obj.Width := 0;
  Check((Capture.Capture(@Video, Pixels) = 3) and (Reads = 1),
    'Invalid dimensions must complete without an image');
  Capture.Take(3, Frame);
  Check(Length(Frame.Pixels) = 0, 'Invalid dimensions returned stale pixels');
  Obj.Width := 1;

  Capture.Arm(Target, 4);
  Video.GetImageData := nil;
  Check((Capture.Capture(@Video, Pixels) = 4) and (Reads = 1),
    'Missing API must complete without an image');
  Capture.Take(4, Frame);
  Check(Length(Frame.Pixels) = 0, 'Missing API returned stale pixels');
  Video.GetImageData := ReadInput;

  Capture.Arm(Target, 5);
  ReplaceRequestDuringRead := True;
  Check((Capture.Capture(@Video, Pixels) = 0) and (Length(Pixels) = 8),
    'Superseded image must only be available to the current render');
  Check(Capture.Capture(@Video, Pixels) = 6, 'New request was lost');
  Capture.Take(6, Frame);
  Check((Reads = 3) and (Length(Frame.Pixels) = 8), 'Same-frame retry failed');
end;

begin
  Capture := TScreenLayoutFrameCapture.Create;
  try
    try
      RunCaptureTests;
      Writeln('PASS: one-shot input capture, target matching, cancellation and retry');
    except
      on E: Exception do
      begin
        Writeln(E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Capture.Free;
  end;
end.
