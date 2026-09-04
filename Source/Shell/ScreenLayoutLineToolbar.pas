// 選択種別に応じて線幅または文字フォントを常設し、Documentと履歴へ同期する。
unit ScreenLayoutLineToolbar;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.StdCtrls, Vcl.AppEvnts, Vcl.Graphics,
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
    FFontFamilyCombo: TComboBox;
    FFontStyleButtons: array[TFontStyle] of TScreenLayoutTextStyleButton;
    FTextAlignmentButton: TScreenLayoutTextAlignmentButton;
    FTextAlignmentButtons: array[TScreenLayoutTextAlignment] of
      TScreenLayoutTextAlignmentButton;
    FTextAlignmentPanel: TPanel;
    FTextPathAttachmentButton: TScreenLayoutTextPathAttachmentButton;
    FTextPathAttachmentButtons: array[TScreenLayoutTextPathAttachment] of
      TScreenLayoutTextPathAttachmentButton;
    FTextPathAttachmentPanel: TPanel;
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
    procedure FontFamilyChanged(Sender: TObject);
    procedure FontStyleClick(Sender: TObject);
    procedure TextAlignmentClick(Sender: TObject);
    procedure TextAlignmentPopupClick(Sender: TObject);
    procedure TextPathAttachmentClick(Sender: TObject);
    procedure TextPathAttachmentPopupClick(Sender: TObject);
    procedure DetailsClick(Sender: TObject);
    function IsTextAlignmentControl(Control: TControl): Boolean;
    function IsTextPathAttachmentControl(Control: TControl): Boolean;
    function IsDetailsControl(Control: TControl): Boolean;
    procedure LineCapClick(Sender: TObject);
    function SelectedLineIndices: TArray<Integer>;
    function SelectedTextIndices: TArray<Integer>;
    function SelectedTextPathIndices: TArray<Integer>;
    function SelectionHasLockedLine: Boolean;
    function SelectionHasLockedText: Boolean;
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
    // 選択中の全Textへフォントファミリーを適用する。
    procedure ApplyFontFamily(const Value: string);
    // 選択中の全Textへ1種類の文字装飾を追加または削除する。
    procedure ApplyFontStyle(Style: TFontStyle; Enabled: Boolean);
    // 選択中の全Textへ枠内配置を適用する。
    procedure ApplyTextAlignment(Value: TScreenLayoutTextAlignment);
    // 選択中の全文字パスへPathに接触させる文字セル面を適用する。
    procedure ApplyTextPathAttachment(
      Value: TScreenLayoutTextPathAttachment);
    // 選択中の全Textへ文字サイズ比率の字間または行間を適用する。
    procedure ApplyTextSpacing(IsLetterSpacing: Boolean; Ratio: Single);
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
    // Text選択時に線幅UIと入れ替えて表示するフォント一覧。
    property FontFamilyCombo: TComboBox read FFontFamilyCombo;
    function FontStyleButton(Style: TFontStyle): TScreenLayoutTextStyleButton;
    property TextAlignmentButton: TScreenLayoutTextAlignmentButton
      read FTextAlignmentButton;
    property TextAlignmentPanel: TPanel read FTextAlignmentPanel;
    function TextAlignmentCell(Value: TScreenLayoutTextAlignment):
      TScreenLayoutTextAlignmentButton;
    property TextPathAttachmentButton: TScreenLayoutTextPathAttachmentButton
      read FTextPathAttachmentButton;
    property TextPathAttachmentPanel: TPanel read FTextPathAttachmentPanel;
    function TextPathAttachmentCell(Value: TScreenLayoutTextPathAttachment):
      TScreenLayoutTextPathAttachmentButton;
    // 線幅の常設UI。所有権はToolbarが保持する。
    property StrokeWidthTrackBar: THorizontalTrackBarControl
      read FStrokeWidthTrackBar;
    property StrokeWidthEdit: TEdit read FStrokeWidthEdit;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, Vcl.Forms,
  ScreenLayoutEditCommands, ScreenLayoutTextCommands;

const
  COLOR_BACKGROUND = TColor($00282828);
  COLOR_EDIT = TColor($00353535);
  COLOR_LABEL = TColor($00C8C8C8);
  COLOR_TEXT = TColor($00EEEEEE);
  STROKE_WIDTH_SCALE = 10;
  STROKE_WIDTH_TRACK_MIN = 10;
  STROKE_WIDTH_TRACK_MAX = 1000;
  LINE_TOOLBAR_WIDTH = 270;
  TEXT_TOOLBAR_WIDTH = 420;

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
  Width := LINE_TOOLBAR_WIDTH;
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
var
  ActiveControl: TWinControl;
  ParentForm: TCustomForm;
begin
  UpdateDetailsPanelFocus;
  ParentForm := GetParentForm(Self);
  if (FTextAlignmentPanel <> nil) and FTextAlignmentPanel.Visible then
  begin
    if (ParentForm = nil) or (Screen.ActiveForm <> ParentForm) then
      FTextAlignmentPanel.Visible := False
    else
    begin
      ActiveControl := ParentForm.ActiveControl;
      if (ActiveControl <> FTextAlignmentButton) and
        not IsTextAlignmentControl(ActiveControl) then
        FTextAlignmentPanel.Visible := False;
    end;
  end;
  if (FTextPathAttachmentPanel <> nil) and
    FTextPathAttachmentPanel.Visible then
  begin
    if (ParentForm = nil) or (Screen.ActiveForm <> ParentForm) then
      FTextPathAttachmentPanel.Visible := False
    else
    begin
      ActiveControl := ParentForm.ActiveControl;
      if (ActiveControl <> FTextPathAttachmentButton) and
        not IsTextPathAttachmentControl(ActiveControl) then
        FTextPathAttachmentPanel.Visible := False;
    end;
  end;
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
  Attachment: TScreenLayoutTextPathAttachment;
  Cap: TVectArtLineCap;
  CaptionLabel: TLabel;
  ParentForm: TCustomForm;
  Style: TFontStyle;
  TextAlignment: TScreenLayoutTextAlignment;
begin
  FFontFamilyCombo := TComboBox.Create(Self);
  FFontFamilyCombo.Parent := Self;
  FFontFamilyCombo.Style := csDropDownList;
  FFontFamilyCombo.DropDownCount := 20;
  FFontFamilyCombo.Color := COLOR_EDIT;
  FFontFamilyCombo.Font.Color := COLOR_TEXT;
  FFontFamilyCombo.Font.Name := 'Segoe UI';
  FFontFamilyCombo.Font.Height := -12;
  FFontFamilyCombo.Items.Assign(Screen.Fonts);
  FFontFamilyCombo.Sorted := True;
  FFontFamilyCombo.OnChange := FontFamilyChanged;
  FFontFamilyCombo.Visible := False;
  for Style := Low(TFontStyle) to High(TFontStyle) do
  begin
    FFontStyleButtons[Style] := TScreenLayoutTextStyleButton.Create(Self);
    FFontStyleButtons[Style].Parent := Self;
    FFontStyleButtons[Style].Style := Style;
    FFontStyleButtons[Style].Font.Style := [Style];
    FFontStyleButtons[Style].OnClick := FontStyleClick;
    FFontStyleButtons[Style].Visible := False;
  end;
  FFontStyleButtons[fsBold].Caption := 'B';
  FFontStyleButtons[fsItalic].Caption := 'I';
  FFontStyleButtons[fsUnderline].Caption := 'U';
  FFontStyleButtons[fsStrikeOut].Caption := 'S';

  FTextAlignmentButton := TScreenLayoutTextAlignmentButton.Create(Self);
  FTextAlignmentButton.Parent := Self;
  FTextAlignmentButton.OnClick := TextAlignmentPopupClick;
  FTextAlignmentButton.ShowHint := True;
  FTextAlignmentButton.Hint := UnicodeText([$914D, $7F6E]);
  FTextAlignmentButton.Visible := False;

  FTextPathAttachmentButton :=
    TScreenLayoutTextPathAttachmentButton.Create(Self);
  FTextPathAttachmentButton.Parent := Self;
  FTextPathAttachmentButton.OnClick := TextPathAttachmentPopupClick;
  FTextPathAttachmentButton.ShowHint := True;
  FTextPathAttachmentButton.Hint := UnicodeText(
    [$30D1, $30B9, $3078, $63A5, $89E6, $3059, $308B, $9762]);
  FTextPathAttachmentButton.Visible := False;

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

  FTextAlignmentPanel := TPanel.Create(Self);
  FTextAlignmentPanel.Parent := ParentForm;
  FTextAlignmentPanel.BevelOuter := bvRaised;
  FTextAlignmentPanel.Color := COLOR_BACKGROUND;
  FTextAlignmentPanel.ParentBackground := False;
  FTextAlignmentPanel.SetBounds(0, 0, 112, 106);
  FTextAlignmentPanel.Visible := False;
  for TextAlignment := Low(TScreenLayoutTextAlignment) to
    High(TScreenLayoutTextAlignment) do
  begin
    FTextAlignmentButtons[TextAlignment] :=
      TScreenLayoutTextAlignmentButton.Create(Self);
    FTextAlignmentButtons[TextAlignment].Parent := FTextAlignmentPanel;
    FTextAlignmentButtons[TextAlignment].Alignment := TextAlignment;
    FTextAlignmentButtons[TextAlignment].SetBounds(
      5 + (Ord(TextAlignment) mod 3) * 35,
      5 + (Ord(TextAlignment) div 3) * 32, 32, 29);
    FTextAlignmentButtons[TextAlignment].OnClick := TextAlignmentClick;
    // 全体枠フィット中は上下方向の余白がないため、中段の左右配置だけを操作可能にする。
    FTextAlignmentButtons[TextAlignment].Enabled :=
      (Ord(TextAlignment) div 3) = 1;
  end;

  FTextPathAttachmentPanel := TPanel.Create(Self);
  FTextPathAttachmentPanel.Parent := ParentForm;
  FTextPathAttachmentPanel.BevelOuter := bvRaised;
  FTextPathAttachmentPanel.Color := COLOR_BACKGROUND;
  FTextPathAttachmentPanel.ParentBackground := False;
  FTextPathAttachmentPanel.SetBounds(0, 0, 77, 69);
  FTextPathAttachmentPanel.Visible := False;
  for Attachment := Low(TScreenLayoutTextPathAttachment) to
    High(TScreenLayoutTextPathAttachment) do
  begin
    FTextPathAttachmentButtons[Attachment] :=
      TScreenLayoutTextPathAttachmentButton.Create(Self);
    FTextPathAttachmentButtons[Attachment].Parent :=
      FTextPathAttachmentPanel;
    FTextPathAttachmentButtons[Attachment].Attachment := Attachment;
    FTextPathAttachmentButtons[Attachment].SetBounds(
      5 + (Ord(Attachment) mod 2) * 35,
      5 + (Ord(Attachment) div 2) * 32, 32, 29);
    FTextPathAttachmentButtons[Attachment].OnClick :=
      TextPathAttachmentClick;
  end;

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

procedure TVectArtLineToolbarControl.ApplyFontStyle(Style: TFontStyle;
  Enabled: Boolean);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if FUpdating then
    Exit;
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if FEditHistory <> nil then
      Command := TVectArtCompoundCommand.Create;
    FDocument.BeginUpdate;
    try
      for I := 0 to High(Indices) do
      begin
        OldData := CaptureScreenLayoutTextData(
          TScreenLayoutTextLayer(FDocument[Indices[I]]));
        if (Style in OldData.FontStyle) = Enabled then
          Continue;
        NewData := OldData;
        if Enabled then
          Include(NewData.FontStyle, Style)
        else
          Exclude(NewData.FontStyle, Style);
        if Command <> nil then
          Command.Add(TScreenLayoutTextDataCommand.Create(FDocument,
            Indices[I], OldData, NewData));
        FDocument.SetTextData(Indices[I], NewData);
      end;
    finally
      FDocument.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyTextAlignment(
  Value: TScreenLayoutTextAlignment);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if FUpdating then
    Exit;
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if FEditHistory <> nil then
      Command := TVectArtCompoundCommand.Create;
    FDocument.BeginUpdate;
    try
      for I := 0 to High(Indices) do
      begin
        OldData := CaptureScreenLayoutTextData(
          TScreenLayoutTextLayer(FDocument[Indices[I]]));
        if OldData.Alignment = Value then
          Continue;
        NewData := OldData;
        NewData.Alignment := Value;
        if Command <> nil then
          Command.Add(TScreenLayoutTextDataCommand.Create(FDocument,
            Indices[I], OldData, NewData));
        FDocument.SetTextData(Indices[I], NewData);
      end;
    finally
      FDocument.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyTextPathAttachment(
  Value: TScreenLayoutTextPathAttachment);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if FUpdating then
    Exit;
  Indices := SelectedTextPathIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if FEditHistory <> nil then
      Command := TVectArtCompoundCommand.Create;
    FDocument.BeginUpdate;
    try
      for I := 0 to High(Indices) do
      begin
        OldData := CaptureScreenLayoutTextData(
          TScreenLayoutTextPathLayer(FDocument[Indices[I]]));
        if OldData.TextPathAttachment = Value then
          Continue;
        NewData := OldData;
        NewData.TextPathAttachment := Value;
        if Command <> nil then
          Command.Add(TScreenLayoutTextDataCommand.Create(FDocument,
            Indices[I], OldData, NewData));
        FDocument.SetTextData(Indices[I], NewData);
      end;
    finally
      FDocument.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyTextSpacing(
  IsLetterSpacing: Boolean; Ratio: Single);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if FUpdating then
    Exit;
  if IsLetterSpacing then
    Ratio := EnsureRange(Ratio, SCREEN_LAYOUT_TEXT_LETTER_SPACING_MIN,
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX)
  else
    Ratio := EnsureRange(Ratio, SCREEN_LAYOUT_TEXT_LINE_SPACING_MIN,
      SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX);
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if FEditHistory <> nil then
      Command := TVectArtCompoundCommand.Create;
    FDocument.BeginUpdate;
    try
      for I := 0 to High(Indices) do
      begin
        OldData := CaptureScreenLayoutTextData(
          TScreenLayoutTextLayer(FDocument[Indices[I]]));
        NewData := OldData;
        if IsLetterSpacing then
        begin
          if SameValue(OldData.LetterSpacingRatio, Ratio) then
            Continue;
          NewData.LetterSpacingRatio := Ratio;
        end
        else
        begin
          if SameValue(OldData.LineSpacingRatio, Ratio) then
            Continue;
          NewData.LineSpacingRatio := Ratio;
        end;
        if Command <> nil then
          Command.Add(TScreenLayoutTextDataCommand.Create(FDocument,
            Indices[I], OldData, NewData));
        FDocument.SetTextData(Indices[I], NewData);
      end;
    finally
      FDocument.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
  finally
    FUpdating := False;
  end;
  RefreshState;
end;

procedure TVectArtLineToolbarControl.ApplyFontFamily(const Value: string);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  Indices: TArray<Integer>;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if FUpdating or (Trim(Value) = '') then
    Exit;
  Indices := SelectedTextIndices;
  if (Length(Indices) = 0) or SelectionHasLockedText then
    Exit;
  FUpdating := True;
  try
    Command := nil;
    if FEditHistory <> nil then
      Command := TVectArtCompoundCommand.Create;
    FDocument.BeginUpdate;
    try
      for I := 0 to High(Indices) do
      begin
        OldData := CaptureScreenLayoutTextData(
          TScreenLayoutTextLayer(FDocument[Indices[I]]));
        if SameText(OldData.FontFamily, Value) then
          Continue;
        NewData := OldData;
        NewData.FontFamily := Value;
        if Command <> nil then
          Command.Add(TScreenLayoutTextDataCommand.Create(FDocument,
            Indices[I], OldData, NewData));
        FDocument.SetTextData(Indices[I], NewData);
      end;
    finally
      FDocument.EndUpdate;
    end;
    if (Command <> nil) and (Command.Count > 0) then
      FEditHistory.AddApplied(Command)
    else
      Command.Free;
  finally
    FUpdating := False;
  end;
  RefreshState;
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

procedure TVectArtLineToolbarControl.FontFamilyChanged(Sender: TObject);
begin
  if FUpdating or (FFontFamilyCombo.ItemIndex < 0) then
    Exit;
  ApplyFontFamily(FFontFamilyCombo.Items[FFontFamilyCombo.ItemIndex]);
end;

procedure TVectArtLineToolbarControl.FontStyleClick(Sender: TObject);
var
  Button: TScreenLayoutTextStyleButton;
begin
  if FUpdating or not (Sender is TScreenLayoutTextStyleButton) then
    Exit;
  Button := TScreenLayoutTextStyleButton(Sender);
  ApplyFontStyle(Button.Style, not Button.Selected);
end;

procedure TVectArtLineToolbarControl.TextAlignmentClick(Sender: TObject);
begin
  if FUpdating or not (Sender is TScreenLayoutTextAlignmentButton) then
    Exit;
  ApplyTextAlignment(TScreenLayoutTextAlignmentButton(Sender).Alignment);
  FTextAlignmentPanel.Visible := False;
end;

procedure TVectArtLineToolbarControl.TextAlignmentPopupClick(
  Sender: TObject);
var
  Position: TPoint;
begin
  if (FTextAlignmentPanel = nil) or
    (FTextAlignmentPanel.Parent = nil) then
    Exit;
  if FTextAlignmentPanel.Visible then
  begin
    FTextAlignmentPanel.Visible := False;
    Exit;
  end;
  FTextPathAttachmentPanel.Visible := False;
  Position := FTextAlignmentButton.ClientToScreen(Point(
    FTextAlignmentButton.Width - FTextAlignmentPanel.Width,
    FTextAlignmentButton.Height + 2));
  Position := FTextAlignmentPanel.Parent.ScreenToClient(Position);
  FTextAlignmentPanel.SetBounds(Position.X, Position.Y,
    FTextAlignmentPanel.Width, FTextAlignmentPanel.Height);
  FTextAlignmentPanel.BringToFront;
  FTextAlignmentPanel.Visible := True;
end;

procedure TVectArtLineToolbarControl.TextPathAttachmentClick(
  Sender: TObject);
begin
  if FUpdating or
    not (Sender is TScreenLayoutTextPathAttachmentButton) then
    Exit;
  ApplyTextPathAttachment(
    TScreenLayoutTextPathAttachmentButton(Sender).Attachment);
  FTextPathAttachmentPanel.Visible := False;
end;

procedure TVectArtLineToolbarControl.TextPathAttachmentPopupClick(
  Sender: TObject);
var
  Position: TPoint;
begin
  if (FTextPathAttachmentPanel = nil) or
    (FTextPathAttachmentPanel.Parent = nil) then
    Exit;
  if FTextPathAttachmentPanel.Visible then
  begin
    FTextPathAttachmentPanel.Visible := False;
    Exit;
  end;
  FTextAlignmentPanel.Visible := False;
  Position := FTextPathAttachmentButton.ClientToScreen(Point(
    FTextPathAttachmentButton.Width - FTextPathAttachmentPanel.Width,
    FTextPathAttachmentButton.Height + 2));
  Position := FTextPathAttachmentPanel.Parent.ScreenToClient(Position);
  FTextPathAttachmentPanel.SetBounds(Position.X, Position.Y,
    FTextPathAttachmentPanel.Width, FTextPathAttachmentPanel.Height);
  FTextPathAttachmentPanel.BringToFront;
  FTextPathAttachmentPanel.Visible := True;
end;

function TVectArtLineToolbarControl.IsTextAlignmentControl(
  Control: TControl): Boolean;
begin
  Result := False;
  while Control <> nil do
  begin
    if Control = FTextAlignmentPanel then
      Exit(True);
    Control := Control.Parent;
  end;
end;

function TVectArtLineToolbarControl.IsTextPathAttachmentControl(
  Control: TControl): Boolean;
begin
  Result := False;
  while Control <> nil do
  begin
    if Control = FTextPathAttachmentPanel then
      Exit(True);
    Control := Control.Parent;
  end;
end;

function TVectArtLineToolbarControl.FontStyleButton(
  Style: TFontStyle): TScreenLayoutTextStyleButton;
begin
  Result := FFontStyleButtons[Style];
end;

function TVectArtLineToolbarControl.TextAlignmentCell(
  Value: TScreenLayoutTextAlignment): TScreenLayoutTextAlignmentButton;
begin
  Result := FTextAlignmentButtons[Value];
end;

function TVectArtLineToolbarControl.TextPathAttachmentCell(
  Value: TScreenLayoutTextPathAttachment):
  TScreenLayoutTextPathAttachmentButton;
begin
  Result := FTextPathAttachmentButtons[Value];
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
  if (FFontFamilyCombo <> nil) and FFontFamilyCombo.Visible then
    Canvas.TextOut(8, 13, UnicodeText([$30D5, $30A9, $30F3, $30C8]))
  else
    Canvas.TextOut(8, 13, UnicodeText([$592A, $3055]));
end;

procedure TVectArtLineToolbarControl.RefreshState;
var
  Alignment: TScreenLayoutTextAlignment;
  AlignmentValue: TScreenLayoutTextAlignment;
  Attachment: TScreenLayoutTextPathAttachment;
  AttachmentValue: TScreenLayoutTextPathAttachment;
  AllRegularTexts: Boolean;
  AllTextPaths: Boolean;
  Color: TColor;
  CommonAlignment: Boolean;
  CommonAttachment: Boolean;
  CommonFontFamily: Boolean;
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
  Style: TFontStyle;
  TextIndices: TArray<Integer>;
  TextPathIndices: TArray<Integer>;
  FontFamilyValue: string;
  WidthValue: Single;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    TextIndices := SelectedTextIndices;
    if Length(TextIndices) > 0 then
    begin
      TextPathIndices := SelectedTextPathIndices;
      AllTextPaths := Length(TextPathIndices) = Length(TextIndices);
      AllRegularTexts := True;
      for I := 0 to High(TextIndices) do
        AllRegularTexts := AllRegularTexts and
          not (FDocument[TextIndices[I]] is TScreenLayoutTextPathLayer);
      Width := TEXT_TOOLBAR_WIDTH;
      Visible := True;
      FDetailsPanel.Visible := False;
      FFontFamilyCombo.Visible := True;
      FStrokeWidthEdit.Visible := False;
      FStrokeWidthTrackBar.Visible := False;
      FDetailsButton.Visible := False;
      FTextAlignmentButton.Visible := AllRegularTexts;
      FTextPathAttachmentButton.Visible := AllTextPaths;
      if not AllRegularTexts then
        FTextAlignmentPanel.Visible := False;
      if not AllTextPaths then
        FTextPathAttachmentPanel.Visible := False;
      for Style := Low(TFontStyle) to High(TFontStyle) do
        FFontStyleButtons[Style].Visible := True;
      FontFamilyValue := TScreenLayoutTextLayer(
        FDocument[TextIndices[0]]).FontFamily;
      CommonFontFamily := True;
      for I := 1 to High(TextIndices) do
      begin
        CommonFontFamily := CommonFontFamily and SameText(FontFamilyValue,
          TScreenLayoutTextLayer(FDocument[TextIndices[I]]).FontFamily);
      end;
      if CommonFontFamily then
        FFontFamilyCombo.ItemIndex :=
          FFontFamilyCombo.Items.IndexOf(FontFamilyValue)
      else
        FFontFamilyCombo.ItemIndex := -1;
      FFontFamilyCombo.Enabled := not SelectionHasLockedText;
      if AllRegularTexts then
      begin
        AlignmentValue := TScreenLayoutTextLayer(
          FDocument[TextIndices[0]]).Alignment;
        CommonAlignment := True;
        for I := 1 to High(TextIndices) do
          CommonAlignment := CommonAlignment and
            (AlignmentValue = TScreenLayoutTextLayer(
              FDocument[TextIndices[I]]).Alignment);
        FTextAlignmentButton.Enabled := not SelectionHasLockedText;
        FTextAlignmentButton.Mixed := not CommonAlignment;
        if CommonAlignment then
          FTextAlignmentButton.Alignment := AlignmentValue;
        for Alignment := Low(TScreenLayoutTextAlignment) to
          High(TScreenLayoutTextAlignment) do
        begin
          FTextAlignmentButtons[Alignment].Enabled :=
            (not SelectionHasLockedText) and
            ((Ord(Alignment) div 3) = 1);
          FTextAlignmentButtons[Alignment].Selected := CommonAlignment and
            (Alignment = AlignmentValue);
        end;
      end;
      if AllTextPaths then
      begin
        AttachmentValue := TScreenLayoutTextPathLayer(
          FDocument[TextPathIndices[0]]).Attachment;
        CommonAttachment := True;
        for I := 1 to High(TextPathIndices) do
          CommonAttachment := CommonAttachment and
            (AttachmentValue = TScreenLayoutTextPathLayer(
              FDocument[TextPathIndices[I]]).Attachment);
        FTextPathAttachmentButton.Enabled := not SelectionHasLockedText;
        FTextPathAttachmentButton.Mixed := not CommonAttachment;
        if CommonAttachment then
          FTextPathAttachmentButton.Attachment := AttachmentValue;
        for Attachment := Low(TScreenLayoutTextPathAttachment) to
          High(TScreenLayoutTextPathAttachment) do
        begin
          FTextPathAttachmentButtons[Attachment].Enabled :=
            not SelectionHasLockedText;
          FTextPathAttachmentButtons[Attachment].Selected :=
            CommonAttachment and (Attachment = AttachmentValue);
        end;
      end;
      for Style := Low(TFontStyle) to High(TFontStyle) do
      begin
        FFontStyleButtons[Style].Selected := True;
        for I := 0 to High(TextIndices) do
          FFontStyleButtons[Style].Selected :=
            FFontStyleButtons[Style].Selected and
            (Style in TScreenLayoutTextLayer(
              FDocument[TextIndices[I]]).FontStyle);
        FFontStyleButtons[Style].Enabled := not SelectionHasLockedText;
      end;
    end
    else
    begin
      Width := LINE_TOOLBAR_WIDTH;
      FFontFamilyCombo.Visible := False;
      FTextAlignmentButton.Visible := False;
      FTextAlignmentPanel.Visible := False;
      FTextPathAttachmentButton.Visible := False;
      FTextPathAttachmentPanel.Visible := False;
      for Style := Low(TFontStyle) to High(TFontStyle) do
        FFontStyleButtons[Style].Visible := False;
      FStrokeWidthEdit.Visible := True;
      FStrokeWidthTrackBar.Visible := True;
      FDetailsButton.Visible := True;
      Indices := SelectedLineIndices;
      if Length(Indices) > 0 then
      begin
        Visible := True;
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
          FStrokeWidthEdit.Text := FormatFloat('0.##', WidthValue)
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
          vetRoundedRectangleLine, vetArc, vetLine, vetEllipseLine,
          vetPath]) then
      begin
        Visible := True;
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
    end;
  finally
    FUpdating := False;
  end;
  Invalidate;
end;

procedure TVectArtLineToolbarControl.Resize;
var
  Style: TFontStyle;
  StyleLeft: Integer;
  TrackWidth: Integer;
begin
  inherited Resize;
  if FFontFamilyCombo <> nil then
    FFontFamilyCombo.SetBounds(60, 8, 180, 25);
  StyleLeft := 246;
  for Style := Low(TFontStyle) to High(TFontStyle) do
    if FFontStyleButtons[Style] <> nil then
      FFontStyleButtons[Style].SetBounds(StyleLeft + Ord(Style) * 32,
        6, 28, 29);
  if FTextAlignmentButton <> nil then
    FTextAlignmentButton.SetBounds(374, 6, 34, 29);
  if FTextPathAttachmentButton <> nil then
    FTextPathAttachmentButton.SetBounds(374, 6, 34, 29);
  TrackWidth := Max(Width - 176, 60);
  if FStrokeWidthTrackBar <> nil then
    FStrokeWidthTrackBar.SetBounds(40, 4, TrackWidth, 34);
  if FStrokeWidthEdit <> nil then
    FStrokeWidthEdit.SetBounds(Width - 128, 8, 48, 25);
  if FDetailsButton <> nil then
    FDetailsButton.SetBounds(Width - 70, 8, 60, 25);
end;

function TVectArtLineToolbarControl.SelectedTextIndices: TArray<Integer>;
var
  I: Integer;
  Selection: TArray<Integer>;
begin
  Result := nil;
  if (FDocument = nil) or (FDocument.SelectionCount = 0) then
    Exit;
  Selection := FDocument.GetSelectedLayerIndices;
  for I := 0 to High(Selection) do
    if not (FDocument[Selection[I]] is TScreenLayoutTextLayer) then
      Exit;
  Result := Selection;
end;

function TVectArtLineToolbarControl.SelectedTextPathIndices:
  TArray<Integer>;
var
  I: Integer;
  Selection: TArray<Integer>;
begin
  Result := nil;
  if (FDocument = nil) or (FDocument.SelectionCount = 0) then
    Exit;
  Selection := FDocument.GetSelectedLayerIndices;
  for I := 0 to High(Selection) do
    if not (FDocument[Selection[I]] is TScreenLayoutTextPathLayer) then
      Exit;
  Result := Selection;
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

function TVectArtLineToolbarControl.SelectionHasLockedText: Boolean;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := False;
  Indices := SelectedTextIndices;
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
