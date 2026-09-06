// DPI対応ホスト内でも編集Formだけを単独アプリと同じ96 DPI座標で生成できることを確認する。
program ScreenLayoutPluginDpiTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Forms,
  ScreenLayoutGradientKindCombo,
  ScreenLayoutLayerPanelFrame,
  ScreenLayoutTextureControl,
  ScreenLayoutToolPaletteFrame;

type
  TTextureControlAccess = class(TScreenLayoutTextureControl)
  public
    function CurrentFontHeight: Integer;
  end;

function TTextureControlAccess.CurrentFontHeight: Integer;
begin
  Result := Font.Height;
end;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
end;

var
  Form: TForm;
  GradientCombo: TScreenLayoutGradientKindCombo;
  LayerFrame: TLayerPanelFrame;
  PreviousContext: DPI_AWARENESS_CONTEXT;
  TextureControl: TTextureControlAccess;
  ToolFrame: TToolPaletteFrame;

begin
  try
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    Application.Initialize;
    PreviousContext := SetThreadDpiAwarenessContext(
      DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED);
    Check(IsValidDpiAwarenessContext(PreviousContext),
      'cannot enter plugin editor DPI context');
    Check(AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext,
      DPI_AWARENESS_CONTEXT_UNAWARE_GDISCALED), 'editor thread is not GDI-scaled');
    Form := TForm.CreateNew(nil);
    try
      LayerFrame := TLayerPanelFrame.Create(Form);
      ToolFrame := TToolPaletteFrame.Create(Form);
      GradientCombo := TScreenLayoutGradientKindCombo.Create(Form);
      TextureControl := TTextureControlAccess.Create(Form);
      Check((Form.CurrentPPI = 96) and (LayerFrame.CurrentPPI = 96) and
        (ToolFrame.CurrentPPI = 96), 'plugin editor controls did not use 96 DPI coordinates');
      Check((LayerFrame.PreferredDockWidth = 150) and
        (ToolFrame.PreferredDockWidth = 58), 'logical dock widths changed');
      Check((Abs(GradientCombo.Font.Height) = 12) and
        (GradientCombo.ItemHeight = 20),
        'gradient text metrics did not use the editor DPI context');
      Check(Abs(TextureControl.CurrentFontHeight) = 12,
        'texture text metrics did not use the editor DPI context');
    finally
      Form.Free;
    end;
    SetThreadDpiAwarenessContext(PreviousContext);
    Check(AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext,
      PreviousContext), 'host DPI context was not restored');
    Writeln('PASS plugin editor DPI isolation');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
