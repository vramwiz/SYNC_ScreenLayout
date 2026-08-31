// VectArtDesignerのメイン画面を提供する。
// 個別ツールの内容はFrameへ分離し、このユニットは外枠と初期配置だけを担当する。
unit VectArtDesignerMainForm;

interface

uses
  System.Classes, System.SysUtils, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.StdCtrls, Winapi.Messages, Winapi.ShellAPI, Winapi.Windows,
  ShortcutAction, VectArtDarkPopupMenu, VectArtDesignerContext,
  VectArtDesignerDockManager,
  VectArtDesignerDocument,
  VectArtDesignerEditHistory, VectArtDesignerEditorState,
  VectArtDesignerEditorWorkspaceFrame, VectArtDesignerLayerPanelFrame,
  VectArtDesignerLineToolbar,
  VectArtDesignerLayerOperations,
  VectArtDesignerEditActionsUI, VectArtDesignerFileActionsUI,
  VectArtDesignerMifContainer, VectArtDesignerMifDocument,
  VectArtDesignerObjectPropertiesFrame, VectArtDesignerToolFrames,
  VectArtDesignerToolPaletteFrame, VectArtDesignerSvgDocument;

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
    FEditorFrame: TEditorWorkspaceFrame;
    FEditorState: TVectArtEditorState;
    FEditActionsUI: TVectArtEditActionsUI;
    FEditHistory: TVectArtEditHistory;
    FFileDropCaptionBase: string;
    FFileDropCaptionEnabled: Boolean;
    FFileActionsUI: TVectArtFileActionsUI;
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
    FMifContainer: TVectArtMifContainer;
    FMifHasEditableDocument: Boolean;
    FMifReader: IVectArtMifContainerReader;
    FMifWriter: IVectArtMifContainerWriter;
    procedure AttachFrame(AFrame: TFrame; AHost: TWinControl);
    procedure CanvasSettingsRequest(Sender: TObject);
    function CreateViewMenuItem(const Caption: string): TPanel;
    procedure DocumentChanged(Sender: TObject);
    procedure FinalizeSkiaRuntime;
    procedure HistoryChanged(Sender: TObject);
    procedure EditorStateChanged(Sender: TObject);
    procedure FileOpenRequest(Sender: TObject; const FileName: string);
    procedure FileOpenShortcut(Sender: TObject);
    procedure FileSaveRequest(Sender: TObject; const FileName: string);
    procedure FileSaveShortcut(Sender: TObject);
    procedure InitializeSkiaRuntime;
    procedure InitializeShortcuts;
    function IsEditingSurfaceFocused: Boolean;
    function IsTextInputFocused: Boolean;
    procedure LoadLayoutSettings;
    procedure SaveLayoutSettings;
    procedure SelectAllLayers;
    procedure SetLayoutEditing(const Value: Boolean);
    procedure ToolMenuItemClick(Sender: TObject);
    procedure ToolVisibilityChanged(Sender: TToolPlaceholderFrame);
    procedure UpdateLayoutEditMenu;
    procedure UpdateToolMenuItems;
    procedure WMDropFiles(var Message: TWMDropFiles); message WM_DROPFILES;
  public
    // 外部ホストが編集メニュー内のキャンバス設定項目を表示するか切り替える。
    procedure SetCanvasSettingsVisible(const Value: Boolean);
    // 単独アプリ専用のファイルメニューを表示し、非表示時は残りのメニューを左詰めする。
    procedure SetFileMenuVisible(const Value: Boolean);
    // 外部ホストがファイルドロップを確認し、ドロップ名をタイトルへ一時表示する。
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
  System.IniFiles, System.IOUtils, System.Math,
  {$IFDEF DEBUG} VectArtDesignerMifDebugLog, {$ENDIF}
  TextRendererSkiaBootstrap, TextRendererSkiaRuntime,
  VectArtDesignerCanvasSettingsDialog,
  VectArtDesignerKeyboardMovement, Winapi.Dwmapi;

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
  FMifReader := CreateVectArtMifContainerReader;
  FMifWriter := CreateVectArtMifContainerWriter;
  lblMenuItems.Visible := False;
  lblShortcutItems.Visible := False;
  FFileActionsUI := TVectArtFileActionsUI.CreateForHosts(Self, Self,
    pnlMenuBar);
  FFileActionsUI.OnOpenFile := FileOpenRequest;
  FFileActionsUI.OnSaveFile := FileSaveRequest;
  FEditActionsUI := TVectArtEditActionsUI.CreateForHosts(Self, Self,
    pnlMenuBar, pnlShortcutBar);
  FEditActionsUI.Document := FDocument;
  FEditActionsUI.History := FEditHistory;
  FEditActionsUI.OnCanvasSettingsRequest := CanvasSettingsRequest;
  FEditActionsUI.OnOpenRequest := FileOpenShortcut;
  FLineToolbar := TVectArtLineToolbarControl.CreateForHost(Self,
    pnlShortcutBar);
  FLineToolbar.Document := FDocument;
  FLineToolbar.EditHistory := FEditHistory;
  FLineToolbar.EditorState := FEditorState;
  FLineToolbar.BringToFront;
  FViewMenu := TVectArtDarkPopupMenu.CreateForControls(Self, Self,
    pnlViewMenuButton, pnlViewMenuPopup);
  FMenuGroup := TVectArtDarkMenuGroup.Create(Self);
  FMenuGroup.RegisterMenu(FFileActionsUI.Menu);
  FMenuGroup.RegisterMenu(FEditActionsUI.Menu);
  FMenuGroup.RegisterMenu(FViewMenu);
  FEditorFrame := TEditorWorkspaceFrame.Create(Self);
  FEditorFrame.Context := FDesignerContext;
  AttachFrame(FEditorFrame, pnlEditorHost);

  FDockManager := TVectDockManager.Create(Self, pnlWorkspace,
    pnlLeftDockArea, pnlRightDockArea, pnlLeftDropTarget,
    pnlRightDropTarget, splLeftRegion, splRightRegion);
  FLayerFrame := TLayerPanelFrame.Create(Self);
  FLayerFrame.Context := FDesignerContext;
  FToolPaletteFrame := TToolPaletteFrame.Create(Self);
  FToolPaletteFrame.Context := FDesignerContext;
  FObjectPropertiesFrame := TObjectPropertiesFrame.Create(Self);
  FObjectPropertiesFrame.Context := FDesignerContext;
  FDockManager.RegisterTool(FLayerFrame, vdsLeft);
  FDockManager.RegisterTool(FToolPaletteFrame, vdsLeft);
  FDockManager.RegisterTool(FObjectPropertiesFrame, vdsRight);
  FDockManager.OnToolVisibilityChanged := ToolVisibilityChanged;

  pnlViewMenuPopup.Height := 128;
  pnlLayoutEditMenuItem.Align := alTop;
  FObjectPropertiesMenuItem := CreateViewMenuItem('Object Properties');
  FToolPaletteMenuItem := CreateViewMenuItem('Tools');
  FLayerMenuItem := CreateViewMenuItem('Layers');

  LayoutFolder := TPath.Combine(TPath.GetDocumentsPath, 'VectArtDesigner');
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

procedure TMainForm.FileOpenRequest(Sender: TObject; const FileName: string);
var
  Container: TVectArtMifContainer;
  {$IFDEF DEBUG} DebugLogFileName: string; {$ENDIF}
  ErrorMessage: string;
  Extension: string;
  ImportMessage: string;
begin
  ErrorMessage := '';
  Extension := LowerCase(ExtractFileExt(FileName));
  if Extension = '.svg' then
  begin
    if not TryLoadVectArtDocumentFromSvgFile(FileName, FDocument,
      ErrorMessage) then
    begin
      lblStatus.Caption := 'SVG open error: ' + ErrorMessage;
      Exit;
    end;
    FreeAndNil(FMifContainer);
    FMifHasEditableDocument := True;
    if FEditHistory <> nil then
      FEditHistory.Clear;
    DocumentChanged(FDocument);
    FFileActionsUI.CurrentFileName := FileName;
    FFileActionsUI.CanSave := True;
    FEditActionsUI.OnSaveRequest := FileSaveShortcut;
    Caption := 'VectArtDesigner - ' + ExtractFileName(FileName);
    lblStatus.Caption := 'SVG document loaded: ' + ExtractFileName(FileName);
    Exit;
  end;
  if Extension <> '.mif' then
  begin
    lblStatus.Caption := 'Open error: unsupported file extension';
    Exit;
  end;
  if (FMifReader = nil) or
    not FMifReader.TryReadFile(FileName, Container, ErrorMessage) then
  begin
    lblStatus.Caption := 'MIF open error: ' + ErrorMessage;
    Exit;
  end;
  FreeAndNil(FMifContainer);
  FMifContainer := Container;
  ImportMessage := '';
  FMifHasEditableDocument := TryLoadVectArtDocumentFromMif(FMifContainer,
    FDocument, ImportMessage);
  {$IFDEF DEBUG}
  DebugLogFileName := WriteMifOpenDebugLog(FileName, FMifContainer,
    ImportMessage);
  {$ENDIF}
  if FMifHasEditableDocument then
  begin
    if FEditHistory <> nil then
      FEditHistory.Clear;
    DocumentChanged(FDocument);
  end;
  FFileActionsUI.CurrentFileName := FileName;
  FFileActionsUI.CanSave := True;
  FEditActionsUI.OnSaveRequest := FileSaveShortcut;
  Caption := 'VectArtDesigner - ' + ExtractFileName(FileName);
  if ImportMessage = '' then
    lblStatus.Caption := Format('MIF document loaded: %s   Chunks: %d',
      [ExtractFileName(FileName), FMifContainer.ChunkCount])
  else
    lblStatus.Caption := Format(
      'MIF container loaded without editable data: %s   Chunks: %d',
      [ExtractFileName(FileName), FMifContainer.ChunkCount]);
  {$IFDEF DEBUG}
  if DebugLogFileName <> '' then
    lblStatus.Caption := lblStatus.Caption + '   Debug log: ' +
      ExtractFileName(DebugLogFileName);
  {$ENDIF}
end;

procedure TMainForm.FileOpenShortcut(Sender: TObject);
begin
  if FFileActionsUI <> nil then
    FFileActionsUI.ExecuteOpen;
end;

procedure TMainForm.FileSaveRequest(Sender: TObject; const FileName: string);
var
  Container: TVectArtMifContainer;
  ErrorMessage: string;
  ExportMessage: string;
  ExportReport: TMifExportReport;
  Extension: string;
begin
  ErrorMessage := '';
  Container := nil;
  Extension := LowerCase(ExtractFileExt(FileName));
  if Extension = '.svg' then
  begin
    if not TrySaveVectArtDocumentToSvgFile(FDocument, FileName,
      ErrorMessage) then
    begin
      lblStatus.Caption := 'SVG save error: ' + ErrorMessage;
      Exit;
    end;
    FreeAndNil(FMifContainer);
    FMifHasEditableDocument := True;
    FFileActionsUI.CurrentFileName := FileName;
    FFileActionsUI.CanSave := True;
    FEditActionsUI.OnSaveRequest := FileSaveShortcut;
    Caption := 'VectArtDesigner - ' + ExtractFileName(FileName);
    lblStatus.Caption := 'SVG document saved: ' + ExtractFileName(FileName);
    Exit;
  end;
  if Extension <> '.mif' then
  begin
    lblStatus.Caption := 'Save error: unsupported file extension';
    Exit;
  end;
  if (FMifContainer <> nil) and not FMifHasEditableDocument then
  begin
    if (FMifWriter = nil) or
      not FMifWriter.TryWriteFile(FMifContainer, FileName, ErrorMessage) then
    begin
      lblStatus.Caption := 'MIF save error: ' + ErrorMessage;
      Exit;
    end;
    FFileActionsUI.CurrentFileName := FileName;
    Caption := 'VectArtDesigner - ' + ExtractFileName(FileName);
    lblStatus.Caption := 'MIF container preserved: ' +
      ExtractFileName(FileName);
    Exit;
  end;
  if not TryCreateVectArtMifFromDocument(FDocument, FMifContainer, Container,
    ExportReport, ErrorMessage) then
  begin
    if ExportReport.Compatibility = mecUnsupported then
    begin
      ExportMessage := 'MIFへ書き出せない項目があります。' +
        sLineBreak + sLineBreak + ExportReport.ToDisplayText;
      Application.MessageBox(PChar(ExportMessage), 'MIF書き出し',
        MB_OK or MB_ICONWARNING);
      lblStatus.Caption := 'MIF save cancelled: unsupported content';
      Exit;
    end;
    lblStatus.Caption := 'MIF document generation error: ' + ErrorMessage;
    Exit;
  end;
  if ExportReport.Compatibility = mecNeedsConfirmation then
  begin
    ExportMessage := 'MIFへの書き出しには注意が必要です。' +
      sLineBreak + sLineBreak + ExportReport.ToDisplayText +
      sLineBreak + sLineBreak + 'この内容で書き出しますか？';
    if Application.MessageBox(PChar(ExportMessage), 'MIF書き出しの確認',
      MB_OKCANCEL or MB_ICONWARNING) <> IDOK then
    begin
      Container.Free;
      Container := nil;
      lblStatus.Caption := 'MIF save cancelled';
      Exit;
    end;
  end;
  try
    if (FMifWriter = nil) or
      not FMifWriter.TryWriteFile(Container, FileName, ErrorMessage) then
    begin
      lblStatus.Caption := 'MIF save error: ' + ErrorMessage;
      Exit;
    end;
    FreeAndNil(FMifContainer);
    FMifContainer := Container;
    Container := nil;
    FMifHasEditableDocument := True;
  finally
    Container.Free;
  end;
  FFileActionsUI.CurrentFileName := FileName;
  FFileActionsUI.CanSave := True;
  FEditActionsUI.OnSaveRequest := FileSaveShortcut;
  Caption := 'VectArtDesigner - ' + ExtractFileName(FileName);
  lblStatus.Caption := 'MIF document saved: ' + ExtractFileName(FileName);
end;

procedure TMainForm.FileSaveShortcut(Sender: TObject);
begin
  if FFileActionsUI <> nil then
    FFileActionsUI.ExecuteSave;
end;

procedure TMainForm.DocumentChanged(Sender: TObject);
begin
  if FEditActionsUI <> nil then
    FEditActionsUI.RefreshState;
  if FEditorFrame <> nil then
    FEditorFrame.CanvasControl.Invalidate;
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

procedure TMainForm.SetFileMenuVisible(const Value: Boolean);
begin
  if (FFileActionsUI = nil) or (FEditActionsUI = nil) then
    Exit;
  FFileActionsUI.Menu.Button.Visible := Value;
  if Value then
  begin
    FEditActionsUI.Menu.Button.Left := 56;
    pnlViewMenuButton.Left := 92;
  end
  else
  begin
    FFileActionsUI.Menu.Close;
    FEditActionsUI.Menu.Button.Left := 0;
    pnlViewMenuButton.Left := 36;
  end;
end;

procedure TMainForm.EditorStateChanged(Sender: TObject);
var
  CanvasSize: string;
begin
  if FEditorFrame <> nil then
    FEditorFrame.CanvasControl.Invalidate;
  if FToolPaletteFrame <> nil then
    FToolPaletteFrame.RefreshState;
  if FLineToolbar <> nil then
    FLineToolbar.RefreshState;
  if (FDocument <> nil) and (FDocument.CanvasLayer <> nil) then
    CanvasSize := Format('%d x %d', [FDocument.CanvasLayer.Width,
      FDocument.CanvasLayer.Height])
  else
    CanvasSize := '-';
  if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetRectangle) then
    lblStatus.Caption := 'Ready   Tool: Rectangle   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetLine) then
    lblStatus.Caption := 'Ready   Tool: Line   Canvas: ' + CanvasSize
  else if (FEditorState <> nil) and
    (FEditorState.CurrentTool = vetPath) then
    lblStatus.Caption := 'Path: click vertices, click first point to close, ' +
      'double-click/right-click to finish   Canvas: ' + CanvasSize
  else
    lblStatus.Caption := 'Ready   Tool: Select   Canvas: ' + CanvasSize;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (FShortcuts <> nil) and FShortcuts.KeyDown(Key, Shift) then
    Exit;
  if (FEditorFrame <> nil) and
    (GetFocus = FEditorFrame.CanvasControl.Handle) and
    HandleSelectionNudge(FDocument, FEditHistory, Key, Shift) then
    Key := 0;
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
  FreeAndNil(FMifContainer);
  FMifReader := nil;
  FMifWriter := nil;
  FreeAndNil(FFileActionsUI);
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
  FShortcuts.Add(Ord('O'), [ssCtrl],
    procedure
    begin
      FFileActionsUI.ExecuteOpen;
    end);
  FShortcuts.Add(Ord('S'), [ssCtrl],
    procedure
    begin
      FFileActionsUI.ExecuteSave;
    end);
  FShortcuts.Add(Ord('S'), [ssCtrl, ssShift],
    procedure
    begin
      FFileActionsUI.ExecuteSaveAs;
    end);
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
      FDocument.SetSelectedLayers([]);
    end,
    function: Boolean
    begin
      Result := IsEditingSurfaceFocused and (FDocument <> nil) and
        (FDocument.SelectionCount > 0);
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
  DroppedFileName: string;
  FileNameLength: UINT;
begin
  Message.Result := 0;
  try
    FileNameLength := DragQueryFile(Message.Drop, 0, nil, 0);
    if FileNameLength = 0 then
      Exit;
    SetLength(DroppedFileName, FileNameLength);
    DragQueryFile(Message.Drop, 0, PChar(DroppedFileName),
      FileNameLength + 1);
    Caption := FFileDropCaptionBase + ' - ' +
      ExtractFileName(DroppedFileName);
  finally
    DragFinish(Message.Drop);
  end;
end;

end.
