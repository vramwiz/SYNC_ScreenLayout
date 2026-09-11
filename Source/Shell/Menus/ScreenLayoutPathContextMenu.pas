// 開いた線Pathに、表示輪郭を閉じたパス図形へ変換する項目を提供する。
unit ScreenLayoutPathContextMenu;

interface

uses
  System.Classes, ScreenLayoutEditHistory, ScreenLayoutObjectContextMenu;

type
  TScreenLayoutPathMenuContributor = class(TScreenLayoutObjectMenuContributor)
  private
    FContext: TScreenLayoutObjectMenuContext;
    FContextMenu: TScreenLayoutObjectContextMenu;
    FEditHistory: TVectArtEditHistory;
    procedure OutlineClick(Sender: TObject);
  public
    constructor Create(ContextMenu: TScreenLayoutObjectContextMenu;
      EditHistory: TVectArtEditHistory);
    function AppliesTo(const Context: TScreenLayoutObjectMenuContext): Boolean;
      override;
    procedure BuildMenu(const Context: TScreenLayoutObjectMenuContext;
      Builder: TScreenLayoutObjectMenuBuilder); override;
  end;

implementation

uses
  ScreenLayoutDocument, ScreenLayoutStrokeOutlineCommands;

constructor TScreenLayoutPathMenuContributor.Create(
  ContextMenu: TScreenLayoutObjectContextMenu;
  EditHistory: TVectArtEditHistory);
begin
  inherited Create;
  FContextMenu := ContextMenu;
  FEditHistory := EditHistory;
end;

function TScreenLayoutPathMenuContributor.AppliesTo(
  const Context: TScreenLayoutObjectMenuContext): Boolean;
begin
  Result := (Context.SingleLayer is TVectArtPathLayer) and
    not TVectArtPathLayer(Context.SingleLayer).Closed;
end;

procedure TScreenLayoutPathMenuContributor.BuildMenu(
  const Context: TScreenLayoutObjectMenuContext;
  Builder: TScreenLayoutObjectMenuBuilder);
begin
  FContext := Context;
  Builder.AddItem('線を閉じたパス図形へ変換', OutlineClick,
    not Context.SingleLayer.Locked);
end;

procedure TScreenLayoutPathMenuContributor.OutlineClick(Sender: TObject);
begin
  if not (FContext.SingleLayer is TVectArtPathLayer) then
    Exit;
  if ExecuteScreenLayoutStrokeOutline(FContext.Document,
    FContext.EditorState, FEditHistory,
    TVectArtPathLayer(FContext.SingleLayer)) and (FContextMenu <> nil) then
    FContextMenu.Close;
end;

end.
