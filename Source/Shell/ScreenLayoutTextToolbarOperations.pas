// 右上ツールバーから要求された文字属性変更をDocumentへ適用し、Undo履歴を組み立てる。
unit ScreenLayoutTextToolbarOperations;

interface

uses
  Vcl.Graphics, ScreenLayoutDocument, ScreenLayoutEditHistory;

// 選択済みTextのフォント装飾を変更する。IndicesはTextだけを指し、ロック確認は呼び出し側が行う。
procedure ApplyScreenLayoutToolbarFontStyle(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Style: TFontStyle; Enabled: Boolean);
// 選択済みTextの枠内配置を変更し、変更があった項目を1件のUndo履歴へまとめる。
procedure ApplyScreenLayoutToolbarTextAlignment(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: TScreenLayoutTextAlignment);
// 選択済み文字パスのPath接触面を変更し、変更があった項目をUndo可能にする。
procedure ApplyScreenLayoutToolbarTextPathAttachment(
  Document: TVectArtDocument; History: TVectArtEditHistory;
  const Indices: TArray<Integer>; Value: TScreenLayoutTextPathAttachment);
// 選択済みTextの字間または行間を変更する。Ratioはモデルが許容する範囲へ制限される。
procedure ApplyScreenLayoutToolbarTextSpacing(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  IsLetterSpacing: Boolean; Ratio: Single);
// 選択済みTextのフォントファミリーを変更し、複数選択は1件のUndo履歴へまとめる。
procedure ApplyScreenLayoutToolbarFontFamily(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  const Value: string);

implementation

uses
  System.Math, System.SysUtils, ScreenLayoutEditCommands,
  ScreenLayoutTextCommands;

procedure AddAppliedCommand(History: TVectArtEditHistory;
  Command: TVectArtCompoundCommand);
begin
  if (Command <> nil) and (Command.Count > 0) and (History <> nil) then
    History.AddApplied(Command)
  else
    Command.Free;
end;

procedure ApplyScreenLayoutToolbarFontStyle(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Style: TFontStyle; Enabled: Boolean);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      OldData := CaptureScreenLayoutTextData(
        TScreenLayoutTextLayer(Document[Indices[I]]));
      if (Style in OldData.FontStyle) = Enabled then
        Continue;
      NewData := OldData;
      if Enabled then
        Include(NewData.FontStyle, Style)
      else
        Exclude(NewData.FontStyle, Style);
      Command.Add(TScreenLayoutTextDataCommand.Create(Document, Indices[I],
        OldData, NewData));
      Document.SetTextData(Indices[I], NewData);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyScreenLayoutToolbarTextAlignment(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: TScreenLayoutTextAlignment);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      OldData := CaptureScreenLayoutTextData(
        TScreenLayoutTextLayer(Document[Indices[I]]));
      if OldData.Alignment = Value then
        Continue;
      NewData := OldData;
      NewData.Alignment := Value;
      Command.Add(TScreenLayoutTextDataCommand.Create(Document, Indices[I],
        OldData, NewData));
      Document.SetTextData(Indices[I], NewData);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyScreenLayoutToolbarTextPathAttachment(
  Document: TVectArtDocument; History: TVectArtEditHistory;
  const Indices: TArray<Integer>; Value: TScreenLayoutTextPathAttachment);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      OldData := CaptureScreenLayoutTextData(
        TScreenLayoutTextPathLayer(Document[Indices[I]]));
      if OldData.TextPathAttachment = Value then
        Continue;
      NewData := OldData;
      NewData.TextPathAttachment := Value;
      Command.Add(TScreenLayoutTextDataCommand.Create(Document, Indices[I],
        OldData, NewData));
      Document.SetTextData(Indices[I], NewData);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyScreenLayoutToolbarTextSpacing(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  IsLetterSpacing: Boolean; Ratio: Single);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if Document = nil then
    Exit;
  if IsLetterSpacing then
    Ratio := EnsureRange(Ratio, SCREEN_LAYOUT_TEXT_LETTER_SPACING_MIN,
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX)
  else
    Ratio := EnsureRange(Ratio, SCREEN_LAYOUT_TEXT_LINE_SPACING_MIN,
      SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX);
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      OldData := CaptureScreenLayoutTextData(
        TScreenLayoutTextLayer(Document[Indices[I]]));
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
      Command.Add(TScreenLayoutTextDataCommand.Create(Document, Indices[I],
        OldData, NewData));
      Document.SetTextData(Indices[I], NewData);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyScreenLayoutToolbarFontFamily(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  const Value: string);
var
  Command: TVectArtCompoundCommand;
  I: Integer;
  NewData: TScreenLayoutTextData;
  OldData: TScreenLayoutTextData;
begin
  if (Document = nil) or (Trim(Value) = '') then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      OldData := CaptureScreenLayoutTextData(
        TScreenLayoutTextLayer(Document[Indices[I]]));
      if SameText(OldData.FontFamily, Value) then
        Continue;
      NewData := OldData;
      NewData.FontFamily := Value;
      Command.Add(TScreenLayoutTextDataCommand.Create(Document, Indices[I],
        OldData, NewData));
      Document.SetTextData(Indices[I], NewData);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

end.
