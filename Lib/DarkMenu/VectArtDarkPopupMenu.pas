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
    FMainForm: TWinControl;
    FOnHover: TNotifyEvent;
    FOnOpening: TNotifyEvent;
    FPopup: TPanel;
    procedure ButtonClick(Sender: TObject);
    procedure ButtonMouseEnter(Sender: TObject);
    function GetPopupHeight: Integer;
    function GetVisible: Boolean;
    procedure InitializeControls(AButton, APopup: TPanel);
    procedure SetPopupHeight(const Value: Integer);
  public
    // メニューバー上へトップボタンとポップアップを新規生成し、両ControlをこのComponentが所有する。
    constructor CreateForHosts(AOwner: TComponent; AMainForm,
      AMenuBar: TWinControl; const ACaption: string; ButtonLeft,
      ButtonWidth, PopupWidth, PopupHeight: Integer); reintroduce;
    // DFMなどで別Ownerが所有する既存Controlへ接続する。Controlの所有権は変更しない。
    constructor CreateForControls(AOwner: TComponent; AMainForm: TWinControl;
      AButton, APopup: TPanel); reintroduce;
    // ポップアップへ高さ32pxの項目を追加し、返したPanelから表示状態などを個別調整できる。
    function AddItem(const ACaption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel;
    // ポップアップを閉じる。すでに閉じている場合は何もしない。
    procedure Close;
    // 指定Controlがトップボタンまたはポップアップ内部に属するかを返す。
    function OwnsControl(AControl: TControl): Boolean;
    // OnOpeningを通知した後、トップボタン直下へポップアップを表示する。
    procedure Open;
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
  System.Types, Vcl.Graphics, Winapi.Messages;

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
  FPopup.Visible := False;
end;

constructor TVectArtDarkPopupMenu.CreateForControls(AOwner: TComponent;
  AMainForm: TWinControl; AButton, APopup: TPanel);
begin
  inherited Create(AOwner);
  FMainForm := AMainForm;
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
  FButton.OnClick := ButtonClick;
  FButton.OnMouseEnter := ButtonMouseEnter;
end;

procedure TVectArtDarkPopupMenu.Open;
var
  Origin: TPoint;
begin
  if FPopup.Visible then
  begin
    FPopup.BringToFront;
    Exit;
  end;
  if Assigned(FOnOpening) then
    FOnOpening(Self);
  Origin := FMainForm.ScreenToClient(FButton.ClientToScreen(Point(0,
    FButton.Height)));
  FPopup.Left := Origin.X;
  FPopup.Top := Origin.Y;
  FPopup.Visible := True;
  FPopup.BringToFront;
end;

function TVectArtDarkPopupMenu.OwnsControl(AControl: TControl): Boolean;
begin
  Result := (AControl <> nil) and
    ((AControl = FButton) or FButton.ContainsControl(AControl) or
     (AControl = FPopup) or FPopup.ContainsControl(AControl));
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
