library SYNC_ScreenLayout_Filter;

// 「画面レイアウト」フィルターのAviUtl2 DLL境界。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Lib\AviUtl2\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Lib\AviUtl2\PluginFilterTable.pas',
  PluginFilterContextManager in 'Lib\AviUtl2\PluginFilterContextManager.pas',
  ScreenLayoutFilterPlugin in 'Source\PlacementPlugin\ScreenLayoutFilterPlugin.pas',
  ScreenLayoutFrameCapture in 'Source\PlacementPlugin\ScreenLayoutFrameCapture.pas',
  ScreenLayoutFilterContext in 'Source\PlacementPlugin\ScreenLayoutFilterContext.pas',
  ScreenLayoutEditorHost in 'Source\PlacementPlugin\ScreenLayoutEditorHost.pas',
  TextRendererSkiaBootstrap in 'Lib\TextRenderer\TextRendererSkiaBootstrap.pas',
  TextRendererTypes in 'Lib\TextRenderer\TextRendererTypes.pas',
  TextRenderer in 'Lib\TextRenderer\TextRenderer.pas',
  TextRendererSkiaRuntime in 'Lib\TextRenderer\TextRendererSkiaRuntime.pas',
  TextRendererSkia in 'Lib\TextRenderer\TextRendererSkia.pas',
  VectArtDarkPopupMenu in 'Lib\DarkMenu\VectArtDarkPopupMenu.pas',
  ShortcutAction in 'Lib\ShortcutAction\ShortcutAction.pas',
  HorizontalTrackBarRenderer in 'Lib\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in 'Lib\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  VectArtDesignerMainForm in 'Source\Shell\VectArtDesignerMainForm.pas' {MainForm},
  VectArtDesignerEditActionsUI in 'Source\Shell\VectArtDesignerEditActionsUI.pas',
  VectArtDesignerStrokeStyleCombo in 'Source\ObjectProperties\VectArtDesignerStrokeStyleCombo.pas',
  VectArtDesignerLineToolbar in 'Source\Shell\VectArtDesignerLineToolbar.pas',
  VectArtDesignerLineStyleControls in 'Source\Shell\VectArtDesignerLineStyleControls.pas',
  VectArtDesignerCanvasSettingsDialog in 'Source\Shell\VectArtDesignerCanvasSettingsDialog.pas',
  VectArtDesignerDocument in 'Source\Core\VectArtDesignerDocument.pas',
  VectArtDesignerGeometry in 'Source\Core\VectArtDesignerGeometry.pas',
  VectArtDesignerRenderer in 'Source\Rendering\VectArtDesignerRenderer.pas',
  VectArtDesignerContext in 'Source\Core\VectArtDesignerContext.pas',
  VectArtDesignerEditorState in 'Source\Core\VectArtDesignerEditorState.pas',
  VectArtDesignerEditCommands in 'Source\Core\Commands\VectArtDesignerEditCommands.pas',
  VectArtDesignerLayerStructureCommands in 'Source\Core\Commands\VectArtDesignerLayerStructureCommands.pas',
  VectArtDesignerLayerBatchCommands in 'Source\Core\Commands\VectArtDesignerLayerBatchCommands.pas',
  VectArtDesignerEditHistory in 'Source\Core\VectArtDesignerEditHistory.pas',
  VectArtDesignerDocumentJson in 'Source\Persistence\VectArtDesignerDocumentJson.pas',
  VectArtDesignerCanvas in 'Source\Editor\VectArtDesignerCanvas.pas',
  VectArtDesignerCanvasInteraction in 'Source\Editor\VectArtDesignerCanvasInteraction.pas',
  VectArtDesignerShapeCreation in 'Source\Editor\VectArtDesignerShapeCreation.pas',
  VectArtDesignerKeyboardMovement in 'Source\Editor\VectArtDesignerKeyboardMovement.pas',
  VectArtDesignerEditorWorkspaceFrame in 'Source\Editor\VectArtDesignerEditorWorkspaceFrame.pas',
  VectArtDesignerSelectionGeometry in 'Source\Editor\VectArtDesignerSelectionGeometry.pas',
  VectArtDesignerLayerList in 'Source\Layers\VectArtDesignerLayerList.pas',
  VectArtDesignerLayerRenderer in 'Source\Layers\VectArtDesignerLayerRenderer.pas',
  VectArtDesignerLayerActions in 'Source\Layers\VectArtDesignerLayerActions.pas',
  VectArtDesignerLayerOperations in 'Source\Layers\VectArtDesignerLayerOperations.pas',
  VectArtDesignerLayerDuplication in 'Source\Layers\VectArtDesignerLayerDuplication.pas',
  VectArtDesignerLayerPanelFrame in 'Source\Layers\VectArtDesignerLayerPanelFrame.pas',
  VectArtDesignerDockManager in 'Source\Layout\VectArtDesignerDockManager.pas',
  VectArtDesignerToolFrames in 'Source\Layout\VectArtDesignerToolFrames.pas',
  VectArtDesignerObjectPropertiesControl in 'Source\ObjectProperties\VectArtDesignerObjectPropertiesControl.pas',
  VectArtDesignerObjectPropertiesFrame in 'Source\ObjectProperties\VectArtDesignerObjectPropertiesFrame.pas',
  VectArtDesignerToolPaletteFrame in 'Source\ToolPalette\VectArtDesignerToolPaletteFrame.pas',
  VectArtDesignerToolPalette in 'Source\ToolPalette\VectArtDesignerToolPalette.pas';

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  InitializeScreenLayoutFilter;
  Result := 1;
end;

procedure UninitializePlugin; cdecl;
begin
  FinalizeScreenLayoutFilter;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := GetScreenLayoutFilterTable;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
