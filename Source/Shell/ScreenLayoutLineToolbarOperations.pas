// 右上ツールバーの線属性変更をレイヤー種別へ振り分け、複数選択のUndo履歴を構築する。
unit ScreenLayoutLineToolbarOperations;

interface

uses
  Vcl.Graphics, ScreenLayoutDocument, ScreenLayoutEditHistory;

// 開いた線レイヤーの共通属性を返す。閉じたPathや非対応レイヤーではFalseを返す。
function TryReadScreenLayoutToolbarLine(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap): Boolean;
// 選択済み線の線端を変更する。矩形線は線端を持たず、変更対象から除外される。
procedure ApplyScreenLayoutToolbarLineCap(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: TVectArtLineCap);
// 選択済み線の線種を変更し、複数選択の変更を1件のUndo履歴へまとめる。
procedure ApplyScreenLayoutToolbarLineStyle(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: TVectArtMifStrokeStyle);
// 選択済み線の幅を変更する。RecordHistory=Falseはドラッグ中のプレビュー更新に使用する。
procedure ApplyScreenLayoutToolbarLineWidth(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: Single; RecordHistory: Boolean);

implementation

uses
  System.Math, ScreenLayoutEditCommands;

procedure AddAppliedCommand(History: TVectArtEditHistory;
  Command: TVectArtCompoundCommand);
begin
  if (Command <> nil) and (Command.Count > 0) and (History <> nil) then
    History.AddApplied(Command)
  else
    Command.Free;
end;

procedure SetLineStroke(Document: TVectArtDocument; Index: Integer;
  Color: TColor; Width: Single; Style: TVectArtMifStrokeStyle);
begin
  if Document[Index] is TScreenLayoutRectangleLineLayer then
    Document.SetRectangleLineStroke(Index, Color, Width, Style)
  else if Document[Index] is TScreenLayoutArcLayer then
    Document.SetArcStroke(Index, Color, Width, Style)
  else
    Document.SetPathStroke(Index, Color, Width, Style);
end;

procedure SetLineCap(Document: TVectArtDocument; Index: Integer;
  Value: TVectArtLineCap);
begin
  if Document[Index] is TScreenLayoutArcLayer then
    Document.SetArcLineCap(Index, Value)
  else if Document[Index] is TVectArtPathLayer then
    Document.SetPathLineCap(Index, Value);
end;

function TryReadScreenLayoutToolbarLine(Layer: TVectArtLayer;
  out Color: TColor; out Width: Single; out Style: TVectArtMifStrokeStyle;
  out LineCap: TVectArtLineCap): Boolean;
begin
  Result := True;
  if Layer is TScreenLayoutRectangleLineLayer then
  begin
    Color := TScreenLayoutRectangleLineLayer(Layer).StrokeColor;
    Width := TScreenLayoutRectangleLineLayer(Layer).StrokeWidth;
    Style := TScreenLayoutRectangleLineLayer(Layer).StrokeStyle;
    LineCap := vlcSquare;
  end
  else if Layer is TScreenLayoutArcLayer then
  begin
    Color := TScreenLayoutArcLayer(Layer).StrokeColor;
    Width := TScreenLayoutArcLayer(Layer).StrokeWidth;
    Style := TScreenLayoutArcLayer(Layer).StrokeStyle;
    LineCap := TScreenLayoutArcLayer(Layer).LineCap;
  end
  else if (Layer is TVectArtPathLayer) and
    not TVectArtPathLayer(Layer).Closed then
  begin
    Color := TVectArtPathLayer(Layer).StrokeColor;
    Width := TVectArtPathLayer(Layer).StrokeWidth;
    Style := TVectArtPathLayer(Layer).MifStrokeStyle;
    LineCap := TVectArtPathLayer(Layer).LineCap;
  end
  else
    Result := False;
end;

procedure ApplyScreenLayoutToolbarLineCap(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: TVectArtLineCap);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  I: Integer;
  OldLineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      if Document[Indices[I]] is TScreenLayoutRectangleLineLayer then
        Continue;
      if not TryReadScreenLayoutToolbarLine(Document[Indices[I]], Color,
        Width, Style, OldLineCap) or (OldLineCap = Value) then
        Continue;
      Command.Add(TVectArtPathLineCapCommand.Create(Document, Indices[I],
        OldLineCap, Value));
      SetLineCap(Document, Indices[I], Value);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyScreenLayoutToolbarLineStyle(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: TVectArtMifStrokeStyle);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  I: Integer;
  LineCap: TVectArtLineCap;
  OldStyle: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if Document = nil then
    Exit;
  Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      if not TryReadScreenLayoutToolbarLine(Document[Indices[I]], Color,
        Width, OldStyle, LineCap) or (OldStyle = Value) then
        Continue;
      Command.Add(TVectArtStrokeCommand.Create(Document, Indices[I], Color,
        Width, OldStyle, Color, Width, Value));
      SetLineStroke(Document, Indices[I], Color, Width, Value);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

procedure ApplyScreenLayoutToolbarLineWidth(Document: TVectArtDocument;
  History: TVectArtEditHistory; const Indices: TArray<Integer>;
  Value: Single; RecordHistory: Boolean);
var
  Color: TColor;
  Command: TVectArtCompoundCommand;
  I: Integer;
  Layer: TVectArtLayer;
  LineCap: TVectArtLineCap;
  Style: TVectArtMifStrokeStyle;
  Width: Single;
begin
  if Document = nil then
    Exit;
  Value := Max(Value, 0.1);
  Command := nil;
  if RecordHistory then
    Command := TVectArtCompoundCommand.Create;
  Document.BeginUpdate;
  try
    for I := 0 to High(Indices) do
    begin
      Layer := Document[Indices[I]];
      if not TryReadScreenLayoutToolbarLine(Layer, Color, Width, Style,
        LineCap) or SameValue(Width, Value) then
        Continue;
      if Command <> nil then
        Command.Add(TVectArtStrokeCommand.Create(Document, Indices[I], Color,
          Width, Style, Color, Value, Style));
      SetLineStroke(Document, Indices[I], Color, Value, Style);
    end;
  finally
    Document.EndUpdate;
  end;
  AddAppliedCommand(History, Command);
end;

end.
