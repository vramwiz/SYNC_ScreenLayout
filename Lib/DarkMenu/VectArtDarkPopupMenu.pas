// ダーク表示のトップメニューと子ポップアップの生成、開閉、マウス判定を共通化する。
// メニュー項目が実行する機能や、複数メニュー間の切替方針は利用側がイベントから決定する。
unit VectArtDarkPopupMenu;

interface

uses
  System.Classes, System.Generics.Collections, Vcl.AppEvnts, Vcl.Controls,
  Vcl.ExtCtrls, Winapi.Windows;

type
  TVectArtDarkPopupMenu = class(TComponent)
  private
    FButton: TPanel;
    FChildMenus: TList<TVectArtDarkPopupMenu>;
    FMainForm: TWinControl;
    FOnHover: TNotifyEvent;
    FOnOpening: TNotifyEvent;
    FParentMenu: TVectArtDarkPopupMenu;
    FPopup: TPanel;
    FSubMenus: TDictionary<TPanel, TVectArtDarkPopupMenu>;
    procedure ButtonClick(Sender: TObject);
    procedure ButtonMouseEnter(Sender: TObject);
    procedure CloseChildMenus(ExceptMenu: TVectArtDarkPopupMenu = nil);
    function GetPopupHeight: Integer;
    function GetVisible: Boolean;
    procedure InitializeControls(AButton, APopup: TPanel);
    procedure ItemMouseEnter(Sender: TObject);
    procedure OpenAtScreenPointCore(const ScreenPoint: TPoint;
      NotifyOpening: Boolean);
    procedure OpenSubMenu(Item: TPanel;
      SubMenu: TVectArtDarkPopupMenu);
    procedure SetPopupHeight(const Value: Integer);
    procedure SubMenuItemClick(Sender: TObject);
  public
    // メニューバー上へトップボタンとポップアップを新規生成し、両ControlをこのComponentが所有する。
    constructor CreateForHosts(AOwner: TComponent; AMainForm,
      AMenuBar: TWinControl; const ACaption: string; ButtonLeft,
      ButtonWidth, PopupWidth, PopupHeight: Integer); reintroduce;
    // DFMなどで別Ownerが所有する既存Controlへ接続する。Controlの所有権は変更しない。
    constructor CreateForControls(AOwner: TComponent; AMainForm: TWinControl;
      AButton, APopup: TPanel); reintroduce;
    // メニューバーを持たず、任意座標または親項目から開くポップアップを生成する。
    constructor CreatePopup(AOwner: TComponent; AMainForm: TWinControl;
      PopupWidth, PopupHeight: Integer); reintroduce;
    destructor Destroy; override;
    // ポップアップへ高さ32pxの項目を追加し、返したPanelから表示状態などを個別調整できる。
    function AddItem(const ACaption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel;
    // 子メニューを持つ項目を追加する。子は別Ownerが所有し、このメニューは参照だけを保持する。
    function AddSubMenu(const ACaption: string; Top: Integer;
      SubMenu: TVectArtDarkPopupMenu): TPanel;
    // ポップアップを閉じる。すでに閉じている場合は何もしない。
    procedure Close;
    // 指定Controlがトップボタンまたはポップアップ内部に属するかを返す。
    function OwnsControl(AControl: TControl): Boolean;
    // OnOpeningを通知した後、トップボタン直下へポップアップを表示する。
    procedure Open;
    // 指定した画面座標を左上候補として開き、フォームおよびモニター内へ位置を補正する。
    procedure OpenAtScreenPoint(const ScreenPoint: TPoint);
    // 項目のEnabledとダーク配色の文字色を同時に更新する。
    procedure SetItemEnabled(Item: TPanel; const Value: Boolean);
    // 現在の表示状態を反転する。通常はトップボタンのクリックから自動的に呼ばれる。
    procedure Toggle;
    property Button: TPanel read FButton;
    // トップボタンへマウスが入るたび通知する。ホバー切替の開始条件は利用側が判断する。
    property OnHover: TNotifyEvent read FOnHover write FOnHover;
    // 非表示から表示へ変わる直前に通知する。利用側は他のメニューをここで閉じられる。
    property OnOpening: TNotifyEvent read FOnOpening write FOnOpening;
    property Popup: TPanel read FPopup;
    property PopupHeight: Integer read GetPopupHeight write SetPopupHeight;
    property Visible: Boolean read GetVisible;
  end;

  TVectArtDarkMenuGroup = class(TComponent)
  private
    FApplicationEvents: TApplicationEvents;
    FMenus: TList<TVectArtDarkPopupMenu>;
    procedure ApplicationDeactivate(Sender: TObject);
    procedure ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
    function AnyMenuVisible: Boolean;
    procedure MenuHover(Sender: TObject);
    procedure MenuOpening(Sender: TObject);
  public
    // アプリケーションメッセージの監視を開始する。Owner破棄時に監視と非所有Menu一覧も解放する。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 登録済みの全ポップアップを閉じる。
    procedure CloseAll;
    // Menuを非所有参照として登録し、相互切替、外側クリック、非アクティブ時の自動Closeを接続する。
    procedure RegisterMenu(Menu: TVectArtDarkPopupMenu);
  end;

implementation

uses
  System.Math, System.Types, Vcl.Forms, Vcl.Graphics, Winapi.Messages;

const
  COLOR_BUTTON = TColor($00222222);
  COLOR_DISABLED = TColor($00757575);
  COLOR_POPUP = TColor($00303030);
  COLOR_TEXT = TColor($00E6E6E6);
  MENU_ITEM_HEIGHT = 32;

function TVectArtDarkPopupMenu.AddItem(const ACaption: string; Top: Integer;
  ClickHandler: TNotifyEvent): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := FPopup;
  Result.SetBounds(0, Top, FPopup.Width, MENU_ITEM_HEIGHT);
  Result.BevelOuter := bvNone;
  Result.Caption := ACaption;
  Result.Color := COLOR_POPUP;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -12;
  Result.Font.Color := COLOR_TEXT;
  Result.ParentBackground := False;
  Result.OnClick := ClickHandler;
  Result.OnMouseEnter := ItemMouseEnter;
end;

function TVectArtDarkPopupMenu.AddSubMenu(const ACaption: string;
  Top: Integer; SubMenu: TVectArtDarkPopupMenu): TPanel;
begin
  Result := AddItem(ACaption + '  >', Top, SubMenuItemClick);
  if SubMenu = nil then
    Exit;
  if (SubMenu.FParentMenu <> nil) and
    (SubMenu.FParentMenu <> Self) then
    SubMenu.FParentMenu.FChildMenus.Remove(SubMenu);
  SubMenu.FParentMenu := Self;
  if not FChildMenus.Contains(SubMenu) then
    FChildMenus.Add(SubMenu);
  FSubMenus.AddOrSetValue(Result, SubMenu);
end;

procedure TVectArtDarkPopupMenu.ButtonClick(Sender: TObject);
begin
  Toggle;
end;

procedure TVectArtDarkPopupMenu.ButtonMouseEnter(Sender: TObject);
begin
  if Assigned(FOnHover) then
    FOnHover(Self);
end;

procedure TVectArtDarkPopupMenu.Close;
begin
  CloseChildMenus;
  FPopup.Visible := False;
end;

procedure TVectArtDarkPopupMenu.CloseChildMenus(
  ExceptMenu: TVectArtDarkPopupMenu);
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FChildMenus do
    if Menu <> ExceptMenu then
      Menu.Close;
end;

constructor TVectArtDarkPopupMenu.CreateForControls(AOwner: TComponent;
  AMainForm: TWinControl; AButton, APopup: TPanel);
begin
  inherited Create(AOwner);
  FMainForm := AMainForm;
  FChildMenus := TList<TVectArtDarkPopupMenu>.Create;
  FSubMenus := TDictionary<TPanel, TVectArtDarkPopupMenu>.Create;
  InitializeControls(AButton, APopup);
end;

constructor TVectArtDarkPopupMenu.CreateForHosts(AOwner: TComponent;
  AMainForm, AMenuBar: TWinControl; const ACaption: string; ButtonLeft,
  ButtonWidth, PopupWidth, PopupHeight: Integer);
var
  ButtonControl: TPanel;
  PopupControl: TPanel;
begin
  inherited Create(AOwner);
  FMainForm := AMainForm;
  FChildMenus := TList<TVectArtDarkPopupMenu>.Create;
  FSubMenus := TDictionary<TPanel, TVectArtDarkPopupMenu>.Create;

  ButtonControl := TPanel.Create(Self);
  ButtonControl.Parent := AMenuBar;
  ButtonControl.SetBounds(ButtonLeft, 0, ButtonWidth, AMenuBar.Height);
  ButtonControl.BevelOuter := bvNone;
  ButtonControl.Caption := ACaption;
  ButtonControl.Color := COLOR_BUTTON;
  ButtonControl.Font.Name := 'Segoe UI';
  ButtonControl.Font.Height := -12;
  ButtonControl.Font.Color := COLOR_TEXT;
  ButtonControl.ParentBackground := False;

  PopupControl := TPanel.Create(Self);
  PopupControl.Parent := AMainForm;
  PopupControl.SetBounds(ButtonLeft, AMenuBar.Height, PopupWidth, PopupHeight);
  PopupControl.BevelOuter := bvNone;
  PopupControl.Color := COLOR_POPUP;
  PopupControl.ParentBackground := False;
  PopupControl.Visible := False;
  InitializeControls(ButtonControl, PopupControl);
end;

constructor TVectArtDarkPopupMenu.CreatePopup(AOwner: TComponent;
  AMainForm: TWinControl; PopupWidth, PopupHeight: Integer);
var
  PopupControl: TPanel;
begin
  inherited Create(AOwner);
  FMainForm := AMainForm;
  FChildMenus := TList<TVectArtDarkPopupMenu>.Create;
  FSubMenus := TDictionary<TPanel, TVectArtDarkPopupMenu>.Create;
  PopupControl := TPanel.Create(Self);
  PopupControl.Parent := AMainForm;
  PopupControl.SetBounds(0, 0, PopupWidth, PopupHeight);
  PopupControl.BevelOuter := bvNone;
  PopupControl.Color := COLOR_POPUP;
  PopupControl.ParentBackground := False;
  PopupControl.Visible := False;
  InitializeControls(nil, PopupControl);
end;

destructor TVectArtDarkPopupMenu.Destroy;
var
  Menu: TVectArtDarkPopupMenu;
begin
  if FParentMenu <> nil then
    FParentMenu.FChildMenus.Remove(Self);
  for Menu in FChildMenus do
    if Menu.FParentMenu = Self then
      Menu.FParentMenu := nil;
  FSubMenus.Free;
  FChildMenus.Free;
  inherited Destroy;
end;

function TVectArtDarkPopupMenu.GetPopupHeight: Integer;
begin
  Result := FPopup.Height;
end;

function TVectArtDarkPopupMenu.GetVisible: Boolean;
begin
  Result := FPopup.Visible;
end;

procedure TVectArtDarkPopupMenu.InitializeControls(AButton,
  APopup: TPanel);
begin
  FButton := AButton;
  FPopup := APopup;
  if FButton <> nil then
  begin
    FButton.OnClick := ButtonClick;
    FButton.OnMouseEnter := ButtonMouseEnter;
  end;
end;

procedure TVectArtDarkPopupMenu.ItemMouseEnter(Sender: TObject);
var
  SubMenu: TVectArtDarkPopupMenu;
begin
  SubMenu := nil;
  if (Sender is TPanel) and
    FSubMenus.TryGetValue(TPanel(Sender), SubMenu) then
  begin
    CloseChildMenus(SubMenu);
    OpenSubMenu(TPanel(Sender), SubMenu);
  end
  else
    CloseChildMenus;
end;

procedure TVectArtDarkPopupMenu.Open;
var
  Origin: TPoint;
begin
  if FButton = nil then
    Exit;
  if FPopup.Visible then
  begin
    FPopup.BringToFront;
    Exit;
  end;
  Origin := FMainForm.ScreenToClient(FButton.ClientToScreen(Point(0,
    FButton.Height)));
  OpenAtScreenPointCore(FMainForm.ClientToScreen(Origin), True);
end;

procedure TVectArtDarkPopupMenu.OpenAtScreenPoint(
  const ScreenPoint: TPoint);
begin
  OpenAtScreenPointCore(ScreenPoint, True);
end;

procedure TVectArtDarkPopupMenu.OpenAtScreenPointCore(
  const ScreenPoint: TPoint; NotifyOpening: Boolean);
var
  ClientBounds: TRect;
  ClientPoint: TPoint;
  Monitor: TMonitor;
  PopupBounds: TRect;
  PopupScreenPoint: TPoint;
  WorkArea: TRect;
begin
  if (FPopup = nil) or (FMainForm = nil) then
    Exit;
  if NotifyOpening and Assigned(FOnOpening) then
    FOnOpening(Self);
  ClientPoint := FMainForm.ScreenToClient(ScreenPoint);
  ClientBounds := FMainForm.ClientRect;
  ClientPoint.X := EnsureRange(ClientPoint.X, ClientBounds.Left,
    Max(ClientBounds.Left, ClientBounds.Right - FPopup.Width));
  ClientPoint.Y := EnsureRange(ClientPoint.Y, ClientBounds.Top,
    Max(ClientBounds.Top, ClientBounds.Bottom - FPopup.Height));

  PopupScreenPoint := FMainForm.ClientToScreen(ClientPoint);
  PopupBounds := Rect(PopupScreenPoint.X, PopupScreenPoint.Y,
    PopupScreenPoint.X + FPopup.Width, PopupScreenPoint.Y + FPopup.Height);
  Monitor := Screen.MonitorFromRect(PopupBounds, mdNearest);
  if Monitor <> nil then
  begin
    WorkArea := Monitor.WorkareaRect;
    if PopupBounds.Right > WorkArea.Right then
      ClientPoint.X := ClientPoint.X - (PopupBounds.Right - WorkArea.Right);
    if PopupBounds.Bottom > WorkArea.Bottom then
      ClientPoint.Y := ClientPoint.Y - (PopupBounds.Bottom - WorkArea.Bottom);
    ClientPoint.X := Max(ClientBounds.Left, ClientPoint.X);
    ClientPoint.Y := Max(ClientBounds.Top, ClientPoint.Y);
  end;
  FPopup.Left := ClientPoint.X;
  FPopup.Top := ClientPoint.Y;
  FPopup.Visible := True;
  FPopup.BringToFront;
end;

procedure TVectArtDarkPopupMenu.OpenSubMenu(Item: TPanel;
  SubMenu: TVectArtDarkPopupMenu);
var
  ItemOrigin: TPoint;
  Monitor: TMonitor;
  WorkArea: TRect;
begin
  if (Item = nil) or (SubMenu = nil) then
    Exit;
  ItemOrigin := Item.ClientToScreen(Point(Item.Width, 0));
  Monitor := Screen.MonitorFromPoint(ItemOrigin, mdNearest);
  if Monitor <> nil then
  begin
    WorkArea := Monitor.WorkareaRect;
    if ItemOrigin.X + SubMenu.Popup.Width > WorkArea.Right then
      ItemOrigin.X := Item.ClientToScreen(Point(-SubMenu.Popup.Width, 0)).X;
  end;
  SubMenu.OpenAtScreenPointCore(ItemOrigin, False);
end;

function TVectArtDarkPopupMenu.OwnsControl(AControl: TControl): Boolean;
var
  Menu: TVectArtDarkPopupMenu;
begin
  Result := False;
  if AControl = nil then
    Exit;
  if ((FButton <> nil) and
      ((AControl = FButton) or FButton.ContainsControl(AControl))) or
    ((FPopup <> nil) and
      ((AControl = FPopup) or FPopup.ContainsControl(AControl))) then
    Exit(True);
  for Menu in FChildMenus do
    if Menu.OwnsControl(AControl) then
      Exit(True);
end;

procedure TVectArtDarkPopupMenu.SetItemEnabled(Item: TPanel;
  const Value: Boolean);
begin
  if Item = nil then
    Exit;
  Item.Enabled := Value;
  if Value then
    Item.Font.Color := COLOR_TEXT
  else
    Item.Font.Color := COLOR_DISABLED;
end;

procedure TVectArtDarkPopupMenu.SetPopupHeight(const Value: Integer);
begin
  FPopup.Height := Value;
end;

procedure TVectArtDarkPopupMenu.Toggle;
begin
  if FPopup.Visible then
    Close
  else
    Open;
end;

procedure TVectArtDarkPopupMenu.SubMenuItemClick(Sender: TObject);
var
  SubMenu: TVectArtDarkPopupMenu;
begin
  if (Sender is TPanel) and
    FSubMenus.TryGetValue(TPanel(Sender), SubMenu) then
    OpenSubMenu(TPanel(Sender), SubMenu);
end;

{ TVectArtDarkMenuGroup }

procedure TVectArtDarkMenuGroup.ApplicationDeactivate(Sender: TObject);
begin
  CloseAll;
end;

procedure TVectArtDarkMenuGroup.ApplicationMessage(var Msg: TMsg;
  var Handled: Boolean);
var
  Menu: TVectArtDarkPopupMenu;
  Target: TControl;
begin
  if ((Msg.message = WM_KEYDOWN) or (Msg.message = WM_SYSKEYDOWN)) and
    (Msg.wParam = VK_ESCAPE) then
  begin
    if AnyMenuVisible then
    begin
      CloseAll;
      Handled := True;
    end;
    Exit;
  end;
  if (Msg.message <> WM_LBUTTONDOWN) and
    (Msg.message <> WM_RBUTTONDOWN) and
    (Msg.message <> WM_MBUTTONDOWN) and
    (Msg.message <> WM_NCLBUTTONDOWN) then
    Exit;
  Target := FindVCLWindow(Msg.pt);
  for Menu in FMenus do
    if Menu.OwnsControl(Target) then
      Exit;
  CloseAll;
end;

function TVectArtDarkMenuGroup.AnyMenuVisible: Boolean;
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FMenus do
    if Menu.Visible then
      Exit(True);
  Result := False;
end;

procedure TVectArtDarkMenuGroup.CloseAll;
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FMenus do
    Menu.Close;
end;

constructor TVectArtDarkMenuGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenus := TList<TVectArtDarkPopupMenu>.Create;
  FApplicationEvents := TApplicationEvents.Create(Self);
  FApplicationEvents.OnDeactivate := ApplicationDeactivate;
  FApplicationEvents.OnMessage := ApplicationMessage;
end;

destructor TVectArtDarkMenuGroup.Destroy;
begin
  FMenus.Free;
  inherited Destroy;
end;

procedure TVectArtDarkMenuGroup.MenuHover(Sender: TObject);
begin
  if AnyMenuVisible and (Sender is TVectArtDarkPopupMenu) then
    TVectArtDarkPopupMenu(Sender).Open;
end;

procedure TVectArtDarkMenuGroup.MenuOpening(Sender: TObject);
var
  Menu: TVectArtDarkPopupMenu;
begin
  for Menu in FMenus do
    if Menu <> Sender then
      Menu.Close;
end;

procedure TVectArtDarkMenuGroup.RegisterMenu(Menu: TVectArtDarkPopupMenu);
begin
  if (Menu = nil) or FMenus.Contains(Menu) then
    Exit;
  FMenus.Add(Menu);
  Menu.OnHover := MenuHover;
  Menu.OnOpening := MenuOpening;
end;

end.
