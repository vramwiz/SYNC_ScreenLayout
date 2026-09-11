program ScreenLayoutVariableWidthTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ScreenLayoutDocument,
  ScreenLayoutDocumentJson,
  ScreenLayoutEditHistory,
  ScreenLayoutEditorState,
  ScreenLayoutGroupCommands,
  ScreenLayoutRenderer,
  ScreenLayoutShapeCreation,
  TextRendererSkiaRuntime;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function ChangeWidthNumber(const Text: string; LayerIndex,
  PointIndex: Integer; const Name: string; Value: Double): string;
var
  Layers: TJSONArray;
  Pair: TJSONPair;
  Root: TJSONObject;
  WidthPoint: TJSONObject;
  WidthPoints: TJSONArray;
begin
  Root := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  try
    Check(Root <> nil, 'test JSON could not be parsed');
    Layers := Root.GetValue<TJSONArray>('layers');
    WidthPoints := TJSONObject(Layers.Items[LayerIndex]).GetValue<TJSONArray>(
      'widthPoints');
    WidthPoint := TJSONObject(WidthPoints.Items[PointIndex]);
    Pair := WidthPoint.RemovePair(Name);
    Check(Pair <> nil, 'width-point test field was missing');
    Pair.Free;
    WidthPoint.AddPair(Name, TJSONNumber.Create(Value));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure AddFreehand(Creation: TVectArtShapeCreation;
  PressureAvailable: Boolean);
begin
  Creation.SetInputPressure(0.2, PressureAvailable);
  Check(Creation.MouseDown(mbLeft, [], 20, 100),
    'freehand mouse down was not accepted');
  Creation.SetInputPressure(1.0, PressureAvailable);
  Check(Creation.MouseMove([ssLeft], 100, 100),
    'freehand mouse move was not accepted');
  Creation.SetInputPressure(0.2, PressureAvailable);
  Check(Creation.MouseUp(mbLeft, [], 180, 100),
    'freehand mouse up was not accepted');
end;

procedure Run;
var
  BeforeInvalid: string;
  Buffer: TVectArtRenderBuffer;
  Clone: TVectArtLayer;
  Creation: TVectArtShapeCreation;
  DefaultPath: TVectArtPathLayer;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  ErrorText: string;
  History: TVectArtEditHistory;
  Invalid: string;
  Loaded: TVectArtDocument;
  Path: TVectArtPathLayer;
  Saved: string;
  UniformPath: TVectArtPathLayer;
  WidthPoints: TArray<TScreenLayoutStrokeWidthPoint>;
begin
  Document := TVectArtDocument.Create;
  Loaded := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Creation := TVectArtShapeCreation.Create;
  Buffer := TVectArtRenderBuffer.Create;
  try
    Document.SetCanvasSize(200, 200);
    EditorState.CurrentTool := vetFreehand;
    EditorState.CreationColor := clBlack;
    EditorState.LineStrokeWidth := 40;
    EditorState.LineCap := vlcSquare;
    Check(EditorState.StrokeWidthMode = slwmUniform,
      'default stroke-width mode was not uniform');
    EditorState.StrokeWidthMode := slwmVariable;
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 200, 200), 1.0);

    AddFreehand(Creation, True);
    Check(Document[1] is TVectArtPathLayer,
      'pressure freehand did not create a path');
    Path := TVectArtPathLayer(Document[1]);
    WidthPoints := Path.WidthPoints;
    Check((Length(WidthPoints) = 3) and
      SameValue(WidthPoints[0].Offset, 0.0) and
      SameValue(WidthPoints[1].Offset, 0.5) and
      SameValue(WidthPoints[2].Offset, 1.0) and
      SameValue(WidthPoints[0].LeftScale, 0.2, 0.001) and
      SameValue(WidthPoints[1].LeftScale, 1.0, 0.001) and
      SameValue(WidthPoints[2].RightScale, 0.2, 0.001),
      'pressure samples were not stored as a width profile');

    AddFreehand(Creation, False);
    Check(Document[2] is TVectArtPathLayer,
      'non-pressure freehand did not create a path');
    UniformPath := TVectArtPathLayer(Document[2]);
    WidthPoints := UniformPath.WidthPoints;
    Check((Length(WidthPoints) = 2) and
      SameValue(WidthPoints[0].LeftScale, 1.0) and
      SameValue(WidthPoints[1].RightScale, 1.0),
      'variable mode without pressure did not create a uniform profile');

    EditorState.StrokeWidthMode := slwmUniform;
    AddFreehand(Creation, False);
    DefaultPath := TVectArtPathLayer(Document[3]);
    Check(Length(DefaultPath.WidthPoints) = 0,
      'uniform mode created a variable-width profile');

    History.Undo;
    History.Redo;
    DefaultPath := TVectArtPathLayer(Document[3]);
    Check(Length(DefaultPath.WidthPoints) = 0,
      'undo/redo changed the uniform path width mode');
    Path := TVectArtPathLayer(Document[1]);
    Check(Length(Path.WidthPoints) = 3,
      'undo/redo lost the pressure path width profile');

    Clone := CloneScreenLayoutLayer(Path, 'Pressure copy');
    try
      Check(Length(TVectArtPathLayer(Clone).WidthPoints) = 3,
        'path clone lost the width profile');
      WidthPoints := TVectArtPathLayer(Clone).WidthPoints;
      WidthPoints[1].LeftScale := 0.4;
      TVectArtPathLayer(Clone).WidthPoints := WidthPoints;
      Check(SameValue(Path.WidthPoints[1].LeftScale, 1.0, 0.001),
        'path clone shared its width-profile array');
    finally
      Clone.Free;
    end;

    UniformPath.Visible := False;
    DefaultPath.Visible := False;
    Saved := SerializeVectArtDocument(Document);
    Check(Pos('"widthPoints"', Saved) > 0,
      'width profile was omitted from JSON');
    Check(TryDeserializeVectArtDocument(Saved, Loaded, ErrorText), ErrorText);
    Path := TVectArtPathLayer(Loaded[1]);
    WidthPoints := Path.WidthPoints;
    Check((Length(WidthPoints) = 3) and
      SameValue(WidthPoints[1].LeftScale, 1.0, 0.001),
      'JSON round trip lost the width profile');
    Check(Length(TVectArtPathLayer(Loaded[2]).WidthPoints) = 2,
      'JSON round trip lost the non-pressure variable mode');
    Check(Length(TVectArtPathLayer(Loaded[3]).WidthPoints) = 0,
      'JSON round trip changed the uniform mode');

    BeforeInvalid := SerializeVectArtDocument(Loaded);
    Invalid := ChangeWidthNumber(Saved, 0, 1, 'offset', 0.0);
    Check(not TryDeserializeVectArtDocument(Invalid, Loaded, ErrorText),
      'unordered width points were accepted');
    Check(SerializeVectArtDocument(Loaded) = BeforeInvalid,
      'invalid width points replaced the current document');
    Invalid := ChangeWidthNumber(Saved, 0, 1, 'leftScale', 2.0);
    Check(not TryDeserializeVectArtDocument(Invalid, Loaded, ErrorText),
      'out-of-range width scale was accepted');
    Check(SerializeVectArtDocument(Loaded) = BeforeInvalid,
      'invalid width scale replaced the current document');

    RenderVectArtDocument(Loaded, Buffer, 200, 200);
    Check(Buffer.Pixels[115 * 200 + 100].A > 200,
      'variable-width center was not rendered at full width');
    Check(Buffer.Pixels[115 * 200 + 30].A < 20,
      'variable-width end was rendered as a uniform stroke');

    Path.Visible := False;
    DefaultPath := TVectArtPathLayer(Loaded[3]);
    DefaultPath.Visible := True;
    RenderVectArtDocument(Loaded, Buffer, 200, 200);
    Check(Buffer.Pixels[115 * 200 + 30].A > 200,
      'non-pressure path did not use the configured uniform width');
  finally
    Buffer.Free;
    Creation.Free;
    History.Free;
    EditorState.Free;
    Loaded.Free;
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
    Writeln('PASS variable width input, model, JSON, clone and rendering');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
