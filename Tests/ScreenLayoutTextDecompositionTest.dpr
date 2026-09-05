program ScreenLayoutTextDecompositionTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in
    '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutFilters in
    '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutTextDecompositionCommands in
    '..\Source\Core\Commands\Text\ScreenLayoutTextDecompositionCommands.pas',
  ScreenLayoutRenderer in
    '..\Source\Rendering\ScreenLayoutRenderer.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function NewTextData(const Text: string): TScreenLayoutTextData;
begin
  Result := Default(TScreenLayoutTextData);
  Result.Alignment := sltaMiddleRight;
  Result.Bounds := TRectF.Create(-120, -60, 120, 60);
  Result.FontFamily := 'Segoe UI';
  Result.FontSize := 32;
  Result.FontStyle := [fsBold];
  Result.LetterSpacingRatio := 0.1;
  Result.LineSpacingRatio := 0.25;
  Result.Name := 'Text';
  Result.Opacity := 0.75;
  Result.RotationDegrees := 30;
  Result.Text := Text;
  Result.TextColor := clWhite;
  Result.TransformMode := slttmFrameFit;
  Result.Visible := True;
  Result.WrapWidth := 200;
end;

procedure CheckCommonValues(Source, Piece: TScreenLayoutTextLayer);
begin
  Check(Piece.Alignment = Source.Alignment, 'alignment was not preserved');
  Check(Piece.FontFamily = Source.FontFamily, 'font family was not preserved');
  Check(Piece.FontSize = Source.FontSize, 'font size was not preserved');
  Check(Piece.FontStyle = Source.FontStyle, 'font style was not preserved');
  Check(Piece.LetterSpacingRatio = Source.LetterSpacingRatio,
    'letter spacing was not preserved');
  Check(Piece.LineSpacingRatio = Source.LineSpacingRatio,
    'line spacing was not preserved');
  Check(Piece.Opacity = Source.Opacity, 'opacity was not preserved');
  Check(Piece.RotationDegrees = Source.RotationDegrees,
    'rotation was not preserved');
  Check(Piece.TransformMode = Source.TransformMode,
    'transform mode was not preserved');
  Check(Piece.FillColor = Source.FillColor, 'text color was not preserved');
  Check(Piece.FilterCount = Source.FilterCount, 'filters were not copied');
  if Piece.FilterCount > 0 then
    Check(Piece.Filters[0] <> Source.Filters[0],
      'filter instance was shared with the source');
end;

function RenderDocument(Document: TVectArtDocument): TBytes;
var
  Buffer: TVectArtRenderBuffer;
begin
  Buffer := TVectArtRenderBuffer.Create;
  try
    RenderVectArtDocument(Document, Buffer, 400, 240);
    SetLength(Result, Buffer.PixelCount * SizeOf(TVectArtRgbaPixel));
    if Length(Result) > 0 then
      Move(Buffer.Data^, Result[0], Length(Result));
  finally
    Buffer.Free;
  end;
end;

function RenderAlphaBounds(Document: TVectArtDocument): TRect;
var
  Buffer: TVectArtRenderBuffer;
  I: Integer;
  X: Integer;
  Y: Integer;
begin
  Result := Rect(400, 240, -1, -1);
  Buffer := TVectArtRenderBuffer.Create;
  try
    RenderVectArtDocument(Document, Buffer, 400, 240);
    for I := 0 to Buffer.PixelCount - 1 do
      if Buffer.Pixels[I].A <> 0 then
      begin
        X := I mod Buffer.Width;
        Y := I div Buffer.Width;
        Result.Left := Min(Result.Left, X);
        Result.Top := Min(Result.Top, Y);
        Result.Right := Max(Result.Right, X + 1);
        Result.Bottom := Max(Result.Bottom, Y + 1);
      end;
  finally
    Buffer.Free;
  end;
end;

procedure TestRenderPositionPreservation;
var
  AfterPixels: TBytes;
  BeforePixels: TBytes;
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  State: TVectArtEditorState;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Document.SetCanvasSize(400, 240);
    Document.CanvasLayer.Transparent := True;
    Data := NewTextData('WIDE' + sLineBreak + 'I');
    Data.Bounds := TRectF.Create(-130, -70, 130, 70);
    Data.Opacity := 1;
    Document.InsertText(1, Data);
    Document.SelectedIndex := 1;
    BeforePixels := RenderDocument(Document);
    Check(ExecuteScreenLayoutTextDecomposition(Document, State, History,
      TScreenLayoutTextLayer(Document[1])),
      'render-parity decomposition failed');
    AfterPixels := RenderDocument(Document);
    Check((Length(BeforePixels) = Length(AfterPixels)) and
      CompareMem(@BeforePixels[0], @AfterPixels[0], Length(BeforePixels)),
      'decomposition changed rendered text placement');
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure TestMultipleLines;
var
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  Original: TScreenLayoutTextLayer;
  Piece1: TScreenLayoutTextLayer;
  Piece2: TScreenLayoutTextLayer;
  State: TVectArtEditorState;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Data := NewTextData('AB' + sLineBreak + 'CD');
    Document.InsertText(1, Data);
    Original := TScreenLayoutTextLayer(Document[1]);
    Original.AddFilter(TScreenLayoutOutlineFilter.Create);
    Document.SelectedIndex := 1;
    Check(ExecuteScreenLayoutTextDecomposition(Document, State, History,
      Original), 'multiple-line decomposition failed');
    Check(Document.LayerCount = 3, 'multiple-line piece count is wrong');
    Piece1 := TScreenLayoutTextLayer(Document[1]);
    Piece2 := TScreenLayoutTextLayer(Document[2]);
    Check(Piece1.Text = 'AB', 'first displayed line was not preserved');
    Check(Piece2.Text = 'CD', 'second displayed line was not preserved');
    CheckCommonValues(Original, Piece1);
    CheckCommonValues(Original, Piece2);
    Check(Document.SelectionCount = 2, 'line pieces were not selected');
    Check(not SameValue(Piece1.Bounds.Top, Piece2.Bounds.Top),
      'line pieces lost their separate positions');

    History.Undo;
    Check(Document.LayerCount = 2, 'line decomposition undo count is wrong');
    Check(Document[1] = Original, 'undo did not restore the source layer');
    Check(Document.SelectedIndex = 1, 'undo did not restore selection');
    History.Redo;
    Check(Document.LayerCount = 3, 'line decomposition redo count is wrong');
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure TestSingleLineCharacters;
var
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  State: TVectArtEditorState;
  Text: string;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Text := 'A' + #$D83D#$DE00 + 'B';
    Data := NewTextData(Text);
    Document.InsertText(1, Data);
    Document.SelectedIndex := 1;
    Check(ExecuteScreenLayoutTextDecomposition(Document, State, History,
      TScreenLayoutTextLayer(Document[1])),
      'single-line decomposition failed');
    Check(Document.LayerCount = 4, 'character piece count is wrong');
    Check(TScreenLayoutTextLayer(Document[1]).Text = 'A',
      'first character is wrong');
    Check(TScreenLayoutTextLayer(Document[2]).Text = #$D83D#$DE00,
      'surrogate pair was split');
    Check(TScreenLayoutTextLayer(Document[3]).Text = 'B',
      'last character is wrong');
    Check(TScreenLayoutTextLayer(Document[1]).Bounds.Left <
      TScreenLayoutTextLayer(Document[2]).Bounds.Left,
      'character positions are not ordered');
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure TestGroupChild;
var
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  Group: TScreenLayoutGroupLayer;
  History: TVectArtEditHistory;
  Original: TScreenLayoutTextLayer;
  State: TVectArtEditorState;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Data := NewTextData('Left' + sLineBreak + 'Right');
    Original := TScreenLayoutTextLayer.Create(Data.Name, Data.Bounds,
      Data.Text, Data.FontFamily, Data.FontSize, Data.WrapWidth,
      Data.TextColor);
    Group := TScreenLayoutGroupLayer.Create('Group');
    Group.AddChild(Original);
    Document.InsertLayer(1, Group);
    State.OpenGroup := Group;
    State.OpenGroupChild := Original;
    Check(ExecuteScreenLayoutTextDecomposition(Document, State, History,
      Original), 'group-child decomposition failed');
    Check(Group.ChildCount = 2, 'group-child piece count is wrong');
    Check(State.OpenGroupChildCount = 2,
      'group-child pieces were not selected');
    History.Undo;
    Check(Group.ChildCount = 1, 'group-child undo count is wrong');
    Check(Group[0] = Original, 'group-child undo did not restore source');
    Check(State.OpenGroupChild = Original,
      'group-child undo did not restore selection');
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure TestClosedPathShapes;
var
  AfterBounds: TRect;
  BeforeBounds: TRect;
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  I: Integer;
  Original: TScreenLayoutTextLayer;
  Shape: TScreenLayoutShapeLayer;
  State: TVectArtEditorState;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Data := NewTextData('A O');
    Document.InsertText(1, Data);
    Original := TScreenLayoutTextLayer(Document[1]);
    Original.AddFilter(TScreenLayoutOutlineFilter.Create);
    Document.SelectedIndex := 1;
    BeforeBounds := RenderAlphaBounds(Document);
    Check(ExecuteScreenLayoutTextDecomposition(Document, State, History,
      Original, sldkClosedPathShapes),
      'closed-path decomposition failed');
    Check(Document.LayerCount = 3,
      'space should not create a closed-path shape');
    for I := 1 to Document.LayerCount - 1 do
    begin
      Check(Document[I] is TScreenLayoutShapeLayer,
        'closed-path result is not a Shape layer');
      Shape := TScreenLayoutShapeLayer(Document[I]);
      Check(Shape.ContourCount > 0, 'glyph Shape has no closed contour');
      Check(Shape.FillRule = slfrEvenOdd,
        'glyph Shape does not use the Even-Odd fill rule');
      Check(Shape.FillColor = Original.FillColor,
        'glyph Shape did not preserve the text color');
      Check(Shape.Opacity = Original.Opacity,
        'glyph Shape did not preserve opacity');
      Check((Shape.FilterCount = 1) and
        (Shape.Filters[0] <> Original.Filters[0]),
        'glyph Shape did not clone the source filter');
    end;
    Check(Document.SelectionCount = 2,
      'closed-path Shapes were not selected');
    AfterBounds := RenderAlphaBounds(Document);
    Check((Abs(BeforeBounds.Left - AfterBounds.Left) <= 2) and
      (Abs(BeforeBounds.Top - AfterBounds.Top) <= 2) and
      (Abs(BeforeBounds.Right - AfterBounds.Right) <= 2) and
      (Abs(BeforeBounds.Bottom - AfterBounds.Bottom) <= 2),
      'closed-path Shapes did not preserve the rendered placement');
    History.Undo;
    Check((Document.LayerCount = 2) and (Document[1] = Original),
      'closed-path decomposition undo did not restore source');
    History.Redo;
    Check((Document.LayerCount = 3) and
      (Document[1] is TScreenLayoutShapeLayer),
      'closed-path decomposition redo failed');
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure Run;
begin
  TestMultipleLines;
  TestSingleLineCharacters;
  TestGroupChild;
  TestClosedPathShapes;
  TestRenderPositionPreservation;
end;

begin
  try
    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      Run;
      Writeln('PASS');
    finally
      TTextRendererSkiaRuntime.Release;
    end;
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
