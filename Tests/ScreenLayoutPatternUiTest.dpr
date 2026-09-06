// パターンUIのモード分離、色編集、複数選択と連続履歴を実際のコントロールで確認する。
program ScreenLayoutPatternUiTest;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Types, System.Math, System.Classes, Winapi.Windows,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Imaging.pngimage,
  ScreenLayoutContext, ScreenLayoutDocument, ScreenLayoutEditorState, ScreenLayoutEditHistory,
  ScreenLayoutPaintStyles, ScreenLayoutPatternStyle, ScreenLayoutColorPickerFrame,
  ScreenLayoutObjectColorController, ScreenLayoutPatternControl, ScreenLayoutTextureControl,
  ColorPickerSVArea, HorizontalTrackBarControl, VerticalScrollBarControl, TextRendererSkiaRuntime;

type
  TPatternAccess = class(TScreenLayoutPatternControl);
  TSVAccess = class(TColorPickerSVArea);
  TSliderAccess = class(THorizontalTrackBarControl);
  TRefreshHost = class
    Controller: TScreenLayoutObjectColorController; // テスト中の再同期先。
    procedure Changed(Sender: TObject);
  end;

procedure TRefreshHost.Changed(Sender: TObject);
begin
  Controller.Refresh;
end;

procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;

procedure Run;
var
  Doc: TVectArtDocument;
  State: TVectArtEditorState;
  History: TVectArtEditHistory;
  Context: IVectArtDesignerContext;
  Controller: TScreenLayoutObjectColorController;
  Host: TRefreshHost;
  Form: TForm;
  Frame: TScreenLayoutColorPickerFrame;
  Control: TPatternAccess;
  SV: TSVAccess;
  Opacity: THorizontalTrackBarControl;
  Before1, Before2: TScreenLayoutPaintStyle;
  Bitmap: TBitmap;
  Png: TPngImage;
  I: Integer;
  Slider: TSliderAccess;
  Scroll: TPanel;
  ScrollBar: TVerticalScrollBarControl;
  Key: Word;
begin
  Doc := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Host := TRefreshHost.Create;
  Form := TForm.CreateNew(nil);
  Frame := TScreenLayoutColorPickerFrame.Create(Form);
  Frame.Parent := Form;
  Frame.Width := 160;
  Controller := TScreenLayoutObjectColorController.Create(Frame);
  try
    Doc.InsertLayer(1, TVectArtRectangleLayer.Create('A', TRectF.Create(-30, -30, 30, 30), clRed));
    Doc.InsertLayer(2, TVectArtRectangleLayer.Create('B', TRectF.Create(40, -30, 100, 30), clBlue));
    Doc[1].Opacity := 0.75;
    Doc.SetSelectedLayers([1, 2]);
    Context := TVectArtDesignerContext.Create(Doc, History, State);
    Controller.SetContext(Context);
    Host.Controller := Controller;
    Controller.OnChanged := Host.Changed;
    State.OnChanged := Host.Changed;
    Doc.OnChanged := Host.Changed;
    Control := nil;
    SV := nil;
    Opacity := nil;
    for I := 0 to Frame.ComponentCount - 1 do
    begin
      if Frame.Components[I] is TScreenLayoutPatternControl then Control := TPatternAccess(Frame.Components[I]);
      if Frame.Components[I] is TColorPickerSVArea then SV := TSVAccess(Frame.Components[I]);
      if Frame.Components[I] is THorizontalTrackBarControl then
        Opacity := THorizontalTrackBarControl(Frame.Components[I]);
    end;
    Check((Control <> nil) and (SV <> nil) and (Opacity <> nil), 'missing controls');
    Check(not Control.Visible, 'solid mode shows pattern controls');
    Frame.SelectPaintKind(slpkPattern);
    Check(Control.Visible and (Doc[1].PaintStyle.Kind = slpkPattern) and
      (Doc[2].PaintStyle.Kind = slpkPattern), 'mode selection did not apply to all objects');
    Check(State.CreationPaintStyle.Kind = slpkPattern, 'new object default missing');
    Control.SelectKind(slptWave);
    Check(Doc[1].PaintStyle.Pattern.Kind = slptWave, 'kind selection not applied');
    Form.SetBounds(-32000, -32000, 200, 650);
    Form.Show;
    Application.ProcessMessages;
    History.Clear;
    Before1 := Doc[1].PaintStyle;
    Before2 := Doc[2].PaintStyle;
    Slider := nil;
    Scroll := nil;
    ScrollBar := nil;
    for I := 0 to Control.ComponentCount - 1 do
    begin
      Check(not (Control.Components[I] is TEdit), 'numeric input still exists');
      Check(not (Control.Components[I] is TScrollBox), 'native scrollbar still exists');
      if Control.Components[I] is TLabel then
        Check(TLabel(Control.Components[I]).Caption =
          ScreenLayoutPatternParameters(Control.Pattern.Kind)[Control.Components[I].Tag].Caption,
          'parameter label includes a numeric value');
      if (Control.Components[I] is THorizontalTrackBarControl) and (Control.Components[I].Tag = 0) then
        Slider := TSliderAccess(Control.Components[I]);
      if Control.Components[I] is TPanel then Scroll := TPanel(Control.Components[I]);
      if Control.Components[I] is TVerticalScrollBarControl then
        ScrollBar := TVerticalScrollBarControl(Control.Components[I]);
    end;
    Check((Slider <> nil) and (Scroll <> nil) and (ScrollBar <> nil), 'shared controls missing');
    Check(Slider.Left >= 66, 'slider is not beside its label');
    Slider.MouseDown(mbLeft, [], 20, 12);
    Slider.MouseMove([ssLeft], 50, 12);
    Check(Doc[1].PaintStyle.Pattern.Number('width') < 256,
      'wide parameter range is still too sensitive');
    Slider.MouseMove([ssLeft], Slider.Width - 1, 12);
    Slider.MouseUp(mbLeft, [], Slider.Width - 1, 12);
    Check(Doc[1].PaintStyle.Pattern.Number('width') = 1024, 'parameter drag lost final value');
    Check(Doc[2].PaintStyle.Pattern.Number('width') = 1024, 'multi selection diverged');
    Check(not Doc.IsInteractiveUpdate, 'gesture leaked interactive state');
    History.Undo;
    Check(Doc[1].PaintStyle.SameAs(Before1) and Doc[2].PaintStyle.SameAs(Before2) and
      not History.CanUndo, 'parameter drag is not one undo');
    History.Redo;
    Controller.Refresh;
    Check(Control.Pattern.Number('width') = 1024, 'redo did not refresh parameter');
    History.Clear;
    Before1 := Doc[1].PaintStyle;
    Control.SelectSlot('background');
    Check(Frame.Opacity = 0, 'transparent background opacity not shown');
    SV.MouseDown(mbLeft, [], 30, 20);
    SV.MouseMove([ssLeft], 60, 45);
    SV.MouseUp(mbLeft, [], 60, 45);
    Check(Doc[1].PaintStyle.Pattern.Slot('background').Color <> Before1.Pattern.Slot('background').Color,
      'background color was not edited');
    Check(Doc[1].PaintStyle.Pattern.Slot('foreground').Color = Before1.Pattern.Slot('foreground').Color,
      'background editing changed foreground');
    History.Undo;
    Check(Doc[1].PaintStyle.SameAs(Before1) and not History.CanUndo, 'color gesture is not one undo');
    Controller.Refresh;
    History.Clear;
    Opacity.OnMouseDown(Opacity, mbLeft, [], 20, 10);
    Opacity.Position := 35;
    Opacity.Position := 60;
    Opacity.OnMouseUp(Opacity, mbLeft, [], 90, 10);
    Check(SameValue(Doc[1].PaintStyle.Pattern.Slot('background').Opacity, 0.6, 0.001),
      'opacity changed the wrong target');
    Check(SameValue(Doc[1].Opacity, 0.75), 'slot alpha changed layer opacity');
    History.Undo;
    Check(Doc[1].PaintStyle.SameAs(Before1) and not History.CanUndo, 'opacity gesture is not one undo');
    Controller.Refresh;
    Control.SelectSlot('foreground');
    Control.SelectKind(slptDots);
    Key := VK_RIGHT;
    Slider.KeyDown(Key, []);
    Check(SameValue(Doc[1].PaintStyle.Pattern.Number('size'), 6.1, 0.001), 'slider keyboard precision failed');
    Check(Slider.DoMouseWheel([], WHEEL_DELTA, Point(0, 0)), 'slider wheel was not handled');
    Check(SameValue(Doc[1].PaintStyle.Pattern.Number('size'), 6.2, 0.001),
      'slider wheel precision failed');
    Check(Slider.DoMouseWheel([], -WHEEL_DELTA, Point(0, 0)) and
      SameValue(Doc[1].PaintStyle.Pattern.Number('size'), 6.1, 0.001),
      'slider reverse wheel precision failed');
    Before1 := Frame.PaintStyle;
    Frame.SelectPaintKind(slpkTexture);
    Check(not Control.Visible, 'texture mode shows pattern UI');
    Frame.SelectPaintKind(slpkPattern);
    Check(Frame.PaintStyle.Pattern.SameAs(Before1.Pattern), 'switching mode lost pattern settings');
    Doc[1].Locked := True;
    Controller.Refresh;
    Check(not Control.Enabled, 'mixed locked selection permits pattern editing');
    Doc[1].Locked := False;
    Controller.Refresh;
    State.CurrentTool := vetRectangle;
    Controller.Refresh;
    Before1 := Doc[1].PaintStyle;
    Control.SelectKind(slptHoneycomb);
    Check(Doc[1].PaintStyle.SameAs(Before1) and
      (State.CreationPaintStyle.Pattern.Kind = slptHoneycomb), 'creation style changed existing object');
    Control.SelectKind(slptWave);
    Application.ProcessMessages;
    ScrollBar.Position := 0;
    for I := 0 to Control.ComponentCount - 1 do
      if (Control.Components[I] is THorizontalTrackBarControl) and (Control.Components[I].Tag = 6) then
        Slider := TSliderAccess(Control.Components[I]);
    Check(Slider.Top >= 0, 'last slider cannot be reached');
    Key := VK_RIGHT;
    Slider.KeyDown(Key, []);
    Check((Slider.Top >= 0) and (Slider.Top + Slider.Height <= Scroll.ClientHeight),
      'synchronization moved the last slider outside the viewport');
    ScrollBar.Position := ScrollBar.Maximum;
    Bitmap := TBitmap.Create;
    Png := TPngImage.Create;
    try
      Bitmap.SetSize(Frame.Width, Frame.Height);
      Bitmap.Canvas.Brush.Color := Frame.Color;
      Bitmap.Canvas.FillRect(Rect(0, 0, Bitmap.Width, Bitmap.Height));
      Frame.PaintTo(Bitmap.Canvas.Handle, 0, 0);
      Png.Assign(Bitmap);
      Png.SaveToFile(ExtractFilePath(ParamStr(0)) + 'pattern-ui.png');
    finally Png.Free; Bitmap.Free; end;
    State.OnChanged := nil;
    Doc.OnChanged := nil;
  finally
    Controller.Free;
    Form.Free;
    Host.Free;
    Context := nil;
    History.Free;
    State.Free;
    Doc.Free;
  end;
end;

begin
  try
    TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try Run; finally TTextRendererSkiaRuntime.Release; end;
    Writeln('PASS pattern sliders, scrolling, multi selection, gestures, mode retention and creation defaults');
  except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); ExitCode := 1; end; end;
end.
