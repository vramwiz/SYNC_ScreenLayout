// Shape輪郭とPath頂点列の置換をUndo／Redo履歴へ記録する。
unit ScreenLayoutShapeEditCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands;

type
  TScreenLayoutPathVerticesCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewVertices: TArray<TScreenLayoutVertex>;
    FOldVertices: TArray<TScreenLayoutVertex>;
    procedure ApplyVertices(const Vertices: TArray<TScreenLayoutVertex>);
  public
    // 適用済みPath編集の前後の頂点列を独立して保持する。
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldVertices, NewVertices: TArray<TScreenLayoutVertex>);
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
  ScreenLayoutPathOperations, ScreenLayoutShapeOperations;

procedure TScreenLayoutPathVerticesCommand.ApplyVertices(
  const Vertices: TArray<TScreenLayoutVertex>);
begin
  if FDocument <> nil then
    FDocument.SetPathVertices(FLayerIndex, Vertices);
end;

constructor TScreenLayoutPathVerticesCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer; const OldVertices,
  NewVertices: TArray<TScreenLayoutVertex>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldVertices := CloneScreenLayoutPathVertices(OldVertices);
  FNewVertices := CloneScreenLayoutPathVertices(NewVertices);
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
