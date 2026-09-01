program ScreenDesignMaker;

uses
  Vcl.Forms,
  TextRendererSkiaBootstrap in 'Lib\TextRenderer\TextRendererSkiaBootstrap.pas',
  TextRendererTypes in 'Lib\TextRenderer\TextRendererTypes.pas',
  TextRenderer in 'Lib\TextRenderer\TextRenderer.pas',
  TextRendererSkiaRuntime in 'Lib\TextRenderer\TextRendererSkiaRuntime.pas',
  TextRendererSkia in 'Lib\TextRenderer\TextRendererSkia.pas',
  VectArtDarkPopupMenu in 'Lib\DarkMenu\VectArtDarkPopupMenu.pas',
  ShortcutAction in 'Lib\ShortcutAction\ShortcutAction.pas',
  HorizontalTrackBarRenderer in 'Lib\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in 'Lib\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  ScreenLayoutMainForm in 'Source\Shell\ScreenLayoutMainForm.pas' {MainForm},
  ScreenLayoutEditActionsUI in 'Source\Shell\ScreenLayoutEditActionsUI.pas',
  ScreenLayoutStrokeStyleCombo in 'Source\ObjectProperties\ScreenLayoutStrokeStyleCombo.pas',
  ScreenLayoutLineToolbar in 'Source\Shell\ScreenLayoutLineToolbar.pas',
  ScreenLayoutLineStyleControls in 'Source\Shell\ScreenLayoutLineStyleControls.pas',
  ScreenLayoutCanvasSettingsDialog in 'Source\Shell\ScreenLayoutCanvasSettingsDialog.pas',
  ScreenLayoutDocument in 'Source\Core\ScreenLayoutDocument.pas',
  ScreenLayoutGeometry in 'Source\Core\ScreenLayoutGeometry.pas',
  ScreenLayoutPathOperations in 'Source\Core\ScreenLayoutPathOperations.pas',
  ScreenLayoutShapeOperations in 'Source\Core\ScreenLayoutShapeOperations.pas',
  ScreenLayoutShapeBooleanGeometry in 'Source\Core\ScreenLayoutShapeBooleanGeometry.pas',
  ScreenLayoutShapeBooleanOperations in 'Source\Core\ScreenLayoutShapeBooleanOperations.pas',
  ScreenLayoutRenderer in 'Source\Rendering\ScreenLayoutRenderer.pas',
  ScreenLayoutShapePath in 'Source\Rendering\ScreenLayoutShapePath.pas',
  ScreenLayoutContext in 'Source\Core\ScreenLayoutContext.pas',
  ScreenLayoutEditorState in 'Source\Core\ScreenLayoutEditorState.pas',
  ScreenLayoutEditCommands in 'Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutShapeEditCommands in 'Source\Core\Commands\ScreenLayoutShapeEditCommands.pas',
  ScreenLayoutShapeBooleanCommands in 'Source\Core\Commands\ScreenLayoutShapeBooleanCommands.pas',
  ScreenLayoutLayerStructureCommands in 'Source\Core\Commands\ScreenLayoutLayerStructureCommands.pas',
  ScreenLayoutLayerBatchCommands in 'Source\Core\Commands\ScreenLayoutLayerBatchCommands.pas',
  ScreenLayoutEditHistory in 'Source\Core\ScreenLayoutEditHistory.pas',
  ScreenLayoutDocumentJson in 'Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutCanvas in 'Source\Editor\ScreenLayoutCanvas.pas',
  ScreenLayoutCanvasInteraction in 'Source\Editor\ScreenLayoutCanvasInteraction.pas',
  ScreenLayoutPathInteraction in 'Source\Editor\ScreenLayoutPathInteraction.pas',
  ScreenLayoutShapeInteraction in 'Source\Editor\ScreenLayoutShapeInteraction.pas',
  ScreenLayoutShapeCreation in 'Source\Editor\ScreenLayoutShapeCreation.pas',
  ScreenLayoutKeyboardMovement in 'Source\Editor\ScreenLayoutKeyboardMovement.pas',
  ScreenLayoutEditorWorkspaceFrame in 'Source\Editor\ScreenLayoutEditorWorkspaceFrame.pas',
  ScreenLayoutSelectionGeometry in 'Source\Editor\ScreenLayoutSelectionGeometry.pas',
  ScreenLayoutLayerList in 'Source\Layers\ScreenLayoutLayerList.pas',
  ScreenLayoutLayerRenderer in 'Source\Layers\ScreenLayoutLayerRenderer.pas',
  ScreenLayoutLayerActions in 'Source\Layers\ScreenLayoutLayerActions.pas',
  ScreenLayoutLayerOperations in 'Source\Layers\ScreenLayoutLayerOperations.pas',
  ScreenLayoutLayerDuplication in 'Source\Layers\ScreenLayoutLayerDuplication.pas',
  ScreenLayoutLayerPanelFrame in 'Source\Layers\ScreenLayoutLayerPanelFrame.pas',
  ScreenLayoutDockManager in 'Source\Layout\ScreenLayoutDockManager.pas',
  ScreenLayoutToolFrames in 'Source\Layout\ScreenLayoutToolFrames.pas',
  ScreenLayoutObjectPropertiesControl in 'Source\ObjectProperties\ScreenLayoutObjectPropertiesControl.pas',
  ScreenLayoutObjectPropertiesFrame in 'Source\ObjectProperties\ScreenLayoutObjectPropertiesFrame.pas',
  ScreenLayoutToolPaletteFrame in 'Source\ToolPalette\ScreenLayoutToolPaletteFrame.pas',
  ScreenLayoutToolPalette in 'Source\ToolPalette\ScreenLayoutToolPalette.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'ScreenDesignMaker';
  Application.CreateForm(TMainForm, MainForm);
  MainForm.Caption := 'ScreenDesignMaker';
  MainForm.EnableStandaloneFileActions;
  Application.Run;
end.
