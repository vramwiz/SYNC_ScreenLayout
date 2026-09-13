// 自由変形の前後状態を階層パスで保持し、Undo／Redoで同じレイヤーへ復元する。
unit ScreenLayoutLayerTransformCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands,
  ScreenLayoutProjectiveTransform;

// 対象レイヤーの変形前後を保持する履歴コマンドを生成する。
// レイヤーの再生成後も解決できるよう、現在のDocument内階層パスを記録する。
function CreateScreenLayoutLayerTransformCommand(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>;
  const BeforeTransforms, AfterTransforms: TArray<TScreenLayoutTransform>):
  TVectArtEditCommand;

implementation

type
  TScreenLayoutLayerTransformCommand = class(TVectArtEditCommand)
  private
    FAfterTransforms  : TArray<TScreenLayoutTransform>; // 確定後に復元する各変形。
    FBeforeTransforms : TArray<TScreenLayoutTransform>; // Undoで復元する各変形。
    FDocument         : TVectArtDocument;                // 階層パスの解決元。
    FPaths            : TArray<TArray<Integer>>;         // Documentから対象へ至る添字列。
  public
    constructor Create(Document: TVectArtDocument;
      const Layers: TArray<TVectArtLayer>;
      const BeforeTransforms, AfterTransforms:
        TArray<TScreenLayoutTransform>);
    procedure Execute; override;
    procedure Undo; override;
  end;

function FindLayerPath(Layer, Target: TVectArtLayer;
  out Path: TArray<Integer>): Boolean;
var
  ChildPath: TArray<Integer>;
  I: Integer;
begin
  Path := nil;
  if Layer = Target then
    Exit(True);
  if Layer is TScreenLayoutGroupLayer then
    for I := 0 to TScreenLayoutGroupLayer(Layer).ChildCount - 1 do
      if FindLayerPath(TScreenLayoutGroupLayer(Layer)[I], Target,
        ChildPath) then
      begin
        Path := [I] + ChildPath;
        Exit(True);
      end;
  Result := False;
end;

function ResolveLayer(Document: TVectArtDocument;
  const Path: TArray<Integer>): TVectArtLayer;
var
  I: Integer;
begin
  Result := nil;
  if (Document = nil) or (Length(Path) = 0) or (Path[0] < 1) or
    (Path[0] >= Document.LayerCount) then
    Exit;
  Result := Document[Path[0]];
  for I := 1 to High(Path) do
  begin
    if not (Result is TScreenLayoutGroupLayer) or (Path[I] < 0) or
      (Path[I] >= TScreenLayoutGroupLayer(Result).ChildCount) then
      Exit(nil);
    Result := TScreenLayoutGroupLayer(Result)[Path[I]];
  end;
end;

constructor TScreenLayoutLayerTransformCommand.Create(
  Document: TVectArtDocument; const Layers: TArray<TVectArtLayer>;
  const BeforeTransforms, AfterTransforms: TArray<TScreenLayoutTransform>);
var
  I: Integer;
  J: Integer;
  Path: TArray<Integer>;
begin
  inherited Create;
  FDocument := Document;
  SetLength(FPaths, Length(Layers));
  for I := 0 to High(Layers) do
    for J := 1 to Document.LayerCount - 1 do
      if FindLayerPath(Document[J], Layers[I], Path) then
      begin
        FPaths[I] := [J] + Path;
        Break;
      end;
  FBeforeTransforms := Copy(BeforeTransforms);
  FAfterTransforms := Copy(AfterTransforms);
end;

procedure TScreenLayoutLayerTransformCommand.Execute;
var
  I: Integer;
  Layer: TVectArtLayer;
begin
  for I := 0 to High(FPaths) do
  begin
    Layer := ResolveLayer(FDocument, FPaths[I]);
    if Layer <> nil then
      Layer.Transform := FAfterTransforms[I];
  end;
  FDocument.Changed;
end;

procedure TScreenLayoutLayerTransformCommand.Undo;
var
  I: Integer;
  Layer: TVectArtLayer;
begin
  for I := 0 to High(FPaths) do
  begin
    Layer := ResolveLayer(FDocument, FPaths[I]);
    if Layer <> nil then
      Layer.Transform := FBeforeTransforms[I];
  end;
  FDocument.Changed;
end;

function CreateScreenLayoutLayerTransformCommand(Document: TVectArtDocument;
  const Layers: TArray<TVectArtLayer>;
  const BeforeTransforms, AfterTransforms: TArray<TScreenLayoutTransform>):
  TVectArtEditCommand;
begin
  Result := TScreenLayoutLayerTransformCommand.Create(Document, Layers,
    BeforeTransforms, AfterTransforms);
end;

end.
