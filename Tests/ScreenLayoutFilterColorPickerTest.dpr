program ScreenLayoutFilterColorPickerTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Math,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  ColorPickerSVArea in '..\Lib\ColorPicker\ColorPickerSVArea.pas',
  HorizontalTrackBarControl in
    '..\Lib\HorizontalTrackBar\HorizontalTrackBarControl.pas',
  ScreenLayoutColorPickerFrame in
    '..\Source\ObjectProperties\ScreenLayoutColorPickerFrame.pas',
  ScreenLayoutContext in '..\Source\Core\Model\ScreenLayoutContext.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Commands\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutFilterCommands in
    '..\Source\Core\Commands\ScreenLayoutFilterCommands.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutObjectColorController in
    '..\Source\ObjectProperties\ScreenLayoutObjectColorController.pas',
  ScreenLayoutObjectPropertyCommands in
    '..\Source\ObjectProperties\ScreenLayoutObjectPropertyCommands.pas',
  ScreenLayoutObjectPropertySelection in
    '..\Source\ObjectProperties\ScreenLayoutObjectPropertySelection.pas';

type
  TColorPickerSVAreaAccess = class(TColorPickerSVArea);

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Context: IVectArtDesignerContext;
  Controller: TScreenLayoutObjectColorController;
  Data: TVectArtRectangleData;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Form: TForm;
  Frame: TScreenLayoutColorPickerFrame;
  History: TVectArtEditHistory;
  I: Integer;
  Layer: TVectArtLayer;
  Outline: TScreenLayoutOutlineFilter;
  Blur: TScreenLayoutBlurFilter;
  Shadow: TScreenLayoutShadowFilter;
  SVArea: TColorPickerSVArea;
  TrackBar: THorizontalTrackBarControl;
begin
  Form := TForm.CreateNew(nil);
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
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

    Context := TVectArtDesignerContext.Create(Document, History, EditorState);
    Frame := TScreenLayoutColorPickerFrame.Create(Form);
    Frame.Parent := Form;
    Frame.SetBounds(0, 0, 200, 205);
    Controller := TScreenLayoutObjectColorController.Create(Frame);
    try
      Controller.SetContext(Context);
      Check(Frame.SelectedColor = clBlue,
        'object color was not shown before selecting a filter');
      Check(Frame.Opacity = 75,
        'object opacity was not shown before selecting a filter');

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
      TColorPickerSVAreaAccess(SVArea).MouseDown(mbLeft, [],
        SVArea.Width - 1, 0);
      TColorPickerSVAreaAccess(SVArea).MouseUp(mbLeft, [],
        SVArea.Width - 1, 0);
      Check((ColorToRGB(Outline.Color) = ColorToRGB(SVArea.Color)) and
        (ColorToRGB(Outline.Color) <> ColorToRGB(clBlack)),
        'picker did not edit the selected outline color');
      Check(History.CanUndo, 'filter color gesture did not create history');
      History.Undo;
      Check(ColorToRGB(Outline.Color) = ColorToRGB(clBlack),
        'filter color undo did not restore the original value');

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
