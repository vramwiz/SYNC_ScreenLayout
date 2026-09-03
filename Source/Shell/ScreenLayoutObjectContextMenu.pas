// キャンバス上のオブジェクト用ダークメニューを構成し、表示要求をメニューライブラリへ橋渡しする。
// 項目が実行する編集コマンドは未実装とし、メニュー構成と階層表示だけを担当する。
unit ScreenLayoutObjectContextMenu;

interface

uses
  System.Classes, System.Types, Vcl.Controls, VectArtDarkMenuGroup,
  VectArtDarkPopupMenu;

type
  TScreenLayoutObjectContextMenu = class(TComponent)
  private
    FMenu: TVectArtDarkPopupMenu;      // 右クリック位置へ表示するルートメニュー。
    FOrderMenu: TVectArtDarkPopupMenu; // 重なり順項目から開く子メニュー。
  public
    // Host上へルートメニューと重なり順サブメニューを生成し、MenuGroupへルートだけを登録する。
    constructor Create(AOwner: TComponent; Host: TWinControl;
      MenuGroup: TVectArtDarkMenuGroup); reintroduce;
    // Canvasの通知座標へメニューを開く。Senderは将来の対象別構成に備えて受け取るが現在は参照しない。
    procedure ShowForObject(Sender: TObject; const ScreenPoint: TPoint);
  end;

implementation

constructor TScreenLayoutObjectContextMenu.Create(AOwner: TComponent;
  Host: TWinControl; MenuGroup: TVectArtDarkMenuGroup);
begin
  inherited Create(AOwner);
  FOrderMenu := TVectArtDarkPopupMenu.CreatePopup(Self, Host, 160, 128);
  FOrderMenu.AddItem('最前面へ', 0, nil);
  FOrderMenu.AddItem('前面へ', 32, nil);
  FOrderMenu.AddItem('背面へ', 64, nil);
  FOrderMenu.AddItem('最背面へ', 96, nil);

  FMenu := TVectArtDarkPopupMenu.CreatePopup(Self, Host, 208, 160);
  FMenu.AddItem('切り取り    Ctrl+X', 0, nil);
  FMenu.AddItem('コピー      Ctrl+C', 32, nil);
  FMenu.AddItem('複製        Ctrl+D', 64, nil);
  FMenu.AddSubMenu('重なり順', 96, FOrderMenu);
  FMenu.AddItem('削除        Delete', 128, nil);
  if MenuGroup <> nil then
    MenuGroup.RegisterMenu(FMenu);
end;

procedure TScreenLayoutObjectContextMenu.ShowForObject(Sender: TObject;
  const ScreenPoint: TPoint);
begin
  FMenu.OpenAtScreenPoint(ScreenPoint);
end;

end.
