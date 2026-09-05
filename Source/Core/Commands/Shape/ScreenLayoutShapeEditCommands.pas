// Shape輪郭とPath頂点列の置換をUndo／Redo履歴へ記録する。
unit ScreenLayoutShapeEditCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands;

// 共通のPath頂点更新を行い、必要な場合だけ文字パスの表示枠も追従させる。
procedure ApplyScreenLayoutPathVertices(Document: TVectArtDocument;
  LayerIndex: Integer; const Vertices: TArray<TScreenLayoutVertex>;
  UpdateTextPathBounds: Boolean = False);

type
  TScreenLayoutPathVerticesCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewVertices: TArray<TScreenLayoutVertex>;
    FOldVertices: TArray<TScreenLayoutVertex>;
    FUpdateTextPathBounds: Boolean;
    procedure ApplyVertices(const Vertices: TArray<TScreenLayoutVertex>);
  public
    // 適用済みPath編集の前後の頂点列を独立して保持する。
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldVertices, NewVertices: TArray<TScreenLayoutVertex>;
      UpdateTextPathBounds: Boolean = False);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutShapeContoursCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewContours: TArray<TScreenLayoutContour>;
    FOldContours: TArray<TScreenLayoutContour>;
    procedure ApplyContours(const Contours: TArray<TScreenLayoutContour>);
  public
    // 適用済み編集の前後の輪郭を独立して保持し、後続編集による配列共有を防ぐ。
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldContours, NewContours: TArray<TScreenLayoutContour>);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.Math, System.Types, ScreenLayoutGeometry,
  ScreenLayoutPathOperations, ScreenLayoutShapeOperations;

procedure ApplyScreenLayoutPathVertices(Document: TVectArtDocument;
  LayerIndex: Integer; const Vertices: TArray<TScreenLayoutVertex>;
  UpdateTextPathBounds: Boolean);
var
  Bounds: TRectF;
  Center: TPointF;
  LocalVertices: TArray<TScreenLayoutVertex>;
  TextPathLayer: TScreenLayoutTextPathLayer;
begin
  if Document = nil then
    Exit;
  Document.BeginUpdate;
  try
    Document.SetPathVertices(LayerIndex, Vertices);
    if UpdateTextPathBounds and (Length(Vertices) > 0) and
      (LayerIndex > 0) and (LayerIndex < Document.LayerCount) and
      (Document[LayerIndex] is TScreenLayoutTextPathLayer) then
    begin
      TextPathLayer := TScreenLayoutTextPathLayer(Document[LayerIndex]);
      if SameValue(TextPathLayer.RotationDegrees, 0.0) then
        Bounds := ScreenLayoutPathVerticesBounds(Vertices)
      else
      begin
        LocalVertices := RotateScreenLayoutPathVertices(Vertices,
          TPointF.Zero, -TextPathLayer.RotationDegrees);
        Bounds := ScreenLayoutPathVerticesBounds(LocalVertices);
      end;
      Bounds.Top := Bounds.Top - Max(TextPathLayer.FontSize, 1.0);
      if Bounds.Width < 1.0 then
        Bounds.Right := Bounds.Left + 1.0;
      if not SameValue(TextPathLayer.RotationDegrees, 0.0) then
      begin
        Center := RotatePointAround(Bounds.CenterPoint, TPointF.Zero,
          TextPathLayer.RotationDegrees);
        Bounds := TRectF.Create(Center.X - Bounds.Width * 0.5,
          Center.Y - Bounds.Height * 0.5,
          Center.X + Bounds.Width * 0.5,
          Center.Y + Bounds.Height * 0.5);
      end;
      TextPathLayer.Bounds := Bounds;
      TextPathLayer.WrapWidth := 0;
      Document.Changed;
    end;
  finally
    Document.EndUpdate;
  end;
end;

procedure TScreenLayoutPathVerticesCommand.ApplyVertices(
  const Vertices: TArray<TScreenLayoutVertex>);
begin
  if FDocument <> nil then
    ApplyScreenLayoutPathVertices(FDocument, FLayerIndex, Vertices,
      FUpdateTextPathBounds);
end;

constructor TScreenLayoutPathVerticesCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer; const OldVertices,
  NewVertices: TArray<TScreenLayoutVertex>;
  UpdateTextPathBounds: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldVertices := CloneScreenLayoutPathVertices(OldVertices);
  FNewVertices := CloneScreenLayoutPathVertices(NewVertices);
  FUpdateTextPathBounds := UpdateTextPathBounds;
end;

procedure TScreenLayoutPathVerticesCommand.Execute;
begin
  ApplyVertices(FNewVertices);
end;

procedure TScreenLayoutPathVerticesCommand.Undo;
begin
  ApplyVertices(FOldVertices);
end;

procedure TScreenLayoutShapeContoursCommand.ApplyContours(
  const Contours: TArray<TScreenLayoutContour>);
begin
  if FDocument <> nil then
    FDocument.SetShapeContours(FLayerIndex, Contours);
end;

constructor TScreenLayoutShapeContoursCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer; const OldContours,
  NewContours: TArray<TScreenLayoutContour>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldContours := CloneScreenLayoutShapeContours(OldContours);
  FNewContours := CloneScreenLayoutShapeContours(NewContours);
end;

procedure TScreenLayoutShapeContoursCommand.Execute;
begin
  ApplyContours(FNewContours);
end;

procedure TScreenLayoutShapeContoursCommand.Undo;
begin
  ApplyContours(FOldContours);
end;

end.
