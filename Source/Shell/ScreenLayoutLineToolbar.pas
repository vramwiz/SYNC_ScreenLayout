// 線幅を常設し、低頻度の線種・線端を詳細パネルから編集してDocumentと履歴へ同期する。
unit ScreenLayoutLineToolbar;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.StdCtrls, Vcl.AppEvnts,
  HorizontalTrackBarControl, ScreenLayoutDocument, ScreenLayoutEditHistory,
  ScreenLayoutEditorState, ScreenLayoutLineStyleControls,
  ScreenLayoutStrokeStyleCombo;

type
  TVectArtLineToolbarControl = class(TCustomControl)
  private
    FDocument: TVectArtDocument;
    FApplicationEvents: TApplicationEvents;
    FDetailsButton: TVectArtDarkButton;
    FDetailsPanel: TPanel;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FContextText: string;
    FMifStrokeStyleCombo: TVectArtMifStrokeStyleCombo;
    FLineCapButtons: array[TVectArtLineCap] of TVectArtLineCapButton;
    FStrokeWidthTrackBar: THorizontalTrackBarControl;
    FStrokeWidthEdit: TEdit;
    FTrackDocumentUpdateActive: Boolean;
    FTrackGestureActive: Boolean;
    FTrackStartIndices: TArray<Integer>;
    FTrackStartWidths: TArray<Single>;
    FUpdating: Boolean;
    procedure ApplyStrokeWidthInternal(Value: Single;
      RecordHistory: Boolean);
    procedure ApplicationIdle(Sender: TObject; var Done: Boolean);
    procedure BuildControls;
    procedure CommitTrackGesture;
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure DetailsClick(Sender: TObject);
    function IsDetailsControl(Control: TControl): Boolean;
    procedure LineCapClick(Sender: TObject);
    function SelectedLineIndices: TArray<Integer>;
    function SelectionHasLockedLine: Boolean;
    procedure StyleChanged(Sender: TObject);
    procedure TrackBarChanged(Sender: TObject);
    procedure TrackBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TrackBarMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    // AHostへ接続したツールバーと、同じForm上の詳細パネルを生成する。AOwnerが両方を所有する。
    constructor CreateForHost(AOwner: TComponent; AHost: TWinControl);
    // 作成初期値または選択中の全Lineへ線端形状を適用し、必要なら履歴へ記録する。
    procedure ApplyLineCap(Value: TVectArtLineCap);
    // 作成初期値または選択中の全Lineへ線種を適用する。
    procedure ApplyMifStrokeStyle(Value: TVectArtMifStrokeStyle);
    // 作成初期値または選択中の全Lineへ線幅を適用する。
    procedure ApplyStrokeWidth(Value: Single);
    // EditorStateと現在選択から表示値、混在状態、有効状態を再同期する。
    procedure RefreshState;
    // 詳細パネル外へフォーカスが移っていればパネルを閉じる。
    procedure UpdateDetailsPanelFocus;
    // Documentは非所有参照。選択中の線属性の読書き対象となる。
    property Document: TVectArtDocument read FDocument write FDocument;
    // 指定した線端形状の選択ボタンを返す。戻り値の所有権はSelfが保持する。
    function LineCapButton(Value: TVectArtLineCap): TVectArtLineCapButton;
    // UIテストとHost側の配置確認に公開する所有Control。
    property DetailsButton: TVectArtDarkButton read FDetailsButton;
    property DetailsPanel: TPanel read FDetailsPanel;
    // EditHistoryとEditorStateは非所有参照。履歴記録と次回作成値の保持に使う。
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write FEditorState;
    property MifStrokeStyleCombo: TVectArtMifStrokeStyleCombo
      read FMifStrokeStyleCombo;
    // 線幅の常設UI。所有権はToolbarが保持する。
    property StrokeWidthTrackBar: THorizontalTrackBarControl
      read FStrokeWidthTrackBar;
    property StrokeWidthEdit: TEdit read FStrokeWidthEdit;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, Vcl.Forms, Vcl.Graphics,
  ScreenLayoutEditCommands;

const
  COLOR_BACKGROUND = TColor($00282828);
  COLOR_EDIT = TColor($00353535);
  COLOR_LABEL = TColor($00C8C8C8);
  COLOR_TEXT = TColor($00EEEEEE);
  STROKE_WIDTH_SCALE = 10;
  STROKE_WIDTH_TRACK_MIN = 10;
  STROKE_WIDTH_TRACK_MAX = 1000;

function UnicodeText(const CodePoints: array of Word): string;
var
  I: Integer;
begin
  SetLength(Result, Length(CodePoints));
  for I := 0 to High(CodePoints) do
    Result[I + 1] := Char(CodePoints[I]);
end;

function ReadLineLayer(Layer: TVectArtLayer; out Color: TColor;
  out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap): Boolean;
begin
  Result := Layer is TScreenLayoutRectangleLineLayer;
  if Result then
  begin
    Color := TScreenLayoutRectangleLineLayer(Layer).StrokeColor;
    Width := TScreenLayoutRectangleLineLayer(Layer).StrokeWidth;
    Style := TScreenLayoutRectangleLineLayer(Layer).StrokeStyle;
    LineCap := vlcSquare;
    Exit;
  end;
  Result := Layer is TScreenLayoutArcLayer;
  if Result then
  begin
    Color := TScreenLayoutArcLayer(Layer).StrokeColor;
    Width := TScreenLayoutArcLayer(Layer).StrokeWidth;
    Style := TScreenLayoutArcLayer(Layer).StrokeStyle;
    LineCap := TScreenLayoutArcLayer(Layer).LineCap;
    Exit;
  end;
  Result := (Layer is TVectArtPathLayer) and
    not TVectArtPathLayer(Layer).Closed;
  if Result then
  begin
    Color := TVectArtPathLayer(Layer).StrokeColor;
    Width := TVectArtPathLayer(Layer).StrokeWidth;
    Style := TVectArtPathLayer(Layer).MifStrokeStyle;
    LineCap := TVectArtPathLayer(Layer).LineCap;
  end;
end;

procedure SetLineLayerStroke(Document: TVectArtDocument; Index: Integer;
  Color: TColor; Width: Single; Style: TVectArtMifStrokeStyle);
begin
  if Document[Index] is TScreenLayoutRectangleLineLayer then
    Document.SetRectangleLineStroke(Index, Color, Width, Style)
  else if Document[Index] is TScreenLayoutArcLayer then
    Document.SetArcStroke(Index, Color, Width, Style)
  else
    Document.SetPathStroke(Index, Color, Width, Style);
end;

procedure SetLineLayerCap(Document: TVectArtDocument; Index: Integer;
  Value: TVectArtLineCap);
begin
  if Document[Index] is TScreenLayoutRectangleLineLayer then
    Exit
  else if Document[Index] is TScreenLayoutArcLayer then
    Document.SetArcLineCap(Index, Value)
  else
    Document.SetPathLineCap(Index, Value);
end;

constructor TVectArtLineToolbarControl.CreateForHost(AOwner: TComponent;
  AHost: TWinControl);
begin
  inherited Create(AOwner);
  Parent := AHost;
  Align := alRight;
  Width := 270;
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  FApplicationEvents := TApplicationEvents.Create(Self);
  FApplicationEvents.OnIdle := ApplicationIdle;
  BuildControls;
  Visible := False;
end;

procedure TVectArtLineToolbarControl.ApplicationIdle(Sender: TObject;
  var Done: Boolean);
begin
  UpdateDetailsPanelFocus;
end;

procedure TVectArtLineToolbarControl.UpdateDetailsPanelFocus;
var
  ActiveControl: TWinControl;
  ParentForm: TCustomForm;
begin
  if (FDetailsPanel = nil) or not FDetailsPanel.Visible then Exit;
  ParentForm := GetParentForm(Self);
  if (ParentForm = nil) or (Screen.ActiveForm <> ParentForm) then
  begin
    FDetailsPanel.Visible := False;
    Exit;
  end;
  ActiveControl := ParentForm.ActiveControl;
  if (ActiveControl <> FDetailsButton) and
    not IsDetailsControl(ActiveControl) then
    FDetailsPanel.Visible := False;
end;

procedure TVectArtLineToolbarControl.BuildControls;
var
  Cap: TVectArtLineCap;
  CaptionLabel: TLabel;
  ParentForm: TCustomForm;
begin
  FStrokeWidthTrackBar := THorizontalTrackBarControl.Create(Self);
  FStrokeWidthTrackBar.Parent := Self;
  FStrokeWidthTrackBar.BackgroundColor := COLOR_BACKGROUND;
  FStrokeWidthTrackBar.ChannelColor := TColor($00505050);
  FStrokeWidthTrackBar.FillColor := TColor($00D77800);
  FStrokeWidthTrackBar.ThumbColor := COLOR_EDIT;
  FStrokeWidthTrackBar.ThumbBorderColor := COLOR_TEXT;
  FStrokeWidthTrackBar.ShowTicks := False;
  FStrokeWidthTrackBar.SetRange(STROKE_WIDTH_TRACK_MIN,
    STROKE_WIDTH_TRACK_MAX);
  FStrokeWidthTrackBar.SmallChange := 10;
  FStrokeWidthTrackBar.LargeChange := 100;
  FStrokeWidthTrackBar.OnChange := TrackBarChanged;
  FStrokeWidthTrackBar.OnMouseDown := TrackBarMouseDown;
  FStrokeWidthTrackBar.OnMouseUp := TrackBarMouseUp;

  FStrokeWidthEdit := TEdit.Create(Self);
  FStrokeWidthEdit.Parent := Self;
  FStrokeWidthEdit.Color := COLOR_EDIT;
  FStrokeWidthEdit.Font.Color := COLOR_TEXT;
  FStrokeWidthEdit.Font.Name := 'Segoe UI';
  FStrokeWidthEdit.Font.Height := -12;
  FStrokeWidthEdit.OnExit := EditExit;
  FStrokeWidthEdit.OnKeyDown := EditKeyDown;

  FMifStrokeStyleCombo := TVectArtMifStrokeStyleCombo.Create(Self);
  FMifStrokeStyleCombo.Parent := Self;
  FMifStrokeStyleCombo.Style := csOwnerDrawFixed;
  FMifStrokeStyleCombo.ItemHeight := 22;
  FMifStrokeStyleCombo.DropDownCount := 9;
  FMifStrokeStyleCombo.Color := COLOR_EDIT;
  FMifStrokeStyleCombo.Font.Color := COLOR_TEXT;
  FMifStrokeStyleCombo.Font.Name := 'Segoe UI';
  FMifStrokeStyleCombo.Font.Height := -12;
  FMifStrokeStyleCombo.OnChange := StyleChanged;

  FDetailsButton := TVectArtDarkButton.Create(Self);
  FDetailsButton.Parent := Self;
  FDetailsButton.Caption := UnicodeText([$8A73, $7D30]);
  FDetailsButton.OnClick := DetailsClick;

  ParentForm := GetParentForm(Self);
  FDetailsPanel := TPanel.Create(Self);
  FDetailsPanel.Parent := ParentForm;
  FDetailsPanel.BevelOuter := bvRaised;
  FDetailsPanel.Color := COLOR_BACKGROUND;
  FDetailsPanel.ParentBackground := False;
  FDetailsPanel.SetBounds(0, 0, 420, 96);
  FDetailsPanel.Visible := False;

  // 線幅は即時操作用にツールバーへ残し、低頻度項目だけを詳細へ収容する。
  FMifStrokeStyleCombo.Parent := FDetailsPanel;
  FMifStrokeStyleCombo.SetBounds(78, 8, 260, 25);

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$7A2E, $985E]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -12;
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(12, 13, 40, 20);

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$5148, $7AEF, $5F62, $72B6]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -12;
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(12, 60, 60, 20);

  for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
  begin
    FLineCapButtons[Cap] := TVectArtLineCapButton.Create(Self);
    FLineCapButtons[Cap].Parent := FDetailsPanel;
    FLineCapButtons[Cap].LineCap := Cap;
    FLineCapButtons[Cap].SetBounds(78 + Ord(Cap) * 46, 51, 40, 34);
    FLineCapButtons[Cap].OnClick := LineCapClick;
    FLineCapButtons[Cap].ShowHint := True;
  end;
  FLineCapButtons[vlcSquare].Hint := UnicodeText([$89D2, $578B]);
  FLineCapButtons[vlcRound].Hint := UnicodeText([$4E38, $578B]);
  FLineCapButtons[vlcTriangle].Hint := UnicodeText([$4E09, $89D2, $578B]);
  FLineCapButtons[vlcSquare].Selected := True;

end;

procedure TVectArtLineToolbarControl.ApplyLineCap(Value: TVectArtLineCap);
var
  Command: TVectArtCompoundCommand;
  Color: TColor;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
  OldLineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if FUpdating then
    Exit;
  Indices := SelectedLineIndices;
  if (Length(Indices) > 0) and SelectionHasLockedLine then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if (Length(Indices) > 0) and (FEditHistory <> nil) then
      Command := TVectArtCompoundCommand.Create;
    if FDocument <> nil then
      FDocument.BeginUpdate;
    try
      for I := 0 to High(Indices) do
      begin
        Layer := FDocument[Indices[I]];
        if Layer is TScreenLayoutRectangleLineLayer then
          Continue;
        ReadLineLayer(Layer, Color, Width, Style, OldLineCap);
        if OldLineCap = Value then
          Continue;
        if Command <> nil then
          Command.Add(TVectArtPathLineCapCommand.Create(FDocument, Indices[I],
            OldLineCap, Value));
        SetLineLayerCap(FDocument, Indices[I], Value);
      end;
    finally
      if FDocument <> nil then
        FDocument.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
    if FEditorState <> nil then
      FEditorState.LineCap := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyMifStrokeStyle(
  Value: TVectArtMifStrokeStyle);
var
  Command: TVectArtCompoundCommand;
  Color: TColor;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
  LineCap: TVectArtLineCap;
  OldStyle: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if FUpdating then
    Exit;
  Indices := SelectedLineIndices;
  if (Length(Indices) > 0) and SelectionHasLockedLine then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if (Length(Indices) > 0) and (FEditHistory <> nil) then
      Command := TVectArtCompoundCommand.Create;
    for I := 0 to High(Indices) do
    begin
      Layer := FDocument[Indices[I]];
      ReadLineLayer(Layer, Color, Width, OldStyle, LineCap);
      if OldStyle = Value then
        Continue;
      if Command <> nil then
        Command.Add(TVectArtStrokeCommand.Create(FDocument, Indices[I],
          Color, Width, OldStyle, Color, Width, Value));
      SetLineLayerStroke(FDocument, Indices[I], Color, Width, Value);
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
    if FEditorState <> nil then
      FEditorState.LineMifStrokeStyle := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyStrokeWidth(Value: Single);
begin
  ApplyStrokeWidthInternal(Value, True);
end;

procedure TVectArtLineToolbarControl.ApplyStrokeWidthInternal(Value: Single;
  RecordHistory: Boolean);
var
  Command: TVectArtCompoundCommand;
  Color: TColor;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if FUpdating then
    Exit;
  Value := Max(Value, 0.1);
  Indices := SelectedLineIndices;
  if (Length(Indices) > 0) and SelectionHasLockedLine then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if RecordHistory and (Length(Indices) > 0) and
      (FEditHistory <> nil) then
      Command := TVectArtCompoundCommand.Create;
    if FDocument <> nil then
      FDocument.BeginUpdate;
    try
      for I := 0 to High(Indices) do
      begin
        Layer := FDocument[Indices[I]];
        ReadLineLayer(Layer, Color, Width, Style, LineCap);
        if SameValue(Width, Value) then
          Continue;
        if Command <> nil then
          Command.Add(TVectArtStrokeCommand.Create(FDocument, Indices[I],
            Color, Width, Style, Color, Value, Style));
        SetLineLayerStroke(FDocument, Indices[I], Color, Value, Style);
      end;
    finally
      if FDocument <> nil then
        FDocument.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
    if (FEditorState <> nil) and
      (RecordHistory or (Length(Indices) = 0)) then
      FEditorState.LineStrokeWidth := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.CommitTrackGesture;
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  FinalWidth: Single;
  HasFinalWidth: Boolean;
  I: Integer;
  Index: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if not FTrackGestureActive then
    Exit;
  FinalWidth := 0;
  FTrackGestureActive := False;
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  if Command <> nil then
    for I := 0 to Min(High(FTrackStartIndices),
      High(FTrackStartWidths)) do
    begin
      Index := FTrackStartIndices[I];
      if (FDocument = nil) or not InRange(Index, 0,
        FDocument.LayerCount - 1) or
        not ((FDocument[Index] is TScreenLayoutRectangleLineLayer) or
          (FDocument[Index] is TScreenLayoutArcLayer) or
          ((FDocument[Index] is TVectArtPathLayer) and
           not TVectArtPathLayer(FDocument[Index]).Closed)) then
        Continue;
      Layer := FDocument[Index];
      ReadLineLayer(Layer, Color, Width, Style, LineCap);
      if SameValue(FTrackStartWidths[I], Width) then
        Continue;
      Command.Add(TVectArtStrokeCommand.Create(FDocument, Index,
        Color, FTrackStartWidths[I], Style, Color, Width, Style));
    end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  Indices := SelectedLineIndices;
  HasFinalWidth := (FDocument <> nil) and (Length(Indices) > 0);
  if HasFinalWidth then
    ReadLineLayer(FDocument[Indices[0]], Color, FinalWidth, Style, LineCap);
  FTrackStartIndices := nil;
  FTrackStartWidths := nil;
  if FTrackDocumentUpdateActive then
  begin
    FTrackDocumentUpdateActive := False;
    FDocument.EndInteractiveUpdate;
  end;
  if (FEditorState <> nil) and HasFinalWidth then
    FEditorState.LineStrokeWidth := FinalWidth;
end;

procedure TVectArtLineToolbarControl.EditExit(Sender: TObject);
var
  Value: Single;
begin
  if FUpdating then
    Exit;
  if TryStrToFloat(Trim(FStrokeWidthEdit.Text), Value) and (Value > 0) then
    ApplyStrokeWidth(Value)
  else
    RefreshState;
end;

procedure TVectArtLineToolbarControl.EditKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    EditExit(Sender);
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    RefreshState;
    Key := 0;
  end;
end;

procedure TVectArtLineToolbarControl.DetailsClick(Sender: TObject);
var
  Position: TPoint;
begin
  if (FDetailsPanel = nil) or (FDetailsPanel.Parent = nil) then
    Exit;
  if FDetailsPanel.Visible then
  begin
    FDetailsPanel.Visible := False;
    Exit;
  end;
  Position := FDetailsButton.ClientToScreen(Point(FDetailsButton.Width -
    FDetailsPanel.Width, FDetailsButton.Height + 2));
  Position := FDetailsPanel.Parent.ScreenToClient(Position);
  FDetailsPanel.SetBounds(Position.X, Position.Y, FDetailsPanel.Width,
    FDetailsPanel.Height);
  FDetailsPanel.BringToFront;
  FDetailsPanel.Visible := True;
end;

function TVectArtLineToolbarControl.IsDetailsControl(
  Control: TControl): Boolean;
begin
  Result := False;
  while Control <> nil do
  begin
    if Control = FDetailsPanel then Exit(True);
    Control := Control.Parent;
  end;
end;

procedure TVectArtLineToolbarControl.LineCapClick(Sender: TObject);
begin
  if FUpdating or not (Sender is TVectArtLineCapButton) then
    Exit;
  ApplyLineCap(TVectArtLineCapButton(Sender).LineCap);
end;

function TVectArtLineToolbarControl.LineCapButton(
  Value: TVectArtLineCap): TVectArtLineCapButton;
begin
  Result := FLineCapButtons[Value];
end;

procedure TVectArtLineToolbarControl.Paint;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -12;
  Canvas.Font.Color := COLOR_TEXT;
  Canvas.TextOut(8, 13, UnicodeText([$592A, $3055]));
end;

procedure TVectArtLineToolbarControl.RefreshState;
var
  Color: TColor;
  CommonStyle: Boolean;
  CommonLineCap: Boolean;
  CommonWidth: Boolean;
  Cap: TVectArtLineCap;
  CurrentLineCap: TVectArtLineCap;
  CurrentStyle: TVectArtMifStrokeStyle;
  CurrentWidth: Single;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLayer;
  LineCapValue: TVectArtLineCap;
  Locked: Boolean;
  StyleValue: TVectArtMifStrokeStyle;
  SupportsLineCap: Boolean;
  WidthValue: Single;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    Indices := SelectedLineIndices;
    if Length(Indices) > 0 then
    begin
      Visible := True;
      if Length(Indices) = 1 then
        if FDocument[Indices[0]] is TScreenLayoutEllipseLineLayer then
          FContextText := 'Selected Ellipse Line'
        else if FDocument[Indices[0]] is
          TScreenLayoutRoundedRectangleLineLayer then
          FContextText := 'Selected Rounded Rectangle Line'
        else if FDocument[Indices[0]] is TScreenLayoutRectangleLineLayer then
          FContextText := 'Selected Rectangle Line'
        else if FDocument[Indices[0]] is TScreenLayoutArcLayer then
          FContextText := 'Selected Arc'
        else
          FContextText := 'Selected Line'
      else
        FContextText := Format('%d Lines', [Length(Indices)]);
      Layer := FDocument[Indices[0]];
      ReadLineLayer(Layer, Color, WidthValue, StyleValue, LineCapValue);
      CommonWidth := True;
      CommonStyle := True;
      CommonLineCap := True;
      SupportsLineCap := not (Layer is TScreenLayoutRectangleLineLayer);
      for I := 1 to High(Indices) do
      begin
        Layer := FDocument[Indices[I]];
        SupportsLineCap := SupportsLineCap and
          not (Layer is TScreenLayoutRectangleLineLayer);
        ReadLineLayer(Layer, Color, CurrentWidth, CurrentStyle,
          CurrentLineCap);
        CommonWidth := CommonWidth and SameValue(CurrentWidth, WidthValue);
        CommonStyle := CommonStyle and (CurrentStyle = StyleValue);
        CommonLineCap := CommonLineCap and
          (CurrentLineCap = LineCapValue);
      end;
      if CommonWidth then
      begin
        FStrokeWidthEdit.Text := FormatFloat('0.##', WidthValue)
      end
      else
        FStrokeWidthEdit.Text := '';
      FStrokeWidthTrackBar.Position := EnsureRange(
        Round(WidthValue * STROKE_WIDTH_SCALE), STROKE_WIDTH_TRACK_MIN,
        STROKE_WIDTH_TRACK_MAX);
      if CommonStyle then
        FMifStrokeStyleCombo.SetPendingItemIndex(Ord(StyleValue))
      else
        FMifStrokeStyleCombo.SetPendingItemIndex(-1);
      if CommonLineCap then
        for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
          FLineCapButtons[Cap].Selected := Cap = LineCapValue
      else
        for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
          FLineCapButtons[Cap].Selected := False;
      Locked := SelectionHasLockedLine;
      FStrokeWidthEdit.Enabled := not Locked;
      FStrokeWidthTrackBar.Enabled := not Locked;
      FMifStrokeStyleCombo.Enabled := not Locked;
      for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
        FLineCapButtons[Cap].Enabled := not Locked and SupportsLineCap;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 0) and
      (FEditorState <> nil) and
      (FEditorState.CurrentTool in [vetRectangleLine,
        vetRoundedRectangleLine, vetArc, vetLine,
        vetEllipseLine,
        vetPath]) then
    begin
      Visible := True;
      if FEditorState.CurrentTool = vetPath then
        FContextText := 'Next Path'
      else if FEditorState.CurrentTool = vetRectangleLine then
        FContextText := 'Next Rectangle Line'
      else if FEditorState.CurrentTool = vetRoundedRectangleLine then
        FContextText := 'Next Rounded Rectangle Line'
      else if FEditorState.CurrentTool = vetEllipseLine then
        FContextText := 'Next Ellipse Line'
      else if FEditorState.CurrentTool = vetArc then
        FContextText := 'Next Arc'
      else
        FContextText := 'Next Line';
      FStrokeWidthEdit.Text := FormatFloat('0.##',
        FEditorState.LineStrokeWidth);
      FStrokeWidthTrackBar.Position := EnsureRange(
        Round(FEditorState.LineStrokeWidth * STROKE_WIDTH_SCALE),
        STROKE_WIDTH_TRACK_MIN, STROKE_WIDTH_TRACK_MAX);
      FMifStrokeStyleCombo.SetPendingItemIndex(
        Ord(FEditorState.LineMifStrokeStyle));
      for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
      begin
        FLineCapButtons[Cap].Selected := Cap = FEditorState.LineCap;
        FLineCapButtons[Cap].Enabled :=
          not (FEditorState.CurrentTool in [vetRectangleLine,
            vetRoundedRectangleLine, vetEllipseLine]);
      end;
      FStrokeWidthEdit.Enabled := True;
      FStrokeWidthTrackBar.Enabled := True;
      FMifStrokeStyleCombo.Enabled := True;
    end
    else
    begin
      Visible := False;
      FDetailsPanel.Visible := False;
    end;
  finally
    FUpdating := False;
  end;
  Invalidate;
end;

procedure TVectArtLineToolbarControl.Resize;
var
  TrackWidth: Integer;
begin
  inherited Resize;
  TrackWidth := Max(Width - 176, 60);
  if FStrokeWidthTrackBar <> nil then
    FStrokeWidthTrackBar.SetBounds(40, 4, TrackWidth, 34);
  if FStrokeWidthEdit <> nil then
    FStrokeWidthEdit.SetBounds(Width - 128, 8, 48, 25);
  if FDetailsButton <> nil then
    FDetailsButton.SetBounds(Width - 70, 8, 60, 25);
end;

function TVectArtLineToolbarControl.SelectedLineIndices: TArray<Integer>;
var
  I: Integer;
  Selection: TArray<Integer>;
begin
  Result := nil;
  if (FDocument = nil) or (FDocument.SelectionCount = 0) then
    Exit;
  Selection := FDocument.GetSelectedLayerIndices;
  for I := 0 to High(Selection) do
    if not ((FDocument[Selection[I]] is TScreenLayoutRectangleLineLayer) or
      (FDocument[Selection[I]] is TScreenLayoutArcLayer) or
      ((FDocument[Selection[I]] is TVectArtPathLayer) and
       not TVectArtPathLayer(FDocument[Selection[I]]).Closed)) then
      Exit;
  Result := Selection;
end;

function TVectArtLineToolbarControl.SelectionHasLockedLine: Boolean;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := False;
  Indices := SelectedLineIndices;
  for I := 0 to High(Indices) do
    if FDocument[Indices[I]].Locked then
      Exit(True);
end;

procedure TVectArtLineToolbarControl.StyleChanged(Sender: TObject);
begin
  if FUpdating or not InRange(FMifStrokeStyleCombo.ItemIndex,
    Ord(Low(TVectArtMifStrokeStyle)), Ord(High(TVectArtMifStrokeStyle))) then
    Exit;
  ApplyMifStrokeStyle(TVectArtMifStrokeStyle(FMifStrokeStyleCombo.ItemIndex));
end;

procedure TVectArtLineToolbarControl.TrackBarChanged(Sender: TObject);
begin
  if FUpdating then
    Exit;
  ApplyStrokeWidthInternal(FStrokeWidthTrackBar.Position /
    STROKE_WIDTH_SCALE, not FTrackGestureActive);
end;

procedure TVectArtLineToolbarControl.TrackBarMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Color: TColor;
  I: Integer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
begin
  if FUpdating or (Button <> mbLeft) or not FStrokeWidthTrackBar.Enabled then
    Exit;
  FTrackGestureActive := True;
  FTrackStartIndices := SelectedLineIndices;
  SetLength(FTrackStartWidths, Length(FTrackStartIndices));
  for I := 0 to High(FTrackStartIndices) do
    ReadLineLayer(FDocument[FTrackStartIndices[I]], Color,
      FTrackStartWidths[I], Style, LineCap);
  if (Length(FTrackStartIndices) > 0) and (FDocument <> nil) then
  begin
    FDocument.BeginInteractiveUpdate;
    FTrackDocumentUpdateActive := True;
  end;
end;

procedure TVectArtLineToolbarControl.TrackBarMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    CommitTrackGesture;
end;

end.
