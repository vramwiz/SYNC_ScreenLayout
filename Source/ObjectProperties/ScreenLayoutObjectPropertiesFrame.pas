// Object Propertiesの各専用Frameを配置し、共通スクロール領域として提供する。
unit ScreenLayoutObjectPropertiesFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  ScreenLayoutColorPickerFrame, ScreenLayoutContext,
  ScreenLayoutGeometryPropertiesFrame, ScreenLayoutLinePropertiesFrame,
  ScreenLayoutObjectColorController, ScreenLayoutObjectLineController,
  ScreenLayoutObjectPropertiesControl, ScreenLayoutToolFrames,
  VerticalScrollBarControl;

type
  TObjectPropertiesFrame = class(TToolPlaceholderFrame)
  private
    FColorController: TScreenLayoutObjectColorController;
    FColorPickerFrame: TScreenLayoutColorPickerFrame;
    FContentPanel: TPanel;
    FContext: IVectArtDesignerContext;
    FGeometryFrame: TScreenLayoutGeometryPropertiesFrame;
    FLineController: TScreenLayoutObjectLineController;
    FLinePropertiesFrame: TScreenLayoutLinePropertiesFrame;
    FLastSelectionCount: Integer;
    FLastSelectionLayer: TObject;
    FPropertiesControl: TVectArtObjectPropertiesControl;
    FScrollBar: TVerticalScrollBarControl;
    FUpdatingScrollBar: Boolean;
    FViewport: TPanel;
    procedure PropertyControllerChanged(Sender: TObject);
    procedure ScrollBarChanged(Sender: TObject);
    procedure SetContext(const Value: IVectArtDesignerContext);
    procedure UpdateScrollLayout;
  protected
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    // 専用Frame、属性Controller、共通スクロール領域を生成して接続する。
    constructor Create(AOwner: TComponent); override;
    // 非所有のFrameより先に属性Controllerを破棄し、イベント参照を残さない。
    destructor Destroy; override;
    // Documentと選択状態から全専用Frameを再同期し、必要な領域だけを再配置する。
    procedure RefreshFromDocument;
    // Contextを交換すると、各Frameと属性Controllerへ同じ編集サービスを接続する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  System.Math, Winapi.Windows, Vcl.Graphics,
  ScreenLayoutDocument, ScreenLayoutObjectPropertySelection;

{$R ScreenLayoutObjectPropertiesFrame.dfm}

const
  APPEARANCE_PANEL_HEIGHT       = 100; // 円弧角度を表示する旧領域の論理高さ。
  COLOR_PANEL_BACKGROUND       = TColor($00212121);
  COLOR_PICKER_PANEL_HEIGHT    = 250; // 色と不透明度Frameの論理高さ。
  GEOMETRY_PANEL_HEIGHT        = 145; // 座標とサイズFrameの論理高さ。
  LINE_PROPERTIES_PANEL_HEIGHT = 190; // 線属性Frameの論理高さ。
  OBJECT_PROPERTIES_DOCK_WIDTH = 160;
  PANEL_GAP                    = 8;
  SCROLL_BAR_WIDTH             = 14;
  SCROLL_WHEEL_PIXELS          = 120;

constructor TObjectPropertiesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConfigureToolAppearance('ObjectProperties', 'Object Properties',
    COLOR_PANEL_BACKGROUND, OBJECT_PROPERTIES_DOCK_WIDTH);
  TitleLabel.Visible := False;

  FViewport := TPanel.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := alClient;
  FViewport.BevelOuter := bvNone;
  FViewport.Color := COLOR_PANEL_BACKGROUND;
  FViewport.ParentBackground := False;

  FContentPanel := TPanel.Create(Self);
  FContentPanel.Parent := FViewport;
  FContentPanel.BevelOuter := bvNone;
  FContentPanel.Color := COLOR_PANEL_BACKGROUND;
  FContentPanel.ParentBackground := False;

  FGeometryFrame := TScreenLayoutGeometryPropertiesFrame.Create(Self);
  FGeometryFrame.Parent := FContentPanel;

  FPropertiesControl := TVectArtObjectPropertiesControl.Create(Self);
  FPropertiesControl.Parent := FContentPanel;
  FPropertiesControl.GeometryControlsVisible := False;
  FPropertiesControl.ColorControlsVisible := False;
  FPropertiesControl.OpacityControlsVisible := False;
  FPropertiesControl.StrokePropertyControlsVisible := False;

  FLinePropertiesFrame := TScreenLayoutLinePropertiesFrame.Create(Self);
  FLinePropertiesFrame.Parent := FContentPanel;
  FLinePropertiesFrame.Visible := False;

  FColorPickerFrame := TScreenLayoutColorPickerFrame.Create(Self);
  FColorPickerFrame.Parent := FContentPanel;

  FColorController := TScreenLayoutObjectColorController.Create(
    FColorPickerFrame);
  FColorController.OnChanged := PropertyControllerChanged;
  FLineController := TScreenLayoutObjectLineController.Create(
    FLinePropertiesFrame);
  FLineController.OnChanged := PropertyControllerChanged;

  FScrollBar := TVerticalScrollBarControl.Create(Self);
  FScrollBar.Parent := FViewport;
  FScrollBar.Visible := False;
  FScrollBar.SmallChange := 40;
  FScrollBar.OnChange := ScrollBarChanged;
  UpdateScrollLayout;
end;

destructor TObjectPropertiesFrame.Destroy;
begin
  FLineController.Free;
  FColorController.Free;
  inherited Destroy;
end;

function TObjectPropertiesFrame.DoMouseWheel(Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  UpdateScrollLayout;
  Result := FScrollBar.Visible and (WheelDelta <> 0);
  if Result then
    FScrollBar.Position := FScrollBar.Position -
      MulDiv(WheelDelta, MulDiv(SCROLL_WHEEL_PIXELS, CurrentPPI, 96),
        WHEEL_DELTA)
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TObjectPropertiesFrame.PropertyControllerChanged(Sender: TObject);
begin
  FPropertiesControl.RefreshFromDocument;
end;

procedure TObjectPropertiesFrame.RefreshFromDocument;
var
  Layers: TArray<TVectArtLayer>;
  SelectionLayer: TObject;
begin
  Layers := ScreenLayoutSelectedOpacityLayers(FContext);
  if Length(Layers) > 0 then
    SelectionLayer := Layers[0]
  else
    SelectionLayer := nil;
  if (FLastSelectionCount <> Length(Layers)) or
    (FLastSelectionLayer <> SelectionLayer) then
  begin
    FLastSelectionCount := Length(Layers);
    FLastSelectionLayer := SelectionLayer;
    if FScrollBar <> nil then
      FScrollBar.Position := 0;
  end;
  FGeometryFrame.RefreshFromDocument;
  FPropertiesControl.RefreshFromDocument;
  FPropertiesControl.Visible :=
    ScreenLayoutSelectionNeedsArcProperties(FContext);
  FColorController.Refresh;
  FLineController.Refresh;
  UpdateScrollLayout;
end;

procedure TObjectPropertiesFrame.Resize;
begin
  inherited;
  if FViewport <> nil then
    UpdateScrollLayout;
end;

procedure TObjectPropertiesFrame.ScrollBarChanged(Sender: TObject);
begin
  if not FUpdatingScrollBar then
    UpdateScrollLayout;
end;

procedure TObjectPropertiesFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  if FContext = nil then
  begin
    FGeometryFrame.EditorState := nil;
    FGeometryFrame.EditHistory := nil;
    FGeometryFrame.Document := nil;
    FPropertiesControl.EditorState := nil;
    FPropertiesControl.EditHistory := nil;
    FPropertiesControl.Document := nil;
  end
  else
  begin
    FGeometryFrame.Document := FContext.Document;
    FGeometryFrame.EditHistory := FContext.EditHistory;
    FGeometryFrame.EditorState := FContext.EditorState;
    FPropertiesControl.Document := FContext.Document;
    FPropertiesControl.EditHistory := FContext.EditHistory;
    FPropertiesControl.EditorState := FContext.EditorState;
  end;
  FColorController.SetContext(FContext);
  FLineController.SetContext(FContext);
  RefreshFromDocument;
end;

procedure TObjectPropertiesFrame.UpdateScrollLayout;
var
  AppearanceHeight: Integer;
  BarWidth: Integer;
  ColorHeight: Integer;
  ColorTop: Integer;
  ContentHeight: Integer;
  ContentWidth: Integer;
  Gap: Integer;
  GeometryHeight: Integer;
  LineHeight: Integer;
  MaximumOffset: Integer;
  NextTop: Integer;
  ScrollStep: Integer;
begin
  // 生成途中は親Handleを使うレイアウト処理をドック登録後まで延期する。
  if (Parent = nil) or (FViewport = nil) or (FContentPanel = nil) or
    (FScrollBar = nil) then
    Exit;
  GeometryHeight := MulDiv(GEOMETRY_PANEL_HEIGHT, CurrentPPI, 96);
  ColorHeight := MulDiv(COLOR_PICKER_PANEL_HEIGHT, CurrentPPI, 96);
  Gap := MulDiv(PANEL_GAP, CurrentPPI, 96);
  if FPropertiesControl.Visible then
    AppearanceHeight := MulDiv(APPEARANCE_PANEL_HEIGHT, CurrentPPI, 96)
  else
    AppearanceHeight := 0;
  if FLinePropertiesFrame.Visible then
    LineHeight := MulDiv(LINE_PROPERTIES_PANEL_HEIGHT, CurrentPPI, 96)
  else
    LineHeight := 0;

  NextTop := GeometryHeight;
  if AppearanceHeight > 0 then
    Inc(NextTop, Gap + AppearanceHeight);
  if LineHeight > 0 then
    Inc(NextTop, Gap + LineHeight);
  ColorTop := Max(NextTop + Gap,
    FViewport.ClientHeight - ColorHeight);
  ContentHeight := Max(ColorTop + ColorHeight, FViewport.ClientHeight);
  MaximumOffset := Max(ContentHeight - FViewport.ClientHeight, 0);
  BarWidth := MulDiv(SCROLL_BAR_WIDTH, CurrentPPI, 96);
  ScrollStep := MulDiv(40, CurrentPPI, 96);

  FUpdatingScrollBar := True;
  try
    FScrollBar.Visible := MaximumOffset > 0;
    if FScrollBar.Visible then
      ContentWidth := Max(FViewport.ClientWidth - BarWidth - 1, 0)
    else
      ContentWidth := FViewport.ClientWidth;
    FScrollBar.SetBounds(Max(FViewport.ClientWidth - BarWidth, 0), 0,
      BarWidth, FViewport.ClientHeight);
    FScrollBar.BringToFront;
    FScrollBar.SmallChange := ScrollStep;
    FScrollBar.LargeChange := Max(FViewport.ClientHeight - ScrollStep,
      ScrollStep);
    FScrollBar.SetRange(MaximumOffset, Max(FViewport.ClientHeight, 1));
    FContentPanel.SetBounds(0, -FScrollBar.Position, ContentWidth,
      ContentHeight);

    FGeometryFrame.SetBounds(0, 0, ContentWidth, GeometryHeight);
    NextTop := GeometryHeight;
    if AppearanceHeight > 0 then
    begin
      Inc(NextTop, Gap);
      FPropertiesControl.SetBounds(0, NextTop, ContentWidth,
        AppearanceHeight);
      Inc(NextTop, AppearanceHeight);
    end;
    if LineHeight > 0 then
    begin
      Inc(NextTop, Gap);
      FLinePropertiesFrame.SetBounds(0, NextTop, ContentWidth, LineHeight);
      Inc(NextTop, LineHeight);
    end;
    ColorTop := Max(NextTop + Gap,
      FViewport.ClientHeight - ColorHeight);
    FColorPickerFrame.SetBounds(0, ColorTop, ContentWidth, ColorHeight);
  finally
    FUpdatingScrollBar := False;
  end;
end;

end.
