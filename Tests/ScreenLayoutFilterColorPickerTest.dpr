program ScreenLayoutFilterColorPickerTest;

{$APPTYPE CONSOLE}

uses
  ScreenLayoutColorHistory, ScreenLayoutPatternStyle,
  System.Classes,
  System.SysUtils,
  System.Math,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  ColorPickerSVArea in '..\Lib\ColorPicker\ColorPickerSVArea.pas',
  HorizontalTrackBarControl in
    '..\Lib\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  VerticalScrollBarControl in
    '..\Lib\VerticalScrollBar\VerticalScrollBarControl.pas',
  ScreenLayoutColorPickerFrame in
    '..\Source\ObjectProperties\Color\ScreenLayoutColorPickerFrame.pas',
  ScreenLayoutColorTargetSelector in
    '..\Source\ObjectProperties\Color\ScreenLayoutColorTargetSelector.pas',
  ScreenLayoutContext in '..\Source\Core\Model\ScreenLayoutContext.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutFilterCommands in
    '..\Source\Core\Commands\ScreenLayoutFilterCommands.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutPaintStyles in
    '..\Source\Core\Model\ScreenLayoutPaintStyles.pas',
  ScreenLayoutObjectColorController in
    '..\Source\ObjectProperties\Color\ScreenLayoutObjectColorController.pas',
  ScreenLayoutObjectPropertyCommands in
    '..\Source\ObjectProperties\ScreenLayoutObjectPropertyCommands.pas',
  ScreenLayoutObjectPropertySelection in
    '..\Source\ObjectProperties\ScreenLayoutObjectPropertySelection.pas';

type
  TColorHistoryAccess = class(TScreenLayoutColorHistory);
  TColorPickerFrameAccess = class(TScreenLayoutColorPickerFrame);
  TColorPickerSVAreaAccess = class(TColorPickerSVArea);
  TColorTargetSelectorAccess = class(TScreenLayoutColorTargetSelector);

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

// 入れ子のグループ、パターン、グラデーション中間点を含めて収集する。
procedure CheckColorCollection;
var
  Palette: TScreenLayoutColorHistory;
  Document: TVectArtDocument;
  Group: TScreenLayoutGroupLayer;
  Layer: TVectArtRectangleLayer;
  Style: TScreenLayoutPaintStyle;
  Expected, Actual: TColor;
  Found: Boolean;
begin
  Palette := TScreenLayoutColorHistory.Create(nil);
  Document := TVectArtDocument.Create;
  try
    Group := TScreenLayoutGroupLayer.Create('Group');
    Document.InsertLayer(Document.LayerCount, Group);
    Layer := TVectArtRectangleLayer.Create('Gradient', TRectF.Create(0, 0, 10, 10), clRed);
    Group.AddChild(Layer);
    Style := TScreenLayoutPaintStyle.Solid(clRed);
    Style.PrepareLinearGradient(clRed);
    Style.Kind := slpkGradient;
    Style.GradientEndColor := clBlue;
    Style.SetGradientStopColor(Style.AddGradientStop(0.5), clYellow);
    Layer.PaintStyle := Style;
    Layer := TVectArtRectangleLayer.Create('Pattern', TRectF.Create(20, 0, 30, 10), clLime);
    Group.AddChild(Layer);
    Style := TScreenLayoutPaintStyle.Solid(clLime);
    Style.Kind := slpkPattern;
    Style.Pattern := TScreenLayoutPatternStyle.Create(slptHatch, clLime);
    Layer.PaintStyle := Style;
    Palette.LoadDocument(Document);
    for Expected in [clRed, clBlue, clYellow, clLime] do
    begin
      Found := False;
      for Actual in Palette.Colors do Found := Found or (Actual = Expected);
      Check(Found, 'nested document color missing');
    end;
    Palette.LoadDocument(nil);
    Check(Length(Palette.Colors) = 0, 'reload retained old history');
  finally
    Document.Free;
    Palette.Free;
  end;
end;

procedure Run;
var
  Palette: TScreenLayoutColorHistory;
  HistoryCount: Integer;
  KindSelector: TComboBox;
  Kind: TScreenLayoutGradientKind;
  FrameDC: HDC;
  Bitmap: TBitmap;
  Png: TPngImage;
  Context: IVectArtDesignerContext;
  Controller: TScreenLayoutObjectColorController;
  Data: TVectArtRectangleData;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Form: TForm;
  Frame: TScreenLayoutColorPickerFrame;
  FixedFrameHeight: Integer;
  FixedModeTop: Integer;
  FixedPickerTop: Integer;
  FixedSVArea: TColorPickerSVArea;
  FixedTargetTop: Integer;
  FixedTargetSelector: TScreenLayoutColorTargetSelector;
  ModeSelector: TControl;
  OpacityLabel: TLabel;
  History: TVectArtEditHistory;
  I: Integer;
  Layer: TVectArtLayer;
  Outline: TScreenLayoutOutlineFilter;
  Blur: TScreenLayoutBlurFilter;
  Shadow: TScreenLayoutShadowFilter;
  ScrollBar: TVerticalScrollBarControl;
  StopOpacity: Single;
  SelectedId: Integer;
  StopColor: TColor;
  StopId: Integer;
  Style: TScreenLayoutPaintStyle;
  SVArea: TColorPickerSVArea;
  TrackBar: THorizontalTrackBarControl;
  TargetSelector: TColorTargetSelectorAccess;
begin
  Form := TForm.CreateNew(nil);
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
    Data := Default(TVectArtRectangleData);
    Data.PaintStyle := TScreenLayoutPaintStyle.Solid(clBlue);
    Data.Bounds := TRectF.Create(-20, -20, 20, 20);
    Data.FillColor := clBlue;
    Data.Locked := False;
    Data.Name := 'Rectangle';
    Data.Opacity := 0.75;
    Data.Visible := True;
    Document.InsertRectangle(Document.LayerCount, Data);
    Layer := Document[1];
    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Color := clBlack;
    Layer.AddFilter(Outline);
    Shadow := TScreenLayoutShadowFilter.Create;
    Shadow.Color := clGreen;
    Shadow.Opacity := 0.4;
    Layer.AddFilter(Shadow);
    Blur := TScreenLayoutBlurFilter.Create;
    Layer.AddFilter(Blur);
    Document.SetSelectedLayers([1]);
    EditorState.CreationColor := clGreen;

    Context := TVectArtDesignerContext.Create(Document, History, EditorState);
    Frame := TScreenLayoutColorPickerFrame.Create(Form);
    Frame.Parent := Form;
    Frame.SetBounds(0, 0, 200, 205);
    Controller := TScreenLayoutObjectColorController.Create(Frame);
    try
      Controller.SetContext(Context);
      KindSelector := nil;
      FixedTargetSelector := nil;
      FixedSVArea := nil;
      ModeSelector := nil;
      OpacityLabel := nil;
      for I := 0 to Frame.ControlCount - 1 do
      begin
        if Frame.Controls[I] is TComboBox then
          KindSelector := TComboBox(Frame.Controls[I]);
        if Frame.Controls[I] is TScreenLayoutColorTargetSelector then
          FixedTargetSelector := TScreenLayoutColorTargetSelector(Frame.Controls[I]);
        if Frame.Controls[I] is TColorPickerSVArea then
          FixedSVArea := TColorPickerSVArea(Frame.Controls[I]);
        if Frame.Controls[I].ClassName = 'TScreenLayoutPaintModeSelector' then
          ModeSelector := Frame.Controls[I];
        if (Frame.Controls[I] is TLabel) and
          (TLabel(Frame.Controls[I]).Caption = '透明度：') then
          OpacityLabel := TLabel(Frame.Controls[I]);
        Check(not (Frame.Controls[I] is TButton), 'coordinate button still exists');
      end;
      Check((KindSelector <> nil) and not KindSelector.Visible, 'solid mode shows gradient kinds');
      Check((FixedTargetSelector <> nil) and (FixedSVArea <> nil) and
        (ModeSelector <> nil) and (OpacityLabel <> nil),
        'fixed color layout controls missing');
      Check((OpacityLabel.Top < FixedTargetSelector.Top) and
        (FixedTargetSelector.Top < ModeSelector.Top), 'fixed color layout order is wrong');
      FixedFrameHeight := Frame.Height;
      FixedTargetTop := FixedTargetSelector.Top;
      FixedModeTop := ModeSelector.Top;
      Check(Frame.SelectedColor = clBlue,
        'object color was not shown before selecting a filter');
      Check(Frame.Opacity = 75,
        'object opacity was not shown before selecting a filter');
      TargetSelector := TColorTargetSelectorAccess.Create(Frame);
      TargetSelector.Parent := Frame;
      Style := TScreenLayoutPaintStyle.Solid(clRed);
      Style.PrepareLinearGradient(clRed);
      Style.Kind := slpkGradient;
      TargetSelector.PaintStyle := Style;
      TargetSelector.SetBounds(0, 0, 100, 26);
      TargetSelector.MouseDown(mbLeft, [ssCtrl], 50, 13);
      Check(Length(TargetSelector.PaintStyle.GetGradientStops) = 1,
        'extracted gradient target did not add a stop');
      TargetSelector.MouseDown(mbRight, [], 50, 13);
      Check(Length(TargetSelector.PaintStyle.GetGradientStops) = 0,
        'extracted gradient target did not remove a stop');

      EditorState.CurrentTool := vetLine;
      Controller.Refresh;
      Check(Frame.ColorEnabled and Frame.OpacityEnabled and
        (ColorToRGB(Frame.SelectedColor) = ColorToRGB(clBlue)) and
        (ColorToRGB(EditorState.CreationColor) = ColorToRGB(clBlue)) and
        (Frame.Opacity = 75) and
        SameValue(EditorState.RectangleOpacity, 0.75),
        'creation tool did not adopt the visible picker color');
      Frame.SelectedColor := clFuchsia;
      Frame.OnChange(Frame);
      Check((EditorState.CreationPaintStyle.Kind = slpkSolid) and
        (ColorToRGB(EditorState.CreationColor) = ColorToRGB(clFuchsia)),
        'confirmed picker color was not adopted as the creation paint');
      Check(ColorToRGB(TVectArtRectangleLayer(Layer).FillColor) =
        ColorToRGB(clBlue),
        'creation color editing changed the selected existing object');
      EditorState.CurrentTool := vetSelect;
      Controller.Refresh;
      Check(Frame.SelectedColor = clBlue,
        'selection mode did not restore existing object color editing');
      EditorState.CurrentTool := vetRectangle;
      Controller.Refresh;
      Check((ColorToRGB(Frame.SelectedColor) = ColorToRGB(clBlue)) and
        (ColorToRGB(EditorState.CreationColor) = ColorToRGB(clBlue)),
        'another creation tool restored a hidden tool color');
      EditorState.CurrentTool := vetSelect;
      Controller.Refresh;

      Style := TScreenLayoutPaintStyle.Solid(clBlue);
      Style.PrepareLinearGradient(clBlue);
      Style.Kind := slpkGradient;
      StopId := Style.AddGradientStop(0.5);
      Layer.PaintStyle := Style;
      EditorState.SelectGradientStop(Layer, StopId);
      Controller.Refresh;
      Check(Frame.PaintModeEnabled and Frame.ColorEnabled and
        (Frame.PaintStyle.Kind = slpkGradient) and
        (Frame.GradientStopId = StopId),
        'selected gradient did not keep the mode selector available');
      Frame.SelectedColor := clYellow;
      Frame.OnChange(Frame);
      Check(Layer.PaintStyle.GetGradientStopColor(StopId, StopColor) and
        (ColorToRGB(StopColor) = ColorToRGB(clYellow)),
        'picker did not edit the selected middle-stop color');
      History.Undo;
      Check(Layer.PaintStyle.GetGradientStopColor(StopId, StopColor) and
        (ColorToRGB(StopColor) <> ColorToRGB(clYellow)),
        'middle-stop color undo did not restore the original color');
      History.Redo;
      Check(Layer.PaintStyle.GetGradientStopColor(StopId, StopColor) and
        (ColorToRGB(StopColor) = ColorToRGB(clYellow)),
        'middle-stop color redo did not restore the edited color');
      Frame.OnColorGestureStart(Frame);
      Frame.SelectedColor := clRed;
      Frame.OnChange(Frame);
      Frame.SelectedColor := clLime;
      Frame.OnChange(Frame);
      Frame.OnColorGestureEnd(Frame);
      Check(Layer.PaintStyle.GetGradientStopColor(StopId, StopColor) and
        (ColorToRGB(StopColor) = ColorToRGB(clLime)),
        'gradient color gesture did not keep its final color');
      History.Undo;
      Check(Layer.PaintStyle.GetGradientStopColor(StopId, StopColor) and
        (ColorToRGB(StopColor) = ColorToRGB(clYellow)),
        'gradient color gesture was not recorded as one undo operation');
      History.Redo;
      Controller.Refresh;
      for SelectedId in [SCREEN_LAYOUT_GRADIENT_START_STOP_ID, StopId, SCREEN_LAYOUT_GRADIENT_END_STOP_ID] do
      begin
        EditorState.SelectGradientStop(Layer, SelectedId);
        Controller.Refresh;
        Check(Frame.Opacity = 100, 'selected stop alpha not synchronized');
        Frame.OnOpacityGestureStart(Frame);
        Frame.Opacity := 20;
        Frame.OnOpacityChange(Frame);
        Frame.Opacity := 60;
        Frame.OnOpacityChange(Frame);
        Frame.OnOpacityGestureEnd(Frame);
        Check(Layer.PaintStyle.GetGradientStopOpacity(SelectedId, StopOpacity) and
          SameValue(StopOpacity, 0.6, 0.001), 'stop alpha not edited');
        Check(SameValue(Layer.Opacity, 0.75, 0.001), 'stop editing changed layer alpha');
        History.Undo;
        Check(Layer.PaintStyle.GetGradientStopOpacity(SelectedId, StopOpacity) and
          SameValue(StopOpacity, 1.0, 0.001), 'alpha gesture was not one Undo');
        History.Redo;
        Check(Layer.PaintStyle.GetGradientStopOpacity(SelectedId, StopOpacity) and
          SameValue(StopOpacity, 0.6, 0.001), 'alpha Redo failed');
      end;
      Style := Layer.PaintStyle;
      Style.GradientKind := slgkRadial;
      Layer.PaintStyle := Style;
      Controller.Refresh;
      Check(Frame.PaintStyle.GradientKind = slgkRadial, 'refresh reset gradient kind');
      Check(KindSelector.Visible, 'gradient mode hides kinds');
      Check((Frame.Height = FixedFrameHeight) and FixedTargetSelector.Visible and
        (FixedTargetSelector.Top = FixedTargetTop) and (ModeSelector.Top = FixedModeTop) and
        (OpacityLabel.Caption = '透明度：'), 'gradient mode moved the fixed color layout');
      for Kind in [slgkRectangle, slgkSweep, slgkRadial] do
      begin
        KindSelector.ItemIndex := Ord(Kind);
        KindSelector.OnChange(KindSelector);
        Check((Layer.PaintStyle.GradientKind = Kind) and
          SameValue(Layer.PaintStyle.LinearStart.X, 0.5) and
          SameValue(Layer.PaintStyle.LinearStart.Y, 0.5), 'radial kind did not start at object center');
      end;
      Controller.Refresh;
      Frame.SetBounds(0, 0, 160, 538);
      FixedPickerTop := FixedSVArea.Top;
      Form.ClientWidth := Frame.Width;
      Form.ClientHeight := Frame.Height;
      TargetSelector.Visible := False;
      Frame.LoadColorHistory(Document);
      Bitmap := TBitmap.Create;
      Png := TPngImage.Create;
      try
        Form.Show;
        Application.ProcessMessages;
        Bitmap.SetSize(Frame.Width, Frame.Height);
        Frame.Update;
        FrameDC := GetDC(Frame.Handle);
        try
          BitBlt(Bitmap.Canvas.Handle, 0, 0, Frame.Width, Frame.Height, FrameDC, 0, 0, SRCCOPY);
        finally
          ReleaseDC(Frame.Handle, FrameDC);
        end;
        Png.Assign(Bitmap);
        Png.SaveToFile(ExtractFilePath(ParamStr(0)) + 'GradientPicker.png');
        Form.Hide;
      finally
        Png.Free;
        Bitmap.Free;
      end;
      Frame.SelectPaintKind(slpkSolid);
      Check(not KindSelector.Visible, 'solid mode did not hide kinds');
      Check((Frame.Height = 538) and FixedTargetSelector.Visible and
        (FixedTargetSelector.Top = FixedTargetTop) and (ModeSelector.Top = FixedModeTop) and
        (FixedSVArea.Top = FixedPickerTop), 'solid mode moved the fixed color layout');
      Frame.Height := 330;
      ScrollBar := nil;
      for I := 0 to Frame.ComponentCount - 1 do
        if Frame.Components[I] is TVerticalScrollBarControl then
          ScrollBar := TVerticalScrollBarControl(Frame.Components[I]);
      Check((ScrollBar <> nil) and ScrollBar.Visible and (ScrollBar.Maximum = 208),
        'short color panel did not show the expected scroll range');
      TColorPickerFrameAccess(Frame).DoMouseWheel([], -WHEEL_DELTA, Point(0, 0));
      Check((ScrollBar.Position > 0) and (FixedSVArea.Top < FixedPickerTop),
        'color panel wheel did not reveal lower controls');
      ScrollBar.Position := ScrollBar.Maximum;
      Check(FixedSVArea.Top + FixedSVArea.Height <= Frame.ClientHeight,
        'color panel could not scroll the picker into view');
      Frame.Height := 538;
      Check(not ScrollBar.Visible and (ScrollBar.Position = 0) and
        (FixedSVArea.Top = FixedPickerTop), 'full color panel did not reset scrolling');
      Check(Layer.PaintStyle.Kind = slpkSolid,
        Format('solid mode did not replace the selected gradient (frame=%d, layer=%d)',
          [Ord(Frame.PaintStyle.Kind), Ord(Layer.PaintStyle.Kind)]));
      History.Undo;
      Check(Layer.PaintStyle.Kind = slpkGradient,
        'paint mode undo did not restore the gradient');
      History.Redo;
      Check(Layer.PaintStyle.Kind = slpkSolid,
        'paint mode redo did not restore the solid mode');

      EditorState.SelectFilter(Layer, Outline);
      Controller.Refresh;
      Check(Frame.ColorEnabled and not Frame.OpacityEnabled,
        'outline should enable color and disable opacity');
      Check(Frame.SelectedColor = clBlack,
        'outline color was not synchronized to the picker');
      SVArea := nil;
      for I := 0 to Frame.ControlCount - 1 do
        if Frame.Controls[I] is TColorPickerSVArea then
          SVArea := TColorPickerSVArea(Frame.Controls[I]);
      Check(SVArea <> nil, 'SV picker control was not created');
      Palette := nil;
      for I := 0 to Frame.ComponentCount - 1 do
        if Frame.Components[I] is TScreenLayoutColorHistory then
          Palette := TScreenLayoutColorHistory(Frame.Components[I]);
      Check(Palette <> nil, 'color history missing');
      Frame.LoadColorHistory(Document);
      Check(Length(Palette.Colors) > 0, 'document colors were not imported');
      Palette.AddColor(clRed);
      HistoryCount := Length(Palette.Colors);
      Palette.AddColor(clRed);
      Check((Length(Palette.Colors) = HistoryCount) and (Palette.Colors[0] = clRed), 'duplicate history');
      TColorPickerSVAreaAccess(SVArea).MouseDown(mbLeft, [],
        SVArea.Width - 1, 0);
      Check(Length(Palette.Colors) = HistoryCount, 'drag added an intermediate color');
      TColorPickerSVAreaAccess(SVArea).MouseUp(mbLeft, [],
        SVArea.Width - 1, 0);
      Check((ColorToRGB(Outline.Color) = ColorToRGB(SVArea.Color)) and
        (ColorToRGB(Outline.Color) <> ColorToRGB(clBlack)),
        'picker did not edit the selected outline color');
      Check(Palette.Colors[0] = ColorToRGB(SVArea.Color), 'committed color missing');
      Check(History.CanUndo, 'filter color gesture did not create history');
      History.Undo;
      Check(ColorToRGB(Outline.Color) = ColorToRGB(clBlack),
        'filter color undo did not restore the original value');

      Palette.SetBounds(0, 0, 160, 78);
      TColorHistoryAccess(Palette).MouseDown(mbLeft, [], 110, 47);
      Check(ColorToRGB(Outline.Color) = ColorToRGB(clRed), 'basic color did not apply to filter');
      Check(Palette.Colors[0] = clRed, 'basic color was not promoted');
      History.Undo;
      Check(ColorToRGB(Outline.Color) = ColorToRGB(clBlack), 'palette selection undo');
      EditorState.SelectFilter(Layer, Shadow);
      Controller.Refresh;
      Check(Frame.ColorEnabled and Frame.OpacityEnabled,
        'shadow should enable both color and opacity');
      Check((Frame.SelectedColor = clGreen) and (Frame.Opacity = 40),
        'shadow color or opacity was not synchronized to the picker');
      TrackBar := nil;
      for I := 0 to Frame.ControlCount - 1 do
        if Frame.Controls[I] is THorizontalTrackBarControl then
          TrackBar := THorizontalTrackBarControl(Frame.Controls[I]);
      Check(TrackBar <> nil, 'opacity track bar was not created');
      TrackBar.OnMouseDown(TrackBar, mbLeft, [],
        TrackBar.Width * 3 div 4, TrackBar.Height div 2);
      TrackBar.Position := 75;
      TrackBar.OnMouseUp(TrackBar, mbLeft, [],
        TrackBar.Width * 3 div 4, TrackBar.Height div 2);
      Check(not SameValue(Shadow.Opacity, 0.4),
        'opacity picker did not edit the selected shadow');
      History.Undo;
      Check(Abs(Shadow.Opacity - 0.4) < 0.001,
        'shadow opacity undo did not restore the original value');

      EditorState.SelectFilter(Layer, Blur);
      Controller.Refresh;
      Check(not Frame.ColorEnabled and not Frame.OpacityEnabled,
        'blur should disable color and opacity editing');

      EditorState.SelectFilter(nil, nil);
      Controller.Refresh;
      Check(Frame.ColorEnabled and Frame.OpacityEnabled and
        (Frame.SelectedColor = clBlue) and (Frame.Opacity = 75),
        'clearing filter selection did not restore object editing');
    finally
      Controller.Free;
    end;
    Context := nil;
  finally
    History.Free;
    EditorState.Free;
    Document.Free;
    Form.Free;
  end;
end;

begin
  try
    Application.Initialize;
    CheckColorCollection;
    Run;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
