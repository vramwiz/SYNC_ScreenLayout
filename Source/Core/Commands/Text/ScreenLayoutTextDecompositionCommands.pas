// 文字レイヤーを表示行または文字単位へ置換し、配置と所有権をUndo／Redo単位で管理する。
unit ScreenLayoutTextDecompositionCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands, ScreenLayoutEditHistory,
  ScreenLayoutEditorState;

type
  TScreenLayoutTextDecompositionKind = (sldkTextFragments,
    sldkClosedPathShapes);

  TScreenLayoutDecomposeTextCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FIndex: Integer;
    FOriginal: TScreenLayoutTextLayer;
    FOriginalInParent: Boolean;
    FParent: TScreenLayoutGroupLayer;
    FPieces: TArray<TVectArtLayer>;
    FPiecesInParent: Boolean;
    function ExtractLayer(Index: Integer): TVectArtLayer;
    function GetPieceCount: Integer;
    procedure InsertLayer(Index: Integer; Layer: TVectArtLayer);
    procedure SelectOriginal;
    procedure SelectPieces;
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AParent: TScreenLayoutGroupLayer;
      Index: Integer; Source: TScreenLayoutTextLayer;
      Kind: TScreenLayoutTextDecompositionKind);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
    property PieceCount: Integer read GetPieceCount;
  end;

// Layerを現在の親内で分解し、成功時は適用済みコマンドを履歴へ追加する。
function ExecuteScreenLayoutTextDecomposition(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; EditHistory: TVectArtEditHistory;
  Layer: TScreenLayoutTextLayer;
  Kind: TScreenLayoutTextDecompositionKind = sldkTextFragments): Boolean;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils, System.Types,
  System.Skia,
  ScreenLayoutFilters, ScreenLayoutGeometry, ScreenLayoutTextGeometry,
  ScreenLayoutTextOutlineGeometry;

function HorizontalAlignmentOffset(Alignment: TScreenLayoutTextAlignment;
  LayoutWidth, TextWidth: Single): Single;
begin
  case Ord(Alignment) mod 3 of
    1: Result := (LayoutWidth - TextWidth) * 0.5;
    2: Result := LayoutWidth - TextWidth;
  else
    Result := 0;
  end;
end;

function PositionedFragmentBounds(Source: TScreenLayoutTextLayer;
  const Layout: TScreenLayoutTextLayout; Left, Top, Width,
  Height: Single): TRectF;
var
  Center: TPointF;
  FragmentCenter: TPointF;
  ScaleX: Single;
  ScaleY: Single;
begin
  ScaleX := Source.Bounds.Width / Layout.Width;
  ScaleY := Source.Bounds.Height / Layout.Height;
  Center := TPointF.Create(
    (Source.Bounds.Left + Source.Bounds.Right) * 0.5,
    (Source.Bounds.Top + Source.Bounds.Bottom) * 0.5);
  FragmentCenter := TPointF.Create(
    Source.Bounds.Left + (Left + Width * 0.5) * ScaleX,
    Source.Bounds.Top + (Top + Height * 0.5) * ScaleY);
  FragmentCenter := RotatePointAround(FragmentCenter, Center,
    Source.RotationDegrees);
  Width := Width * ScaleX;
  Height := Height * ScaleY;
  Result := TRectF.Create(FragmentCenter.X - Width * 0.5,
    FragmentCenter.Y - Height * 0.5, FragmentCenter.X + Width * 0.5,
    FragmentCenter.Y + Height * 0.5);
end;

function CreateTextFragment(Source: TScreenLayoutTextLayer;
  const Text: string; const Bounds: TRectF; WrapWidth: Single;
  Number: Integer): TScreenLayoutTextLayer;
var
  I: Integer;
begin
  Result := TScreenLayoutTextLayer.Create(
    Format('%s %d', [Source.Name, Number]), Bounds, Text,
    Source.FontFamily, Source.FontSize, Max(WrapWidth, 1.0),
    Source.FillColor);
  Result.Alignment := Source.Alignment;
  Result.FontStyle := Source.FontStyle;
  Result.LetterSpacingRatio := Source.LetterSpacingRatio;
  Result.LineSpacingRatio := Source.LineSpacingRatio;
  Result.Locked := Source.Locked;
  Result.Opacity := Source.Opacity;
  Result.RotationDegrees := Source.RotationDegrees;
  Result.TransformMode := Source.TransformMode;
  Result.Visible := Source.Visible;
  for I := 0 to Source.FilterCount - 1 do
    Result.AddFilter(Source.Filters[I].Clone);
end;

function BuildTextFragments(Source: TScreenLayoutTextLayer):
  TArray<TVectArtLayer>;
var
  Bounds: TRectF;
  Font: ISkFont;
  Fragment: TScreenLayoutTextLayer;
  Fragments: TList<TVectArtLayer>;
  GapIndex: Integer;
  I: Integer;
  IndividualLetterSpacingRatios: TArray<Single>;
  Layout: TScreenLayoutTextLayout;
  Left: Single;
  LetterSpacing: Single;
  LineText: string;
  TextWidth: Single;
  UnitLength: Integer;
  UnitText: string;
begin
  Result := nil;
  if (Source = nil) or (Source.Text = '') then
    Exit;
  IndividualLetterSpacingRatios :=
    Source.IndividualLetterSpacingRatios;
  Layout := BuildScreenLayoutTextLayout(Source.Text, Source.FontFamily,
    Source.FontSize, Source.WrapWidth, Source.FontStyle,
    Source.LetterSpacingRatio, Source.LineSpacingRatio,
    IndividualLetterSpacingRatios);
  if (Layout.Width <= 0) or (Layout.Height <= 0) then
    Exit;
  Font := CreateScreenLayoutTextFont(Source.FontFamily, Source.FontSize,
    Source.FontStyle);
  LetterSpacing := Source.FontSize * Source.LetterSpacingRatio;
  Fragments := TList<TVectArtLayer>.Create;
  try
    if Length(Layout.Lines) > 1 then
    begin
      for I := 0 to High(Layout.Lines) do
      begin
        LineText := Layout.Lines[I];
        if LineText = '' then
          Continue;
        TextWidth := MeasureScreenLayoutText(LineText, Font, LetterSpacing,
          Source.FontSize, IndividualLetterSpacingRatios,
          Layout.LineGapOffsets[I]);
        Left := HorizontalAlignmentOffset(Source.Alignment, Layout.Width,
          TextWidth);
        Bounds := PositionedFragmentBounds(Source, Layout, Left,
          I * Layout.LineHeight, TextWidth, Layout.LineHeight);
        Fragment := CreateTextFragment(Source, LineText, Bounds, TextWidth,
          Fragments.Count + 1);
        Fragments.Add(Fragment);
      end;
    end
    else
    begin
      LineText := Layout.Lines[0];
      GapIndex := Layout.LineGapOffsets[0];
      TextWidth := MeasureScreenLayoutText(LineText, Font, LetterSpacing,
        Source.FontSize, IndividualLetterSpacingRatios, GapIndex);
      Left := HorizontalAlignmentOffset(Source.Alignment, Layout.Width,
        TextWidth);
      I := 1;
      while I <= Length(LineText) do
      begin
        UnitLength := ScreenLayoutTextUnitLengthAt(LineText, I);
        UnitText := Copy(LineText, I, UnitLength);
        TextWidth := Font.MeasureText(UnitText);
        Bounds := PositionedFragmentBounds(Source, Layout, Left, 0,
          TextWidth, Layout.LineHeight);
        Fragment := CreateTextFragment(Source, UnitText, Bounds, TextWidth,
          Fragments.Count + 1);
        Fragments.Add(Fragment);
        Left := Left + TextWidth;
        Inc(I, UnitLength);
        if I <= Length(LineText) then
        begin
          Left := Left + LetterSpacing;
          if GapIndex < Length(IndividualLetterSpacingRatios) then
            Left := Left + Source.FontSize *
              IndividualLetterSpacingRatios[GapIndex];
          Inc(GapIndex);
        end;
      end;
    end;
    Result := Fragments.ToArray;
  finally
    Fragments.Free;
  end;
end;

function BuildClosedPathShapeFragments(Source: TScreenLayoutTextLayer):
  TArray<TVectArtLayer>;
var
  Data: TScreenLayoutShapeData;
  I: Integer;
  J: Integer;
  ShapeData: TArray<TScreenLayoutShapeData>;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  ShapeData := BuildScreenLayoutTextOutlineShapes(Source);
  SetLength(Result, Length(ShapeData));
  for I := 0 to High(ShapeData) do
  begin
    Data := ShapeData[I];
    ShapeLayer := TScreenLayoutShapeLayer.Create(Data.Name, Data.Contours);
    ShapeLayer.FillColor := Data.FillColor;
    ShapeLayer.FillRule := Data.FillRule;
    ShapeLayer.Locked := Data.Locked;
    ShapeLayer.Opacity := Data.Opacity;
    ShapeLayer.PaintStyle := Source.PaintStyle;
    ShapeLayer.StrokeColor := Data.StrokeColor;
    ShapeLayer.StrokeStyle := Data.StrokeStyle;
    ShapeLayer.StrokeWidth := Data.StrokeWidth;
    ShapeLayer.Visible := Data.Visible;
    for J := 0 to Source.FilterCount - 1 do
      ShapeLayer.AddFilter(Source.Filters[J].Clone);
    Result[I] := ShapeLayer;
  end;
end;

constructor TScreenLayoutDecomposeTextCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AParent: TScreenLayoutGroupLayer; Index: Integer;
  Source: TScreenLayoutTextLayer; Kind: TScreenLayoutTextDecompositionKind);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FParent := AParent;
  FIndex := Index;
  FOriginal := Source;
  FOriginalInParent := True;
  case Kind of
    sldkTextFragments:
      FPieces := BuildTextFragments(Source);
    sldkClosedPathShapes:
      FPieces := BuildClosedPathShapeFragments(Source);
  end;
end;

destructor TScreenLayoutDecomposeTextCommand.Destroy;
var
  Piece: TVectArtLayer;
begin
  if not FOriginalInParent then
    FOriginal.Free;
  if not FPiecesInParent then
    for Piece in FPieces do
      Piece.Free;
  inherited Destroy;
end;

procedure TScreenLayoutDecomposeTextCommand.Execute;
var
  I: Integer;
begin
  if (FDocument = nil) or (Length(FPieces) = 0) then
    Exit;
  FDocument.BeginUpdate;
  try
    FOriginal := TScreenLayoutTextLayer(ExtractLayer(FIndex));
    FOriginalInParent := False;
    for I := 0 to High(FPieces) do
      InsertLayer(FIndex + I, FPieces[I]);
    FPiecesInParent := True;
    if FParent <> nil then
      FDocument.Changed;
    FEditorState.ValidateSelectedFilter(FDocument);
    SelectPieces;
  finally
    FDocument.EndUpdate;
  end;
end;

function TScreenLayoutDecomposeTextCommand.ExtractLayer(
  Index: Integer): TVectArtLayer;
begin
  if FParent <> nil then
    Result := FParent.ExtractChild(Index)
  else
    Result := FDocument.ExtractLayer(Index);
end;

function TScreenLayoutDecomposeTextCommand.GetPieceCount: Integer;
begin
  Result := Length(FPieces);
end;

procedure TScreenLayoutDecomposeTextCommand.InsertLayer(Index: Integer;
  Layer: TVectArtLayer);
begin
  if FParent <> nil then
    FParent.InsertChild(Index, Layer)
  else
    FDocument.InsertLayer(Index, Layer);
end;

procedure TScreenLayoutDecomposeTextCommand.SelectOriginal;
begin
  if FParent <> nil then
  begin
    FDocument.SetSelectedLayers([]);
    FEditorState.SetOpenGroupChildren([FOriginal]);
  end
  else
    FDocument.SetSelectedLayers([FIndex]);
end;

procedure TScreenLayoutDecomposeTextCommand.SelectPieces;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  if FParent <> nil then
  begin
    FDocument.SetSelectedLayers([]);
    FEditorState.SetOpenGroupChildren(FPieces);
  end
  else
  begin
    SetLength(Indices, Length(FPieces));
    for I := 0 to High(Indices) do
      Indices[I] := FIndex + I;
    FDocument.SetSelectedLayers(Indices);
  end;
end;

procedure TScreenLayoutDecomposeTextCommand.Undo;
var
  I: Integer;
begin
  if (FDocument = nil) or not FPiecesInParent then
    Exit;
  FDocument.BeginUpdate;
  try
    for I := High(FPieces) downto 0 do
      ExtractLayer(FIndex + I);
    FPiecesInParent := False;
    InsertLayer(FIndex, FOriginal);
    FOriginalInParent := True;
    if FParent <> nil then
      FDocument.Changed;
    FEditorState.ValidateSelectedFilter(FDocument);
    SelectOriginal;
  finally
    FDocument.EndUpdate;
  end;
end;

function FindLayerIndex(Document: TVectArtDocument;
  Parent: TScreenLayoutGroupLayer; Layer: TVectArtLayer): Integer;
var
  I: Integer;
begin
  if Parent <> nil then
  begin
    for I := 0 to Parent.ChildCount - 1 do
      if Parent[I] = Layer then
        Exit(I);
  end
  else if Document <> nil then
  begin
    for I := 1 to Document.LayerCount - 1 do
      if Document[I] = Layer then
        Exit(I);
  end;
  Result := -1;
end;

function ExecuteScreenLayoutTextDecomposition(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; EditHistory: TVectArtEditHistory;
  Layer: TScreenLayoutTextLayer;
  Kind: TScreenLayoutTextDecompositionKind): Boolean;
var
  Command: TScreenLayoutDecomposeTextCommand;
  Index: Integer;
  Parent: TScreenLayoutGroupLayer;
begin
  Result := False;
  if (Document = nil) or (EditorState = nil) or (Layer = nil) or
    Layer.Locked then
    Exit;
  Parent := nil;
  if (EditorState.OpenGroup <> nil) and
    EditorState.IsOpenGroupChildSelected(Layer) then
    Parent := EditorState.OpenGroup;
  Index := FindLayerIndex(Document, Parent, Layer);
  if Index < 0 then
    Exit;
  Command := TScreenLayoutDecomposeTextCommand.Create(Document,
    EditorState, Parent, Index, Layer, Kind);
  if Command.PieceCount = 0 then
  begin
    Command.Free;
    Exit;
  end;
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
  Result := True;
end;

end.
