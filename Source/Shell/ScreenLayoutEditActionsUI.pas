// Editメニューとコード描画Undo／Redoショートカットを構築・管理する。
unit ScreenLayoutEditActionsUI;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  VectArtDarkPopupMenu, ScreenLayoutDocument, ScreenLayoutEditHistory;

type
  TVectArtEditShortcutControl = class(TCustomControl)
  private
    FDocument: TVectArtDocument;
    FHistory: TVectArtEditHistory;
    function ButtonEnabled(Index: Integer): Boolean;
    function ButtonRect(Index: Integer): TRect;
    function CanApplyShapeBoolean: Boolean;
    procedure DrawButton(Index: Integer; const Caption: string);
    procedure DrawIcon(Index: Integer; const Bounds: TRect);
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetHistory(const Value: TVectArtEditHistory);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshState;
    property Document: TVectArtDocument read FDocument write SetDocument;
    property History: TVectArtEditHistory read FHistory write SetHistory;
  end;

  TVectArtEditActionsUI = class(TComponent)
  private
    FCanvasSettingsItem: TPanel;
    FCanvasSettingsVisible: Boolean;
    FDocument: TVectArtDocument;
    FHistory: TVectArtEditHistory;
    FMenu: TVectArtDarkPopupMenu;
    FOnCanvasSettingsRequest: TNotifyEvent;
    FRedoItem: TPanel;
    FShortcutControl: TVectArtEditShortcutControl;
    FUndoItem: TPanel;
    procedure CanvasSettingsClick(Sender: TObject);
    function NewMenuItem(const Caption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel;
    procedure RedoClick(Sender: TObject);
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetHistory(const Value: TVectArtEditHistory);
    procedure SetCanvasSettingsVisible(const Value: Boolean);
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
  end;

implementation

uses
  Vcl.Graphics, ScreenLayoutShapeBooleanOperations;

const
  BUTTON_UNDO_INDEX      = 0;
  BUTTON_REDO_INDEX      = 1;
  BUTTON_UNION_INDEX     = 2;
  BUTTON_SUBTRACT_INDEX  = 3;
  BUTTON_INTERSECT_INDEX = 4;
  BUTTON_XOR_INDEX       = 5;
  BUTTON_COUNT           = 6;
  BUTTON_WIDTH           = 78;
  COLOR_BACKGROUND = TColor($00282828);
  COLOR_BUTTON = TColor($00303030);
  COLOR_DISABLED = TColor($00757575);
  COLOR_TEXT = TColor($00E6E6E6);

{ TVectArtEditShortcutControl }

function TVectArtEditShortcutControl.ButtonEnabled(Index: Integer): Boolean;
begin
  case Index of
    BUTTON_UNDO_INDEX: Result := (FHistory <> nil) and FHistory.CanUndo;
    BUTTON_REDO_INDEX: Result := (FHistory <> nil) and FHistory.CanRedo;
    BUTTON_UNION_INDEX..BUTTON_XOR_INDEX: Result := CanApplyShapeBoolean;
  else
    Result := False;
  end;
end;

function TVectArtEditShortcutControl.ButtonRect(Index: Integer): TRect;
begin
  Result := Rect(Index * BUTTON_WIDTH, 0, (Index + 1) * BUTTON_WIDTH,
    ClientHeight);
end;

function TVectArtEditShortcutControl.CanApplyShapeBoolean: Boolean;
begin
  Result := CanExecuteScreenLayoutShapeBoolean(FDocument);
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
var
  IconColor: TColor;
begin
  Canvas.Pen.Width := 1;
  if ButtonEnabled(Index) then
    IconColor := COLOR_TEXT
  else
    IconColor := COLOR_DISABLED;
  Canvas.Pen.Color := IconColor;
  Canvas.Brush.Style := bsClear;
  case Index of
    BUTTON_UNDO_INDEX, BUTTON_REDO_INDEX:
      begin
        Canvas.Arc(Bounds.Left + 3, Bounds.Top + 4, Bounds.Right - 3,
          Bounds.Bottom - 2, Bounds.Right - 4, Bounds.Top + 7,
          Bounds.Left + 4, Bounds.Top + 7);
        if Index = BUTTON_UNDO_INDEX then
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
    BUTTON_UNION_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Left + 8, Bounds.Top + 10);
        Canvas.LineTo(Bounds.Right - 5, Bounds.Top + 10);
        Canvas.MoveTo(Bounds.Left + 11, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Left + 11, Bounds.Bottom - 5);
      end;
    BUTTON_SUBTRACT_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Left + 9, Bounds.Top + 9);
        Canvas.LineTo(Bounds.Right - 3, Bounds.Top + 9);
      end;
    BUTTON_INTERSECT_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.Brush.Color := IconColor;
        Canvas.Brush.Style := bsSolid;
        Canvas.FillRect(Rect(Bounds.Left + 7, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 6));
        Canvas.Brush.Style := bsClear;
      end;
    BUTTON_XOR_INDEX:
      begin
        Canvas.Rectangle(Bounds.Left + 2, Bounds.Top + 7,
          Bounds.Right - 6, Bounds.Bottom - 1);
        Canvas.Rectangle(Bounds.Left + 7, Bounds.Top + 2,
          Bounds.Right - 1, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Left + 8, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Right - 5, Bounds.Bottom - 6);
        Canvas.MoveTo(Bounds.Right - 5, Bounds.Top + 7);
        Canvas.LineTo(Bounds.Left + 8, Bounds.Bottom - 6);
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
    Index := X div BUTTON_WIDTH;
    if (Index >= 0) and (Index < BUTTON_COUNT) then
    begin
      if (Index = BUTTON_UNDO_INDEX) and (FHistory <> nil) and
        FHistory.CanUndo then
        FHistory.Undo
      else if (Index = BUTTON_REDO_INDEX) and (FHistory <> nil) and
        FHistory.CanRedo then
        FHistory.Redo
      else if (Index = BUTTON_UNION_INDEX) and CanApplyShapeBoolean then
        ExecuteScreenLayoutShapeBoolean(FDocument, FHistory, slsboUnion)
      else if (Index = BUTTON_SUBTRACT_INDEX) and CanApplyShapeBoolean then
        ExecuteScreenLayoutShapeBoolean(FDocument, FHistory, slsboSubtract)
      else if (Index = BUTTON_INTERSECT_INDEX) and CanApplyShapeBoolean then
        ExecuteScreenLayoutShapeBoolean(FDocument, FHistory, slsboIntersect)
      else if (Index = BUTTON_XOR_INDEX) and CanApplyShapeBoolean then
        ExecuteScreenLayoutShapeBoolean(FDocument, FHistory, slsboXor);
    end;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtEditShortcutControl.Paint;
const
  CAPTIONS: array[0..BUTTON_COUNT - 1] of string =
    ('Undo', 'Redo', '加算', '減算', 'AND', 'XOR');
var
  I: Integer;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  for I := 0 to BUTTON_COUNT - 1 do
    DrawButton(I, CAPTIONS[I]);
end;

procedure TVectArtEditShortcutControl.MouseMove(Shift: TShiftState;
  X, Y: Integer);
var
  Index: Integer;
begin
  Index := X div BUTTON_WIDTH;
  if (Index < 0) or (Index >= BUTTON_COUNT) then
  begin
    Hint := '';
    inherited MouseMove(Shift, X, Y);
    Exit;
  end;
  case Index of
    BUTTON_UNDO_INDEX: Hint := '元に戻す';
    BUTTON_REDO_INDEX: Hint := 'やり直す';
    BUTTON_UNION_INDEX: Hint := '選択したShapeを加算';
    BUTTON_SUBTRACT_INDEX:
      Hint := 'アクティブShapeからほかの選択Shapeを減算';
    BUTTON_INTERSECT_INDEX: Hint := '選択したShapeの共通部分を残す';
    BUTTON_XOR_INDEX: Hint := '選択したShapeの重ならない部分を残す';
  end;
  inherited MouseMove(Shift, X, Y);
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

procedure TVectArtEditShortcutControl.SetDocument(
  const Value: TVectArtDocument);
begin
  FDocument := Value;
  RefreshState;
end;

{ TVectArtEditActionsUI }

constructor TVectArtEditActionsUI.CreateForHosts(AOwner: TComponent;
  AMainForm, AMenuBar, AShortcutHost: TWinControl);
begin
  inherited Create(AOwner);
  FMenu := TVectArtDarkPopupMenu.CreateForHosts(Self, AMainForm, AMenuBar,
    '編集', 0, 36, 190, 96);
  FUndoItem := NewMenuItem('Undo    Ctrl+Z', 0, UndoClick);
  FRedoItem := NewMenuItem('Redo    Ctrl+Y', 32, RedoClick);
  FCanvasSettingsItem := NewMenuItem('キャンバスの設定', 64,
    CanvasSettingsClick);
  FCanvasSettingsVisible := True;

  FShortcutControl := TVectArtEditShortcutControl.Create(Self);
  FShortcutControl.Parent := AShortcutHost;
  FShortcutControl.Align := alClient;
  FShortcutControl.ShowHint := True;
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
end;

procedure TVectArtEditActionsUI.SetDocument(const Value: TVectArtDocument);
begin
  FDocument := Value;
  FShortcutControl.Document := Value;
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
    FMenu.PopupHeight := 96
  else
    FMenu.PopupHeight := 64;
end;

procedure TVectArtEditActionsUI.UndoClick(Sender: TObject);
begin
  FMenu.Close;
  if (FHistory <> nil) and FHistory.CanUndo then
    FHistory.Undo;
end;

end.
