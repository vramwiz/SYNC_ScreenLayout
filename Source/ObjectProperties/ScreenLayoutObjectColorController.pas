// 埋め込みカラーピッカーと選択レイヤーの色・不透明度を双方向同期する。
unit ScreenLayoutObjectColorController;

interface

uses
  System.Classes, Vcl.Graphics, ScreenLayoutColorPickerFrame,
  ScreenLayoutContext, ScreenLayoutDocument;

type
  TScreenLayoutObjectColorController = class
  private
    FContext: IVectArtDesignerContext;
    FFrame: TScreenLayoutColorPickerFrame;
    FOnChanged: TNotifyEvent;
    FOpacityDocumentUpdateActive: Boolean;
    FOpacityGestureActive: Boolean;
    FOpacityStartLayers: TArray<TVectArtLayer>;
    FOpacityStartValues: TArray<Single>;
    FUpdatingColor: Boolean;
    procedure ColorChanged(Sender: TObject);
    procedure OpacityChanged(Sender: TObject);
    procedure OpacityGestureEnd(Sender: TObject);
    procedure OpacityGestureStart(Sender: TObject);
  public
    // FrameのイベントをDocument編集へ接続する。Frameの所有権は取得しない。
    constructor Create(AFrame: TScreenLayoutColorPickerFrame);
    // 編集対象のContextを交換する。呼び出し側はContext内サービスの寿命を保証する。
    procedure SetContext(const Value: IVectArtDesignerContext);
    // 現在選択の値とロック状態をFrameへ反映し、変更イベントは発生させない。
    procedure Refresh;
    // Documentへ属性を反映した後、他の表示同期が必要なことを呼び出し側へ通知する。
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math, ScreenLayoutEditCommands,
  ScreenLayoutObjectPropertyCommands, ScreenLayoutObjectPropertySelection;

procedure TScreenLayoutObjectColorController.ColorChanged(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  Layer: TVectArtLayer;
  NewColor: TColor;
  OldColor: TColor;
  Target: TScreenLayoutLayerColorTarget;
begin
  if FUpdatingColor or (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewColor := ColorToRGB(FFrame.SelectedColor);
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for Layer in ScreenLayoutSelectedColorLayers(FContext) do
      if not Layer.Locked and TryGetScreenLayoutLayerColor(Layer, OldColor,
        Target) and (ColorToRGB(OldColor) <> NewColor) then
      begin
        Command.Add(TScreenLayoutLayerColorCommand.Create(Document, Layer,
          Target, OldColor, NewColor));
        if Target = slctFill then
        begin
          if Layer is TVectArtRectangleLayer then
            TVectArtRectangleLayer(Layer).FillColor := NewColor
          else
            TScreenLayoutShapeLayer(Layer).FillColor := NewColor;
        end
        else if Layer is TScreenLayoutRectangleLineLayer then
          TScreenLayoutRectangleLineLayer(Layer).StrokeColor := NewColor
        else if Layer is TScreenLayoutArcLayer then
          TScreenLayoutArcLayer(Layer).StrokeColor := NewColor
        else if Layer is TVectArtPathLayer then
          TVectArtPathLayer(Layer).StrokeColor := NewColor
        else
          TScreenLayoutShapeLayer(Layer).StrokeColor := NewColor;
        Document.Changed;
      end;
  finally
    Document.EndUpdate;
  end;
  if (Command.Count > 0) and (FContext.EditHistory <> nil) then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

constructor TScreenLayoutObjectColorController.Create(
  AFrame: TScreenLayoutColorPickerFrame);
begin
  inherited Create;
  FFrame := AFrame;
  FFrame.OnChange := ColorChanged;
  FFrame.OnOpacityChange := OpacityChanged;
  FFrame.OnOpacityGestureEnd := OpacityGestureEnd;
  FFrame.OnOpacityGestureStart := OpacityGestureStart;
end;

procedure TScreenLayoutObjectColorController.OpacityChanged(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  Layer: TVectArtLayer;
  NewValue: Single;
  OldValue: Single;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewValue := FFrame.Opacity / 100.0;
  Command := nil;
  if not FOpacityGestureActive then
    Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for Layer in ScreenLayoutSelectedOpacityLayers(FContext) do
      if not Layer.Locked then
      begin
        OldValue := Layer.Opacity;
        if SameValue(OldValue, NewValue) then
          Continue;
        if Command <> nil then
          Command.Add(TScreenLayoutLayerOpacityCommand.Create(Document,
            Layer, OldValue, NewValue));
        Layer.Opacity := NewValue;
        Document.Changed;
      end;
  finally
    Document.EndUpdate;
  end;
  if (Command <> nil) and (Command.Count > 0) and
    (FContext.EditHistory <> nil) then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  if FContext.EditorState <> nil then
    FContext.EditorState.RectangleOpacity := NewValue;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TScreenLayoutObjectColorController.OpacityGestureEnd(
  Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
begin
  if not FOpacityGestureActive then
    Exit;
  FOpacityGestureActive := False;
  Command := TVectArtCompoundCommand.Create;
  for I := 0 to Min(High(FOpacityStartLayers),
    High(FOpacityStartValues)) do
    if (FOpacityStartLayers[I] <> nil) and
      not SameValue(FOpacityStartValues[I], FOpacityStartLayers[I].Opacity) then
      Command.Add(TScreenLayoutLayerOpacityCommand.Create(FContext.Document,
        FOpacityStartLayers[I], FOpacityStartValues[I],
        FOpacityStartLayers[I].Opacity));
  if (Command.Count > 0) and (FContext.EditHistory <> nil) then
    FContext.EditHistory.AddApplied(Command)
  else
    Command.Free;
  FOpacityStartLayers := nil;
  FOpacityStartValues := nil;
  if FOpacityDocumentUpdateActive then
  begin
    FOpacityDocumentUpdateActive := False;
    FContext.Document.EndInteractiveUpdate;
  end;
end;

procedure TScreenLayoutObjectColorController.OpacityGestureStart(
  Sender: TObject);
var
  I: Integer;
begin
  if (FContext = nil) or (FContext.Document = nil) then
    Exit;
  FOpacityStartLayers := ScreenLayoutSelectedOpacityLayers(FContext);
  if Length(FOpacityStartLayers) = 0 then
    Exit;
  for I := 0 to High(FOpacityStartLayers) do
    if FOpacityStartLayers[I].Locked then
      Exit;
  SetLength(FOpacityStartValues, Length(FOpacityStartLayers));
  for I := 0 to High(FOpacityStartLayers) do
    FOpacityStartValues[I] := FOpacityStartLayers[I].Opacity;
  FOpacityGestureActive := True;
  FContext.Document.BeginInteractiveUpdate;
  FOpacityDocumentUpdateActive := True;
end;

procedure TScreenLayoutObjectColorController.Refresh;
var
  ColorEnabled: Boolean;
  ColorLayers: TArray<TVectArtLayer>;
  ColorValue: TColor;
  I: Integer;
  OpacityEnabled: Boolean;
  OpacityLayers: TArray<TVectArtLayer>;
  Target: TScreenLayoutLayerColorTarget;
begin
  ColorLayers := ScreenLayoutSelectedColorLayers(FContext);
  ColorEnabled := Length(ColorLayers) > 0;
  for I := 0 to High(ColorLayers) do
    ColorEnabled := ColorEnabled and not ColorLayers[I].Locked;
  FFrame.ColorEnabled := ColorEnabled;
  if (Length(ColorLayers) > 0) and
    TryGetScreenLayoutLayerColor(ColorLayers[0], ColorValue, Target) then
  begin
    FUpdatingColor := True;
    try
      FFrame.SelectedColor := ColorValue;
    finally
      FUpdatingColor := False;
    end;
  end;

  OpacityLayers := ScreenLayoutSelectedOpacityLayers(FContext);
  OpacityEnabled := Length(OpacityLayers) > 0;
  for I := 0 to High(OpacityLayers) do
    OpacityEnabled := OpacityEnabled and not OpacityLayers[I].Locked;
  FFrame.OpacityEnabled := OpacityEnabled;
  if Length(OpacityLayers) > 0 then
    FFrame.Opacity := Round(EnsureRange(OpacityLayers[0].Opacity,
      0.0, 1.0) * 100);
end;

procedure TScreenLayoutObjectColorController.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  Refresh;
end;

end.
