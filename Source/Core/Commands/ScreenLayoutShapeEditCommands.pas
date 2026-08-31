// Shape輪郭の置換をUndo／Redo履歴へ記録する専用コマンドを提供する。
unit ScreenLayoutShapeEditCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands;

type
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
  ScreenLayoutShapeOperations;

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
