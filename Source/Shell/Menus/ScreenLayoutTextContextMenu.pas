// 文字オブジェクト固有の右クリック項目を提供し、処理本体からメニュー構成を分離する。
unit ScreenLayoutTextContextMenu;

interface

uses
  System.Classes, ScreenLayoutEditHistory, ScreenLayoutObjectContextMenu,
  ScreenLayoutTextDecompositionCommands;

type
  TScreenLayoutTextMenuContributor = class(
    TScreenLayoutObjectMenuContributor)
  private
    FContext: TScreenLayoutObjectMenuContext;
    FContextMenu: TScreenLayoutObjectContextMenu;
    FEditHistory: TVectArtEditHistory;
    procedure DecomposeAsClosedPathsClick(Sender: TObject);
    procedure DecomposeAsTextClick(Sender: TObject);
    procedure ExecuteDecomposition(Kind: TScreenLayoutTextDecompositionKind);
  public
    constructor Create(ContextMenu: TScreenLayoutObjectContextMenu;
      EditHistory: TVectArtEditHistory);
    // 単一の文字オブジェクトが選択されている場合だけ文字専用項目を提供する。
    function AppliesTo(const Context: TScreenLayoutObjectMenuContext): Boolean;
      override;
    // 文字レイヤーまたは閉じたパス図形へ分解するサブメニューを追加する。
    procedure BuildMenu(const Context: TScreenLayoutObjectMenuContext;
      Builder: TScreenLayoutObjectMenuBuilder); override;
  end;

implementation

uses
  ScreenLayoutDocument;

constructor TScreenLayoutTextMenuContributor.Create(
  ContextMenu: TScreenLayoutObjectContextMenu;
  EditHistory: TVectArtEditHistory);
begin
  inherited Create;
  FContextMenu := ContextMenu;
  FEditHistory := EditHistory;
end;

function TScreenLayoutTextMenuContributor.AppliesTo(
  const Context: TScreenLayoutObjectMenuContext): Boolean;
begin
  Result := Context.SingleLayer is TScreenLayoutTextLayer;
end;

procedure TScreenLayoutTextMenuContributor.BuildMenu(
  const Context: TScreenLayoutObjectMenuContext;
  Builder: TScreenLayoutObjectMenuBuilder);
var
  DecomposeMenu: TScreenLayoutObjectMenuBuilder;
begin
  FContext := Context;
  DecomposeMenu := Builder.AddSubMenu('テキストの分解', 208);
  DecomposeMenu.AddItem('行／文字へ分解', DecomposeAsTextClick,
    not Context.SingleLayer.Locked);
  DecomposeMenu.AddItem('閉じたパス図形へ分解',
    DecomposeAsClosedPathsClick, not Context.SingleLayer.Locked);
end;

procedure TScreenLayoutTextMenuContributor.DecomposeAsClosedPathsClick(
  Sender: TObject);
begin
  ExecuteDecomposition(sldkClosedPathShapes);
end;

procedure TScreenLayoutTextMenuContributor.DecomposeAsTextClick(
  Sender: TObject);
begin
  ExecuteDecomposition(sldkTextFragments);
end;

procedure TScreenLayoutTextMenuContributor.ExecuteDecomposition(
  Kind: TScreenLayoutTextDecompositionKind);
var
  Layer: TVectArtLayer;
begin
  Layer := FContext.SingleLayer;
  if not (Layer is TScreenLayoutTextLayer) then
    Exit;
  if ExecuteScreenLayoutTextDecomposition(FContext.Document,
    FContext.EditorState, FEditHistory, TScreenLayoutTextLayer(Layer),
    Kind) and
    (FContextMenu <> nil) then
    FContextMenu.Close;
end;

end.
