program ScreenLayoutPathWidthInteractionTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  ScreenLayoutDocument,
  ScreenLayoutEditHistory,
  ScreenLayoutPathInteraction;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Data: TVectArtPathData;
  Document: TVectArtDocument;
  Handles: TArray<TScreenLayoutPathWidthHandle>;
  History: TVectArtEditHistory;
  Interaction: TScreenLayoutPathInteraction;
  Path: TVectArtPathLayer;
  Target: TPoint;
  WidthPoints: TArray<TScreenLayoutStrokeWidthPoint>;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TScreenLayoutPathInteraction.Create;
  try
    Document.SetCanvasSize(200, 200);
    Data := Default(TVectArtPathData);
    SetLength(Data.Vertices, 2);
    Data.Vertices[0].Position := TPointF.Create(-80, 0);
    Data.Vertices[0].OutgoingSegment := slskLine;
    Data.Vertices[1].Position := TPointF.Create(80, 0);
    Data.WidthPoints := UniformScreenLayoutStrokeWidthPoints;
    Data.Name := 'Variable path';
    Data.Opacity := 1;
    Data.StrokeWidth := 40;
    Data.Visible := True;
    Document.InsertPath(1, Data);
    Document.SelectedIndex := 1;
    Path := TVectArtPathLayer(Document[1]);
    Interaction.Configure(Document, History, Rect(0, 0, 200, 200), 1.0);

    Handles := Interaction.SelectedWidthHandles;
    Check(Length(Handles) = 2,
      'variable path did not expose its endpoint width handles');
    Check(Interaction.BeginWidthHandleDragAt(Handles[0].LeftPoint.X,
      Handles[0].LeftPoint.Y), 'left width handle was not draggable');
    Target := Point((Handles[0].CenterPoint.X + Handles[0].LeftPoint.X) div 2,
      (Handles[0].CenterPoint.Y + Handles[0].LeftPoint.Y) div 2);
    Check(Interaction.DragWidthTo(Target.X, Target.Y),
      'width-handle drag was not applied');
    Interaction.CommitDrag;
    WidthPoints := Path.WidthPoints;
    Check(SameValue(WidthPoints[0].LeftScale, 0.5, 0.06) and
      SameValue(WidthPoints[0].RightScale, 1.0, 0.001),
      'left width drag changed the wrong side or scale');
    Check(History.CanUndo, 'width drag did not create Undo history');
    History.Undo;
    Check(SameValue(Path.WidthPoints[0].LeftScale, 1.0, 0.001),
      'width drag Undo did not restore the scale');
    History.Redo;

    Check(Interaction.InsertWidthPointAt(100, 100),
      'center-line width point was not inserted');
    WidthPoints := Path.WidthPoints;
    Check((Length(WidthPoints) = 3) and
      SameValue(WidthPoints[1].Offset, 0.5, 0.02),
      'inserted width point has the wrong normalized offset');
    Handles := Interaction.SelectedWidthHandles;
    Check(Interaction.DeleteWidthPointAt(Handles[1].CenterPoint.X,
      Handles[1].CenterPoint.Y), 'interior width point was not deleted');
    Check(Length(Path.WidthPoints) = 2,
      'width-point deletion left the profile unchanged');
    History.Undo;
    Check(Length(Path.WidthPoints) = 3,
      'width-point deletion Undo did not restore the point');
  finally
    Interaction.Free;
    History.Free;
    Document.Free;
  end;
end;

begin
  try
    Run;
    Writeln('PASS variable-width handles, insert, delete and Undo/Redo');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
