// 左ドックのスプリッター増減分が主要なレイヤーパネルへ反映されることを検証する。
program ScreenLayoutDockResizeTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  ScreenLayoutDockManager in '..\Source\Layout\ScreenLayoutDockManager.pas',
  ScreenLayoutLayerPanelFrame in '..\Source\Layers\ScreenLayoutLayerPanelFrame.pas',
  ScreenLayoutToolPaletteFrame in '..\Source\ToolPalette\ScreenLayoutToolPaletteFrame.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

var
  DockManager: TVectDockManager;
  DropLeft: TPanel;
  DropRight: TPanel;
  Form: TForm;
  LeftArea: TPanel;
  LayerFrame: TLayerPanelFrame;
  OriginalAreaWidth: Integer;
  OriginalLayerWidth: Integer;
  RightArea: TPanel;
  SplitterLeft: TSplitter;
  SplitterRight: TSplitter;
  ToolFrame: TToolPaletteFrame;
  Workspace: TPanel;
begin
  Application.Initialize;
  Form := TForm.Create(nil);
  try
    Form.SetBounds(0, 0, 1000, 700);
    Workspace := TPanel.Create(Form);
    Workspace.Parent := Form;
    Workspace.Align := alClient;
    LeftArea := TPanel.Create(Form);
    LeftArea.Parent := Workspace;
    LeftArea.Align := alLeft;
    RightArea := TPanel.Create(Form);
    RightArea.Parent := Workspace;
    RightArea.Align := alRight;
    SplitterLeft := TSplitter.Create(Form);
    SplitterLeft.Parent := Workspace;
    SplitterLeft.Align := alLeft;
    SplitterRight := TSplitter.Create(Form);
    SplitterRight.Parent := Workspace;
    SplitterRight.Align := alRight;
    DropLeft := TPanel.Create(Form);
    DropLeft.Parent := Workspace;
    DropRight := TPanel.Create(Form);
    DropRight.Parent := Workspace;
    DockManager := TVectDockManager.Create(Form, Workspace, LeftArea,
      RightArea, DropLeft, DropRight, SplitterLeft, SplitterRight);
    try
      LayerFrame := TLayerPanelFrame.Create(Form);
      ToolFrame := TToolPaletteFrame.Create(Form);
      DockManager.RegisterTool(LayerFrame, vdsLeft);
      DockManager.RegisterTool(ToolFrame, vdsLeft);
      Form.Show;
      Application.ProcessMessages;
      OriginalAreaWidth := LeftArea.Width;
      OriginalLayerWidth := LayerFrame.Width;
      LeftArea.Width := OriginalAreaWidth + 40;
      Workspace.Realign;
      Check(Assigned(SplitterLeft.OnMoved),
        'Left splitter has no resize handler');
      SplitterLeft.OnMoved(SplitterLeft);
      Application.ProcessMessages;
      Check(LayerFrame.Width = OriginalLayerWidth + 40,
        Format('Layer width did not follow splitter: %d -> %d',
          [OriginalLayerWidth, LayerFrame.Width]));
      Writeln('PASS');
    finally
      DockManager.Free;
    end;
  finally
    Form.Free;
  end;
end.
