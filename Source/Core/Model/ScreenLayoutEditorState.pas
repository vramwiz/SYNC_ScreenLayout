// 編集ツールなど、複数の編集UIが共有する一時状態を管理する。
unit ScreenLayoutEditorState;

interface

uses
  System.Classes, System.Generics.Collections, Vcl.Graphics,
  ScreenLayoutDocument;

type
  TVectArtEditorTool = (vetSelect, vetRectangleLine, vetRectangle,
    vetRoundedRectangleLine, vetRoundedRectangle,
    vetEllipseLine, vetEllipse, vetArc, vetArcShape, vetLine, vetPath,
    vetShape, vetText);

  TVectArtEditorState = class
  private
    FCurrentTool: TVectArtEditorTool;
    FLineCap: TVectArtLineCap;
    FLineStrokeColor: TColor;
    FLineMifStrokeStyle: TVectArtMifStrokeStyle;
    FLineStrokeWidth: Single;
    FNextVertexKind: TScreenLayoutVertexKind;
    FOnChanged: TNotifyEvent;
    FOpenGroup: TScreenLayoutGroupLayer;
    FOpenGroupChild: TVectArtLayer;
    FOpenGroupChildren: TList<TVectArtLayer>;
    FOpenGroupPath: TList<TScreenLayoutGroupLayer>;
    FRectangleFillColor: TColor;
    FRectangleOpacity: Single;
    procedure SetCurrentTool(const Value: TVectArtEditorTool);
    procedure SetLineCap(const Value: TVectArtLineCap);
    procedure SetLineStrokeColor(const Value: TColor);
    procedure SetLineMifStrokeStyle(const Value: TVectArtMifStrokeStyle);
    procedure SetLineStrokeWidth(const Value: Single);
    procedure SetNextVertexKind(const Value: TScreenLayoutVertexKind);
    procedure SetOpenGroup(const Value: TScreenLayoutGroupLayer);
    procedure SetOpenGroupChild(const Value: TVectArtLayer);
    procedure SetRectangleFillColor(const Value: TColor);
    procedure SetRectangleOpacity(const Value: Single);
  public
    constructor Create;
    destructor Destroy; override;
    // ツールを選択し、選択済みの組み合わせツールでは線／図形または頂点種別を切り替える。
    procedure ActivateTool(const Value: TVectArtEditorTool);
    function GetOpenGroupChildren: TArray<TVectArtLayer>;
    function IsGroupInOpenPath(Group: TScreenLayoutGroupLayer): Boolean;
    function IsOpenGroupChildSelected(Layer: TVectArtLayer): Boolean;
    // 現在のグループ直下にある子グループへ編集対象を移す。
    procedure OpenChildGroup(Value: TScreenLayoutGroupLayer);
    // Document内に実在する任意のグループまでの編集パスを復元する。
    procedure OpenGroupInDocument(Document: TVectArtDocument;
      Value: TScreenLayoutGroupLayer);
    // 最上位を1とする現在のグループ編集深度を返す。
    function OpenGroupDepth: Integer;
    // 親へ1階層戻り、最上位ではグループ編集を閉じる。
    procedure OpenParentGroup;
    // レイヤー一覧で開状態を示す最上位グループを返す。
    function RootOpenGroup: TScreenLayoutGroupLayer;
    procedure SetOpenGroupChildren(const Layers: TArray<TVectArtLayer>);
    procedure ToggleOpenGroupChild(Layer: TVectArtLayer);
    // Document変更後に編集パスと直下選択を実在する階層まで復旧する。
    procedure ValidateOpenGroupPath(Document: TVectArtDocument);
    function OpenGroupChildCount: Integer;
    property CurrentTool: TVectArtEditorTool read FCurrentTool
      write SetCurrentTool;
    property LineCap: TVectArtLineCap read FLineCap write SetLineCap;
    property LineStrokeColor: TColor read FLineStrokeColor
      write SetLineStrokeColor;
    property LineMifStrokeStyle: TVectArtMifStrokeStyle read FLineMifStrokeStyle
      write SetLineMifStrokeStyle;
    property LineStrokeWidth: Single read FLineStrokeWidth
      write SetLineStrokeWidth;
    property NextVertexKind: TScreenLayoutVertexKind read FNextVertexKind
      write SetNextVertexKind;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    // 解除せず内部編集対象として開いているグループ。所有権はDocumentが保持する。
    property OpenGroup: TScreenLayoutGroupLayer read FOpenGroup
      write SetOpenGroup;
    property OpenGroupChild: TVectArtLayer read FOpenGroupChild
      write SetOpenGroupChild;
    property RectangleFillColor: TColor read FRectangleFillColor
      write SetRectangleFillColor;
    property RectangleOpacity: Single read FRectangleOpacity
      write SetRectangleOpacity;
  end;

implementation

uses
  System.Math;

const
  DEFAULT_RECTANGLE_COLOR = TColor($00E2904A);

function FindOpenGroupPath(Layer: TVectArtLayer;
  Target: TScreenLayoutGroupLayer;
  Path: TList<TScreenLayoutGroupLayer>): Boolean;
var
  Group: TScreenLayoutGroupLayer;
  I: Integer;
begin
  Result := False;
  if not (Layer is TScreenLayoutGroupLayer) then
    Exit;
  Group := TScreenLayoutGroupLayer(Layer);
  Path.Add(Group);
  if Group = Target then
    Exit(True);
  for I := 0 to Group.ChildCount - 1 do
    if FindOpenGroupPath(Group[I], Target, Path) then
      Exit(True);
  Path.Delete(Path.Count - 1);
end;

constructor TVectArtEditorState.Create;
begin
  inherited Create;
  FOpenGroupChildren := TList<TVectArtLayer>.Create;
  FOpenGroupPath := TList<TScreenLayoutGroupLayer>.Create;
  FCurrentTool := vetSelect;
  FLineCap := vlcSquare;
  FLineStrokeColor := clBlack;
  FLineMifStrokeStyle := vssSolid;
  FLineStrokeWidth := 1.0;
  FNextVertexKind := slvkSharp;
  FRectangleFillColor := DEFAULT_RECTANGLE_COLOR;
  FRectangleOpacity := 1.0;
end;

destructor TVectArtEditorState.Destroy;
begin
  FOpenGroupPath.Free;
  FOpenGroupChildren.Free;
  inherited Destroy;
end;

function TVectArtEditorState.GetOpenGroupChildren: TArray<TVectArtLayer>;
begin
  Result := FOpenGroupChildren.ToArray;
end;

function TVectArtEditorState.IsOpenGroupChildSelected(
  Layer: TVectArtLayer): Boolean;
begin
  Result := (Layer <> nil) and (FOpenGroupChildren.IndexOf(Layer) >= 0);
end;

function TVectArtEditorState.OpenGroupChildCount: Integer;
begin
  Result := FOpenGroupChildren.Count;
end;

procedure TVectArtEditorState.OpenChildGroup(
  Value: TScreenLayoutGroupLayer);
var
  I: Integer;
begin
  if (Value = nil) or (FOpenGroup = nil) or (FOpenGroup = Value) then
    Exit;
  for I := 0 to FOpenGroup.ChildCount - 1 do
    if FOpenGroup[I] = Value then
    begin
      FOpenGroupPath.Add(Value);
      FOpenGroup := Value;
      FOpenGroupChild := nil;
      FOpenGroupChildren.Clear;
      if Assigned(FOnChanged) then
        FOnChanged(Self);
      Exit;
    end;
end;

function TVectArtEditorState.IsGroupInOpenPath(
  Group: TScreenLayoutGroupLayer): Boolean;
begin
  Result := (Group <> nil) and (FOpenGroupPath.IndexOf(Group) >= 0);
end;

procedure TVectArtEditorState.OpenGroupInDocument(
  Document: TVectArtDocument; Value: TScreenLayoutGroupLayer);
var
  Found: Boolean;
  I: Integer;
  Path: TList<TScreenLayoutGroupLayer>;
begin
  if Value = nil then
  begin
    OpenGroup := nil;
    Exit;
  end;
  Path := TList<TScreenLayoutGroupLayer>.Create;
  try
    Found := False;
    if Document <> nil then
      for I := 1 to Document.LayerCount - 1 do
        if FindOpenGroupPath(Document[I], Value, Path) then
        begin
          Found := True;
          Break;
        end;
    if not Found then
      Exit;
    FOpenGroupPath.Clear;
    FOpenGroupPath.AddRange(Path);
    FOpenGroup := Value;
    FOpenGroupChild := nil;
    FOpenGroupChildren.Clear;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
  finally
    Path.Free;
  end;
end;

function TVectArtEditorState.OpenGroupDepth: Integer;
begin
  Result := FOpenGroupPath.Count;
end;

procedure TVectArtEditorState.OpenParentGroup;
begin
  if FOpenGroupPath.Count <= 1 then
  begin
    OpenGroup := nil;
    Exit;
  end;
  FOpenGroupPath.Delete(FOpenGroupPath.Count - 1);
  FOpenGroup := FOpenGroupPath.Last;
  FOpenGroupChild := nil;
  FOpenGroupChildren.Clear;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TVectArtEditorState.RootOpenGroup: TScreenLayoutGroupLayer;
begin
  if FOpenGroupPath.Count > 0 then
    Result := FOpenGroupPath.First
  else
    Result := nil;
end;

procedure TVectArtEditorState.ValidateOpenGroupPath(
  Document: TVectArtDocument);
var
  Changed: Boolean;
  ChildIndex: Integer;
  Found: Boolean;
  I: Integer;
  Parent: TScreenLayoutGroupLayer;
  ValidCount: Integer;
begin
  Changed := False;
  ValidCount := 0;
  if (Document <> nil) and (FOpenGroupPath.Count > 0) then
    for I := 1 to Document.LayerCount - 1 do
      if Document[I] = FOpenGroupPath[0] then
      begin
        ValidCount := 1;
        Break;
      end;
  while (ValidCount > 0) and (ValidCount < FOpenGroupPath.Count) do
  begin
    Parent := FOpenGroupPath[ValidCount - 1];
    Found := False;
    for ChildIndex := 0 to Parent.ChildCount - 1 do
      if Parent[ChildIndex] = FOpenGroupPath[ValidCount] then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Break;
    Inc(ValidCount);
  end;
  while FOpenGroupPath.Count > ValidCount do
  begin
    FOpenGroupPath.Delete(FOpenGroupPath.Count - 1);
    Changed := True;
  end;
  if FOpenGroupPath.Count > 0 then
    FOpenGroup := FOpenGroupPath.Last
  else
    FOpenGroup := nil;
  for I := FOpenGroupChildren.Count - 1 downto 0 do
  begin
    Found := False;
    if FOpenGroup <> nil then
      for ChildIndex := 0 to FOpenGroup.ChildCount - 1 do
        if FOpenGroup[ChildIndex] = FOpenGroupChildren[I] then
        begin
          Found := True;
          Break;
        end;
    if not Found then
    begin
      FOpenGroupChildren.Delete(I);
      Changed := True;
    end;
  end;
  if FOpenGroupChildren.Count > 0 then
    FOpenGroupChild := FOpenGroupChildren.Last
  else if FOpenGroupChild <> nil then
  begin
    FOpenGroupChild := nil;
    Changed := True;
  end;
  if Changed and Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetOpenGroupChildren(
  const Layers: TArray<TVectArtLayer>);
var
  Layer: TVectArtLayer;
begin
  FOpenGroupChildren.Clear;
  for Layer in Layers do
    if (Layer <> nil) and (FOpenGroupChildren.IndexOf(Layer) < 0) then
      FOpenGroupChildren.Add(Layer);
  if FOpenGroupChildren.Count > 0 then
    FOpenGroupChild := FOpenGroupChildren.Last
  else
    FOpenGroupChild := nil;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.ToggleOpenGroupChild(Layer: TVectArtLayer);
var
  Index: Integer;
begin
  if Layer = nil then
    Exit;
  Index := FOpenGroupChildren.IndexOf(Layer);
  if Index >= 0 then
    FOpenGroupChildren.Delete(Index)
  else
    FOpenGroupChildren.Add(Layer);
  if FOpenGroupChildren.Count > 0 then
    FOpenGroupChild := FOpenGroupChildren.Last
  else
    FOpenGroupChild := nil;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.ActivateTool(const Value: TVectArtEditorTool);
begin
  if (Value in [vetRectangleLine, vetRectangle]) and
    (FCurrentTool in [vetRectangleLine, vetRectangle]) then
  begin
    if FCurrentTool = vetRectangleLine then
      CurrentTool := vetRectangle
    else
      CurrentTool := vetRectangleLine;
  end
  else if (Value in [vetRoundedRectangleLine, vetRoundedRectangle]) and
    (FCurrentTool in [vetRoundedRectangleLine, vetRoundedRectangle]) then
  begin
    if FCurrentTool = vetRoundedRectangleLine then
      CurrentTool := vetRoundedRectangle
    else
      CurrentTool := vetRoundedRectangleLine;
  end
  else if (Value in [vetEllipseLine, vetEllipse]) and
    (FCurrentTool in [vetEllipseLine, vetEllipse]) then
  begin
    if FCurrentTool = vetEllipseLine then
      CurrentTool := vetEllipse
    else
      CurrentTool := vetEllipseLine;
  end
  else if (Value in [vetArc, vetArcShape]) and
    (FCurrentTool in [vetArc, vetArcShape]) then
  begin
    if FCurrentTool = vetArc then
      CurrentTool := vetArcShape
    else
      CurrentTool := vetArc;
  end
  else if (Value in [vetPath, vetShape]) and (FCurrentTool = Value) then
  begin
    if FNextVertexKind = slvkSharp then
      NextVertexKind := slvkBezier
    else
      NextVertexKind := slvkSharp;
  end
  else
    CurrentTool := Value;
end;

procedure TVectArtEditorState.SetNextVertexKind(
  const Value: TScreenLayoutVertexKind);
begin
  if FNextVertexKind = Value then
    Exit;
  FNextVertexKind := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetOpenGroup(
  const Value: TScreenLayoutGroupLayer);
begin
  if FOpenGroup = Value then
    Exit;
  FOpenGroupPath.Clear;
  if Value <> nil then
    FOpenGroupPath.Add(Value);
  FOpenGroup := Value;
  FOpenGroupChild := nil;
  FOpenGroupChildren.Clear;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetOpenGroupChild(const Value: TVectArtLayer);
begin
  if (FOpenGroupChild = Value) and
    (((Value = nil) and (FOpenGroupChildren.Count = 0)) or
     ((Value <> nil) and (FOpenGroupChildren.Count = 1))) then
    Exit;
  FOpenGroupChildren.Clear;
  if Value <> nil then
    FOpenGroupChildren.Add(Value);
  FOpenGroupChild := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineCap(const Value: TVectArtLineCap);
begin
  if FLineCap = Value then
    Exit;
  FLineCap := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineStrokeColor(const Value: TColor);
begin
  if FLineStrokeColor = Value then
    Exit;
  FLineStrokeColor := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineMifStrokeStyle(
  const Value: TVectArtMifStrokeStyle);
begin
  if FLineMifStrokeStyle = Value then
    Exit;
  FLineMifStrokeStyle := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineStrokeWidth(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := Max(Value, 0.1);
  if SameValue(FLineStrokeWidth, NewValue) then
    Exit;
  FLineStrokeWidth := NewValue;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetCurrentTool(const Value: TVectArtEditorTool);
begin
  if FCurrentTool = Value then
    Exit;
  FCurrentTool := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetRectangleFillColor(const Value: TColor);
begin
  if FRectangleFillColor = Value then
    Exit;
  FRectangleFillColor := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetRectangleOpacity(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FRectangleOpacity, NewValue) then
    Exit;
  FRectangleOpacity := NewValue;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

end.
