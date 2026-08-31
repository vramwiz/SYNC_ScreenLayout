// Editメニューとコード描画Undo／Redoショートカットを構築・管理する。
unit VectArtDesignerEditActionsUI;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  VectArtDarkPopupMenu, VectArtDesignerDocument,
  VectArtDesignerEditHistory;

type
  TVectArtEditShortcutControl = class(TCustomControl)
  private
    FHistory: TVectArtEditHistory;
    FOnOpenRequest: TNotifyEvent;
    FOnSaveRequest: TNotifyEvent;
    function ButtonEnabled(Index: Integer): Boolean;
    function ButtonRect(Index: Integer): TRect;
    procedure DrawButton(Index: Integer; const Caption: string);
    procedure DrawIcon(Index: Integer; const Bounds: TRect);
    procedure SetHistory(const Value: TVectArtEditHistory);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshState;
    property History: TVectArtEditHistory read FHistory write SetHistory;
    property OnOpenRequest: TNotifyEvent read FOnOpenRequest
      write FOnOpenRequest;
    property OnSaveRequest: TNotifyEvent read FOnSaveRequest
      write FOnSaveRequest;
  end;

  TVectArtEditActionsUI = class(TComponent)
  private
    FCanvasSettingsItem: TPanel;
    FCanvasSettingsVisible: Boolean;
    FDocument: TVectArtDocument;
    FHistory: TVectArtEditHistory;
    FMenu: TVectArtDarkPopupMenu;
    FMifCompatibleModeItem: TPanel;
    FOnOpenRequest: TNotifyEvent;
    FOnSaveRequest: TNotifyEvent;
    FOnCanvasSettingsRequest: TNotifyEvent;
    FRedoItem: TPanel;
    FShortcutControl: TVectArtEditShortcutControl;
    FStandardModeItem: TPanel;
    FUndoItem: TPanel;
    procedure CanvasSettingsClick(Sender: TObject);
    procedure MifCompatibleModeClick(Sender: TObject);
    function NewMenuItem(const Caption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel;
    procedure RedoClick(Sender: TObject);
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetHistory(const Value: TVectArtEditHistory);
    procedure SetCanvasSettingsVisible(const Value: Boolean);
    procedure SetOnOpenRequest(const Value: TNotifyEvent);
    procedure SetOnSaveRequest(const Value: TNotifyEvent);
    procedure StandardModeClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
  public
    constructor CreateForHosts(AOwner: TComponent; AMainForm,
      AMenuBar, AShortcutHost: TWinControl);
    procedure RefreshState;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property History: TVectArtEditHistory read FHistory write SetHistory;
    property Menu: TVectArtDarkPopupMenu read FMenu;
    property CanvasSettingsVisible: Boolean read FCanvasSettingsVisible
      write SetCanvasSettingsVisible;
    property OnCanvasSettingsRequest: TNotifyEvent
      read FOnCanvasSettingsRequest write FOnCanvasSettingsRequest;
    property OnOpenRequest: TNotifyEvent read FOnOpenRequest
      write SetOnOpenRequest;
    property OnSaveRequest: TNotifyEvent read FOnSaveRequest
      write SetOnSaveRequest;
  end;

implementation

uses
  System.Math, Vcl.Graphics;

const
  BUTTON_COUNT = 5;
  BUTTON_WIDTH = 78;
  COLOR_BACKGROUND = TColor($00282828);
  COLOR_BUTTON = TColor($00303030);
  COLOR_DISABLED = TColor($00757575);
  COLOR_TEXT = TColor($00E6E6E6);

{ TVectArtEditShortcutControl }

function TVectArtEditShortcutControl.ButtonEnabled(Index: Integer): Boolean;
begin
  case Index of
    1: Result := Assigned(FOnOpenRequest);
    2: Result := Assigned(FOnSaveRequest);
    3: Result := (FHistory <> nil) and FHistory.CanUndo;
    4: Result := (FHistory <> nil) and FHistory.CanRedo;
  else
    Result := False;
  end;
end;

function TVectArtEditShortcutControl.ButtonRect(Index: Integer): TRect;
begin
  Result := Rect(Index * BUTTON_WIDTH, 0, (Index + 1) * BUTTON_WIDTH,
    ClientHeight);
end;

constructor TVectArtEditShortcutControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
end;

procedure TVectArtEditShortcutControl.DrawButton(Index: Integer;
  const Caption: string);
var
  Bounds: TRect;
begin
  Bounds := ButtonRect(Index);
  Canvas.Brush.Color := COLOR_BUTTON;
  Canvas.FillRect(Bounds);
  DrawIcon(Index, Rect(Bounds.Left + 7, Bounds.Top + 10,
    Bounds.Left + 27, Bounds.Top + 30));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -12;
  if ButtonEnabled(Index) then
    Canvas.Font.Color := COLOR_TEXT
  else
    Canvas.Font.Color := COLOR_DISABLED;
  Canvas.TextOut(Bounds.Left + 32,
    Bounds.Top + (Bounds.Height - Canvas.TextHeight(Caption)) div 2,
    Caption);
end;

procedure TVectArtEditShortcutControl.DrawIcon(Index: Integer;
  const Bounds: TRect);
begin
  Canvas.Pen.Width := 1;
  if ButtonEnabled(Index) then
    Canvas.Pen.Color := COLOR_TEXT
  else
    Canvas.Pen.Color := COLOR_DISABLED;
  Canvas.Brush.Style := bsClear;
  case Index of
    0:
      begin
        Canvas.Rectangle(Bounds.Left + 4, Bounds.Top + 2,
          Bounds.Right - 3, Bounds.Bottom - 2);
        Canvas.MoveTo(Bounds.Left + 10, Bounds.Top + 6);
        Canvas.LineTo(Bounds.Left + 10, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Left + 6, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Right - 6, Bounds.Top + 10);
      end;
    1:
      begin
        Canvas.MoveTo(Bounds.Left + 2, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Left + 8, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Left + 11, Bounds.Top + 4);
        Canvas.LineTo(Bounds.Right - 2, Bounds.Top + 4);
        Canvas.LineTo(Bounds.Right - 4, Bounds.Bottom - 3);
        Canvas.LineTo(Bounds.Left + 3, Bounds.Bottom - 3);
        Canvas.LineTo(Bounds.Left + 2, Bounds.Top + 7);
      end;
    2:
      begin
        Canvas.Rectangle(Bounds.Left + 3, Bounds.Top + 2,
          Bounds.Right - 3, Bounds.Bottom - 2);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 3,
          Bounds.Right - 7, Bounds.Top + 9);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 13,
          Bounds.Right - 7, Bounds.Bottom - 3);
      end;
    3, 4:
      begin
        Canvas.Arc(Bounds.Left + 3, Bounds.Top + 4, Bounds.Right - 3,
          Bounds.Bottom - 2, Bounds.Right - 4, Bounds.Top + 7,
          Bounds.Left + 4, Bounds.Top + 7);
        if Index = 3 then
        begin
          Canvas.MoveTo(Bounds.Left + 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Left + 8, Bounds.Top + 3);
          Canvas.MoveTo(Bounds.Left + 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Left + 8, Bounds.Top + 11);
        end
        else
        begin
          Canvas.MoveTo(Bounds.Right - 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Right - 8, Bounds.Top + 3);
          Canvas.MoveTo(Bounds.Right - 3, Bounds.Top + 7);
          Canvas.LineTo(Bounds.Right - 8, Bounds.Top + 11);
        end;
      end;
  end;
end;

procedure TVectArtEditShortcutControl.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  if Button = mbLeft then
  begin
    Index := EnsureRange(X div BUTTON_WIDTH, 0, BUTTON_COUNT - 1);
    if (Index = 1) and Assigned(FOnOpenRequest) then
      FOnOpenRequest(Self)
    else if (Index = 2) and Assigned(FOnSaveRequest) then
      FOnSaveRequest(Self)
    else if (Index = 3) and (FHistory <> nil) and FHistory.CanUndo then
      FHistory.Undo
    else if (Index = 4) and (FHistory <> nil) and FHistory.CanRedo then
      FHistory.Redo;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtEditShortcutControl.Paint;
const
  CAPTIONS: array[0..BUTTON_COUNT - 1] of string =
    ('New', 'Open', 'Save', 'Undo', 'Redo');
var
  I: Integer;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  for I := 0 to BUTTON_COUNT - 1 do
    DrawButton(I, CAPTIONS[I]);
end;

procedure TVectArtEditShortcutControl.RefreshState;
begin
  Invalidate;
end;

procedure TVectArtEditShortcutControl.SetHistory(
  const Value: TVectArtEditHistory);
begin
  FHistory := Value;
  RefreshState;
end;

{ TVectArtEditActionsUI }

constructor TVectArtEditActionsUI.CreateForHosts(AOwner: TComponent;
  AMainForm, AMenuBar, AShortcutHost: TWinControl);
begin
  inherited Create(AOwner);
  FMenu := TVectArtDarkPopupMenu.CreateForHosts(Self, AMainForm, AMenuBar,
    '編集', 56, 36, 190, 160);
  FUndoItem := NewMenuItem('Undo    Ctrl+Z', 0, UndoClick);
  FRedoItem := NewMenuItem('Redo    Ctrl+Y', 32, RedoClick);
  FCanvasSettingsItem := NewMenuItem('キャンバスの設定', 64,
    CanvasSettingsClick);
  FMifCompatibleModeItem := NewMenuItem('□ モード: MIF互換', 96,
    MifCompatibleModeClick);
  FStandardModeItem := NewMenuItem('✓ モード: 標準', 128,
    StandardModeClick);
  FCanvasSettingsVisible := True;

  FShortcutControl := TVectArtEditShortcutControl.Create(Self);
  FShortcutControl.Parent := AShortcutHost;
  FShortcutControl.Align := alClient;
end;

procedure TVectArtEditActionsUI.MifCompatibleModeClick(Sender: TObject);
begin
  FMenu.Close;
  if FDocument <> nil then
    FDocument.EditingMode := vemMifCompatible;
  RefreshState;
end;

procedure TVectArtEditActionsUI.CanvasSettingsClick(Sender: TObject);
begin
  FMenu.Close;
  if FCanvasSettingsVisible and Assigned(FOnCanvasSettingsRequest) then
    FOnCanvasSettingsRequest(Self);
end;

function TVectArtEditActionsUI.NewMenuItem(const Caption: string;
  Top: Integer; ClickHandler: TNotifyEvent): TPanel;
begin
  Result := FMenu.AddItem(Caption, Top, ClickHandler);
end;

procedure TVectArtEditActionsUI.RedoClick(Sender: TObject);
begin
  FMenu.Close;
  if (FHistory <> nil) and FHistory.CanRedo then
    FHistory.Redo;
end;

procedure TVectArtEditActionsUI.RefreshState;
begin
  FShortcutControl.RefreshState;
  FUndoItem.Enabled := (FHistory <> nil) and FHistory.CanUndo;
  FRedoItem.Enabled := (FHistory <> nil) and FHistory.CanRedo;
  if FUndoItem.Enabled then FUndoItem.Font.Color := COLOR_TEXT
  else FUndoItem.Font.Color := COLOR_DISABLED;
  if FRedoItem.Enabled then FRedoItem.Font.Color := COLOR_TEXT
  else FRedoItem.Font.Color := COLOR_DISABLED;
  if (FDocument <> nil) and
    (FDocument.EditingMode = vemMifCompatible) then
  begin
    FMifCompatibleModeItem.Caption := '✓ モード: MIF互換';
    FStandardModeItem.Caption := '□ モード: 標準';
  end
  else
  begin
    FMifCompatibleModeItem.Caption := '□ モード: MIF互換';
    FStandardModeItem.Caption := '✓ モード: 標準';
  end;
end;

procedure TVectArtEditActionsUI.SetDocument(const Value: TVectArtDocument);
begin
  FDocument := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetHistory(const Value: TVectArtEditHistory);
begin
  FHistory := Value;
  FShortcutControl.History := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetCanvasSettingsVisible(
  const Value: Boolean);
begin
  FCanvasSettingsVisible := Value;
  FCanvasSettingsItem.Visible := Value;
  if Value then
  begin
    FMifCompatibleModeItem.Top := 96;
    FStandardModeItem.Top := 128;
    FMenu.PopupHeight := 160
  end
  else
  begin
    FMifCompatibleModeItem.Top := 64;
    FStandardModeItem.Top := 96;
    FMenu.PopupHeight := 128;
  end;
end;

procedure TVectArtEditActionsUI.SetOnOpenRequest(const Value: TNotifyEvent);
begin
  FOnOpenRequest := Value;
  FShortcutControl.OnOpenRequest := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.SetOnSaveRequest(const Value: TNotifyEvent);
begin
  FOnSaveRequest := Value;
  FShortcutControl.OnSaveRequest := Value;
  RefreshState;
end;

procedure TVectArtEditActionsUI.StandardModeClick(Sender: TObject);
begin
  FMenu.Close;
  if FDocument <> nil then
    FDocument.EditingMode := vemStandard;
  RefreshState;
end;

procedure TVectArtEditActionsUI.UndoClick(Sender: TObject);
begin
  FMenu.Close;
  if (FHistory <> nil) and FHistory.CanUndo then
    FHistory.Undo;
end;

end.
