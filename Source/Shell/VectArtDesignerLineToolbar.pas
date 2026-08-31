// Lineの作成初期値と選択中Lineの装飾を詳細パネルから編集し、Documentと履歴へ同期する。
unit VectArtDesignerLineToolbar;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.StdCtrls, Vcl.AppEvnts,
  HorizontalTrackBarControl, VectArtDesignerDocument, VectArtDesignerEditHistory,
  VectArtDesignerEditorState, VectArtDesignerLineStyleControls,
  VectArtDesignerStrokeStyleCombo;

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
    FLineJoinButtons: array[TVectArtLineJoin] of TVectArtLineJoinButton;
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
    procedure LineJoinClick(Sender: TObject);
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
    // 作成初期値または選択中の全Lineへ接合形式を適用する。
    procedure ApplyLineJoin(Value: TVectArtLineJoin);
    // 作成初期値または選択中の全Lineへ線種を適用する。
    procedure ApplyMifStrokeStyle(Value: TVectArtMifStrokeStyle);
    // 作成初期値または選択中の全Lineへ線幅を適用する。
    procedure ApplyStrokeWidth(Value: Single);
    // EditorStateと現在選択から表示値、混在状態、有効状態を再同期する。
    procedure RefreshState;
    // 詳細パネル外へフォーカスが移っていればパネルを閉じる。
    procedure UpdateDetailsPanelFocus;
    property Document: TVectArtDocument read FDocument write FDocument;
    // 指定した線端形状の選択ボタンを返す。戻り値の所有権はSelfが保持する。
    function LineCapButton(Value: TVectArtLineCap): TVectArtLineCapButton;
    // 指定した接合形式の選択ボタンを返す。戻り値の所有権はSelfが保持する。
    function LineJoinButton(Value: TVectArtLineJoin): TVectArtLineJoinButton;
    property DetailsButton: TVectArtDarkButton read FDetailsButton;
    property DetailsPanel: TPanel read FDetailsPanel;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write FEditorState;
    property MifStrokeStyleCombo: TVectArtMifStrokeStyleCombo
      read FMifStrokeStyleCombo;
    property StrokeWidthTrackBar: THorizontalTrackBarControl
      read FStrokeWidthTrackBar;
    property StrokeWidthEdit: TEdit read FStrokeWidthEdit;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, Vcl.Forms, Vcl.Graphics,
  VectArtDesignerEditCommands;

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

constructor TVectArtLineToolbarControl.CreateForHost(AOwner: TComponent;
  AHost: TWinControl);
begin
  inherited Create(AOwner);
  Parent := AHost;
  Align := alRight;
  Width := 230;
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
  Join: TVectArtLineJoin;
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
  FDetailsPanel.SetBounds(0, 0, 420, 180);
  FDetailsPanel.Visible := False;

  FStrokeWidthTrackBar.Parent := FDetailsPanel;
  FStrokeWidthTrackBar.SetBounds(78, 3, 190, 34);
  FStrokeWidthEdit.Parent := FDetailsPanel;
  FStrokeWidthEdit.SetBounds(278, 8, 60, 25);
  FMifStrokeStyleCombo.Parent := FDetailsPanel;
  FMifStrokeStyleCombo.SetBounds(78, 47, 260, 25);

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$592A, $3055]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -12;
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(12, 13, 40, 20);

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$7A2E, $985E]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -12;
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(12, 52, 40, 20);

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$5148, $7AEF, $5F62, $72B6]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -12;
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(12, 101, 60, 20);

  for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
  begin
    FLineCapButtons[Cap] := TVectArtLineCapButton.Create(Self);
    FLineCapButtons[Cap].Parent := FDetailsPanel;
    FLineCapButtons[Cap].LineCap := Cap;
    FLineCapButtons[Cap].SetBounds(78 + Ord(Cap) * 46, 93, 40, 34);
    FLineCapButtons[Cap].OnClick := LineCapClick;
    FLineCapButtons[Cap].ShowHint := True;
  end;
  FLineCapButtons[vlcButt].Hint := UnicodeText([$5E73, $578B]);
  FLineCapButtons[vlcSquare].Hint := UnicodeText([$89D2, $578B]);
  FLineCapButtons[vlcRound].Hint := UnicodeText([$4E38, $578B]);
  FLineCapButtons[vlcButt].Selected := True;

  CaptionLabel := TLabel.Create(Self);
  CaptionLabel.Parent := FDetailsPanel;
  CaptionLabel.Caption := UnicodeText([$63A5, $5408, $5F62, $5F0F]);
  CaptionLabel.Font.Name := 'Segoe UI';
  CaptionLabel.Font.Height := -12;
  CaptionLabel.Font.Color := COLOR_LABEL;
  CaptionLabel.SetBounds(12, 146, 60, 20);

  for Join := Low(TVectArtLineJoin) to High(TVectArtLineJoin) do
  begin
    FLineJoinButtons[Join] := TVectArtLineJoinButton.Create(Self);
    FLineJoinButtons[Join].Parent := FDetailsPanel;
    FLineJoinButtons[Join].LineJoin := Join;
    FLineJoinButtons[Join].SetBounds(78 + Ord(Join) * 46, 135, 40, 34);
    FLineJoinButtons[Join].OnClick := LineJoinClick;
    FLineJoinButtons[Join].ShowHint := True;
  end;
  FLineJoinButtons[vljMiter].Hint := 'Miter';
  FLineJoinButtons[vljBevel].Hint := 'Bevel';
  FLineJoinButtons[vljRound].Hint := 'Round';
  FLineJoinButtons[vljMiter].Selected := True;

end;

procedure TVectArtLineToolbarControl.ApplyLineCap(Value: TVectArtLineCap);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLineLayer;
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
        Layer := TVectArtLineLayer(FDocument[Indices[I]]);
        if Layer.LineCap = Value then
          Continue;
        if Command <> nil then
          Command.Add(TVectArtLineCapCommand.Create(FDocument, Indices[I],
            Layer.LineCap, Value));
        FDocument.SetLineCap(Indices[I], Value);
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

procedure TVectArtLineToolbarControl.ApplyLineJoin(Value: TVectArtLineJoin);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLineLayer;
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
        Layer := TVectArtLineLayer(FDocument[Indices[I]]);
        if Layer.LineJoin = Value then
          Continue;
        if Command <> nil then
          Command.Add(TVectArtLineJoinCommand.Create(FDocument, Indices[I],
            Layer.LineJoin, Value));
        FDocument.SetLineJoin(Indices[I], Value);
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
      FEditorState.LineJoin := Value;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyMifStrokeStyle(
  Value: TVectArtMifStrokeStyle);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLineLayer;
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
      Layer := TVectArtLineLayer(FDocument[Indices[I]]);
      if Layer.MifStrokeStyle = Value then
        Continue;
      if Command <> nil then
        Command.Add(TVectArtStrokeCommand.Create(FDocument, Indices[I],
          Layer.StrokeColor, Layer.StrokeWidth, Layer.MifStrokeStyle,
          Layer.StrokeColor, Layer.StrokeWidth, Value));
      FDocument.SetLineStroke(Indices[I], Layer.StrokeColor,
        Layer.StrokeWidth, Value);
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
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLineLayer;
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
        Layer := TVectArtLineLayer(FDocument[Indices[I]]);
        if SameValue(Layer.StrokeWidth, Value) then
          Continue;
        if Command <> nil then
          Command.Add(TVectArtStrokeCommand.Create(FDocument, Indices[I],
            Layer.StrokeColor, Layer.StrokeWidth, Layer.MifStrokeStyle,
            Layer.StrokeColor, Value, Layer.MifStrokeStyle));
        FDocument.SetLineStroke(Indices[I], Layer.StrokeColor, Value,
          Layer.MifStrokeStyle);
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
  Command: TVectArtCompoundCommand;
  FinalWidth: Single;
  HasFinalWidth: Boolean;
  I: Integer;
  Index: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLineLayer;
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
        not (FDocument[Index] is TVectArtLineLayer) then
        Continue;
      Layer := TVectArtLineLayer(FDocument[Index]);
      if SameValue(FTrackStartWidths[I], Layer.StrokeWidth) then
        Continue;
      Command.Add(TVectArtStrokeCommand.Create(FDocument, Index,
        Layer.StrokeColor, FTrackStartWidths[I], Layer.MifStrokeStyle,
        Layer.StrokeColor, Layer.StrokeWidth, Layer.MifStrokeStyle));
    end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  Indices := SelectedLineIndices;
  HasFinalWidth := (FDocument <> nil) and (Length(Indices) > 0);
  if HasFinalWidth then
    FinalWidth := TVectArtLineLayer(FDocument[Indices[0]]).StrokeWidth;
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

procedure TVectArtLineToolbarControl.LineJoinClick(Sender: TObject);
begin
  if FUpdating or not (Sender is TVectArtLineJoinButton) then
    Exit;
  ApplyLineJoin(TVectArtLineJoinButton(Sender).LineJoin);
end;

function TVectArtLineToolbarControl.LineCapButton(
  Value: TVectArtLineCap): TVectArtLineCapButton;
begin
  Result := FLineCapButtons[Value];
end;

function TVectArtLineToolbarControl.LineJoinButton(
  Value: TVectArtLineJoin): TVectArtLineJoinButton;
begin
  Result := FLineJoinButtons[Value];
end;

procedure TVectArtLineToolbarControl.Paint;
begin
  Canvas.Brush.Color := COLOR_BACKGROUND;
  Canvas.FillRect(ClientRect);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Height := -12;
  Canvas.Font.Color := COLOR_TEXT;
  Canvas.TextOut(10, 13, FContextText);
end;

procedure TVectArtLineToolbarControl.RefreshState;
var
  CommonStyle: Boolean;
  CommonLineCap: Boolean;
  CommonLineJoin: Boolean;
  CommonWidth: Boolean;
  Cap: TVectArtLineCap;
  I: Integer;
  Indices: TArray<Integer>;
  Layer: TVectArtLineLayer;
  LineCapValue: TVectArtLineCap;
  LineJoinValue: TVectArtLineJoin;
  Join: TVectArtLineJoin;
  Locked: Boolean;
  StyleValue: TVectArtMifStrokeStyle;
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
        FContextText := 'Selected Line'
      else
        FContextText := Format('%d Lines', [Length(Indices)]);
      Layer := TVectArtLineLayer(FDocument[Indices[0]]);
      WidthValue := Layer.StrokeWidth;
      LineCapValue := Layer.LineCap;
      LineJoinValue := Layer.LineJoin;
      StyleValue := Layer.MifStrokeStyle;
      CommonWidth := True;
      CommonStyle := True;
      CommonLineCap := True;
      CommonLineJoin := True;
      for I := 1 to High(Indices) do
      begin
        Layer := TVectArtLineLayer(FDocument[Indices[I]]);
        CommonWidth := CommonWidth and SameValue(Layer.StrokeWidth,
          WidthValue);
        CommonStyle := CommonStyle and (Layer.MifStrokeStyle = StyleValue);
        CommonLineCap := CommonLineCap and
          (Layer.LineCap = LineCapValue);
        CommonLineJoin := CommonLineJoin and
          (Layer.LineJoin = LineJoinValue);
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
      if CommonLineJoin then
        for Join := Low(TVectArtLineJoin) to High(TVectArtLineJoin) do
          FLineJoinButtons[Join].Selected := Join = LineJoinValue
      else
        for Join := Low(TVectArtLineJoin) to High(TVectArtLineJoin) do
          FLineJoinButtons[Join].Selected := False;
      Locked := SelectionHasLockedLine;
      FStrokeWidthEdit.Enabled := not Locked;
      FStrokeWidthTrackBar.Enabled := not Locked;
      FMifStrokeStyleCombo.Enabled := not Locked;
      for Cap := Low(TVectArtLineCap) to High(TVectArtLineCap) do
        FLineCapButtons[Cap].Enabled := not Locked;
      for Join := Low(TVectArtLineJoin) to High(TVectArtLineJoin) do
        FLineJoinButtons[Join].Enabled := not Locked;
    end
    else if (FDocument <> nil) and (FDocument.SelectionCount = 0) and
      (FEditorState <> nil) and (FEditorState.CurrentTool = vetLine) then
    begin
      Visible := True;
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
        FLineCapButtons[Cap].Enabled := True;
      end;
      for Join := Low(TVectArtLineJoin) to High(TVectArtLineJoin) do
      begin
        FLineJoinButtons[Join].Selected := Join = FEditorState.LineJoin;
        FLineJoinButtons[Join].Enabled := True;
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
begin
  inherited Resize;
  if FDetailsButton <> nil then
    FDetailsButton.SetBounds(Width - 82, 8, 72, 25);
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
    if not (FDocument[Selection[I]] is TVectArtLineLayer) then
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
  I: Integer;
begin
  if FUpdating or (Button <> mbLeft) or not FStrokeWidthTrackBar.Enabled then
    Exit;
  FTrackGestureActive := True;
  FTrackStartIndices := SelectedLineIndices;
  SetLength(FTrackStartWidths, Length(FTrackStartIndices));
  for I := 0 to High(FTrackStartIndices) do
    FTrackStartWidths[I] := TVectArtLineLayer(
      FDocument[FTrackStartIndices[I]]).StrokeWidth;
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
