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
  ScreenLayoutPluginDocument in 'Source\PlacementPlugin\ScreenLayoutPluginDocument.pas',
  ScreenLayoutEditorHost in 'Source\PlacementPlugin\ScreenLayoutEditorHost.pas',
  TextRendererSkiaBootstrap in 'Lib\TextRenderer\TextRendererSkiaBootstrap.pas',
  TextRendererTypes in 'Lib\TextRenderer\TextRendererTypes.pas',
  TextRenderer in 'Lib\TextRenderer\TextRenderer.pas',
  TextRendererSkiaRuntime in 'Lib\TextRenderer\TextRendererSkiaRuntime.pas',
  TextRendererSkia in 'Lib\TextRenderer\TextRendererSkia.pas',
  VectArtDarkPopupMenu in 'Lib\DarkMenu\VectArtDarkPopupMenu.pas',
  VectArtDarkMenuGroup in 'Lib\DarkMenu\VectArtDarkMenuGroup.pas',
  ShortcutAction in 'Lib\ShortcutAction\ShortcutAction.pas',
  HorizontalTrackBarRenderer in 'Lib\HorizontalTrackBar\HorizontalTrackBarRenderer.pas',
  HorizontalTrackBarControl in 'Lib\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  ScreenLayoutMainForm in 'Source\Shell\ScreenLayoutMainForm.pas' {MainForm},
  ScreenLayoutObjectContextMenu in 'Source\Shell\ScreenLayoutObjectContextMenu.pas',
  ScreenLayoutTextContextMenu in 'Source\Shell\ScreenLayoutTextContextMenu.pas',
  ScreenLayoutEditActionsUI in 'Source\Shell\ScreenLayoutEditActionsUI.pas',
  ScreenLayoutStrokeStyleCombo in 'Source\ObjectProperties\ScreenLayoutStrokeStyleCombo.pas',
  ScreenLayoutLineToolbar in 'Source\Shell\ScreenLayoutLineToolbar.pas',
  ScreenLayoutLineStyleControls in 'Source\Shell\ScreenLayoutLineStyleControls.pas',
  ScreenLayoutCanvasSettingsDialog in 'Source\Shell\ScreenLayoutCanvasSettingsDialog.pas',
  ScreenLayoutDocument in 'Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutTextDecompositionCommands in 'Source\Core\Commands\ScreenLayoutTextDecompositionCommands.pas',
  ScreenLayoutFilters in 'Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutGeometry in 'Source\Core\Geometry\ScreenLayoutGeometry.pas',
  ScreenLayoutEllipseGeometry in 'Source\Core\Geometry\ScreenLayoutEllipseGeometry.pas',
  ScreenLayoutTextGeometry in 'Source\Core\Geometry\ScreenLayoutTextGeometry.pas',
  ScreenLayoutTextPathGeometry in 'Source\Core\Geometry\ScreenLayoutTextPathGeometry.pas',
  ScreenLayoutTextOutlineGeometry in 'Source\Core\Geometry\ScreenLayoutTextOutlineGeometry.pas',
  ScreenLayoutPathOperations in 'Source\Core\Geometry\ScreenLayoutPathOperations.pas',
  ScreenLayoutShapeOperations in 'Source\Core\Geometry\ScreenLayoutShapeOperations.pas',
  ScreenLayoutShapeBooleanGeometry in 'Source\Core\Geometry\ScreenLayoutShapeBooleanGeometry.pas',
  ScreenLayoutShapeBooleanOperations in 'Source\Core\Geometry\ScreenLayoutShapeBooleanOperations.pas',
  ScreenLayoutLayerGeometry in 'Source\Core\Geometry\ScreenLayoutLayerGeometry.pas',
  ScreenLayoutRenderer in 'Source\Rendering\ScreenLayoutRenderer.pas',
  ScreenLayoutCanvasGuides in 'Source\Rendering\ScreenLayoutCanvasGuides.pas',
  ScreenLayoutCanvasPreview in 'Source\Rendering\ScreenLayoutCanvasPreview.pas',
  ScreenLayoutOverlayPrimitives in 'Source\Rendering\ScreenLayoutOverlayPrimitives.pas',
  ScreenLayoutTextEditOverlay in 'Source\Rendering\ScreenLayoutTextEditOverlay.pas',
  ScreenLayoutShapePath in 'Source\Rendering\ScreenLayoutShapePath.pas',
  ScreenLayoutContext in 'Source\Core\Model\ScreenLayoutContext.pas',
  ScreenLayoutEditorState in 'Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditCommands in 'Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutShapeEditCommands in 'Source\Core\Commands\ScreenLayoutShapeEditCommands.pas',
  ScreenLayoutShapeBooleanCommands in 'Source\Core\Commands\ScreenLayoutShapeBooleanCommands.pas',
  ScreenLayoutTextCommands in 'Source\Core\Commands\ScreenLayoutTextCommands.pas',
  ScreenLayoutLayerStructureCommands in 'Source\Core\Commands\ScreenLayoutLayerStructureCommands.pas',
  ScreenLayoutLayerBatchCommands in 'Source\Core\Commands\ScreenLayoutLayerBatchCommands.pas',
  ScreenLayoutGroupCommands in 'Source\Core\Commands\ScreenLayoutGroupCommands.pas',
  ScreenLayoutGroupChildCommands in 'Source\Core\Commands\ScreenLayoutGroupChildCommands.pas',
  ScreenLayoutGroupTransformCommands in 'Source\Core\Commands\ScreenLayoutGroupTransformCommands.pas',
  ScreenLayoutFilterCommands in 'Source\Core\Commands\ScreenLayoutFilterCommands.pas',
  ScreenLayoutEditHistory in 'Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutDocumentJson in 'Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutDocumentJsonReader in 'Source\Persistence\ScreenLayoutDocumentJsonReader.pas',
  ScreenLayoutDocumentJsonWriter in 'Source\Persistence\ScreenLayoutDocumentJsonWriter.pas',
  ScreenLayoutCanvas in 'Source\Editor\ScreenLayoutCanvas.pas',
  ScreenLayoutCanvasInteraction in 'Source\Editor\Interaction\ScreenLayoutCanvasInteraction.pas',
  ScreenLayoutTextPathCharacterInteraction in
    'Source\Editor\Interaction\ScreenLayoutTextPathCharacterInteraction.pas',
  ScreenLayoutContextMenuInteraction in 'Source\Editor\Interaction\ScreenLayoutContextMenuInteraction.pas',
  ScreenLayoutFilterInteraction in 'Source\Editor\Interaction\ScreenLayoutFilterInteraction.pas',
  ScreenLayoutGroupInteraction in 'Source\Editor\Interaction\ScreenLayoutGroupInteraction.pas',
  ScreenLayoutTextEditing in 'Source\Editor\Interaction\ScreenLayoutTextEditing.pas',
  ScreenLayoutInteractionGeometry in 'Source\Editor\Interaction\ScreenLayoutInteractionGeometry.pas',
  ScreenLayoutPathInteraction in 'Source\Editor\Interaction\ScreenLayoutPathInteraction.pas',
  ScreenLayoutShapeInteraction in 'Source\Editor\Interaction\ScreenLayoutShapeInteraction.pas',
  ScreenLayoutShapeCreation in 'Source\Editor\Creation\ScreenLayoutShapeCreation.pas',
  ScreenLayoutLayerNaming in 'Source\Editor\Creation\ScreenLayoutLayerNaming.pas',
  ScreenLayoutImageImport in 'Source\Editor\Creation\ScreenLayoutImageImport.pas',
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
  ScreenLayoutFilterDetailsFrame in 'Source\ObjectProperties\ScreenLayoutFilterDetailsFrame.pas',
  ScreenLayoutFilterListControl in 'Source\ObjectProperties\ScreenLayoutFilterListControl.pas',
  ScreenLayoutFilterFrame in 'Source\ObjectProperties\ScreenLayoutFilterFrame.pas',
  ScreenLayoutObjectPropertiesFrame in 'Source\ObjectProperties\ScreenLayoutObjectPropertiesFrame.pas',
  ScreenLayoutToolPaletteFrame in 'Source\ToolPalette\ScreenLayoutToolPaletteFrame.pas',
  ScreenLayoutToolPalette in 'Source\ToolPalette\ScreenLayoutToolPalette.pas',
  WindowsImeController in 'Lib\InputMethod\WindowsImeController.pas';

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
