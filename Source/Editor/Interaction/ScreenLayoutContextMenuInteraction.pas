// 右クリック位置のレイヤーまたは開いたグループ内の子を、コンテキストメニュー対象として選択する。
// メニューの生成と表示、および通常の左クリック選択やドラッグ操作は担当しない。
unit ScreenLayoutContextMenuInteraction;

interface

uses
  System.Types, ScreenLayoutDocument, ScreenLayoutEditorState;

// HitLayerIndexと論理座標の当たり先を選択へ反映し、メニューを表示できる対象があればTrueを返す。
// 既存の複数選択内を右クリックした場合は選択を維持し、未選択対象だけを単一選択へ切り替える。
function SelectScreenLayoutContextMenuTarget(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; HitLayerIndex: Integer;
  const LogicalPoint: TPointF; LogicalPointValid: Boolean): Boolean;

implementation

uses
  ScreenLayoutGroupInteraction;

function SelectScreenLayoutContextMenuTarget(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; HitLayerIndex: Integer;
  const LogicalPoint: TPointF; LogicalPointValid: Boolean): Boolean;
var
  GroupChild: TVectArtLayer;
begin
  Result := False;
  if Document = nil then
    Exit;
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) and
    LogicalPointValid then
  begin
    GroupChild := HitTestGroupChild(EditorState.OpenGroup, LogicalPoint);
    if GroupChild <> nil then
    begin
      if not EditorState.IsOpenGroupChildSelected(GroupChild) then
        EditorState.OpenGroupChild := GroupChild;
      Document.SetSelectedLayers([]);
      Exit(True);
    end;
  end;
  if HitLayerIndex <= 0 then
    Exit;
  if not Document.IsLayerSelected(HitLayerIndex) then
    Document.SelectedIndex := HitLayerIndex;
  Result := True;
end;

end.
