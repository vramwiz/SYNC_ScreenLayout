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
  ScreenLayoutMainForm in 'Source\Shell\ScreenLayoutMainForm.pas' {MainForm},
  ScreenLayoutEditActionsUI in 'Source\Shell\ScreenLayoutEditActionsUI.pas',
  ScreenLayoutStrokeStyleCombo in 'Source\ObjectProperties\ScreenLayoutStrokeStyleCombo.pas',
  ScreenLayoutLineToolbar in 'Source\Shell\ScreenLayoutLineToolbar.pas',
  ScreenLayoutLineStyleControls in 'Source\Shell\ScreenLayoutLineStyleControls.pas',
  ScreenLayoutCanvasSettingsDialog in 'Source\Shell\ScreenLayoutCanvasSettingsDialog.pas',
  ScreenLayoutDocument in 'Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutGeometry in 'Source\Core\Geometry\ScreenLayoutGeometry.pas',
  ScreenLayoutEllipseGeometry in 'Source\Core\Geometry\ScreenLayoutEllipseGeometry.pas',
  ScreenLayoutPathOperations in 'Source\Core\Geometry\ScreenLayoutPathOperations.pas',
  ScreenLayoutShapeOperations in 'Source\Core\Geometry\ScreenLayoutShapeOperations.pas',
  ScreenLayoutShapeBooleanGeometry in 'Source\Core\Geometry\ScreenLayoutShapeBooleanGeometry.pas',
  ScreenLayoutShapeBooleanOperations in 'Source\Core\Geometry\ScreenLayoutShapeBooleanOperations.pas',
  ScreenLayoutRenderer in 'Source\Rendering\ScreenLayoutRenderer.pas',
  ScreenLayoutShapePath in 'Source\Rendering\ScreenLayoutShapePath.pas',
  ScreenLayoutContext in 'Source\Core\Model\ScreenLayoutContext.pas',
  ScreenLayoutEditorState in 'Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditCommands in 'Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutShapeEditCommands in 'Source\Core\Commands\ScreenLayoutShapeEditCommands.pas',
  ScreenLayoutShapeBooleanCommands in 'Source\Core\Commands\ScreenLayoutShapeBooleanCommands.pas',
  ScreenLayoutLayerStructureCommands in 'Source\Core\Commands\ScreenLayoutLayerStructureCommands.pas',
  ScreenLayoutLayerBatchCommands in 'Source\Core\Commands\ScreenLayoutLayerBatchCommands.pas',
  ScreenLayoutEditHistory in 'Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutDocumentJson in 'Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutDocumentJsonReader in 'Source\Persistence\ScreenLayoutDocumentJsonReader.pas',
  ScreenLayoutDocumentJsonWriter in 'Source\Persistence\ScreenLayoutDocumentJsonWriter.pas',
  ScreenLayoutCanvas in 'Source\Editor\ScreenLayoutCanvas.pas',
  ScreenLayoutCanvasInteraction in 'Source\Editor\Interaction\ScreenLayoutCanvasInteraction.pas',
  ScreenLayoutInteractionGeometry in 'Source\Editor\Interaction\ScreenLayoutInteractionGeometry.pas',
  ScreenLayoutPathInteraction in 'Source\Editor\Interaction\ScreenLayoutPathInteraction.pas',
  ScreenLayoutShapeInteraction in 'Source\Editor\Interaction\ScreenLayoutShapeInteraction.pas',
  ScreenLayoutShapeCreation in 'Source\Editor\Creation\ScreenLayoutShapeCreation.pas',
  ScreenLayoutLayerNaming in 'Source\Editor\Creation\ScreenLayoutLayerNaming.pas',
  ScreenLayoutKeyboardMovement in 'Source\Editor\Interaction\ScreenLayoutKeyboardMovement.pas',
  ScreenLayoutEditorWorkspaceFrame in 'Source\Editor\ScreenLayoutEditorWorkspaceFrame.pas',
  ScreenLayoutSelectionGeometry in 'Source\Editor\Interaction\ScreenLayoutSelectionGeometry.pas',
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
