// 文字編集中だけ表示する選択範囲と新規入力ガイドの配置計算・描画を担当する。
unit ScreenLayoutTextEditOverlay;

interface

uses
  System.Types, Vcl.Direct2D, Vcl.Graphics, ScreenLayoutDocument;

type
  TScreenLayoutTextEditOverlayState = record
    Layer: TScreenLayoutTextLayer; // 編集対象。nilなら選択範囲を表示しない。
    Text: string;                  // Document反映前を含む現在の編集文字列。
    CaretIndex: Integer;           // 選択可動端のUTF-16挿入位置。
    SelectionAnchor: Integer;      // 選択固定端のUTF-16挿入位置。
    CompositionText: string;       // Document未反映のIME未確定文字列。
    CompositionPosition: TPoint;   // 未確定文字列の画面座標上の左上。
    CompositionFontHeight: Integer; // IME受取用Editと同じフォント高。
    CanvasBounds: TRect;           // コントロール座標上の出力範囲。
    CanvasWidth: Integer;          // 中央原点変換に使用する論理出力幅。
    CanvasHeight: Integer;         // 中央原点変換に使用する論理出力高。
    Zoom: Single;                  // 論理座標から画面座標への表示倍率。
    DragActive: Boolean;           // 新規文字入力ガイドのドラッグ中ならTrue。
    DragStart: TPoint;             // コントロール座標上のドラッグ始点。
    DragCurrent: TPoint;           // コントロール座標上の現在の終点。
  end;

// Documentを変更せず、文字選択範囲と新規入力ガイドをGDIへ描画する。
procedure DrawScreenLayoutTextEditOverlay(Target: TCanvas;
  const State: TScreenLayoutTextEditOverlayState); overload;
// GDI版と同じ配置計算を使用して文字編集オーバーレイをDirect2Dへ描画する。
procedure DrawScreenLayoutTextEditOverlay(Target: TDirect2DCanvas;
  const State: TScreenLayoutTextEditOverlayState); overload;

implementation

uses
  System.Math, System.Skia, ScreenLayoutGeometry, ScreenLayoutTextEditing,
  ScreenLayoutOverlayShapes, ScreenLayoutTextGeometry;

type
  TScreenLayoutTextSelectionRun = record
    Bounds: TRect; // 選択された行内範囲の画面座標矩形。
    Text: string;  // 選択色の矩形上へ描画する文字列。
  end;

function HorizontalTextAlignmentOffset(
  Alignment: TScreenLayoutTextAlignment; LayoutWidth,
  LineWidth: Single): Single;
begin
  case Ord(Alignment) mod 3 of
    1: Result := (LayoutWidth - LineWidth) * 0.5;
    2: Result := LayoutWidth - LineWidth;
  else
    Result := 0;
  end;
end;

function ToScreenX(Value: Single;
  const State: TScreenLayoutTextEditOverlayState): Integer;
begin
  Result := LogicalToScreenX(Value, State.CanvasBounds, State.Zoom,
    State.CanvasWidth);
end;

function ToScreenY(Value: Single;
  const State: TScreenLayoutTextEditOverlayState): Integer;
begin
  Result := LogicalToScreenY(Value, State.CanvasBounds, State.Zoom,
    State.CanvasHeight);
end;

function BuildSelectionRuns(const State: TScreenLayoutTextEditOverlayState;
  out FontHeight: Integer): TArray<TScreenLayoutTextSelectionRun>;
var
  CaretLines: TArray<TScreenLayoutCaretLine>;
  Font: ISkFont;
  I: Integer;
  Layout: TScreenLayoutTextLayout;
  LineHeight: Single;
  LineOffset: Single;
  LineWidth: Single;
  PrefixText: string;
  RunIndex: Integer;
  ScaleX: Single;
  ScaleY: Single;
  SelectionEnd: Integer;
  SelectionStart: Integer;
  SelectedText: string;
  SpanEnd: Integer;
  SpanStart: Integer;
begin
  Result := nil;
  FontHeight := 0;
  if State.Layer = nil then
    Exit;
  SelectionStart := Min(State.CaretIndex, State.SelectionAnchor);
  SelectionEnd := Max(State.CaretIndex, State.SelectionAnchor);
  if SelectionStart = SelectionEnd then
    Exit;
  Font := CreateScreenLayoutTextFont(State.Layer.FontFamily,
    State.Layer.FontSize, State.Layer.FontStyle);
  LineHeight := Max(Font.Spacing + State.Layer.FontSize *
    State.Layer.LineSpacingRatio, 1.0);
  CaretLines := BuildScreenLayoutTextCaretLines(State.Text,
    State.Layer.FontFamily, State.Layer.FontSize, State.Layer.WrapWidth,
    State.Layer.FontStyle, State.Layer.LetterSpacingRatio,
    State.Layer.LineSpacingRatio);
  Layout := BuildScreenLayoutTextLayout(State.Text,
    State.Layer.FontFamily, State.Layer.FontSize, State.Layer.WrapWidth,
    State.Layer.FontStyle, State.Layer.LetterSpacingRatio,
    State.Layer.LineSpacingRatio);
  if State.Layer is TScreenLayoutTextPathLayer then
  begin
    ScaleX := 1.0;
    ScaleY := 1.0;
  end
  else
  begin
    ScaleX := State.Layer.Bounds.Width / Max(Layout.Width, 1.0);
    ScaleY := State.Layer.Bounds.Height /
      Max(Layout.Height, State.Layer.FontSize);
  end;
  FontHeight := -Max(Round(State.Layer.FontSize * ScaleY * State.Zoom), 1);
  for I := 0 to High(CaretLines) do
  begin
    SpanStart := Max(SelectionStart, CaretLines[I].StartIndex);
    SpanEnd := Min(SelectionEnd, CaretLines[I].EndIndex);
    if SpanStart >= SpanEnd then
      Continue;
    PrefixText := Copy(State.Text, CaretLines[I].StartIndex + 1,
      SpanStart - CaretLines[I].StartIndex);
    SelectedText := Copy(State.Text, SpanStart + 1, SpanEnd - SpanStart);
    LineWidth := MeasureScreenLayoutText(CaretLines[I].Text, Font,
      State.Layer.FontSize * State.Layer.LetterSpacingRatio);
    LineOffset := HorizontalTextAlignmentOffset(State.Layer.Alignment,
      Layout.Width, LineWidth);
    RunIndex := Length(Result);
    SetLength(Result, RunIndex + 1);
    Result[RunIndex].Bounds := Rect(
      ToScreenX(State.Layer.Bounds.Left + (LineOffset +
        MeasureScreenLayoutText(PrefixText, Font,
          State.Layer.FontSize * State.Layer.LetterSpacingRatio)) * ScaleX,
        State),
      ToScreenY(State.Layer.Bounds.Top + I * LineHeight * ScaleY, State),
      ToScreenX(State.Layer.Bounds.Left + (LineOffset +
        MeasureScreenLayoutText(PrefixText + SelectedText, Font,
          State.Layer.FontSize * State.Layer.LetterSpacingRatio)) * ScaleX,
        State),
      ToScreenY(State.Layer.Bounds.Top + (I + 1) * LineHeight * ScaleY,
        State));
    Result[RunIndex].Text := SelectedText;
  end;
end;

function InputGuideRect(
  const State: TScreenLayoutTextEditOverlayState): TRect;
begin
  Result := TRect.Create(Min(State.DragStart.X, State.DragCurrent.X),
    Min(State.DragStart.Y, State.DragCurrent.Y),
    Max(State.DragStart.X, State.DragCurrent.X),
    Max(State.DragStart.Y, State.DragCurrent.Y));
end;

procedure DrawContrastText(Target: TCanvas; const State:
  TScreenLayoutTextEditOverlayState); overload;
var
  OffsetX: Integer;
  OffsetY: Integer;
begin
  if (State.Layer = nil) or (State.CompositionText = '') then
    Exit;
  Target.Font.Name := State.Layer.FontFamily;
  Target.Font.Height := State.CompositionFontHeight;
  Target.Font.Style := State.Layer.FontStyle + [fsUnderline];
  Target.Brush.Style := bsClear;
  Target.Font.Color := clWhite;
  for OffsetY := -1 to 1 do
    for OffsetX := -1 to 1 do
      if (OffsetX <> 0) or (OffsetY <> 0) then
        Target.TextOut(State.CompositionPosition.X + OffsetX,
          State.CompositionPosition.Y + OffsetY, State.CompositionText);
  Target.Font.Color := clBlack;
  Target.TextOut(State.CompositionPosition.X, State.CompositionPosition.Y,
    State.CompositionText);
end;

procedure DrawContrastText(Target: TDirect2DCanvas; const State:
  TScreenLayoutTextEditOverlayState); overload;
var
  OffsetX: Integer;
  OffsetY: Integer;
begin
  if (State.Layer = nil) or (State.CompositionText = '') then
    Exit;
  Target.Font.Name := State.Layer.FontFamily;
  Target.Font.Height := State.CompositionFontHeight;
  Target.Font.Style := State.Layer.FontStyle + [fsUnderline];
  Target.Brush.Style := bsClear;
  Target.Font.Color := clWhite;
  for OffsetY := -1 to 1 do
    for OffsetX := -1 to 1 do
      if (OffsetX <> 0) or (OffsetY <> 0) then
        Target.TextOut(State.CompositionPosition.X + OffsetX,
          State.CompositionPosition.Y + OffsetY, State.CompositionText);
  Target.Font.Color := clBlack;
  Target.TextOut(State.CompositionPosition.X, State.CompositionPosition.Y,
    State.CompositionText);
end;

procedure DrawScreenLayoutTextEditOverlay(Target: TCanvas;
  const State: TScreenLayoutTextEditOverlayState);
var
  FontHeight: Integer;
  GuideRect: TRect;
  Run: TScreenLayoutTextSelectionRun;
  Runs: TArray<TScreenLayoutTextSelectionRun>;
begin
  Runs := BuildSelectionRuns(State, FontHeight);
  if Length(Runs) > 0 then
  begin
    Target.Font.Name := State.Layer.FontFamily;
    Target.Font.Height := FontHeight;
    Target.Font.Style := State.Layer.FontStyle;
    Target.Font.Color := clHighlightText;
    for Run in Runs do
    begin
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := clHighlight;
      Target.FillRect(Run.Bounds);
      Target.Brush.Style := bsClear;
      Target.TextOut(Run.Bounds.Left, Run.Bounds.Top, Run.Text);
    end;
  end;
  DrawContrastText(Target, State);
  if State.DragActive then
  begin
    GuideRect := InputGuideRect(State);
    DrawOverlayFrameRect(Target, GuideRect, clBlack, psDot);
  end;
end;

procedure DrawScreenLayoutTextEditOverlay(Target: TDirect2DCanvas;
  const State: TScreenLayoutTextEditOverlayState);
var
  FontHeight: Integer;
  GuideRect: TRect;
  Run: TScreenLayoutTextSelectionRun;
  Runs: TArray<TScreenLayoutTextSelectionRun>;
begin
  Runs := BuildSelectionRuns(State, FontHeight);
  if Length(Runs) > 0 then
  begin
    Target.Font.Name := State.Layer.FontFamily;
    Target.Font.Height := FontHeight;
    Target.Font.Style := State.Layer.FontStyle;
    Target.Font.Color := clHighlightText;
    for Run in Runs do
    begin
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := clHighlight;
      Target.FillRect(Run.Bounds);
      Target.Brush.Style := bsClear;
      Target.TextOut(Run.Bounds.Left, Run.Bounds.Top, Run.Text);
    end;
  end;
  DrawContrastText(Target, State);
  if State.DragActive then
  begin
    GuideRect := InputGuideRect(State);
    DrawOverlayFrameRect(Target, GuideRect, clBlack, psDot);
  end;
end;

end.
