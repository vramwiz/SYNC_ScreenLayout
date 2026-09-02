// グループまたはグループ内レイヤーの移動・拡大縮小・回転をUndo／Redo可能にする。
unit ScreenLayoutGroupTransformCommands;

interface

uses
  System.Types, ScreenLayoutDocument, ScreenLayoutEditCommands;

type
  // 適用済みの平行移動量を保持し、同じレイヤーへ逆変換できるようにする。
  TScreenLayoutTranslateLayerCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDX: Single;
    FDY: Single;
    FLayer: TVectArtLayer;
    procedure Translate(DX, DY: Single);
  public
    constructor Create(ADocument: TVectArtDocument; Layer: TVectArtLayer;
      DX, DY: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 選択全体の変形前後の外接範囲を使い、単一レイヤーの倍率を可逆にする。
  TScreenLayoutScaleLayerCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FSourceBounds: TRectF;
    FTargetBounds: TRectF;
    procedure Scale(const SourceBounds, TargetBounds: TRectF);
  public
    constructor Create(ADocument: TVectArtDocument; Layer: TVectArtLayer;
      const SourceBounds, TargetBounds: TRectF);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 共通中心と回転量を保持し、グループ内レイヤーの回転を可逆にする。
  TScreenLayoutRotateLayerCommand = class(TVectArtEditCommand)
  private
    FCenter: TPointF;
    FDegrees: Single;
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    procedure Rotate(Degrees: Single);
  public
    constructor Create(ADocument: TVectArtDocument; Layer: TVectArtLayer;
      const Center: TPointF; Degrees: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // トップレベルで複数選択されたグループだけを一括移動する。
  TScreenLayoutTranslateGroupsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDX: Single;
    FDY: Single;
    FLayerIndices: TArray<Integer>;
    procedure Translate(DX, DY: Single);
  public
    constructor Create(ADocument: TVectArtDocument;
      const LayerIndices: TArray<Integer>; DX, DY: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  ScreenLayoutLayerGeometry;

constructor TScreenLayoutTranslateLayerCommand.Create(
  ADocument: TVectArtDocument; Layer: TVectArtLayer; DX, DY: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := Layer;
  FDX := DX;
  FDY := DY;
end;

procedure TScreenLayoutTranslateLayerCommand.Execute;
begin
  Translate(FDX, FDY);
end;

procedure TScreenLayoutTranslateLayerCommand.Translate(DX, DY: Single);
begin
  TranslateScreenLayoutLayer(FLayer, DX, DY);
  FDocument.Changed;
end;

procedure TScreenLayoutTranslateLayerCommand.Undo;
begin
  Translate(-FDX, -FDY);
end;

constructor TScreenLayoutScaleLayerCommand.Create(
  ADocument: TVectArtDocument; Layer: TVectArtLayer;
  const SourceBounds, TargetBounds: TRectF);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := Layer;
  FSourceBounds := SourceBounds;
  FTargetBounds := TargetBounds;
end;

procedure TScreenLayoutScaleLayerCommand.Execute;
begin
  Scale(FSourceBounds, FTargetBounds);
end;

procedure TScreenLayoutScaleLayerCommand.Scale(
  const SourceBounds, TargetBounds: TRectF);
begin
  ScaleScreenLayoutLayer(FLayer, SourceBounds, TargetBounds);
  FDocument.Changed;
end;

procedure TScreenLayoutScaleLayerCommand.Undo;
begin
  Scale(FTargetBounds, FSourceBounds);
end;

constructor TScreenLayoutRotateLayerCommand.Create(
  ADocument: TVectArtDocument; Layer: TVectArtLayer;
  const Center: TPointF; Degrees: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := Layer;
  FCenter := Center;
  FDegrees := Degrees;
end;

procedure TScreenLayoutRotateLayerCommand.Execute;
begin
  Rotate(FDegrees);
end;

procedure TScreenLayoutRotateLayerCommand.Rotate(Degrees: Single);
begin
  RotateScreenLayoutLayer(FLayer, FCenter, Degrees);
  FDocument.Changed;
end;

procedure TScreenLayoutRotateLayerCommand.Undo;
begin
  Rotate(-FDegrees);
end;

constructor TScreenLayoutTranslateGroupsCommand.Create(
  ADocument: TVectArtDocument; const LayerIndices: TArray<Integer>;
  DX, DY: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndices := Copy(LayerIndices);
  FDX := DX;
  FDY := DY;
end;

procedure TScreenLayoutTranslateGroupsCommand.Execute;
begin
  Translate(FDX, FDY);
end;

procedure TScreenLayoutTranslateGroupsCommand.Translate(DX, DY: Single);
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := 0 to High(FLayerIndices) do
      if (FLayerIndices[I] > 0) and
        (FLayerIndices[I] < FDocument.LayerCount) and
        (FDocument[FLayerIndices[I]] is TScreenLayoutGroupLayer) then
        TranslateScreenLayoutLayer(FDocument[FLayerIndices[I]], DX, DY);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutTranslateGroupsCommand.Undo;
begin
  Translate(-FDX, -FDY);
end;

end.
