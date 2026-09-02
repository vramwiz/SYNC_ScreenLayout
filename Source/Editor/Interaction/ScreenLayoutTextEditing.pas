// Windows IMEの確定前入力と、描画側で保持する文字編集バッファの操作を担当する。
unit ScreenLayoutTextEditing;

interface

uses
  System.Types, Winapi.Messages, Vcl.StdCtrls;

type
  TScreenLayoutCommittedTextEvent = procedure(Sender: TObject;
    const Text: string) of object;
  TScreenLayoutCompositionEvent = procedure(Sender: TObject;
    const Text: string; CursorPosition: Integer; Active: Boolean) of object;

  TScreenLayoutCaretLine = record
    EndIndex: Integer;   // 改行文字を含まないUTF-16終端位置。
    StartIndex: Integer; // 行先頭の直前にあるUTF-16位置。
    Text: string;        // 折り返し後にこの行へ表示する文字列。
  end;

  TScreenLayoutImeEdit = class(TEdit)
  private
    FOnCommittedText: TScreenLayoutCommittedTextEvent;
    FOnComposition: TScreenLayoutCompositionEvent;
    procedure WMChar(var Message: TWMChar); message WM_CHAR;
    procedure WMImeComposition(var Message: TMessage);
      message WM_IME_COMPOSITION;
    procedure WMImeEndComposition(var Message: TMessage);
      message WM_IME_ENDCOMPOSITION;
    procedure WMImeStartComposition(var Message: TMessage);
      message WM_IME_STARTCOMPOSITION;
  public
    // IMEまたは通常キー入力が確定した文字列を通知する。
    property OnCommittedText: TScreenLayoutCommittedTextEvent
      read FOnCommittedText write FOnCommittedText;
    // IME未確定文字列、変換カーソル位置、変換中かどうかを通知する。
    property OnComposition: TScreenLayoutCompositionEvent
      read FOnComposition write FOnComposition;
  end;

// 明示改行とWrapWidthによる折り返しを反映した仮想カーソル行を返す。
function BuildScreenLayoutTextCaretLines(const Text, FontFamily: string;
  FontSize, WrapWidth: Single): TArray<TScreenLayoutCaretLine>;
// 指定行の横位置に最も近いUTF-16カーソル位置を返す。
function ScreenLayoutTextCaretIndexAtLineX(
  const Line: TScreenLayoutCaretLine; const FontFamily: string;
  FontSize, TargetX: Single): Integer;
// 折り返し後の組版座標から、最も近い行と文字間のUTF-16位置を返す。
function ScreenLayoutTextCaretIndexAtPoint(const Text, FontFamily: string;
  FontSize, WrapWidth, TargetX, TargetY: Single): Integer;
// 選択範囲を削除してカーソルを範囲先頭へ移し、削除した場合にTrueを返す。
function DeleteScreenLayoutTextSelection(var Text: string;
  var CaretIndex, SelectionAnchor: Integer;
  var PreferredCaretX: Single): Boolean;
// 選択範囲を置換してTextを挿入し、カーソルを挿入末尾へ移す。
procedure InsertScreenLayoutTextAtCaret(var Buffer: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  const Text: string);
// サロゲートペアとCRLFを分割せず左右へ移動し、必要なら選択を拡張する。
procedure MoveScreenLayoutTextCaretHorizontal(const Text: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  Direction: Integer; ExtendSelection: Boolean);

implementation

uses
  System.Generics.Collections, System.Math, System.Skia, Winapi.Imm,
  ScreenLayoutTextGeometry;

function TextUnitLengthAt(const Text: string; Index: Integer): Integer;
begin
  Result := 1;
  if (Index >= 1) and (Index < Length(Text)) and
    (Ord(Text[Index]) >= $D800) and (Ord(Text[Index]) <= $DBFF) and
    (Ord(Text[Index + 1]) >= $DC00) and
    (Ord(Text[Index + 1]) <= $DFFF) then
    Result := 2;
end;

function BuildScreenLayoutTextCaretLines(const Text, FontFamily: string;
  FontSize, WrapWidth: Single): TArray<TScreenLayoutCaretLine>;
var
  Candidate: string;
  CharacterLength: Integer;
  CurrentLine: TScreenLayoutCaretLine;
  Font: ISkFont;
  I: Integer;
  Lines: TList<TScreenLayoutCaretLine>;
  NewLineLength: Integer;
  NextCharacter: string;
begin
  Font := CreateScreenLayoutTextFont(FontFamily, FontSize);
  Lines := TList<TScreenLayoutCaretLine>.Create;
  try
    CurrentLine := Default(TScreenLayoutCaretLine);
    CurrentLine.StartIndex := 0;
    I := 1;
    while I <= Length(Text) do
    begin
      NewLineLength := 0;
      if Text[I] = #13 then
      begin
        NewLineLength := 1;
        if (I < Length(Text)) and (Text[I + 1] = #10) then
          NewLineLength := 2;
      end
      else if Text[I] = #10 then
        NewLineLength := 1;
      if NewLineLength > 0 then
      begin
        CurrentLine.EndIndex := I - 1;
        Lines.Add(CurrentLine);
        Inc(I, NewLineLength);
        CurrentLine := Default(TScreenLayoutCaretLine);
        CurrentLine.StartIndex := I - 1;
        Continue;
      end;
      CharacterLength := TextUnitLengthAt(Text, I);
      NextCharacter := Copy(Text, I, CharacterLength);
      Candidate := CurrentLine.Text + NextCharacter;
      if (CurrentLine.Text <> '') and (WrapWidth > 0) and
        (Font.MeasureText(Candidate) > WrapWidth) then
      begin
        CurrentLine.EndIndex := I - 1;
        Lines.Add(CurrentLine);
        CurrentLine := Default(TScreenLayoutCaretLine);
        CurrentLine.StartIndex := I - 1;
        CurrentLine.Text := NextCharacter;
      end
      else
        CurrentLine.Text := Candidate;
      Inc(I, CharacterLength);
    end;
    CurrentLine.EndIndex := Length(Text);
    Lines.Add(CurrentLine);
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

function ScreenLayoutTextCaretIndexAtLineX(
  const Line: TScreenLayoutCaretLine; const FontFamily: string;
  FontSize, TargetX: Single): Integer;
var
  CharacterLength: Integer;
  Font: ISkFont;
  I: Integer;
  PreviousWidth: Single;
  Width: Single;
begin
  Result := Line.StartIndex;
  Font := CreateScreenLayoutTextFont(FontFamily, FontSize);
  PreviousWidth := 0;
  I := 1;
  while I <= Length(Line.Text) do
  begin
    CharacterLength := TextUnitLengthAt(Line.Text, I);
    Width := Font.MeasureText(Copy(Line.Text, 1,
      I + CharacterLength - 1));
    if TargetX < (PreviousWidth + Width) * 0.5 then
      Exit;
    Inc(Result, CharacterLength);
    PreviousWidth := Width;
    Inc(I, CharacterLength);
  end;
end;

function ScreenLayoutTextCaretIndexAtPoint(const Text, FontFamily: string;
  FontSize, WrapWidth, TargetX, TargetY: Single): Integer;
var
  Font: ISkFont;
  LineHeight: Single;
  LineIndex: Integer;
  Lines: TArray<TScreenLayoutCaretLine>;
begin
  Lines := BuildScreenLayoutTextCaretLines(Text, FontFamily, FontSize,
    WrapWidth);
  if Length(Lines) = 0 then
    Exit(0);
  Font := CreateScreenLayoutTextFont(FontFamily, FontSize);
  LineHeight := Max(Font.Spacing, FontSize);
  LineIndex := EnsureRange(Floor(TargetY / Max(LineHeight, 1.0)), 0,
    High(Lines));
  Result := ScreenLayoutTextCaretIndexAtLineX(Lines[LineIndex],
    FontFamily, FontSize, TargetX);
end;

function DeleteScreenLayoutTextSelection(var Text: string;
  var CaretIndex, SelectionAnchor: Integer;
  var PreferredCaretX: Single): Boolean;
var
  SelectionEnd: Integer;
  SelectionStart: Integer;
begin
  SelectionStart := Min(CaretIndex, SelectionAnchor);
  SelectionEnd := Max(CaretIndex, SelectionAnchor);
  Result := SelectionStart <> SelectionEnd;
  if not Result then
    Exit;
  Delete(Text, SelectionStart + 1, SelectionEnd - SelectionStart);
  CaretIndex := SelectionStart;
  SelectionAnchor := SelectionStart;
  PreferredCaretX := -1.0;
end;

procedure InsertScreenLayoutTextAtCaret(var Buffer: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  const Text: string);
begin
  if Text = '' then
    Exit;
  DeleteScreenLayoutTextSelection(Buffer, CaretIndex, SelectionAnchor,
    PreferredCaretX);
  Insert(Text, Buffer, CaretIndex + 1);
  Inc(CaretIndex, Length(Text));
  SelectionAnchor := CaretIndex;
  PreferredCaretX := -1.0;
end;

procedure MoveScreenLayoutTextCaretHorizontal(const Text: string;
  var CaretIndex, SelectionAnchor: Integer; var PreferredCaretX: Single;
  Direction: Integer; ExtendSelection: Boolean);
var
  SelectionEnd: Integer;
  SelectionStart: Integer;
begin
  SelectionStart := Min(CaretIndex, SelectionAnchor);
  SelectionEnd := Max(CaretIndex, SelectionAnchor);
  if not ExtendSelection and (SelectionStart <> SelectionEnd) then
  begin
    if Direction < 0 then
      CaretIndex := SelectionStart
    else
      CaretIndex := SelectionEnd;
  end
  else if Direction < 0 then
  begin
    if CaretIndex > 0 then
      Dec(CaretIndex);
    if (CaretIndex > 0) and (Ord(Text[CaretIndex]) >= $D800) and
      (Ord(Text[CaretIndex]) <= $DBFF) then
      Dec(CaretIndex);
    if (CaretIndex > 0) and (Text[CaretIndex] = #13) and
      (Text[CaretIndex + 1] = #10) then
      Dec(CaretIndex);
  end
  else
  begin
    if CaretIndex < Length(Text) then
      Inc(CaretIndex);
    if (CaretIndex < Length(Text)) and
      (Ord(Text[CaretIndex]) >= $D800) and
      (Ord(Text[CaretIndex]) <= $DBFF) then
      Inc(CaretIndex);
    if (CaretIndex < Length(Text)) and (Text[CaretIndex] = #13) and
      (Text[CaretIndex + 1] = #10) then
      Inc(CaretIndex);
  end;
  if not ExtendSelection then
    SelectionAnchor := CaretIndex;
  PreferredCaretX := -1.0;
end;

procedure TScreenLayoutImeEdit.WMChar(var Message: TWMChar);
begin
  if (Message.CharCode >= 32) and Assigned(FOnCommittedText) then
    FOnCommittedText(Self, string(WideChar(Message.CharCode)));
  // 確定文字はDocument側へ渡し、Edit自身の文字列には残さない。
  Message.Result := 0;
end;

procedure TScreenLayoutImeEdit.WMImeComposition(var Message: TMessage);
var
  ByteCount: Integer;
  CompositionCursor: Integer;
  CompositionText: string;
  InputContext: HIMC;
begin
  CompositionText := '';
  CompositionCursor := 0;
  InputContext := ImmGetContext(Handle);
  if InputContext <> 0 then
  try
    ByteCount := ImmGetCompositionStringW(InputContext, GCS_COMPSTR,
      nil, 0);
    if ByteCount > 0 then
    begin
      SetLength(CompositionText, ByteCount div SizeOf(Char));
      ImmGetCompositionStringW(InputContext, GCS_COMPSTR,
        PChar(CompositionText), ByteCount);
    end;
    CompositionCursor := ImmGetCompositionStringW(InputContext,
      GCS_CURSORPOS, nil, 0);
    if CompositionCursor < 0 then
      CompositionCursor := 0;
  finally
    ImmReleaseContext(Handle, InputContext);
  end;
  inherited;
  if Assigned(FOnComposition) then
    FOnComposition(Self, CompositionText, CompositionCursor, True);
end;

procedure TScreenLayoutImeEdit.WMImeEndComposition(var Message: TMessage);
begin
  inherited;
  if Assigned(FOnComposition) then
    FOnComposition(Self, '', 0, False);
end;

procedure TScreenLayoutImeEdit.WMImeStartComposition(var Message: TMessage);
begin
  inherited;
  if Assigned(FOnComposition) then
    FOnComposition(Self, '', 0, True);
end;

end.
