// 配置中と確定後のRGBA画像を比較し、描画スタイルと文書非変更を検証する。
program ScreenLayoutPlacementPreviewTest;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.SysUtils, System.Types, Vcl.Controls, Vcl.Graphics,
  ScreenLayoutDocument, ScreenLayoutEditorState, ScreenLayoutShapeCreation,
  ScreenLayoutPlacementPreview, ScreenLayoutCanvasRenderCache, ScreenLayoutPaintStyles,
  TextRendererSkiaRuntime;
procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;
procedure Run;
var
  Document: TVectArtDocument;
  State: TVectArtEditorState;
  Creation: TVectArtShapeCreation;
  Preview: TScreenLayoutPlacementPreview;
  FinalImage: TScreenLayoutCanvasRenderCache;
  Tool: TVectArtEditorTool;
  Kind: TScreenLayoutPaintKind;
  Style: TScreenLayoutPaintStyle;
  Bounds: TRect;
  Revision: Int64;
  Y: Integer;
begin
  State := TVectArtEditorState.Create;
  Creation := TVectArtShapeCreation.Create;
  Preview := TScreenLayoutPlacementPreview.Create;
  FinalImage := TScreenLayoutCanvasRenderCache.Create;
  try
    for Tool in [vetRectangle, vetRoundedRectangle, vetEllipse, vetArc, vetArcShape] do
      for Kind in [slpkSolid, slpkGradient, slpkPattern] do
      begin
        Document := TVectArtDocument.Create;
        try
          Document.SetCanvasSize(200, 200);
          Document.CanvasLayer.Transparent := True;
          State.CurrentTool := Tool;
          Style := TScreenLayoutPaintStyle.Solid(clRed);
          if Kind = slpkGradient then
          begin
            Style.PrepareLinearGradient(clRed);
            Style.GradientEndColor := clBlue;
          end;
          if Kind = slpkPattern then Style.PreparePattern;
          Style.Kind := Kind;
          State.CreationPaintStyle := Style;
          State.RectangleOpacity := 0.4;
          Creation.Configure(Document, nil, State, Rect(0, 0, 200, 200), 1);
          Creation.MouseDown(mbLeft, [], 60, 60);
          Creation.MouseMove([ssLeft], 140, 120);
          Bounds := Creation.PreviewRect;
          Revision := Document.Revision;
          Preview.Update(Document, State, Bounds, Rect(0, 0, 200, 200), 1);
          Check((Document.LayerCount = 1) and (Document.Revision = Revision), 'preview changed document');
          Check(Preview.Bitmap.Width = 200, 'preview image missing');
          Creation.MouseUp(mbLeft, [], 140, 120);
          Check(Document.LayerCount = 2, 'shape not committed');
          FinalImage.Reset;
          FinalImage.Update(Document, 200, 200, 0, nil, clNone, False, False);
          for Y := 0 to 199 do
            Check(CompareMem(Preview.Bitmap.ScanLine[Y], FinalImage.Bitmap.ScanLine[Y], 200 * 4),
              Format('preview differs from committed pixels: tool=%d kind=%d row=%d', [Ord(Tool), Ord(Kind), Y]));
          Preview.Update(Document, State, TRect.Empty, Rect(0, 0, 200, 200), 1);
          Check(Preview.Bitmap.Width = 0, 'finished preview was retained');
        finally
          Document.Free;
        end;
      end;
  finally
    FinalImage.Free;
    Preview.Free;
    Creation.Free;
    State.Free;
  end;
end;
begin
  TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
  try
    try Run; Writeln('PASS');
    except on E: Exception do begin Writeln('FAIL: ', E.Message); ExitCode := 1; end; end;
  finally
    TTextRendererSkiaRuntime.Release;
  end;
end.
