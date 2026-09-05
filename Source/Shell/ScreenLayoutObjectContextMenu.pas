// キャンバス上のオブジェクト用ダークメニューを構成し、表示要求をメニューライブラリへ橋渡しする。
// 共通項目を持ち、対象固有の項目と編集コマンドは登録された提供者へ委譲する。
unit ScreenLayoutObjectContextMenu;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  Vcl.Controls, Vcl.ExtCtrls, ScreenLayoutDocument, ScreenLayoutEditorState,
  VectArtDarkMenuGroup, VectArtDarkPopupMenu;

type
  // 表示直前の選択を固定し、項目の適用判定と実行対象を提供者へ渡す。
  TScreenLayoutObjectMenuContext = record
    Document: TVectArtDocument;       // トップレベル選択と編集対象を所有するDocument。
    EditorState: TVectArtEditorState; // 開いたグループとその直下選択を保持する状態。
    Layers: TArray<TVectArtLayer>;    // 右クリック後に確定した実際の選択レイヤー。
    function SelectionCount: Integer;
    function SingleLayer: TVectArtLayer;
  end;

  // 提供者が座標やPopup高さを管理せず、項目とサブメニューだけを宣言するための構築窓口。
  TScreenLayoutObjectMenuBuilder = class
  private
    FHost: TWinControl;
    FMenu: TVectArtDarkPopupMenu;
    FNextTop: Integer;
    FOwnedBuilders: TObjectList<TScreenLayoutObjectMenuBuilder>;
    FOwnedSubMenus: TObjectList<TVectArtDarkPopupMenu>;
  public
    constructor Create(Menu: TVectArtDarkPopupMenu; Host: TWinControl);
    destructor Destroy; override;
    function AddItem(const Caption: string; ClickHandler: TNotifyEvent;
      Enabled: Boolean = True): TPanel;
    function AddSubMenu(const Caption: string;
      Width: Integer = 160): TScreenLayoutObjectMenuBuilder;
    procedure AddSeparator;
  end;

  // 別ユニットから対象固有の項目を追加する拡張点。登録後の所有権はメニューへ移る。
  TScreenLayoutObjectMenuContributor = class
  public
    function AppliesTo(const Context: TScreenLayoutObjectMenuContext): Boolean;
      virtual; abstract;
    procedure BuildMenu(const Context: TScreenLayoutObjectMenuContext;
      Builder: TScreenLayoutObjectMenuBuilder); virtual; abstract;
  end;

  TScreenLayoutObjectContextMenu = class(TComponent)
  private
    FBuilder: TScreenLayoutObjectMenuBuilder;
    FContributors: TObjectList<TScreenLayoutObjectMenuContributor>;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FHitLayerIndices: TArray<Integer>;
    FHost: TWinControl;
    FMenu: TVectArtDarkPopupMenu;
    function CaptureContext: TScreenLayoutObjectMenuContext;
    procedure Rebuild(const Context: TScreenLayoutObjectMenuContext);
    procedure SelectHitLayer(Sender: TObject);
  public
    // Host上へルートメニューを生成し、現在の選択を取得するモデルを非所有参照で保持する。
    constructor Create(AOwner: TComponent; Host: TWinControl;
      MenuGroup: TVectArtDarkMenuGroup; Document: TVectArtDocument;
      EditorState: TVectArtEditorState); reintroduce;
    destructor Destroy; override;
    // 提供者の所有権を受け取り、以後の表示時に適用判定と項目構築を呼び出す。
    procedure RegisterContributor(
      Contributor: TScreenLayoutObjectMenuContributor);
    // Canvasの通知座標へ、現在の選択に適用できる項目を構築してメニューを開く。
    procedure ShowForObject(Sender: TObject; const ScreenPoint: TPoint);
      overload;
    procedure ShowForObject(Sender: TObject; const ScreenPoint: TPoint;
      const LayerIndices: TArray<Integer>); overload;
    // 実行済み項目からポップアップと開いている子メニューを閉じる。
    procedure Close;
    property Menu: TVectArtDarkPopupMenu read FMenu;
  end;

implementation

const
  MENU_ITEM_HEIGHT = 32;
  MENU_SEPARATOR_HEIGHT = 8;

{ TScreenLayoutObjectMenuContext }

function TScreenLayoutObjectMenuContext.SelectionCount: Integer;
begin
  Result := Length(Layers);
end;

function TScreenLayoutObjectMenuContext.SingleLayer: TVectArtLayer;
begin
  if Length(Layers) = 1 then
    Result := Layers[0]
  else
    Result := nil;
end;

{ TScreenLayoutObjectMenuBuilder }

function TScreenLayoutObjectMenuBuilder.AddItem(const Caption: string;
  ClickHandler: TNotifyEvent; Enabled: Boolean): TPanel;
begin
  Result := FMenu.AddItem(Caption, FNextTop, ClickHandler);
  FMenu.SetItemEnabled(Result, Enabled);
  Inc(FNextTop, MENU_ITEM_HEIGHT);
  FMenu.PopupHeight := FNextTop;
end;

procedure TScreenLayoutObjectMenuBuilder.AddSeparator;
begin
  if FNextTop = 0 then
    Exit;
  FMenu.AddSeparator(FNextTop, MENU_SEPARATOR_HEIGHT);
  Inc(FNextTop, MENU_SEPARATOR_HEIGHT);
  FMenu.PopupHeight := FNextTop;
end;

function TScreenLayoutObjectMenuBuilder.AddSubMenu(const Caption: string;
  Width: Integer): TScreenLayoutObjectMenuBuilder;
var
  SubMenu: TVectArtDarkPopupMenu;
begin
  SubMenu := TVectArtDarkPopupMenu.CreatePopup(nil, FHost, Width, 1);
  FOwnedSubMenus.Add(SubMenu);
  FMenu.AddSubMenu(Caption, FNextTop, SubMenu);
  Inc(FNextTop, MENU_ITEM_HEIGHT);
  FMenu.PopupHeight := FNextTop;
  Result := TScreenLayoutObjectMenuBuilder.Create(SubMenu, FHost);
  FOwnedBuilders.Add(Result);
end;

constructor TScreenLayoutObjectMenuBuilder.Create(
  Menu: TVectArtDarkPopupMenu; Host: TWinControl);
begin
  inherited Create;
  FMenu := Menu;
  FHost := Host;
  FOwnedBuilders := TObjectList<TScreenLayoutObjectMenuBuilder>.Create(True);
  FOwnedSubMenus := TObjectList<TVectArtDarkPopupMenu>.Create(True);
end;

destructor TScreenLayoutObjectMenuBuilder.Destroy;
begin
  FOwnedBuilders.Free;
  FOwnedSubMenus.Free;
  FMenu.ClearItems;
  inherited Destroy;
end;

{ TScreenLayoutObjectContextMenu }

function TScreenLayoutObjectContextMenu.CaptureContext:
  TScreenLayoutObjectMenuContext;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := Default(TScreenLayoutObjectMenuContext);
  Result.Document := FDocument;
  Result.EditorState := FEditorState;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) and
    (FEditorState.OpenGroupChildCount > 0) then
  begin
    Result.Layers := FEditorState.GetOpenGroupChildren;
    Exit;
  end;
  if FDocument = nil then
    Exit;
  Indices := FDocument.GetSelectedLayerIndices;
  SetLength(Result.Layers, Length(Indices));
  for I := 0 to High(Indices) do
    Result.Layers[I] := FDocument[Indices[I]];
end;

constructor TScreenLayoutObjectContextMenu.Create(AOwner: TComponent;
  Host: TWinControl; MenuGroup: TVectArtDarkMenuGroup;
  Document: TVectArtDocument; EditorState: TVectArtEditorState);
begin
  inherited Create(AOwner);
  FHost := Host;
  FDocument := Document;
  FEditorState := EditorState;
  FContributors := TObjectList<TScreenLayoutObjectMenuContributor>.Create(True);
  FMenu := TVectArtDarkPopupMenu.CreatePopup(Self, Host, 208, 1);
  if MenuGroup <> nil then
    MenuGroup.RegisterMenu(FMenu);
end;

procedure TScreenLayoutObjectContextMenu.Close;
begin
  FMenu.Close;
end;

destructor TScreenLayoutObjectContextMenu.Destroy;
begin
  FBuilder.Free;
  FContributors.Free;
  inherited Destroy;
end;

procedure TScreenLayoutObjectContextMenu.Rebuild(
  const Context: TScreenLayoutObjectMenuContext);
var
  Contributor: TScreenLayoutObjectMenuContributor;
  I: Integer;
  LayerBuilder: TScreenLayoutObjectMenuBuilder;
  OrderBuilder: TScreenLayoutObjectMenuBuilder;
  Panel: TPanel;
begin
  FreeAndNil(FBuilder);
  FBuilder := TScreenLayoutObjectMenuBuilder.Create(FMenu, FHost);
  FBuilder.AddItem('切り取り    Ctrl+X', nil);
  FBuilder.AddItem('コピー      Ctrl+C', nil);
  FBuilder.AddItem('複製        Ctrl+D', nil);
  OrderBuilder := FBuilder.AddSubMenu('重なり順');
  OrderBuilder.AddItem('最前面へ', nil);
  OrderBuilder.AddItem('前面へ', nil);
  OrderBuilder.AddItem('背面へ', nil);
  OrderBuilder.AddItem('最背面へ', nil);
  FBuilder.AddItem('削除        Delete', nil);
  if (Length(FHitLayerIndices) > 1) and
    ((FEditorState = nil) or (FEditorState.OpenGroup = nil)) then
  begin
    FBuilder.AddSeparator;
    LayerBuilder := FBuilder.AddSubMenu('この位置のレイヤー', 208);
    for I := 0 to High(FHitLayerIndices) do
      if (FHitLayerIndices[I] > 0) and
        (FHitLayerIndices[I] < FDocument.LayerCount) then
      begin
        Panel := LayerBuilder.AddItem(
          FDocument[FHitLayerIndices[I]].Name, SelectHitLayer);
        Panel.Tag := FHitLayerIndices[I];
      end;
  end;
  for Contributor in FContributors do
    if Contributor.AppliesTo(Context) then
    begin
      FBuilder.AddSeparator;
      Contributor.BuildMenu(Context, FBuilder);
    end;
end;

procedure TScreenLayoutObjectContextMenu.RegisterContributor(
  Contributor: TScreenLayoutObjectMenuContributor);
begin
  if Contributor = nil then
    raise EArgumentNilException.Create('Contributor');
  FContributors.Add(Contributor);
end;

procedure TScreenLayoutObjectContextMenu.ShowForObject(Sender: TObject;
  const ScreenPoint: TPoint);
begin
  FHitLayerIndices := nil;
  Rebuild(CaptureContext);
  FMenu.OpenAtScreenPoint(ScreenPoint);
end;

procedure TScreenLayoutObjectContextMenu.ShowForObject(Sender: TObject;
  const ScreenPoint: TPoint; const LayerIndices: TArray<Integer>);
begin
  FHitLayerIndices := Copy(LayerIndices);
  Rebuild(CaptureContext);
  FMenu.OpenAtScreenPoint(ScreenPoint);
end;

procedure TScreenLayoutObjectContextMenu.SelectHitLayer(Sender: TObject);
var
  LayerIndex: Integer;
begin
  if not (Sender is TPanel) or (FDocument = nil) then
    Exit;
  LayerIndex := TPanel(Sender).Tag;
  if (LayerIndex <= 0) or (LayerIndex >= FDocument.LayerCount) then
    Exit;
  FDocument.SelectedIndex := LayerIndex;
  Close;
end;

end.
