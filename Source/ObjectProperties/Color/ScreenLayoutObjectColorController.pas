// 埋め込みカラーピッカーを、選択オブジェクトまたは選択フィルターへ双方向同期する。
// 作成色とグラデーション点も含む対象解決はScreenLayoutColorTargetsへ委譲する。
unit ScreenLayoutObjectColorController;

interface

uses
  System.Classes, Vcl.Graphics, ScreenLayoutColorPickerFrame,
  ScreenLayoutContext, ScreenLayoutDocument, ScreenLayoutFilters,
  ScreenLayoutObjectPropertyCommands, ScreenLayoutPaintStyles;

type
  TScreenLayoutObjectColorController = class
  private
    FColorDocumentUpdateActive: Boolean;
    FColorGestureActive: Boolean;
    FColorGestureFilter: TScreenLayoutFilter;
    FColorGestureGradientLayer: TVectArtLayer;
    FColorGestureOldParameters: TScreenLayoutFilter;
    FColorGestureOldPaintStyle: TScreenLayoutPaintStyle;
    FColorStartLayers: TArray<TVectArtLayer>;
    FColorStartTargets: TArray<TScreenLayoutLayerColorTarget>;
    FColorStartValues: TArray<TColor>;
    FContext: IVectArtDesignerContext;
    FCreationTargetStateKnown: Boolean;
    FFrame: TScreenLayoutColorPickerFrame;
    FLastUsesCreationPaint: Boolean;
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
    procedure GradientStopSelected(Sender: TObject);
    procedure AdoptVisiblePickerAsCreationPaint;
    procedure OpacityChanged(Sender: TObject);
    procedure PaintStyleChanged(Sender: TObject);
    procedure OpacityGestureEnd(Sender: TObject);
    procedure OpacityGestureStart(Sender: TObject);
  public
    // FrameのイベントをDocument編集へ接続する。Frameの所有権は取得しない。
    constructor Create(AFrame: TScreenLayoutColorPickerFrame);
    // 未確定の対話更新を閉じ、保持中のフィルタースナップショットを破棄する。
    destructor Destroy; override;
    // 編集対象のContextを交換する。呼び出し側はContext内サービスの寿命を保証する。
    procedure SetContext(const Value: IVectArtDesignerContext);
    // フィルター、グラデーション点、レイヤー、作成色の優先順でFrameへ現在値を反映する。
    procedure Refresh;
    // Documentへ属性を反映した後、他の表示同期が必要なことを呼び出し側へ通知する。
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math, ScreenLayoutEditCommands, ScreenLayoutFilterCommands,
  ScreenLayoutColorTargets, ScreenLayoutEditorState, ScreenLayoutPaintCommands,
  ScreenLayoutObjectPropertySelection;

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
  FFrame.OnGradientStopSelect := GradientStopSelected;
  FFrame.OnOpacityChange := OpacityChanged;
  FFrame.OnOpacityGestureEnd := OpacityGestureEnd;
  FFrame.OnOpacityGestureStart := OpacityGestureStart;
  FFrame.OnPaintStyleChange := PaintStyleChanged;
end;

procedure TScreenLayoutObjectColorController.AdoptVisiblePickerAsCreationPaint;
begin
  if (FContext = nil) or (FContext.EditorState = nil) then
    Exit;
  // 無効な対象（画像やぼかしなど）は表示値を作成既定へ上書きしない。
  if FFrame.ColorEnabled then
    FContext.EditorState.CreationPaintStyle := FFrame.PaintStyle;
  if FFrame.OpacityEnabled then
    FContext.EditorState.RectangleOpacity := FFrame.Opacity / 100.0;
end;

procedure TScreenLayoutObjectColorController.PaintStyleChanged(
  Sender: TObject);
var
  Command: TVectArtCompoundCommand;
  Filter: TScreenLayoutFilter;
  Layer: TVectArtLayer;
  NewStyle: TScreenLayoutPaintStyle;
  OldStyle: TScreenLayoutPaintStyle;
begin
  if FRefreshing or (FContext = nil) or (FContext.EditorState = nil) or
    (FContext.Document = nil) then
    Exit;
  NewStyle := FFrame.PaintStyle;
  if not ScreenLayoutUsesCreationPaint(FContext) and
    not ScreenLayoutSelectedFilter(FContext, Layer, Filter) then
  begin
    Command := TVectArtCompoundCommand.Create;
    FContext.Document.BeginUpdate;
    try
      for Layer in ScreenLayoutSelectedColorLayers(FContext) do
        if not Layer.Locked then
        begin
          OldStyle := Layer.PaintStyle;
          if OldStyle.Kind <> slpkGradient then
            OldStyle := TScreenLayoutPaintStyle.Solid(FFrame.SelectedColor);
          if OldStyle.SameAs(NewStyle) then
            Continue;
          Command.Add(TScreenLayoutSetLayerPaintStyleCommand.Create(
            FContext.Document, Layer, OldStyle, NewStyle));
          Layer.PaintStyle := NewStyle;
          FContext.Document.Changed;
        end;
    finally
      FContext.Document.EndUpdate;
    end;
    if Command.Count > 0 then
      AddAppliedCommand(FContext, Command)
    else
      Command.Free;
  end;
  // 選択対象へ適用したモードを、次回作成用にも同時に採用する。
  FContext.EditorState.CreationPaintStyle := NewStyle;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
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
  NewStyle: TScreenLayoutPaintStyle;
  OldColor: TColor;
  OldParameters: TScreenLayoutFilter;
  OldStyle: TScreenLayoutPaintStyle;
  StopId: Integer;
  Target: TScreenLayoutLayerColorTarget;
begin
  if FRefreshing or FUpdatingColor or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  Document := FContext.Document;
  NewColor := ColorToRGB(FFrame.SelectedColor);
  if ScreenLayoutSelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not TryGetScreenLayoutFilterColor(Filter, OldColor) then
      Exit;
    if ColorToRGB(OldColor) = NewColor then
    begin
      if FContext.EditorState <> nil then
        FContext.EditorState.CreationPaintStyle := FFrame.PaintStyle;
      Exit;
    end;
    if FColorGestureActive then
    begin
      SetScreenLayoutFilterColor(Filter, NewColor);
      Document.Changed;
    end
    else
    begin
      OldParameters := Filter.Clone;
      SetScreenLayoutFilterColor(Filter, NewColor);
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
  else if ScreenLayoutSelectedGradientStop(FContext, Layer, StopId,
    OldColor) then
  begin
    if Layer.Locked then
      Exit;
    OldStyle := Layer.PaintStyle;
    NewStyle := FFrame.PaintStyle;
    if OldStyle.SameAs(NewStyle) then
      Exit;
    Layer.PaintStyle := NewStyle;
    Document.Changed;
    if not FColorGestureActive then
      AddAppliedCommand(FContext, TScreenLayoutSetLayerPaintStyleCommand.Create(
        Document, Layer, OldStyle, NewStyle));
  end
  else if not ScreenLayoutUsesCreationPaint(FContext) then
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
          SetScreenLayoutLayerColor(Layer, Target, NewColor);
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
  // 対象を先に更新してから、確定色を次回作成用にも必ず採用する。
  // EditorStateの同期通知がピッカーを古い対象色へ戻すことを防ぐ。
  if FContext.EditorState <> nil then
    FContext.EditorState.CreationPaintStyle := FFrame.PaintStyle;
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
  if FColorGestureGradientLayer <> nil then
  begin
    if not FColorGestureOldPaintStyle.SameAs(
      FColorGestureGradientLayer.PaintStyle) then
      AddAppliedCommand(FContext, TScreenLayoutSetLayerPaintStyleCommand.Create(
        FContext.Document, FColorGestureGradientLayer,
        FColorGestureOldPaintStyle, FColorGestureGradientLayer.PaintStyle));
  end
  else if (FColorGestureFilter <> nil) and
    (FColorGestureOldParameters <> nil) then
  begin
    if TryGetScreenLayoutFilterColor(FColorGestureOldParameters, Color) and
      TryGetScreenLayoutFilterColor(FColorGestureFilter, CurrentColor) and
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
  FColorGestureGradientLayer := nil;
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
  StopId: Integer;
  Target: TScreenLayoutLayerColorTarget;
begin
  if FColorGestureActive or (FContext = nil) or
    (FContext.Document = nil) then
    Exit;
  if ScreenLayoutSelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not TryGetScreenLayoutFilterColor(Filter, Color) then
      Exit;
    FColorGestureFilter := Filter;
    FColorGestureOldParameters := Filter.Clone;
  end
  else if ScreenLayoutSelectedGradientStop(FContext, Layer, StopId,
    Color) then
  begin
    if Layer.Locked then
      Exit;
    FColorGestureGradientLayer := Layer;
    FColorGestureOldPaintStyle := Layer.PaintStyle;
  end
  else if ScreenLayoutUsesCreationPaint(FContext) then
    Exit
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

procedure TScreenLayoutObjectColorController.GradientStopSelected(
  Sender: TObject);
var
  Color: TColor;
  Layer: TVectArtLayer;
  StopId: Integer;
begin
  if not ScreenLayoutSelectedGradientStop(FContext, Layer, StopId,
    Color) then
    Exit;
  FContext.EditorState.SelectGradientStop(Layer, FFrame.GradientStopId);
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
  if ScreenLayoutSelectedFilter(FContext, Layer, Filter) then
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
  else if ScreenLayoutUsesCreationPaint(FContext) then
  begin
    if FContext.EditorState <> nil then
      FContext.EditorState.RectangleOpacity := NewValue;
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
  if ScreenLayoutSelectedFilter(FContext, Layer, Filter) then
  begin
    if Layer.Locked or not (Filter is TScreenLayoutShadowFilter) then
      Exit;
    FOpacityGestureFilter := Filter;
    FOpacityGestureOldParameters := Filter.Clone;
  end
  else if ScreenLayoutUsesCreationPaint(FContext) then
    Exit
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
  CreationPaintActive: Boolean;
  Filter: TScreenLayoutFilter;
  I: Integer;
  Layer: TVectArtLayer;
  OpacityEnabled: Boolean;
  OpacityLayers: TArray<TVectArtLayer>;
  StopId: Integer;
  Target: TScreenLayoutLayerColorTarget;
begin
  if FRefreshing then
    Exit;
  FRefreshing := True;
  try
    CreationPaintActive := ScreenLayoutUsesCreationPaint(FContext);
    if FCreationTargetStateKnown and CreationPaintActive and
      not FLastUsesCreationPaint then
      AdoptVisiblePickerAsCreationPaint;
    FCreationTargetStateKnown := True;
    FLastUsesCreationPaint := CreationPaintActive;

    if ScreenLayoutSelectedFilter(FContext, Layer, Filter) then
    begin
      FFrame.PaintModeEnabled := False;
      FFrame.TargetCaption := '色：' + Filter.DisplayName;
      ColorEnabled := not Layer.Locked and TryGetScreenLayoutFilterColor(Filter,
        ColorValue);
      FFrame.ColorEnabled := ColorEnabled;
      if ColorEnabled then
      begin
        FUpdatingColor := True;
        try
          FFrame.PaintStyle := TScreenLayoutPaintStyle.Solid(ColorValue);
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

    if CreationPaintActive then
    begin
      FFrame.PaintModeEnabled := True;
      FFrame.TargetCaption := '作成色';
      FFrame.ColorEnabled := True;
      FFrame.OpacityEnabled := True;
      FUpdatingColor := True;
      try
        FFrame.PaintStyle := FContext.EditorState.CreationPaintStyle;
      finally
        FUpdatingColor := False;
      end;
      FFrame.Opacity := Round(EnsureRange(
        FContext.EditorState.RectangleOpacity, 0.0, 1.0) * 100);
      Exit;
    end;

    FFrame.TargetCaption := '色';
    ColorLayers := ScreenLayoutSelectedColorLayers(FContext);
    OpacityLayers := ScreenLayoutSelectedOpacityLayers(FContext);
    if (Length(ColorLayers) = 0) and (Length(OpacityLayers) = 0) and
      (FContext <> nil) and (FContext.EditorState <> nil) then
    begin
      FFrame.PaintModeEnabled := True;
      FFrame.TargetCaption := '作成色';
      FFrame.ColorEnabled := True;
      FFrame.OpacityEnabled := True;
      FUpdatingColor := True;
      try
        FFrame.PaintStyle := FContext.EditorState.CreationPaintStyle;
      finally
        FUpdatingColor := False;
      end;
      FFrame.Opacity := Round(EnsureRange(
        FContext.EditorState.RectangleOpacity, 0.0, 1.0) * 100);
      Exit;
    end;
    ColorEnabled := Length(ColorLayers) > 0;
    FFrame.PaintModeEnabled := True;
    for I := 0 to High(ColorLayers) do
      ColorEnabled := ColorEnabled and not ColorLayers[I].Locked;
    FFrame.ColorEnabled := ColorEnabled;
    if (Length(ColorLayers) > 0) and
      TryGetScreenLayoutLayerColor(ColorLayers[0], ColorValue, Target) then
    begin
      FUpdatingColor := True;
      try
        if ColorLayers[0].PaintStyle.Kind = slpkGradient then
        begin
          FFrame.PaintStyle := ColorLayers[0].PaintStyle;
          if ScreenLayoutSelectedGradientStop(FContext, Layer, StopId,
            ColorValue) then
          begin
            FFrame.GradientStopId := StopId;
            FFrame.TargetCaption := 'グラデーション色';
          end;
        end
        else
          FFrame.PaintStyle := TScreenLayoutPaintStyle.Solid(ColorValue);
      finally
        FUpdatingColor := False;
      end;
    end;

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
  FCreationTargetStateKnown := False;
  FLastUsesCreationPaint := False;
  Refresh;
end;

end.
