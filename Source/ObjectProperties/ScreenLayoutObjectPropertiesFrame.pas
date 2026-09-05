// フィルターUIと色・不透明度UIを同階層の独立Frameとして提供する。
unit ScreenLayoutObjectPropertiesFrame;

interface

uses
  System.Classes, Vcl.Controls, ScreenLayoutColorPickerFrame, ScreenLayoutContext,
  ScreenLayoutFilterFrame, ScreenLayoutObjectColorController,
  ScreenLayoutToolFrames;

type
  TObjectPropertiesFrame = class(TToolPlaceholderFrame)
  private
    FColorController: TScreenLayoutObjectColorController;
    FColorPickerFrame: TScreenLayoutColorPickerFrame;
    FContext: IVectArtDesignerContext;
    FFilterFrame: TScreenLayoutFilterFrame;
    procedure PropertyControllerChanged(Sender: TObject);
    procedure SetContext(const Value: IVectArtDesignerContext);
  public
    // 独立したフィルターFrameと下部固定の色選択Frameを生成する。
    constructor Create(AOwner: TComponent); override;
    // 非所有のFrameより先に属性Controllerを破棄し、イベント参照を残さない。
    destructor Destroy; override;
    // Documentと選択状態からフィルターおよび色選択を再同期する。
    procedure RefreshFromDocument;
    // Contextを交換すると、各子Frameへ同じ編集サービスを接続する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  Winapi.Windows, Vcl.Graphics;

{$R ScreenLayoutObjectPropertiesFrame.dfm}

const
  COLOR_PANEL_BACKGROUND       = TColor($00212121);
  COLOR_PICKER_PANEL_HEIGHT    = 241; // モード列を含め下端に固定する高さ。
  OBJECT_PROPERTIES_DOCK_WIDTH = 160;

constructor TObjectPropertiesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConfigureToolAppearance('ObjectProperties', 'Object Properties',
    COLOR_PANEL_BACKGROUND, OBJECT_PROPERTIES_DOCK_WIDTH);
  TitleLabel.Visible := False;

  FColorPickerFrame := TScreenLayoutColorPickerFrame.Create(Self);
  FColorPickerFrame.Parent := Self;
  FColorPickerFrame.Align := alBottom;
  FColorPickerFrame.Height := MulDiv(COLOR_PICKER_PANEL_HEIGHT,
    CurrentPPI, 96);

  FFilterFrame := TScreenLayoutFilterFrame.Create(Self);
  FFilterFrame.Parent := Self;
  FFilterFrame.Align := alClient;

  FColorController := TScreenLayoutObjectColorController.Create(
    FColorPickerFrame);
  FColorController.OnChanged := PropertyControllerChanged;
end;

destructor TObjectPropertiesFrame.Destroy;
begin
  FColorController.Free;
  inherited Destroy;
end;

procedure TObjectPropertiesFrame.PropertyControllerChanged(Sender: TObject);
begin
  RefreshFromDocument;
end;

procedure TObjectPropertiesFrame.RefreshFromDocument;
begin
  FColorController.Refresh;
  FFilterFrame.RefreshFromDocument;
end;

procedure TObjectPropertiesFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  FColorController.SetContext(FContext);
  FFilterFrame.Context := FContext;
  RefreshFromDocument;
end;

end.
