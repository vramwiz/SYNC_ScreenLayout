// ダーク表示のドロップダウン、任意位置ポップアップ、階層サブメニューの生成と配置を担当する。
// メニュー項目が実行する機能は利用側へ委譲し、子メニューの所有権は変更しない。
// 複数のルートメニューをまたぐ排他制御とアプリケーションメッセージ監視は担当しない。
unit VectArtDarkPopupMenu;

interface

uses
  System.Classes, System.Generics.Collections, Vcl.Controls, Vcl.ExtCtrls,
  Winapi.Windows;

type
  TVectArtDarkPopupMenu = class(TComponent)
  private
    FButton: TPanel;
    FChildMenus: TList<TVectArtDarkPopupMenu>; // このメニューから開く子への非所有参照。
    FMainForm: TWinControl;
    FOnHover: TNotifyEvent;
    FOnOpening: TNotifyEvent;
    FParentMenu: TVectArtDarkPopupMenu; // 親メニューへの非所有参照。ルートではnil。
    FPopup: TPanel;
    FSubMenus: TDictionary<TPanel, TVectArtDarkPopupMenu>; // 項目Panelと子メニューの対応。
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
    // 親子メニュー間の非所有参照を解除してから、内部生成したPanelと対応表を破棄する。
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
    // メニューバー型だけが持つ起点ボタン。任意位置ポップアップではnilを返す。
    property Button: TPanel read FButton;
    // トップボタンへマウスが入るたび通知する。ホバー切替の開始条件は利用側が判断する。
    property OnHover: TNotifyEvent read FOnHover write FOnHover;
    // 非表示から表示へ変わる直前に通知する。利用側は他のメニューをここで閉じられる。
    property OnOpening: TNotifyEvent read FOnOpening write FOnOpening;
    // 利用側が既存DFM項目の追加や表示状態の調整に使用するポップアップ本体。
    property Popup: TPanel read FPopup;
    // 項目数に応じて利用側が変更できるポップアップ本体の高さ。
    property PopupHeight: Integer read GetPopupHeight write SetPopupHeight;
    // ルートまたは子ポップアップ本体が現在表示されているかを返す。
    property Visible: Boolean read GetVisible;
  end;

implementation

uses
  System.Math, System.Types, Vcl.Forms, Vcl.Graphics;

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

end.
