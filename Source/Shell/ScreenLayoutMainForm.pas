// ScreenLayoutのメイン画面を提供する。
// 個別ツールの内容はFrameへ分離し、このユニットは外枠と初期配置だけを担当する。
unit ScreenLayoutMainForm;

interface

uses
  System.Classes, System.SysUtils, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.StdCtrls, Winapi.Messages, Winapi.ShellAPI, Winapi.Windows,
  ShortcutAction, VectArtDarkPopupMenu, ScreenLayoutContext,
  ScreenLayoutDockManager,
  ScreenLayoutDocument,
  ScreenLayoutEditHistory, ScreenLayoutEditorState,
  ScreenLayoutEditorWorkspaceFrame, ScreenLayoutLayerPanelFrame,
  ScreenLayoutLineToolbar,
  ScreenLayoutLayerOperations, ScreenLayoutEditActionsUI,
  ScreenLayoutGroupCommands,
  ScreenLayoutObjectPropertiesFrame, ScreenLayoutToolFrames,
  ScreenLayoutToolPaletteFrame;

type
  TMainForm = class(TForm)
    pnlMenuBar: TPanel;
    lblMenuItems: TLabel;
    pnlViewMenuButton: TPanel;
    pnlViewMenuPopup: TPanel;
    pnlLayoutEditMenuItem: TPanel;
    pnlShortcutBar: TPanel;
    lblShortcutItems: TLabel;
    pnlStatusBar: TPanel;
    lblStatus: TLabel;
    pnlWorkspace: TPanel;
    pnlLeftDockArea: TPanel;
    splLeftRegion: TSplitter;
    pnlRightDockArea: TPanel;
    splRightRegion: TSplitter;
    pnlEditorHost: TPanel;
    pnlLeftDropTarget: TPanel;
    pnlRightDropTarget: TPanel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure lblLayoutEditMenuItemClick(Sender: TObject);
  private
    FDockManager: TVectDockManager;
    FDesignerContext: IVectArtDesignerContext;
    FDocument: TVectArtDocument;
    FCurrentDocumentFileName: string;
    FEditorFrame: TEditorWorkspaceFrame;
    FEditorState: TVectArtEditorState;
    FEditActionsUI: TVectArtEditActionsUI;
    FEditHistory: TVectArtEditHistory;
    FFileDropCaptionBase: string;
    FFileDropCaptionEnabled: Boolean;
    FFileMenu: TVectArtDarkPopupMenu;
    FLayerFrame: TLayerPanelFrame;
    FLineToolbar: TVectArtLineToolbarControl;
    FObjectPropertiesFrame: TObjectPropertiesFrame;
    FSkiaAcquired: Boolean;
    FShortcuts: TShortcutAction;
    FToolPaletteFrame: TToolPaletteFrame;
    FViewMenu: TVectArtDarkPopupMenu;
    FLayoutEditing: Boolean;
    FLayoutFileName: string;
    FMenuGroup: TVectArtDarkMenuGroup;
    FLayerMenuItem: TPanel;
    FObjectPropertiesMenuItem: TPanel;
    FToolPaletteMenuItem: TPanel;
    procedure ActivateToolShortcut(const Tool: TVectArtEditorTool);
    procedure AttachFrame(AFrame: TFrame; AHost: TWinControl);
    procedure CanvasSettingsRequest(Sender: TObject);
    function CreateViewMenuItem(const Caption: string): TPanel;
    procedure DocumentChanged(Sender: TObject);
    procedure FinalizeSkiaRuntime;
    procedure FileOpenClick(Sender: TObject);
    procedure FileSaveClick(Sender: TObject);
    procedure HistoryChanged(Sender: TObject);
    procedure EditorStateChanged(Sender: TObject);
    procedure InitializeSkiaRuntime;
    procedure InitializeShortcuts;
    function IsEditingSurfaceFocused: Boolean;
    function IsTextInputFocused: Boolean;
    function ToolShortcutEnabled: Boolean;
    function VertexShortcutEnabled: Boolean;
    procedure LoadLayoutSettings;
    procedure LoadDocument;
    procedure SaveLayoutSettings;
    procedure SaveDocumentAs;
    procedure SelectAllLayers;
    procedure SetLayoutEditing(const Value: Boolean);
    procedure ToolMenuItemClick(Sender: TObject);
    procedure ToolVisibilityChanged(Sender: TToolPlaceholderFrame);
    procedure UpdateLayoutEditMenu;
    procedure UpdateToolMenuItems;
    procedure WMDropFiles(var Message: TWMDropFiles); message WM_DROPFILES;
  public
    // 単独アプリだけがJSONの読込・保存メニューを生成するための初期化口。
    procedure EnableStandaloneFileActions;
    // 外部ホストが編集メニュー内のキャンバス設定項目を表示するか切り替える。
    procedure SetCanvasSettingsVisible(const Value: Boolean);
    // ウィンドウへドロップされた画像ファイルの配置を有効化する。
    procedure SetFileDropCaptionEnabled(const Value: Boolean);
    // プラグインホストが編集中だけ表示する参照背景を設定する。
    procedure SetReferenceBackgroundRgba(const Pixels: TBytes;
      Width, Height: Integer);
    // プラグインなど外部ホストが、同じ編集UIへDocumentを受け渡すための接続口。
    property Document: TVectArtDocument read FDocument;
  end;

var
  MainForm: TMainForm;

implementation

uses
  System.IniFiles, System.IOUtils, System.Math, System.Types,
  TextRendererSkiaBootstrap, TextRendererSkiaRuntime,
  ScreenLayoutCanvasSettingsDialog,
  ScreenLayoutDocumentJson, ScreenLayoutImageImport,
  ScreenLayoutKeyboardMovement,
  Vcl.Dialogs, Winapi.Dwmapi;

{$R *.dfm}

const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

function CheckedMenuCaption(const IsVisible: Boolean;
  const Caption: string): string;
begin
  if IsVisible then
    Result := '✓ ' + Caption
  else
    Result := '□ ' + Caption;
end;

procedure TMainForm.ActivateToolShortcut(const Tool: TVectArtEditorTool);
begin
  if FEditorState <> nil then
    FEditorState.ActivateTool(Tool);
end;

function ConstrainToMonitor(const Bounds: TRect): TRect;
var
  Monitor: TMonitor;
  WorkArea: TRect;
begin
  Result := Bounds;
  Monitor := Screen.MonitorFromRect(Result, mdNearest);
  WorkArea := Monitor.WorkareaRect;
  if Result.Width > WorkArea.Width then
    Result.Right := Result.Left + WorkArea.Width;
  if Result.Height > WorkArea.Height then
    Result.Bottom := Result.Top + WorkArea.Height;
  if Result.Left < WorkArea.Left then
    OffsetRect(Result, WorkArea.Left - Result.Left, 0);
  if Result.Top < WorkArea.Top then
    OffsetRect(Result, 0, WorkArea.Top - Result.Top);
  if Result.Right > WorkArea.Right then
    OffsetRect(Result, WorkArea.Right - Result.Right, 0);
  if Result.Bottom > WorkArea.Bottom then
    OffsetRect(Result, 0, WorkArea.Bottom - Result.Bottom);
end;

procedure TMainForm.AttachFrame(AFrame: TFrame; AHost: TWinControl);
begin
  AFrame.Parent := AHost;
  AFrame.Align := alClient;
  AFrame.Visible := True;
end;

function TMainForm.CreateViewMenuItem(const Caption: string): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := pnlViewMenuPopup;
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.Caption := Caption;
  Result.Color := pnlViewMenuPopup.Color;
  Result.Font.Assign(pnlLayoutEditMenuItem.Font);
  Result.Height := 32;
  Result.ParentBackground := False;
  Result.OnClick := ToolMenuItemClick;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  DarkModeEnabled: BOOL;
  LayoutFolder: string;
begin
  DarkModeEnabled := True;
  DwmSetWindowAttribute(Handle, DWMWA_USE_IMMERSIVE_DARK_MODE,
    @DarkModeEnabled, SizeOf(DarkModeEnabled));

  InitializeSkiaRuntime;

  FDocument := TVectArtDocument.Create;
  FDocument.OnChanged := DocumentChanged;
  FEditorState := TVectArtEditorState.Create;
  FEditorState.OnChanged := EditorStateChanged;
  FEditHistory := TVectArtEditHistory.Create;
  FEditHistory.OnChanged := HistoryChanged;
  FDesignerContext := TVectArtDesignerContext.Create(FDocument, FEditHistory,
    FEditorState);
  lblMenuItems.Visible := False;
  lblShortcutItems.Visible := False;
  FEditActionsUI := TVectArtEditActionsUI.CreateForHosts(Self, Self,
    pnlMenuBar, pnlShortcutBar);
  FEditActionsUI.Document := FDocument;
  FEditActionsUI.History := FEditHistory;
  FEditActionsUI.OnCanvasSettingsRequest := CanvasSettingsRequest;
  pnlViewMenuButton.Left := 36;
  FLineToolbar := TVectArtLineToolbarControl.CreateForHost(Self,
    pnlShortcutBar);
  FLineToolbar.Document := FDocument;
  FLineToolbar.EditHistory := FEditHistory;
  FLineToolbar.EditorState := FEditorState;
  FLineToolbar.BringToFront;
  FViewMenu := TVectArtDarkPopupMenu.CreateForControls(Self, Self,
    pnlViewMenuButton, pnlViewMenuPopup);
  FMenuGroup := TVectArtDarkMenuGroup.Create(Self);
  FMenuGroup.RegisterMenu(FEditActionsUI.Menu);
  FMenuGroup.RegisterMenu(FViewMenu);
  FEditorFrame := TEditorWorkspaceFrame.Create(Self);
  FEditorFrame.Context := FDesignerContext;
  AttachFrame(FEditorFrame, pnlEditorHost);

  FDockManager := TVectDockManager.Create(Self, pnlWorkspace,
    pnlLeftDockArea, pnlRightDockArea, pnlLeftDropTarget,
    pnlRightDropTarget, splLeftRegion, splRightRegion);
  FLayerFrame := TLayerPanelFrame.Create(Self);
  FToolPaletteFrame := TToolPaletteFrame.Create(Self);
  FObjectPropertiesFrame := TObjectPropertiesFrame.Create(Self);
  // Context設定は、各Frameが正式なドックスロットへ接続された後に行う。
  FDockManager.RegisterTool(FLayerFrame, vdsLeft);
  FDockManager.RegisterTool(FToolPaletteFrame, vdsLeft);
  FDockManager.RegisterTool(FObjectPropertiesFrame, vdsRight);
  FLayerFrame.Context := FDesignerContext;
  FToolPaletteFrame.Context := FDesignerContext;
  FObjectPropertiesFrame.Context := FDesignerContext;
  FDockManager.OnToolVisibilityChanged := ToolVisibilityChanged;

  pnlViewMenuPopup.Height := 128;
  pnlLayoutEditMenuItem.Align := alTop;
  FObjectPropertiesMenuItem := CreateViewMenuItem('Object Properties');
  FToolPaletteMenuItem := CreateViewMenuItem('Tools');
  FLayerMenuItem := CreateViewMenuItem('Layers');

  LayoutFolder := TPath.Combine(TPath.GetDocumentsPath, 'ScreenDesignMaker');
  FLayoutFileName := TPath.Combine(LayoutFolder, 'MainForm.ini');
  try
    TDirectory.CreateDirectory(LayoutFolder);
  except
    on E: Exception do
      lblStatus.Caption := 'Layout folder error: ' + E.Message;
  end;

  FLayoutEditing := False;
  FViewMenu.Close;
  UpdateLayoutEditMenu;
  UpdateToolMenuItems;
  LoadLayoutSettings;
  InitializeShortcuts;
  HistoryChanged(FEditHistory);
  EditorStateChanged(FEditorState);
end;

procedure TMainForm.CanvasSettingsRequest(Sender: TObject);
var
  CanvasHeight: Integer;
  CanvasWidth: Integer;
begin
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) then
    Exit;
  if ExecuteCanvasSettingsDialog(Self, FDocument.CanvasLayer.Width,
    FDocument.CanvasLayer.Height, CanvasWidth, CanvasHeight) then
  begin
    FDocument.SetCanvasSize(CanvasWidth, CanvasHeight);
    EditorStateChanged(FEditorState);
  end;
end;

procedure TMainForm.DocumentChanged(Sender: TObject);
begin
  if FEditorState <> nil then
    FEditorState.ValidateOpenGroupPath(FDocument);
  if FEditActionsUI <> nil then
    FEditActionsUI.RefreshState;
  if FEditorFrame <> nil then
    FEditorFrame.CanvasControl.Invalidate;
  if FLayerFrame <> nil then
    FLayerFrame.RefreshFromDocument;
  if (FDocument <> nil) and FDocument.IsInteractiveUpdate then
    Exit;
  if FLayerFrame <> nil then
    FLayerFrame.RefreshFromDocument;
  if FObjectPropertiesFrame <> nil then
    FObjectPropertiesFrame.RefreshFromDocument;
  if FLineToolbar <> nil then
    FLineToolbar.RefreshState;
  EditorStateChanged(FEditorState);
end;

procedure TMainForm.EnableStandaloneFileActions;
begin
  SetFileDropCaptionEnabled(True);
  if FFileMenu <> nil then
    Exit;
  FEditActionsUI.Menu.Button.Left := 56;
  pnlViewMenuButton.Left := 92;
  FFileMenu := TVectArtDarkPopupMenu.CreateForHosts(Self, Self, pnlMenuBar,
    'ファイル', 0, 56, 220, 64);
  FFileMenu.AddItem('JSONを開く...    Ctrl+O', 0, FileOpenClick);
  FFileMenu.AddItem('JSONへ保存...    Ctrl+S', 32, FileSaveClick);
  FMenuGroup.RegisterMenu(FFileMenu);
end;

procedure TMainForm.FileOpenClick(Sender: TObject);
begin
  if FFileMenu <> nil then
    FFileMenu.Close;
  LoadDocument;
end;

procedure TMainForm.FileSaveClick(Sender: TObject);
begin
  if FFileMenu <> nil then
    FFileMenu.Close;
  SaveDocumentAs;
end;

procedure TMainForm.SetReferenceBackgroundRgba(const Pixels: TBytes;
  Width, Height: Integer);
begin
  if (FEditorFrame <> nil) and (FEditorFrame.CanvasControl <> nil) then
    FEditorFrame.CanvasControl.SetReferenceBackgroundRgba(Pixels,
      Width, Height);
end;

procedure TMainForm.SetCanvasSettingsVisible(const Value: Boolean);
begin
  if FEditActionsUI <> nil then
    FEditActionsUI.CanvasSettingsVisible := Value;
end;

procedure TMainForm.EditorStateChanged(Sender: TObject);
var
  CanvasSize: string;
  VertexMode: string;
begin
  if FEditorFrame <> nil then
    FEditorFrame.CanvasControl.Invalidate;
  if FLayerFrame <> nil then
    FLayerFrame.RefreshFromDocument;
  if FObjectPropertiesFrame <> nil then
    FObjectPropertiesFrame.RefreshFromDocument;
  if FToolPaletteFrame <> nil then
    FToolPaletteFrame.RefreshState;
  if FLineToolbar <> nil then
    FLineToolbar.RefreshState;
  if (FDocument <> nil) and (FDocument.CanvasLayer <> nil) then
    CanvasSize := Format('%d x %d', [FDocument.CanvasLayer.Width,
      FDocument.CanvasLayer.Height])
  else
    CanvasSize := '-';
  VertexMode := 'Sharp';
  if (FEditorState <> nil) and
    (FEditorState.NextVertexKind = slvkBezier) then
    VertexMode := 'Bezier';
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRectangleLine) then
    lblStatus.Caption := 'Ready   Tool: Rectangle Line   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRectangle) then
    lblStatus.Caption := 'Ready   Tool: Rectangle   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRoundedRectangleLine) then
    lblStatus.Caption := 'Ready   Tool: Rounded Rectangle Line   Canvas: ' +
      CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRoundedRectangle) then
    lblStatus.Caption := 'Ready   Tool: Rounded Rectangle   Canvas: ' +
      CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetEllipseLine) then
    lblStatus.Caption := 'Ready   Tool: Ellipse Line   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetEllipse) then
    lblStatus.Caption := 'Ready   Tool: Ellipse   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetArc) then
    lblStatus.Caption := 'Ready   Tool: Arc   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetArcShape) then
    lblStatus.Caption := 'Ready   Tool: Arc Shape   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetLine) then
    lblStatus.Caption := 'Ready   Tool: Line   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetPath) then
    lblStatus.Caption := 'Path (' + VertexMode +
      '): V sharp / B bezier, click vertices, ' +
      'double-click/right-click to finish   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetShape) then
    lblStatus.Caption := 'Shape (' + VertexMode +
      '): click at least three vertices, then click ' +
      'the first point or double-click/right-click to close   Canvas: ' +
      CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetText) then
    lblStatus.Caption := 'Text: drag an input guide, type, click outside to ' +
      'finish   Canvas: ' + CanvasSize
  else
    lblStatus.Caption := 'Ready   Tool: Select   Canvas: ' + CanvasSize;
  if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
  begin
    lblStatus.Caption := lblStatus.Caption + '   Open group: ' +
      FEditorState.OpenGroup.Name;
    if FEditorState.OpenGroupDepth > 1 then
      lblStatus.Caption := lblStatus.Caption + '   Esc: parent group'
    else
      lblStatus.Caption := lblStatus.Caption + '   Esc: close';
  end;
  if (FEditorState <> nil) and (FEditorState.OpenGroupChild <> nil) then
    lblStatus.Caption := lblStatus.Caption + '   Child: ' +
      FEditorState.OpenGroupChild.Name;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (FFileMenu <> nil) and (Key = Ord('O')) and (Shift = [ssCtrl]) then
  begin
    LoadDocument;
    Key := 0;
    Exit;
  end;
  if (FFileMenu <> nil) and (Key = Ord('S')) and (Shift = [ssCtrl]) then
  begin
    SaveDocumentAs;
    Key := 0;
    Exit;
  end;
  if (FShortcuts <> nil) and FShortcuts.KeyDown(Key, Shift) then
    Exit;
  if (FEditorFrame <> nil) and
    (GetFocus = FEditorFrame.CanvasControl.Handle) and
    HandleSelectionNudge(FDocument, FEditHistory, Key, Shift) then
    Key := 0;
end;

procedure TMainForm.LoadDocument;
var
  ErrorMessage: string;
  OpenDialog: TFileOpenDialog;
  SkippedReferenceCount: Integer;
begin
  if FDocument = nil then
    Exit;
  OpenDialog := TFileOpenDialog.Create(Self);
  try
    try
      OpenDialog.Title := '画面レイアウトJSONを開く';
      OpenDialog.DefaultExtension := 'json';
      OpenDialog.Options := [fdoFileMustExist, fdoPathMustExist,
        fdoForceFileSystem];
      with OpenDialog.FileTypes.Add do
      begin
        DisplayName := 'JSONファイル (*.json)';
        FileMask := '*.json';
      end;
      OpenDialog.FileTypeIndex := 1;
      if FCurrentDocumentFileName <> '' then
      begin
        OpenDialog.DefaultFolder := ExtractFilePath(
          FCurrentDocumentFileName);
        OpenDialog.FileName := ExtractFileName(FCurrentDocumentFileName);
      end
      else
        OpenDialog.DefaultFolder := TPath.GetDocumentsPath;
      if not OpenDialog.Execute(Handle) then
        Exit;
      if FEditorState <> nil then
        FEditorState.OpenGroup := nil;
      if not TryLoadVectArtDocumentFromJsonFile(OpenDialog.FileName,
        FDocument, SkippedReferenceCount, ErrorMessage) then
        raise EConvertError.Create(ErrorMessage);
      FCurrentDocumentFileName := OpenDialog.FileName;
      FEditHistory.Clear;
      Caption := 'ScreenDesignMaker - ' +
        ExtractFileName(FCurrentDocumentFileName);
      if SkippedReferenceCount > 0 then
        lblStatus.Caption := Format('Loaded: %s (%d missing references skipped)',
          [FCurrentDocumentFileName, SkippedReferenceCount])
      else
        lblStatus.Caption := 'Loaded: ' + FCurrentDocumentFileName;
    except
      on E: Exception do
      begin
        lblStatus.Caption := 'Load error: ' + E.Message;
        Application.MessageBox(PChar('JSONの読込に失敗しました。' +
          sLineBreak + E.Message), 'ScreenDesignMaker',
          MB_OK or MB_ICONERROR);
      end;
    end;
  finally
    OpenDialog.Free;
  end;
end;

procedure TMainForm.SaveDocumentAs;
var
  JsonText: string;
  SaveDialog: TFileSaveDialog;
  Utf8Encoding: TUTF8Encoding;
begin
  if FDocument = nil then
    Exit;
  SaveDialog := TFileSaveDialog.Create(Self);
  try
    try
      SaveDialog.Title := '画面レイアウトをJSONへ保存';
      SaveDialog.DefaultExtension := 'json';
      if FCurrentDocumentFileName <> '' then
      begin
        SaveDialog.FileName := ExtractFileName(FCurrentDocumentFileName);
        SaveDialog.DefaultFolder := ExtractFilePath(
          FCurrentDocumentFileName);
      end
      else
      begin
        SaveDialog.FileName := 'ScreenLayout.json';
        SaveDialog.DefaultFolder := TPath.GetDocumentsPath;
      end;
      SaveDialog.Options := [fdoOverWritePrompt, fdoPathMustExist,
        fdoForceFileSystem];
      with SaveDialog.FileTypes.Add do
      begin
        DisplayName := 'JSONファイル (*.json)';
        FileMask := '*.json';
      end;
      SaveDialog.FileTypeIndex := 1;
      if not SaveDialog.Execute(Handle) then
        Exit;
      JsonText := SerializeVectArtDocument(FDocument);
      Utf8Encoding := TUTF8Encoding.Create(False);
      try
        TFile.WriteAllText(SaveDialog.FileName, JsonText, Utf8Encoding);
      finally
        Utf8Encoding.Free;
      end;
      FCurrentDocumentFileName := SaveDialog.FileName;
      Caption := 'ScreenDesignMaker - ' +
        ExtractFileName(FCurrentDocumentFileName);
      lblStatus.Caption := 'Saved: ' + SaveDialog.FileName;
    except
      on E: Exception do
      begin
        lblStatus.Caption := 'Save error: ' + E.Message;
        Application.MessageBox(PChar('JSONの保存に失敗しました。' +
          sLineBreak + E.Message), 'ScreenDesignMaker',
          MB_OK or MB_ICONERROR);
      end;
    end;
  finally
    SaveDialog.Free;
  end;
end;

procedure TMainForm.HistoryChanged(Sender: TObject);
begin
  if FEditActionsUI <> nil then
    FEditActionsUI.RefreshState;
end;

procedure TMainForm.ToolMenuItemClick(Sender: TObject);
begin
  if Sender = FLayerMenuItem then
    FDockManager.SetToolVisible(FLayerFrame,
      not FDockManager.ToolVisible(FLayerFrame))
  else if Sender = FToolPaletteMenuItem then
    FDockManager.SetToolVisible(FToolPaletteFrame,
      not FDockManager.ToolVisible(FToolPaletteFrame))
  else if Sender = FObjectPropertiesMenuItem then
    FDockManager.SetToolVisible(FObjectPropertiesFrame,
      not FDockManager.ToolVisible(FObjectPropertiesFrame));
  FViewMenu.Close;
end;

procedure TMainForm.ToolVisibilityChanged(Sender: TToolPlaceholderFrame);
begin
  UpdateToolMenuItems;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  if FFileDropCaptionEnabled then
    DragAcceptFiles(Handle, False);
  SaveLayoutSettings;
  FreeAndNil(FShortcuts);
  FreeAndNil(FLineToolbar);
  FDockManager.Free;
  if FDocument <> nil then
    FDocument.OnChanged := nil;
  if FEditorFrame <> nil then
    FEditorFrame.Context := nil;
  if FLayerFrame <> nil then
    FLayerFrame.Context := nil;
  if FObjectPropertiesFrame <> nil then
    FObjectPropertiesFrame.Context := nil;
  if FToolPaletteFrame <> nil then
    FToolPaletteFrame.Context := nil;
  FDesignerContext := nil;
  if FEditorState <> nil then
    FEditorState.OnChanged := nil;
  if FEditHistory <> nil then
    FEditHistory.OnChanged := nil;
  FreeAndNil(FEditActionsUI);
  FreeAndNil(FEditHistory);
  FreeAndNil(FEditorState);
  FreeAndNil(FDocument);
  FinalizeSkiaRuntime;
end;

procedure TMainForm.SetFileDropCaptionEnabled(const Value: Boolean);
begin
  if FFileDropCaptionEnabled = Value then
    Exit;
  FFileDropCaptionEnabled := Value;
  if Value then
    FFileDropCaptionBase := Caption;
  DragAcceptFiles(Handle, Value);
end;

procedure TMainForm.InitializeShortcuts;
begin
  FShortcuts := TShortcutAction.Create;
  FShortcuts.Add(Ord('S'), [],
    procedure
    begin
      ActivateToolShortcut(vetSelect);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('R'), [],
    procedure
    begin
      ActivateToolShortcut(vetRectangle);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('U'), [],
    procedure
    begin
      ActivateToolShortcut(vetRoundedRectangle);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('C'), [],
    procedure
    begin
      ActivateToolShortcut(vetEllipse);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('A'), [],
    procedure
    begin
      ActivateToolShortcut(vetArcShape);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('L'), [],
    procedure
    begin
      ActivateToolShortcut(vetLine);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('P'), [],
    procedure
    begin
      ActivateToolShortcut(vetPath);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('G'), [],
    procedure
    begin
      ActivateToolShortcut(vetShape);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('T'), [],
    procedure
    begin
      ActivateToolShortcut(vetText);
    end,
    ToolShortcutEnabled);
  FShortcuts.Add(Ord('V'), [],
    procedure
    begin
      FEditorState.NextVertexKind := slvkSharp;
    end,
    VertexShortcutEnabled);
  FShortcuts.Add(Ord('B'), [],
    procedure
    begin
      FEditorState.NextVertexKind := slvkBezier;
    end,
    VertexShortcutEnabled);
  FShortcuts.Add(Ord('Z'), [ssCtrl],
    procedure
    begin
      FEditHistory.Undo;
    end,
    function: Boolean
    begin
      Result := (FEditHistory <> nil) and not IsTextInputFocused;
    end);
  FShortcuts.Add(Ord('Z'), [ssCtrl, ssShift],
    procedure
    begin
      FEditHistory.Redo;
    end,
    function: Boolean
    begin
      Result := (FEditHistory <> nil) and not IsTextInputFocused;
    end);
  FShortcuts.Add(Ord('Y'), [ssCtrl],
    procedure
    begin
      FEditHistory.Redo;
    end,
    function: Boolean
    begin
      Result := (FEditHistory <> nil) and not IsTextInputFocused;
    end);
  FShortcuts.Add(Ord('A'), [ssCtrl],
    procedure
    begin
      SelectAllLayers;
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FDocument <> nil) and
        (FDocument.LayerCount > 1);
    end);
  FShortcuts.Add(Ord('D'), [ssCtrl],
    procedure
    begin
      FLayerFrame.RunLayerAction(vlaDuplicate);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FLayerFrame <> nil) and
        FLayerFrame.CanRunLayerAction(vlaDuplicate);
    end);
  FShortcuts.Add(Ord('G'), [ssCtrl],
    procedure
    begin
      if (FEditorState <> nil) and
        (FEditorState.OpenGroup <> nil) then
        GroupOpenGroupChildren(FDocument, FEditHistory, FEditorState)
      else
        GroupSelectedLayers(FDocument, FEditHistory);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FEditorState <> nil) and
        (((FEditorState.OpenGroup <> nil) and
          CanGroupOpenGroupChildren(FEditorState)) or
         ((FEditorState.OpenGroup = nil) and
          CanGroupSelectedLayers(FDocument)));
    end);
  FShortcuts.Add(Ord('G'), [ssCtrl, ssShift],
    procedure
    begin
      if (FEditorState <> nil) and
        (FEditorState.OpenGroup <> nil) then
        UngroupOpenGroupChild(FDocument, FEditHistory, FEditorState)
      else
        UngroupSelectedLayer(FDocument, FEditHistory);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FEditorState <> nil) and
        (((FEditorState.OpenGroup <> nil) and
          CanUngroupOpenGroupChild(FEditorState)) or
         ((FEditorState.OpenGroup = nil) and
          CanUngroupSelectedLayer(FDocument)));
    end);
  FShortcuts.Add(VK_DELETE, [],
    procedure
    begin
      FLayerFrame.RunLayerAction(vlaDelete);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FLayerFrame <> nil) and
        FLayerFrame.CanRunLayerAction(vlaDelete);
    end);
  FShortcuts.Add(VK_ESCAPE, [],
    procedure
    begin
      if (FEditorState <> nil) and (FEditorState.OpenGroup <> nil) then
        FEditorState.OpenParentGroup
      else
        FDocument.SetSelectedLayers([]);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FDocument <> nil) and
        ((FDocument.SelectionCount > 0) or
         ((FEditorState <> nil) and (FEditorState.OpenGroup <> nil)));
    end);
end;

function TMainForm.IsEditingSurfaceFocused: Boolean;
begin
  Result := ((FEditorFrame <> nil) and
    (GetFocus = FEditorFrame.CanvasControl.Handle)) or
    ((FLayerFrame <> nil) and
    (GetFocus = FLayerFrame.LayerList.Handle));
end;

function TMainForm.IsTextInputFocused: Boolean;
var
  FocusedControl: TWinControl;
begin
  FocusedControl := FindControl(GetFocus);
  Result := (FocusedControl is TCustomEdit) or
    (FocusedControl is TCustomComboBox);
end;

function TMainForm.ToolShortcutEnabled: Boolean;
begin
  Result := (FEditorState <> nil) and not IsTextInputFocused;
end;

function TMainForm.VertexShortcutEnabled: Boolean;
begin
  Result := ToolShortcutEnabled and
    (FEditorState.CurrentTool in [vetPath, vetShape]);
end;

procedure TMainForm.SelectAllLayers;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  if (FDocument = nil) or (FDocument.LayerCount <= 1) then
    Exit;
  SetLength(Indices, FDocument.LayerCount - 1);
  for I := 1 to FDocument.LayerCount - 1 do
    Indices[I - 1] := I;
  FDocument.SetSelectedLayers(Indices);
end;

procedure TMainForm.FinalizeSkiaRuntime;
begin
  if not FSkiaAcquired then
    Exit;
  TTextRendererSkiaRuntime.Release;
  FSkiaAcquired := False;
end;

procedure TMainForm.InitializeSkiaRuntime;
begin
  try
    TTextRendererSkiaRuntime.Acquire(BundledSkiaRuntimeFileName);
    FSkiaAcquired := True;
  except
    on E: Exception do
      lblStatus.Caption := 'Skia runtime error: ' + E.Message;
  end;
end;

procedure TMainForm.LoadLayoutSettings;
var
  Bounds: TRect;
  Ini: TMemIniFile;
  SavedHeight: Integer;
  SavedWidth: Integer;
begin
  if (FLayoutFileName = '') or not TFile.Exists(FLayoutFileName) then
    Exit;
  Ini := nil;
  try
    try
      Ini := TMemIniFile.Create(FLayoutFileName, TEncoding.UTF8);
      if Ini.ReadInteger('File', 'Version', 0) <> 1 then
        Exit;
      SavedWidth := Max(Ini.ReadInteger('MainForm', 'Width', Width),
        Constraints.MinWidth);
      SavedHeight := Max(Ini.ReadInteger('MainForm', 'Height', Height),
        Constraints.MinHeight);
      Bounds := Rect(
        Ini.ReadInteger('MainForm', 'Left', Left),
        Ini.ReadInteger('MainForm', 'Top', Top), 0, 0);
      Bounds.Right := Bounds.Left + SavedWidth;
      Bounds.Bottom := Bounds.Top + SavedHeight;
      Bounds := ConstrainToMonitor(Bounds);
      SetBounds(Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height);
      FDockManager.LoadLayout(Ini);
      if SameText(Ini.ReadString('MainForm', 'WindowState', 'Normal'),
        'Maximized') then
        WindowState := wsMaximized
      else
        WindowState := wsNormal;
      UpdateToolMenuItems;
    except
      on E: Exception do
        lblStatus.Caption := 'Layout load error: ' + E.Message;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.SaveLayoutSettings;
var
  Ini: TMemIniFile;
  Placement: TWindowPlacement;
  SavedBounds: TRect;
begin
  if (FLayoutFileName = '') or (FDockManager = nil) then
    Exit;
  Ini := nil;
  try
    try
      Ini := TMemIniFile.Create(FLayoutFileName, TEncoding.UTF8);
      Placement.Length := SizeOf(Placement);
      if GetWindowPlacement(Handle, @Placement) then
        SavedBounds := Placement.rcNormalPosition
      else
        SavedBounds := BoundsRect;
      Ini.WriteInteger('File', 'Version', 1);
      Ini.WriteInteger('MainForm', 'Left', SavedBounds.Left);
      Ini.WriteInteger('MainForm', 'Top', SavedBounds.Top);
      Ini.WriteInteger('MainForm', 'Width', SavedBounds.Width);
      Ini.WriteInteger('MainForm', 'Height', SavedBounds.Height);
      if WindowState = wsMaximized then
        Ini.WriteString('MainForm', 'WindowState', 'Maximized')
      else
        Ini.WriteString('MainForm', 'WindowState', 'Normal');
      FDockManager.SaveLayout(Ini);
      Ini.UpdateFile;
    except
      on E: Exception do
        lblStatus.Caption := 'Layout save error: ' + E.Message;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.UpdateToolMenuItems;
begin
  FLayerMenuItem.Caption := CheckedMenuCaption(
    FDockManager.ToolVisible(FLayerFrame), 'Layers');
  FToolPaletteMenuItem.Caption := CheckedMenuCaption(
    FDockManager.ToolVisible(FToolPaletteFrame), 'Tools');
  FObjectPropertiesMenuItem.Caption := CheckedMenuCaption(
    FDockManager.ToolVisible(FObjectPropertiesFrame), 'Object Properties');
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  if FDockManager <> nil then
    FDockManager.Resize;
end;

procedure TMainForm.lblLayoutEditMenuItemClick(Sender: TObject);
begin
  SetLayoutEditing(not FLayoutEditing);
  FViewMenu.Close;
end;

procedure TMainForm.SetLayoutEditing(const Value: Boolean);
begin
  if FLayoutEditing = Value then
    Exit;
  FLayoutEditing := Value;
  FDockManager.LayoutEditing := Value;
  UpdateLayoutEditMenu;
end;

procedure TMainForm.UpdateLayoutEditMenu;
begin
  if FLayoutEditing then
    pnlLayoutEditMenuItem.Caption := '✓ レイアウト編集'
  else
    pnlLayoutEditMenuItem.Caption := '□ レイアウト編集';
end;

procedure TMainForm.WMDropFiles(var Message: TWMDropFiles);
var
  CanvasClientPoint: TPoint;
  DropPoint: TPoint;
  DropScreenPoint: TPoint;
  DroppedFileNames: TArray<string>;
  ErrorMessage: string;
  FileCount: UINT;
  FileIndex: UINT;
  FileNameLength: UINT;
  ImportedCount: Integer;
  LogicalDropPoint: TPointF;
begin
  Message.Result := 0;
  try
    FileCount := DragQueryFile(Message.Drop, $FFFFFFFF, nil, 0);
    if FileCount = 0 then
      Exit;
    SetLength(DroppedFileNames, FileCount);
    for FileIndex := 0 to FileCount - 1 do
    begin
      FileNameLength := DragQueryFile(Message.Drop, FileIndex, nil, 0);
      SetLength(DroppedFileNames[FileIndex], FileNameLength);
      DragQueryFile(Message.Drop, FileIndex,
        PChar(DroppedFileNames[FileIndex]), FileNameLength + 1);
    end;

    LogicalDropPoint := TPointF.Zero;
    if DragQueryPoint(Message.Drop, DropPoint) and
      (FEditorFrame <> nil) and (FEditorFrame.CanvasControl <> nil) then
    begin
      DropScreenPoint := ClientToScreen(DropPoint);
      CanvasClientPoint := FEditorFrame.CanvasControl.ScreenToClient(
        DropScreenPoint);
      FEditorFrame.CanvasControl.TryClientPointToLogical(CanvasClientPoint,
        LogicalDropPoint);
    end;
    ImportedCount := ImportScreenLayoutImageFiles(FDocument, FEditHistory,
      DroppedFileNames, LogicalDropPoint, ErrorMessage);
    if ImportedCount > 0 then
    begin
      FEditorState.CurrentTool := vetSelect;
      lblStatus.Caption := Format('%d image(s) imported', [ImportedCount]);
      if ErrorMessage <> '' then
        lblStatus.Caption := lblStatus.Caption + '  ' + ErrorMessage;
      if FFileDropCaptionEnabled and (Length(DroppedFileNames) = 1) then
        Caption := FFileDropCaptionBase + ' - ' +
          ExtractFileName(DroppedFileNames[0]);
    end
    else if ErrorMessage <> '' then
      lblStatus.Caption := 'Image import failed: ' + ErrorMessage;
  finally
    DragFinish(Message.Drop);
  end;
end;

end.
