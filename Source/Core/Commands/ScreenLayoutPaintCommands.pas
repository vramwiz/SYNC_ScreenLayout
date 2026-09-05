// キャンバス操作と属性UIが共有する描画スタイル変更をUndo／Redo可能にする。
unit ScreenLayoutPaintCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands, ScreenLayoutPaintStyles;

type
  TScreenLayoutSetLayerPaintStyleCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FNewValue: TScreenLayoutPaintStyle;
    FOldValue: TScreenLayoutPaintStyle;
    procedure Apply(const Value: TScreenLayoutPaintStyle);
  public
    // 適用前後の描画スタイルを値として保持し、同じレイヤーへ復元できるようにする。
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      const OldValue, NewValue: TScreenLayoutPaintStyle);
    // 保存した変更後の描画スタイルを反映し、Documentへ変更を通知する。
    procedure Execute; override;
    // 保存した変更前の描画スタイルを復元し、Documentへ変更を通知する。
    procedure Undo; override;
  end;

implementation

procedure TScreenLayoutSetLayerPaintStyleCommand.Apply(
  const Value: TScreenLayoutPaintStyle);
begin
  if (FDocument = nil) or (FLayer = nil) then
    Exit;
  FLayer.PaintStyle := Value;
  FDocument.Changed;
end;

constructor TScreenLayoutSetLayerPaintStyleCommand.Create(
  Document: TVectArtDocument; Layer: TVectArtLayer;
  const OldValue, NewValue: TScreenLayoutPaintStyle);
begin
  inherited Create;
  FDocument := Document;
  FLayer := Layer;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TScreenLayoutSetLayerPaintStyleCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TScreenLayoutSetLayerPaintStyleCommand.Undo;
begin
  Apply(FOldValue);
end;

end.
