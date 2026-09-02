// 編集ツールなど、複数の編集UIが共有する一時状態を管理する。
unit ScreenLayoutEditorState;

interface

uses
  System.Classes, Vcl.Graphics, ScreenLayoutDocument;

type
  TVectArtEditorTool = (vetSelect, vetRectangleLine, vetRectangle,
    vetRoundedRectangleLine, vetRoundedRectangle,
    vetEllipseLine, vetEllipse, vetArc, vetArcShape, vetLine, vetPath,
    vetShape);

  TVectArtEditorState = class
  private
    FCurrentTool: TVectArtEditorTool;
    FLineCap: TVectArtLineCap;
    FLineStrokeColor: TColor;
    FLineMifStrokeStyle: TVectArtMifStrokeStyle;
    FLineStrokeWidth: Single;
    FNextVertexKind: TScreenLayoutVertexKind;
    FOnChanged: TNotifyEvent;
    FRectangleFillColor: TColor;
    FRectangleOpacity: Single;
    procedure SetCurrentTool(const Value: TVectArtEditorTool);
    procedure SetLineCap(const Value: TVectArtLineCap);
    procedure SetLineStrokeColor(const Value: TColor);
    procedure SetLineMifStrokeStyle(const Value: TVectArtMifStrokeStyle);
    procedure SetLineStrokeWidth(const Value: Single);
    procedure SetNextVertexKind(const Value: TScreenLayoutVertexKind);
    procedure SetRectangleFillColor(const Value: TColor);
    procedure SetRectangleOpacity(const Value: Single);
  public
    constructor Create;
    // ツールを選択し、選択済みの組み合わせツールでは線／図形または頂点種別を切り替える。
    procedure ActivateTool(const Value: TVectArtEditorTool);
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

constructor TVectArtEditorState.Create;
begin
  inherited Create;
  FCurrentTool := vetSelect;
  FLineCap := vlcSquare;
  FLineStrokeColor := clBlack;
  FLineMifStrokeStyle := vssSolid;
  FLineStrokeWidth := 1.0;
  FNextVertexKind := slvkSharp;
  FRectangleFillColor := DEFAULT_RECTANGLE_COLOR;
  FRectangleOpacity := 1.0;
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
