// 文字レイヤーの挿入、削除、編集セッションをUndo／Redo可能にする。
unit ScreenLayoutTextCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands;

// 文字レイヤーの全永続属性を独立したデータへ写す。
function CaptureScreenLayoutTextData(
  Layer: TScreenLayoutTextLayer): TScreenLayoutTextData;

type
  TScreenLayoutInsertTextCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutTextData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutTextData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteTextCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutTextData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutTextData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutTextDataCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FIndex: Integer;
    FNewData: TScreenLayoutTextData;
    FOldData: TScreenLayoutTextData;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const OldData, NewData: TScreenLayoutTextData);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

function CaptureScreenLayoutTextData(
  Layer: TScreenLayoutTextLayer): TScreenLayoutTextData;
begin
  Result := Default(TScreenLayoutTextData);
  if Layer = nil then
    Exit;
  Result.Alignment := Layer.Alignment;
  Result.Bounds := Layer.Bounds;
  Result.FontFamily := Layer.FontFamily;
  Result.FontSize := Layer.FontSize;
  Result.FontStyle := Layer.FontStyle;
  Result.IndividualLetterSpacingRatios :=
    Layer.IndividualLetterSpacingRatios;
  Result.LetterSpacingRatio := Layer.LetterSpacingRatio;
  Result.LineSpacingRatio := Layer.LineSpacingRatio;
  Result.Locked := Layer.Locked;
  Result.Name := Layer.Name;
  Result.Opacity := Layer.Opacity;
  Result.RotationDegrees := Layer.RotationDegrees;
  Result.Text := Layer.Text;
  Result.TextColor := Layer.FillColor;
  Result.TransformMode := Layer.TransformMode;
  Result.Visible := Layer.Visible;
  Result.WrapWidth := Layer.WrapWidth;
end;

constructor TScreenLayoutInsertTextCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutTextData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertTextCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertText(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertTextCommand.Undo;
var
  RemovedData: TScreenLayoutTextData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveText(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

constructor TScreenLayoutDeleteTextCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutTextData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteTextCommand.Execute;
var
  RemovedData: TScreenLayoutTextData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveText(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteTextCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertText(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

constructor TScreenLayoutTextDataCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const OldData, NewData: TScreenLayoutTextData);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FOldData := OldData;
  FNewData := NewData;
  FOldData.IndividualLetterSpacingRatios :=
    Copy(OldData.IndividualLetterSpacingRatios);
  FNewData.IndividualLetterSpacingRatios :=
    Copy(NewData.IndividualLetterSpacingRatios);
end;

procedure TScreenLayoutTextDataCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetTextData(FIndex, FNewData);
end;

procedure TScreenLayoutTextDataCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetTextData(FIndex, FOldData);
end;

end.
