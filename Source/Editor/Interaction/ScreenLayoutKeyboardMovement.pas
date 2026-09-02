// 選択図形のキーボード微移動とUndo履歴への登録を担当する。
unit ScreenLayoutKeyboardMovement;

interface

uses
  System.Classes, ScreenLayoutDocument, ScreenLayoutEditHistory;

// 矢印キーを選択Rectangleまたは楕円弧の移動として処理した場合にTrueを返す。
function HandleSelectionNudge(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory; Key: Word;
  Shift: TShiftState): Boolean;

implementation

uses
  System.Generics.Collections, System.Types, Winapi.Windows,
  ScreenLayoutEditCommands;

const
  NUDGE_DISTANCE       = 1;
  FAST_NUDGE_DISTANCE  = 10;

function HandleSelectionNudge(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory; Key: Word;
  Shift: TShiftState): Boolean;
var
  Distance: Single;
  DX: Single;
  DY: Single;
  I: Integer;
  Indices: TList<Integer>;
  NewBounds: TArray<TRectF>;
  OldBounds: TArray<TRectF>;
begin
  Result := False;
  if (ADocument = nil) or (AEditHistory = nil) or
    (ssCtrl in Shift) or (ssAlt in Shift) or
    not (Key in [VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN]) then
    Exit;
  Distance := NUDGE_DISTANCE;
  if ssShift in Shift then
    Distance := FAST_NUDGE_DISTANCE;
  DX := 0;
  DY := 0;
  case Key of
    VK_LEFT:  DX := -Distance;
    VK_UP:    DY := -Distance;
    VK_RIGHT: DX := Distance;
    VK_DOWN:  DY := Distance;
  end;

  Indices := TList<Integer>.Create;
  try
    for I := 1 to ADocument.LayerCount - 1 do
      if ADocument.IsLayerSelected(I) then
      begin
        // マウス移動と同様、ロックを含む選択全体は移動しない。
        if ADocument[I].Locked then
          Exit;
        if (ADocument[I] is TScreenLayoutRectangleLineLayer) or
          (ADocument[I] is TVectArtRectangleLayer) or
          (ADocument[I] is TScreenLayoutArcLayer) then
          Indices.Add(I);
      end;
    if Indices.Count = 0 then
      Exit;

    SetLength(OldBounds, Indices.Count);
    SetLength(NewBounds, Indices.Count);
    for I := 0 to Indices.Count - 1 do
    begin
      if ADocument[Indices[I]] is TScreenLayoutRectangleLineLayer then
        OldBounds[I] := TScreenLayoutRectangleLineLayer(
          ADocument[Indices[I]]).Bounds
      else if ADocument[Indices[I]] is TScreenLayoutArcLayer then
        OldBounds[I] := TScreenLayoutArcLayer(
          ADocument[Indices[I]]).Bounds
      else
        OldBounds[I] := TVectArtRectangleLayer(
          ADocument[Indices[I]]).Bounds;
      NewBounds[I] := OldBounds[I];
      NewBounds[I].Offset(DX, DY);
      if ADocument[Indices[I]] is TScreenLayoutRectangleLineLayer then
        ADocument.SetRectangleLineBounds(Indices[I], NewBounds[I])
      else if ADocument[Indices[I]] is TScreenLayoutArcLayer then
        ADocument.SetArcBounds(Indices[I], NewBounds[I])
      else
        ADocument.SetRectangleBounds(Indices[I], NewBounds[I]);
    end;
    AEditHistory.AddApplied(TVectArtBoundsCommand.Create(ADocument,
      Indices.ToArray, OldBounds, NewBounds));
    Result := True;
  finally
    Indices.Free;
  end;
end;

end.
