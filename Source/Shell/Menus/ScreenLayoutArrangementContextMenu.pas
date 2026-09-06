// 複数選択時の右クリックメニューへ、整列と均等間隔配置を追加する。
unit ScreenLayoutArrangementContextMenu;

interface

uses
  System.Classes, ScreenLayoutDocument, ScreenLayoutEditHistory,
  ScreenLayoutEditorState, ScreenLayoutObjectContextMenu;

type
  TScreenLayoutArrangementMenuContributor = class(
    TScreenLayoutObjectMenuContributor)
  private
    FContextMenu: TScreenLayoutObjectContextMenu;
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    procedure ArrangementClick(Sender: TObject);
  public
    constructor Create(ContextMenu: TScreenLayoutObjectContextMenu;
      Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
      EditorState: TVectArtEditorState);
    function AppliesTo(
      const Context: TScreenLayoutObjectMenuContext): Boolean; override;
    procedure BuildMenu(const Context: TScreenLayoutObjectMenuContext;
      Builder: TScreenLayoutObjectMenuBuilder); override;
  end;

implementation

uses
  Vcl.ExtCtrls, ScreenLayoutLayerArrangementOperations;

constructor TScreenLayoutArrangementMenuContributor.Create(
  ContextMenu: TScreenLayoutObjectContextMenu; Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
begin
  inherited Create;
  FContextMenu := ContextMenu;
  FDocument := Document;
  FEditHistory := EditHistory;
  FEditorState := EditorState;
end;

function TScreenLayoutArrangementMenuContributor.AppliesTo(
  const Context: TScreenLayoutObjectMenuContext): Boolean;
begin
  Result := Context.SelectionCount >= 2;
end;

procedure TScreenLayoutArrangementMenuContributor.ArrangementClick(
  Sender: TObject);
begin
  if not (Sender is TPanel) then
    Exit;
  if FContextMenu <> nil then
    FContextMenu.Close;
  ArrangeScreenLayoutSelection(FDocument, FEditHistory, FEditorState,
    TScreenLayoutArrangement(TPanel(Sender).Tag));
end;

procedure TScreenLayoutArrangementMenuContributor.BuildMenu(
  const Context: TScreenLayoutObjectMenuContext;
  Builder: TScreenLayoutObjectMenuBuilder);
const
  CAPTIONS: array[TScreenLayoutArrangement] of string =
    ('左端揃え', '水平中央揃え', '右端揃え', '上端揃え',
     '垂直中央揃え', '下端揃え', '水平間隔を均等化',
     '垂直間隔を均等化');
var
  Arrangement: TScreenLayoutArrangement;
  ArrangementBuilder: TScreenLayoutObjectMenuBuilder;
  Item: TPanel;
begin
  ArrangementBuilder := Builder.AddSubMenu('整列と均等配置', 208);
  for Arrangement := Low(TScreenLayoutArrangement) to
    High(TScreenLayoutArrangement) do
  begin
    if Arrangement in [slaAlignTop, slaDistributeHorizontal] then
      ArrangementBuilder.AddSeparator;
    Item := ArrangementBuilder.AddItem(CAPTIONS[Arrangement],
      ArrangementClick, CanArrangeScreenLayoutSelection(FDocument,
        FEditorState, Arrangement));
    Item.Tag := Ord(Arrangement);
  end;
end;

end.
