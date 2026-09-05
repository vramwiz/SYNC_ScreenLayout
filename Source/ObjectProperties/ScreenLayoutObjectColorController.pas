// 埋め込みカラーピッカーを、選択オブジェクトまたは選択フィルターへ双方向同期する。
unit ScreenLayoutObjectColorController;

interface

uses
  System.Classes, Vcl.Graphics, ScreenLayoutColorPickerFrame,
  ScreenLayoutContext, ScreenLayoutDocument, ScreenLayoutFilters,
  ScreenLayoutObjectPropertyCommands;

type
  TScreenLayoutObjectColorController = class
  private
    FColorDocumentUpdateActive: Boolean;
    FColorGestureActive: Boolean;
    FColorGestureFilter: TScreenLayoutFilter;
    FColorGestureOldParameters: TScreenLayoutFilter;
    FColorStartLayers: TArray<TVectArtLayer>;
    FColorStartTargets: TArray<TScreenLayoutLayerColorTarget>;
    FColorStartValues: TArray<TColor>;
    FContext: IVectArtDesignerContext;
    FFrame: TScreenLayoutColorPickerFrame;
    FOnChanged: TNotifyEvent;
    FOpacityDocumentUpdateActive: Boolean;
    FOpacityGestureActive: Boolean;
    FOpacityGestureFilter: TScreenLayoutFilter;
    FOpacityGestureOldParameters: TScreenLayoutFilter;
    FOpacityStartLayers: TArray<TVectArtLayer>;
    FOpacityStartValues: TArray<Single>;
    FRefreshing: Boolean;
    FUpdatingColor: Boolean;
    procedure ColorChanged(Sender: TObject);
    procedure ColorGestureEnd(Sender: TObject);
    procedure ColorGestureStart(Sender: TObject);
    procedure OpacityChanged(Sender: TObject);
    procedure OpacityGestureEnd(Sender: TObject);
    procedure OpacityGestureStart(Sender: TObject);
  public
    // FrameのイベントをDocument編集へ接続する。Frameの所有権は取得しない。
    constructor Create(AFrame: TScreenLayoutColorPickerFrame);
    // 未確定の対話更新を閉じ、保持中のフィルタースナップショットを破棄する。
    destructor Destroy; override;
    // 編集対象のContextを交換する。呼び出し側はContext内サービスの寿命を保証する。
    procedure SetContext(const Value: IVectArtDesignerContext);
    // フィルター選択を優先し、それ以外では現在選択の本体色と不透明度をFrameへ反映する。
    procedure Refresh;
    // Documentへ属性を反映した後、他の表示同期が必要なことを呼び出し側へ通知する。
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math, ScreenLayoutEditCommands, ScreenLayoutFilterCommands,
  ScreenLayoutObjectPropertySelection;

function SelectedFilter(const Context: IVectArtDesignerContext;
  out Layer: TVectArtLayer; out Filter: TScreenLayoutFilter): Boolean;
var
  I: Integer;
begin
  Layer := nil;
  Filter := nil;
  Result := False;
  if (Context = nil) or (Context.EditorState = nil) then
    Exit;
  Layer := Context.EditorState.SelectedFilterLayer;
  Filter := Context.EditorState.SelectedFilter;
  if (Layer = nil) or (Filter = nil) then
    Exit;
  for I := 0 to Layer.FilterCount - 1 do
    if Layer.Filters[I] = Filter then
      Exit(True);
  Layer := nil;
  Filter := nil;
end;

function TryGetFilterColor(Filter: TScreenLayoutFilter;
  out Value: TColor): Boolean;
begin
  Result := True;
  if Filter is TScreenLayoutOutlineFilter then
    Value := TScreenLayoutOutlineFilter(Filter).Color
  else if Filter is TScreenLayoutShadowFilter then
    Value := TScreenLayoutShadowFilter(Filter).Color
  else
  begin
    Value := clNone;
    Result := False;
  end;
end;

procedure SetFilterColor(Filter: TScreenLayoutFilter; Value: TColor);
begin
  Value := ColorToRGB(Value);
  if Filter is TScreenLayoutOutlineFilter then
    TScreenLayoutOutlineFilter(Filter).Color := Value
  else if Filter is TScreenLayoutShadowFilter then
    TScreenLayoutShadowFilter(Filter).Color := Value;
end;

procedure SetLayerColor(Layer: TVectArtLayer;
  Target: TScreenLayoutLayerColorTarget; Value: TColor);
begin
  Value := ColorToRGB(Value);
  if Target = slctFill then
  begin
    if Layer is TVectArtRectangleLayer then
      TVectArtRectangleLayer(Layer).FillColor := Value
    else if Layer is TScreenLayoutShapeLayer then
      TScreenLayoutShapeLayer(Layer).FillColor := Value;
  end
  else if Layer is TScreenLayoutRectangleLineLayer then
    TScreenLayoutRectangleLineLayer(Layer).StrokeColor := Value
  else if Layer is TScreenLayoutArcLayer then
    TScreenLayoutArcLayer(Layer).StrokeColor := Value
  else if Layer is TVectArtPathLayer then
    TVectArtPathLayer(Layer).StrokeColor := Value
  else if Layer is TScreenLayoutShapeLayer then
    TScreenLayoutShapeLayer(Layer).StrokeColor := Value;
end;

procedure AddAppliedCommand(const Context: IVectArtDesignerContext;
  Command: TVectArtEditCommand);
begin
  if (Command <> nil) and (Context <> nil) and
    (Context.EditHistory <> nil) then
    Context.EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

constructor TScreenLayoutObjectColorController.Create(
  AFrame: TScreenLayoutColorPickerFrame);
begin
  inherited Create;
  FFrame := AFrame;
  FFrame.OnChange := ColorChanged;
  FFrame.OnColorGestureEnd := ColorGestureEnd;
  FFrame.OnColorGestureStart := ColorGestureStart;
  FFrame.OnOpacityChange := OpacityChanged;
  FFrame.OnOpacityGestureEnd := OpacityGestureEnd;
  FFrame.OnOpacityGestureStart := OpacityGestureStart;
end;

destructor TScreenLayoutObjectColorController.Destroy;
begin
  if FColorDocumentUpdateActive and (FContext <> nil) and
    (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
  if FOpacityDocumentUpdateActive and (FContext <> nil) and
    (FContext.Document <> nil) then
    FContext.Document.EndInteractiveUpdate;
  FColorGestureOldParameters.Free;
  FOpacityGestureOldParameters.Free;
  inherited Destroy;
end;

procedure TScreenLayoutObjectColorController.ColorChanged(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  Filter: TScreenLayoutFilter;
  Layer: TVectArtLayer;
  NewColor: TColor;
  NewParameters: TScreenLayoutFilter;
  OldColor: TColor;
  OldParameters: TScreenLayoutFilter;
  Target: TScreenLayoutLayerColorTarget;
begin
  if FRefreshing or FUpdatingColor or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewColor := ColorToRGB(FFrame.SelectedColor);
  if SelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not TryGetFilterColor(Filter, OldColor) or
      (ColorToRGB(OldColor) = NewColor) then
      Exit;
    if FColorGestureActive then
    begin
      SetFilterColor(Filter, NewColor);
      Document.Changed;
    end
    else
    begin
      OldParameters := Filter.Clone;
      SetFilterColor(Filter, NewColor);
      Document.Changed;
      NewParameters := Filter.Clone;
      try
        AddAppliedCommand(FContext,
          TScreenLayoutSetFilterParametersCommand.Create(Document, Filter,
            OldParameters, NewParameters));
      finally
        NewParameters.Free;
        OldParameters.Free;
      end;
    end;
  end
  else
  begin
    Command := nil;
    if not FColorGestureActive then
      Command := TVectArtCompoundCommand.Create;
    Document.BeginUpdate;
    try
      for Layer in ScreenLayoutSelectedColorLayers(FContext) do
        if not Layer.Locked and TryGetScreenLayoutLayerColor(Layer, OldColor,
          Target) and (ColorToRGB(OldColor) <> NewColor) then
        begin
          if Command <> nil then
            Command.Add(TScreenLayoutLayerColorCommand.Create(Document,
              Layer, Target, OldColor, NewColor));
          SetLayerColor(Layer, Target, NewColor);
          Document.Changed;
        end;
    finally
      Document.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TScreenLayoutObjectColorController.ColorGestureEnd(Sender: TObject);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  CurrentColor: TColor;
  I: Integer;
  Target: TScreenLayoutLayerColorTarget;
begin
  if not FColorGestureActive then
    Exit;
  FColorGestureActive := False;
  if (FColorGestureFilter <> nil) and
    (FColorGestureOldParameters <> nil) then
  begin
    if TryGetFilterColor(FColorGestureOldParameters, Color) and
      TryGetFilterColor(FColorGestureFilter, CurrentColor) and
      (ColorToRGB(Color) <> ColorToRGB(CurrentColor)) then
      AddAppliedCommand(FContext,
        TScreenLayoutSetFilterParametersCommand.Create(FContext.Document,
          FColorGestureFilter, FColorGestureOldParameters,
          FColorGestureFilter));
  end
  else
  begin
    Command := TVectArtCompoundCommand.Create;
    for I := 0 to Min(High(FColorStartLayers),
      High(FColorStartValues)) do
      if TryGetScreenLayoutLayerColor(FColorStartLayers[I], Color, Target) and
        (ColorToRGB(Color) <> ColorToRGB(FColorStartValues[I])) then
        Command.Add(TScreenLayoutLayerColorCommand.Create(FContext.Document,
          FColorStartLayers[I], FColorStartTargets[I],
          FColorStartValues[I], Color));
    if Command.Count > 0 then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  FColorGestureFilter := nil;
  FColorGestureOldParameters.Free;
  FColorGestureOldParameters := nil;
  FColorStartLayers := nil;
  FColorStartTargets := nil;
  FColorStartValues := nil;
  if FColorDocumentUpdateActive then
  begin
    FColorDocumentUpdateActive := False;
    FContext.Document.EndInteractiveUpdate;
  end;
end;

procedure TScreenLayoutObjectColorController.ColorGestureStart(
  Sender: TObject);
var
  Color: TColor;
  Filter: TScreenLayoutFilter;
  I: Integer;
  Layer: TVectArtLayer;
  Target: TScreenLayoutLayerColorTarget;
begin
  if FColorGestureActive or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  if SelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not TryGetFilterColor(Filter, Color) then
      Exit;
    FColorGestureFilter := Filter;
    FColorGestureOldParameters := Filter.Clone;
  end
  else
  begin
    FColorStartLayers := ScreenLayoutSelectedColorLayers(FContext);
    if Length(FColorStartLayers) = 0 then
      Exit;
    SetLength(FColorStartTargets, Length(FColorStartLayers));
    SetLength(FColorStartValues, Length(FColorStartLayers));
    for I := 0 to High(FColorStartLayers) do
    begin
      if FColorStartLayers[I].Locked or
        not TryGetScreenLayoutLayerColor(FColorStartLayers[I],
          FColorStartValues[I], Target) then
      begin
        FColorStartLayers := nil;
        FColorStartTargets := nil;
        FColorStartValues := nil;
        Exit;
      end;
      FColorStartTargets[I] := Target;
    end;
  end;
  FColorGestureActive := True;
  FContext.Document.BeginInteractiveUpdate;
  FColorDocumentUpdateActive := True;
end;

procedure TScreenLayoutObjectColorController.OpacityChanged(Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Document: TVectArtDocument;
  Filter: TScreenLayoutFilter;
  Layer: TVectArtLayer;
  NewParameters: TScreenLayoutFilter;
  NewValue: Single;
  OldParameters: TScreenLayoutFilter;
  OldValue: Single;
begin
  if FRefreshing or (FContext = nil) or (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewValue := FFrame.Opacity / 100.0;
  if SelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not (Filter is TScreenLayoutShadowFilter) then
      Exit;
    OldValue := TScreenLayoutShadowFilter(Filter).Opacity;
    if SameValue(OldValue, NewValue) then
      Exit;
    if FOpacityGestureActive then
    begin
      TScreenLayoutShadowFilter(Filter).Opacity := NewValue;
      Document.Changed;
    end
    else
    begin
      OldParameters := Filter.Clone;
      TScreenLayoutShadowFilter(Filter).Opacity := NewValue;
      Document.Changed;
      NewParameters := Filter.Clone;
      try
        AddAppliedCommand(FContext,
          TScreenLayoutSetFilterParametersCommand.Create(Document, Filter,
            OldParameters, NewParameters));
      finally
        NewParameters.Free;
        OldParameters.Free;
      end;
    end;
  end
  else
  begin
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
    if (Command <> nil) and (Command.Count > 0) then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
    if FContext.EditorState <> nil then
      FContext.EditorState.RectangleOpacity := NewValue;
  end;
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
  if (FOpacityGestureFilter is TScreenLayoutShadowFilter) and
    (FOpacityGestureOldParameters <> nil) then
  begin
    if not SameValue(
      TScreenLayoutShadowFilter(FOpacityGestureOldParameters).Opacity,
      TScreenLayoutShadowFilter(FOpacityGestureFilter).Opacity) then
      AddAppliedCommand(FContext,
        TScreenLayoutSetFilterParametersCommand.Create(FContext.Document,
          FOpacityGestureFilter, FOpacityGestureOldParameters,
          FOpacityGestureFilter));
  end
  else
  begin
    Command := TVectArtCompoundCommand.Create;
    for I := 0 to Min(High(FOpacityStartLayers),
      High(FOpacityStartValues)) do
      if not SameValue(FOpacityStartValues[I],
        FOpacityStartLayers[I].Opacity) then
        Command.Add(TScreenLayoutLayerOpacityCommand.Create(FContext.Document,
          FOpacityStartLayers[I], FOpacityStartValues[I],
          FOpacityStartLayers[I].Opacity));
    if Command.Count > 0 then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  FOpacityGestureFilter := nil;
  FOpacityGestureOldParameters.Free;
  FOpacityGestureOldParameters := nil;
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
  Filter: TScreenLayoutFilter;
  I: Integer;
  Layer: TVectArtLayer;
begin
  if FOpacityGestureActive or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  if SelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not (Filter is TScreenLayoutShadowFilter) then
      Exit;
    FOpacityGestureFilter := Filter;
    FOpacityGestureOldParameters := Filter.Clone;
  end
  else
  begin
    FOpacityStartLayers := ScreenLayoutSelectedOpacityLayers(FContext);
    if Length(FOpacityStartLayers) = 0 then
      Exit;
    for I := 0 to High(FOpacityStartLayers) do
      if FOpacityStartLayers[I].Locked then
      begin
        FOpacityStartLayers := nil;
        Exit;
      end;
    SetLength(FOpacityStartValues, Length(FOpacityStartLayers));
    for I := 0 to High(FOpacityStartLayers) do
      FOpacityStartValues[I] := FOpacityStartLayers[I].Opacity;
  end;
  FOpacityGestureActive := True;
  FContext.Document.BeginInteractiveUpdate;
  FOpacityDocumentUpdateActive := True;
end;

procedure TScreenLayoutObjectColorController.Refresh;
var
  ColorEnabled: Boolean;
  ColorLayers: TArray<TVectArtLayer>;
  ColorValue: TColor;
  Filter: TScreenLayoutFilter;
  I: Integer;
  Layer: TVectArtLayer;
  OpacityEnabled: Boolean;
  OpacityLayers: TArray<TVectArtLayer>;
  Target: TScreenLayoutLayerColorTarget;
begin
  if FRefreshing then
    Exit;
  FRefreshing := True;
  try
    if SelectedFilter(FContext, Layer, Filter) then
    begin
      FFrame.TargetCaption := 'Color - ' + Filter.DisplayName;
      ColorEnabled := not Layer.Locked and TryGetFilterColor(Filter,
        ColorValue);
      FFrame.ColorEnabled := ColorEnabled;
      if ColorEnabled then
      begin
        FUpdatingColor := True;
        try
          FFrame.SelectedColor := ColorValue;
        finally
          FUpdatingColor := False;
        end;
      end;
      OpacityEnabled := not Layer.Locked and
        (Filter is TScreenLayoutShadowFilter);
      FFrame.OpacityEnabled := OpacityEnabled;
      if Filter is TScreenLayoutShadowFilter then
        FFrame.Opacity := Round(EnsureRange(
          TScreenLayoutShadowFilter(Filter).Opacity, 0.0, 1.0) * 100)
      else
        FFrame.Opacity := 100;
      Exit;
    end;

    FFrame.TargetCaption := 'Color';
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
  finally
    FRefreshing := False;
  end;
end;

procedure TScreenLayoutObjectColorController.SetContext(
  const Value: IVectArtDesignerContext);
begin
  if FColorGestureActive then
    ColorGestureEnd(Self);
  if FOpacityGestureActive then
    OpacityGestureEnd(Self);
  FContext := Value;
  Refresh;
end;

end.
