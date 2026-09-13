// 全レイヤー共通の反転、複数選択軸、履歴、保存復元を検証する。
program ScreenLayoutLayerFlipTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutGroupCommands in
    '..\Source\Core\Commands\Layer\Group\ScreenLayoutGroupCommands.pas',
  ScreenLayoutLayerFlipOperations in
    '..\Source\Core\Commands\Layer\Transform\ScreenLayoutLayerFlipOperations.pas',
  ScreenLayoutTextOutlineGeometry in
    '..\Source\Core\Geometry\Text\ScreenLayoutTextOutlineGeometry.pas',
  ScreenLayoutDocumentJson in
    '..\Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutPaintStyles in
    '..\Source\Core\Model\ScreenLayoutPaintStyles.pas',
  ScreenLayoutPatternStyle in
    '..\Source\Core\Model\Pattern\ScreenLayoutPatternStyle.pas',
  ScreenLayoutTextureStyle in
    '..\Source\Core\Model\ScreenLayoutTextureStyle.pas',
  ScreenLayoutRenderer in
    '..\Source\Rendering\ScreenLayoutRenderer.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
end;

procedure CheckSame(A, B: Single; const MessageText: string);
begin
  Check(SameValue(A, B, 0.0001), MessageText);
end;

procedure CheckTextRenderMirror;
const
  SIZE = 200;
var
  AfterBuffer: TVectArtRenderBuffer;
  BeforeBuffer: TVectArtRenderBuffer;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  State: TVectArtEditorState;
  TextLayer: TScreenLayoutTextLayer;
  AfterShapes: TArray<TScreenLayoutShapeData>;
  BeforeShapes: TArray<TScreenLayoutShapeData>;
  BeforeLeft, BeforeRight, AfterLeft, AfterRight: Integer;
  AfterAlpha, AfterWeightedX: Int64;
  BeforeAlpha, BeforeWeightedX: Int64;
  X: Integer;
  Y: Integer;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  BeforeBuffer := TVectArtRenderBuffer.Create;
  AfterBuffer := TVectArtRenderBuffer.Create;
  try
    Document.SetCanvasSize(SIZE, SIZE);
    TextLayer := TScreenLayoutTextLayer.Create('Text',
      TRectF.Create(-70, -25, 70, 25), 'Mirror', 'Segoe UI', 32, 140,
      clWhite);
    Document.InsertLayer(1, TextLayer);
    Document.SelectedIndex := 1;
    BeforeShapes := BuildScreenLayoutTextOutlineShapes(TextLayer);
    RenderVectArtDocument(Document, BeforeBuffer, SIZE, SIZE);
    FlipScreenLayoutSelection(Document, History, State, slfdHorizontal);
    AfterShapes := BuildScreenLayoutTextOutlineShapes(TextLayer);
    Check((Length(BeforeShapes) > 0) and
      (Length(AfterShapes) = Length(BeforeShapes)),
      'text outline reflection changed the glyph count');
    CheckSame(BeforeShapes[0].Contours[0].Vertices[0].Position.X +
      AfterShapes[0].Contours[0].Vertices[0].Position.X,
      TextLayer.Bounds.Left + TextLayer.Bounds.Right,
      'text outline geometry was not reflected');
    RenderVectArtDocument(Document, AfterBuffer, SIZE, SIZE);
    BeforeLeft := SIZE;
    BeforeRight := -1;
    AfterLeft := SIZE;
    AfterRight := -1;
    BeforeAlpha := 0;
    BeforeWeightedX := 0;
    AfterAlpha := 0;
    AfterWeightedX := 0;
    for Y := 0 to SIZE - 1 do
      for X := 0 to SIZE - 1 do
      begin
        if BeforeBuffer.Pixels[Y * SIZE + X].A > 0 then
        begin
          BeforeLeft := Min(BeforeLeft, X);
          BeforeRight := Max(BeforeRight, X);
          Inc(BeforeAlpha, BeforeBuffer.Pixels[Y * SIZE + X].A);
          Inc(BeforeWeightedX,
            Int64(X) * BeforeBuffer.Pixels[Y * SIZE + X].A);
        end;
        if AfterBuffer.Pixels[Y * SIZE + X].A > 0 then
        begin
          AfterLeft := Min(AfterLeft, X);
          AfterRight := Max(AfterRight, X);
          Inc(AfterAlpha, AfterBuffer.Pixels[Y * SIZE + X].A);
          Inc(AfterWeightedX,
            Int64(X) * AfterBuffer.Pixels[Y * SIZE + X].A);
        end;
      end;
    Check((BeforeLeft = SIZE - 1 - AfterRight) and
      (BeforeRight = SIZE - 1 - AfterLeft),
      Format('text bounds were not mirrored: %d..%d <> %d..%d',
        [BeforeLeft, BeforeRight, AfterLeft, AfterRight]));
    Check(Abs(BeforeAlpha - AfterAlpha) <= BeforeAlpha div 20,
      Format('text reflection changed total coverage: %d <> %d',
        [BeforeAlpha, AfterAlpha]));
    Check(Abs((BeforeWeightedX * AfterAlpha +
      AfterWeightedX * BeforeAlpha) -
      Int64(SIZE - 1) * BeforeAlpha * AfterAlpha) <=
      Int64(BeforeAlpha) * AfterAlpha div 4,
      Format('text reflection center mismatch: %.3f + %.3f',
        [BeforeWeightedX / BeforeAlpha, AfterWeightedX / AfterAlpha]));
  finally
    AfterBuffer.Free;
    BeforeBuffer.Free;
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure Run;
var
  Arc: TScreenLayoutArcLayer;
  BeforeJson: string;
  ChangedJson: string;
  Document: TVectArtDocument;
  ErrorText: string;
  Group: TScreenLayoutGroupLayer;
  GroupChildA: TVectArtRectangleLayer;
  GroupChildB: TVectArtRectangleLayer;
  History: TVectArtEditHistory;
  Loaded: TVectArtDocument;
  Path: TVectArtPathLayer;
  RectangleA: TVectArtRectangleLayer;
  RectangleB: TVectArtRectangleLayer;
  Rounded: TScreenLayoutRoundedRectangleLayer;
  Radii: TScreenLayoutCornerRadii;
  Shadow: TScreenLayoutShadowFilter;
  State: TVectArtEditorState;
  Style: TScreenLayoutPaintStyle;
  TextLayer: TScreenLayoutTextLayer;
  Texture: TScreenLayoutTextureStyle;
  Pattern: TScreenLayoutPatternStyle;
  Vertices: TArray<TScreenLayoutVertex>;
  WidthPoints: TArray<TScreenLayoutStrokeWidthPoint>;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  Loaded := TVectArtDocument.Create;
  try
    Document.SetCanvasSize(400, 300);
    RectangleA := TVectArtRectangleLayer.Create('A',
      TRectF.Create(-80, -20, -40, 20), clRed);
    Style := TScreenLayoutPaintStyle.Solid(clRed);
    Style.PrepareLinearGradient(clRed);
    Style.PreparePattern;
    Style.PrepareTexture;
    Style.Kind := slpkGradient;
    Style.LinearStart := TPointF.Create(0.1, 0.2);
    Style.LinearEnd := TPointF.Create(0.8, 0.9);
    RectangleA.PaintStyle := Style;
    Shadow := TScreenLayoutShadowFilter.Create;
    Shadow.OffsetX := 7;
    Shadow.OffsetY := 9;
    RectangleA.AddFilter(Shadow);
    RectangleB := TVectArtRectangleLayer.Create('B',
      TRectF.Create(20, -10, 80, 10), clBlue);
    Document.InsertLayer(1, RectangleA);
    Document.InsertLayer(2, RectangleB);
    Document.SetSelectedLayers([1, 2]);
    BeforeJson := SerializeVectArtDocument(Document);
    FlipScreenLayoutSelection(Document, History, State, slfdHorizontal);
    CheckSame(RectangleA.Bounds.CenterPoint.X, 60,
      'first rectangle did not cross the selection center');
    CheckSame(RectangleB.Bounds.CenterPoint.X, -50,
      'second rectangle did not cross the selection center');
    Style := RectangleA.PaintStyle;
    CheckSame(Style.LinearStart.X, 0.9, 'gradient start was not reflected');
    CheckSame(Style.LinearEnd.X, 0.2, 'gradient end was not reflected');
    Pattern := Style.Pattern;
    Texture := Style.Texture;
    Check(Pattern.FlipHorizontal, 'pattern reflection was not retained');
    Check(Texture.FlipHorizontal, 'texture reflection was not retained');
    CheckSame(TScreenLayoutShadowFilter(RectangleA.Filters[0]).OffsetX,
      -7, 'shadow offset was not reflected');
    ChangedJson := SerializeVectArtDocument(Document);
    History.Undo;
    Check(SerializeVectArtDocument(Document) = BeforeJson,
      'Undo did not restore exact serialized values');
    History.Redo;
    Check(SerializeVectArtDocument(Document) = ChangedJson,
      'Redo did not restore exact serialized values');

    Document.SetSelectedLayers([1]);
    FlipScreenLayoutSelection(Document, History, State, slfdHorizontal);
    Style := RectangleA.PaintStyle;
    Pattern := Style.Pattern;
    Texture := Style.Texture;
    Check(not Pattern.FlipHorizontal, 'second pattern flip did not cancel');
    Check(not Texture.FlipHorizontal, 'second texture flip did not cancel');

    Radii.TopLeft := 1;
    Radii.TopRight := 2;
    Radii.BottomRight := 3;
    Radii.BottomLeft := 4;
    Rounded := TScreenLayoutRoundedRectangleLayer.Create('Rounded',
      TRectF.Create(-20, -20, 20, 20), clGreen, Radii);
    Document.InsertLayer(3, Rounded);
    Document.SelectedIndex := 3;
    FlipScreenLayoutSelection(Document, History, State, slfdVertical);
    CheckSame(Rounded.CornerRadii.TopLeft, 4,
      'top-left radius was not vertically reflected');
    CheckSame(Rounded.CornerRadii.BottomRight, 2,
      'bottom-right radius was not vertically reflected');

    Arc := TScreenLayoutArcLayer.Create('Arc',
      TRectF.Create(-30, -10, 30, 10));
    Arc.StartAngleDegrees := 25;
    Arc.SweepAngleDegrees := 120;
    Arc.RotationDegrees := 15;
    Document.InsertLayer(4, Arc);
    Document.SelectedIndex := 4;
    FlipScreenLayoutSelection(Document, History, State, slfdHorizontal);
    CheckSame(Arc.StartAngleDegrees, 35, 'arc start angle was not reflected');
    CheckSame(Arc.SweepAngleDegrees, 120, 'arc sweep changed during reflection');
    CheckSame(Arc.RotationDegrees, -15, 'arc rotation was not reflected');

    SetLength(Vertices, 2);
    Vertices[0].Position := TPointF.Create(-20, -5);
    Vertices[0].OutgoingControl := TPointF.Create(4, 6);
    Vertices[1].Position := TPointF.Create(40, 15);
    Vertices[1].IncomingControl := TPointF.Create(-3, -7);
    Path := TVectArtPathLayer.Create('Path', Vertices, False);
    SetLength(WidthPoints, 2);
    WidthPoints[0].Offset := 0;
    WidthPoints[0].LeftScale := 0.25;
    WidthPoints[0].RightScale := 0.75;
    WidthPoints[1].Offset := 1;
    WidthPoints[1].LeftScale := 0.5;
    WidthPoints[1].RightScale := 1;
    Path.WidthPoints := WidthPoints;
    Document.InsertLayer(5, Path);
    Document.SelectedIndex := 5;
    FlipScreenLayoutSelection(Document, History, State, slfdHorizontal);
    Vertices := Path.Vertices;
    CheckSame(Vertices[0].Position.X, 40, 'path position was not reflected');
    CheckSame(Vertices[1].Position.X, -20, 'path end was not reflected');
    CheckSame(Vertices[0].OutgoingControl.X, -4,
      'path control vector was not reflected');
    WidthPoints := Path.WidthPoints;
    CheckSame(WidthPoints[0].LeftScale, 0.75,
      'path left width was not swapped during reflection');
    CheckSame(WidthPoints[1].RightScale, 0.5,
      'path right width was not swapped during reflection');

    TextLayer := TScreenLayoutTextLayer.Create('Text',
      TRectF.Create(-60, -15, 60, 15), 'Mirror', 'Segoe UI', 24, 120,
      clWhite);
    TextLayer.RotationDegrees := 20;
    Document.InsertLayer(6, TextLayer);
    Document.SelectedIndex := 6;
    FlipScreenLayoutSelection(Document, History, State, slfdHorizontal);
    Check(TextLayer.FlipHorizontal, 'text glyph reflection was not retained');
    CheckSame(TextLayer.RotationDegrees, -20,
      'text rotation was not reflected');
    ChangedJson := SerializeVectArtDocument(Document);
    Check(TryDeserializeVectArtDocument(ChangedJson, Loaded, ErrorText),
      'flipped JSON was rejected: ' + ErrorText);
    Check((Loaded[6] is TScreenLayoutTextLayer) and
      Loaded[6].FlipHorizontal, 'text reflection was lost in JSON');
    Style := Loaded[1].PaintStyle;
    Check(Style.Pattern.FlipHorizontal =
      Document[1].PaintStyle.Pattern.FlipHorizontal,
      'pattern reflection was lost in JSON');

    Group := TScreenLayoutGroupLayer.Create('Group');
    GroupChildA := TVectArtRectangleLayer.Create('Child A',
      TRectF.Create(-40, 40, -20, 60), clRed);
    GroupChildB := TVectArtRectangleLayer.Create('Child B',
      TRectF.Create(20, 80, 40, 100), clBlue);
    Group.AddChild(GroupChildA);
    Group.AddChild(GroupChildB);
    Document.InsertLayer(7, Group);
    State.OpenGroupInDocument(Document, Group);
    State.SetOpenGroupChildren([GroupChildA, GroupChildB]);
    Check(CanFlipScreenLayoutSelection(Document, State),
      'open-group selection was not flippable');
    FlipScreenLayoutSelection(Document, History, State, slfdVertical);
    CheckSame(GroupChildA.Bounds.CenterPoint.Y, 90,
      'first group child did not cross the shared axis');
    CheckSame(GroupChildB.Bounds.CenterPoint.Y, 50,
      'second group child did not cross the shared axis');
    GroupChildB.Locked := True;
    Check(not CanFlipScreenLayoutSelection(Document, State),
      'mixed locked open-group selection was enabled');
  finally
    Loaded.Free;
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

begin
  try
    TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0)) +
      'sk4d.dll');
    try
      Run;
      CheckTextRenderMirror;
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    Writeln('ScreenLayoutLayerFlipTest: OK');
  except
    on E: Exception do
    begin
      Writeln('ScreenLayoutLayerFlipTest: FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
