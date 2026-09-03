program ScreenLayoutCanvasGuideTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  ScreenLayoutCanvasGuides in
    '..\Source\Rendering\ScreenLayoutCanvasGuides.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckPoint(const Actual, Expected: TPoint;
  const MessageText: string);
begin
  Check((Actual.X = Expected.X) and (Actual.Y = Expected.Y),
    Format('%s: expected (%d,%d), got (%d,%d)', [MessageText,
      Expected.X, Expected.Y, Actual.X, Actual.Y]));
end;

procedure TestCropMarksFollowDisplayedBounds;
var
  Points: TArray<TPoint>;
begin
  Points := BuildCanvasCropMarkPoints(Rect(100, 80, 500, 380));
  Check(Length(Points) = 16, 'four corners must produce eight segments');
  CheckPoint(Points[0], Point(80, 80), 'left mark start');
  CheckPoint(Points[1], Point(92, 80), 'left mark end');
  CheckPoint(Points[14], Point(499, 387), 'bottom-right mark start');
  CheckPoint(Points[15], Point(499, 399), 'bottom-right mark end');

  Points := BuildCanvasCropMarkPoints(Rect(40, 30, 240, 180));
  CheckPoint(Points[0], Point(20, 30), 'zoomed-out bounds mark start');
  CheckPoint(Points[1], Point(32, 30), 'zoomed-out bounds mark end');

  Points := BuildCanvasCropMarkPoints(Rect(-200, -100, 1400, 1100));
  CheckPoint(Points[0], Point(-220, -100), 'zoomed-in bounds mark start');
  CheckPoint(Points[1], Point(-208, -100), 'zoomed-in bounds mark end');
end;

procedure TestInvalidBoundsHaveNoMarks;
begin
  Check(Length(BuildCanvasCropMarkPoints(TRect.Empty)) = 0,
    'empty bounds must not produce marks');
end;

begin
  try
    TestCropMarksFollowDisplayedBounds;
    TestInvalidBoundsHaveNoMarks;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.Message);
      Halt(1);
    end;
  end;
end.
