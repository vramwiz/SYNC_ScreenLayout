// 編集ツールなど、複数の編集UIが共有する一時状態を管理する。
// 現在の線装飾初期値はMIF互換用とし、標準モード用の状態とは名前で区別する。
unit VectArtDesignerEditorState;

interface

uses
  System.Classes, Vcl.Graphics, VectArtDesignerDocument;

type
  TVectArtEditorTool = (vetSelect, vetRectangle, vetLine, vetPath);

  TVectArtEditorState = class
  private
    FLineMifAntiAlias: Boolean;
    FLineMifEndMarker: TVectArtMifLineMarker;
    FLineMifEndMarkerSize: Single;
    FLineMifStartMarker: TVectArtMifLineMarker;
    FLineMifStartMarkerSize: Single;
    FCurrentTool: TVectArtEditorTool;
    FLineCap: TVectArtLineCap;
    FLineJoin: TVectArtLineJoin;
    FLineStrokeColor: TColor;
    FLineMifStrokeStyle: TVectArtMifStrokeStyle;
    FLineStrokeWidth: Single;
    FOnChanged: TNotifyEvent;
    FPathLineCap: TVectArtLineCap;
    FPathLineJoin: TVectArtLineJoin;
    FPathMifAntiAlias: Boolean;
    FRectangleFillColor: TColor;
    FRectangleOpacity: Single;
    FRectangleStrokeColor: TColor;
    FRectangleMifStrokeStyle: TVectArtMifStrokeStyle;
    FRectangleStrokeWidth: Single;
    procedure SetCurrentTool(const Value: TVectArtEditorTool);
    procedure SetLineCap(const Value: TVectArtLineCap);
    procedure SetLineMifAntiAlias(const Value: Boolean);
    procedure SetLineMifEndMarker(const Value: TVectArtMifLineMarker);
    procedure SetLineMifEndMarkerSize(const Value: Single);
    procedure SetLineMifStartMarker(const Value: TVectArtMifLineMarker);
    procedure SetLineMifStartMarkerSize(const Value: Single);
    procedure SetLineJoin(const Value: TVectArtLineJoin);
    procedure SetLineStrokeColor(const Value: TColor);
    procedure SetLineMifStrokeStyle(const Value: TVectArtMifStrokeStyle);
    procedure SetLineStrokeWidth(const Value: Single);
    procedure SetPathLineCap(const Value: TVectArtLineCap);
    procedure SetPathLineJoin(const Value: TVectArtLineJoin);
    procedure SetPathMifAntiAlias(const Value: Boolean);
    procedure SetRectangleFillColor(const Value: TColor);
    procedure SetRectangleOpacity(const Value: Single);
    procedure SetRectangleStrokeColor(const Value: TColor);
    procedure SetRectangleMifStrokeStyle(const Value: TVectArtMifStrokeStyle);
    procedure SetRectangleStrokeWidth(const Value: Single);
  public
    constructor Create;
    property CurrentTool: TVectArtEditorTool read FCurrentTool
      write SetCurrentTool;
    property LineCap: TVectArtLineCap read FLineCap write SetLineCap;
    property LineMifAntiAlias: Boolean read FLineMifAntiAlias write SetLineMifAntiAlias;
    property LineMifEndMarker: TVectArtMifLineMarker read FLineMifEndMarker
      write SetLineMifEndMarker;
    property LineMifEndMarkerSize: Single read FLineMifEndMarkerSize
      write SetLineMifEndMarkerSize;
    property LineMifStartMarker: TVectArtMifLineMarker read FLineMifStartMarker
      write SetLineMifStartMarker;
    property LineMifStartMarkerSize: Single read FLineMifStartMarkerSize
      write SetLineMifStartMarkerSize;
    property LineJoin: TVectArtLineJoin read FLineJoin write SetLineJoin;
    property LineStrokeColor: TColor read FLineStrokeColor
      write SetLineStrokeColor;
    property LineMifStrokeStyle: TVectArtMifStrokeStyle read FLineMifStrokeStyle
      write SetLineMifStrokeStyle;
    property LineStrokeWidth: Single read FLineStrokeWidth
      write SetLineStrokeWidth;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property PathLineCap: TVectArtLineCap read FPathLineCap write SetPathLineCap;
    property PathLineJoin: TVectArtLineJoin read FPathLineJoin write SetPathLineJoin;
    property PathMifAntiAlias: Boolean read FPathMifAntiAlias
      write SetPathMifAntiAlias;
    property RectangleFillColor: TColor read FRectangleFillColor
      write SetRectangleFillColor;
    property RectangleOpacity: Single read FRectangleOpacity
      write SetRectangleOpacity;
    property RectangleStrokeColor: TColor read FRectangleStrokeColor
      write SetRectangleStrokeColor;
    property RectangleMifStrokeStyle: TVectArtMifStrokeStyle
      read FRectangleMifStrokeStyle write SetRectangleMifStrokeStyle;
    property RectangleStrokeWidth: Single read FRectangleStrokeWidth
      write SetRectangleStrokeWidth;
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
  FLineMifAntiAlias := True;
  FLineMifEndMarker := vlmNone;
  FLineMifEndMarkerSize := 4.0;
  FLineMifStartMarker := vlmNone;
  FLineMifStartMarkerSize := 4.0;
  FLineCap := vlcButt;
  FLineJoin := vljMiter;
  FLineStrokeColor := clBlack;
  FLineMifStrokeStyle := vssSolid;
  FLineStrokeWidth := 1.0;
  FPathLineCap := vlcButt;
  FPathLineJoin := vljMiter;
  FPathMifAntiAlias := True;
  FRectangleFillColor := DEFAULT_RECTANGLE_COLOR;
  FRectangleOpacity := 1.0;
  FRectangleStrokeColor := clBlack;
  FRectangleMifStrokeStyle := vssSolid;
  FRectangleStrokeWidth := 0.0;
end;

procedure TVectArtEditorState.SetPathLineCap(const Value: TVectArtLineCap);
begin
  if FPathLineCap = Value then
    Exit;
  FPathLineCap := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetPathLineJoin(const Value: TVectArtLineJoin);
begin
  if FPathLineJoin = Value then
    Exit;
  FPathLineJoin := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetPathMifAntiAlias(const Value: Boolean);
begin
  if FPathMifAntiAlias = Value then
    Exit;
  FPathMifAntiAlias := Value;
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

procedure TVectArtEditorState.SetLineMifAntiAlias(const Value: Boolean);
begin
  if FLineMifAntiAlias = Value then
    Exit;
  FLineMifAntiAlias := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineMifEndMarker(
  const Value: TVectArtMifLineMarker);
begin
  if FLineMifEndMarker = Value then
    Exit;
  FLineMifEndMarker := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineMifEndMarkerSize(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := Max(Value, 1.0);
  if SameValue(FLineMifEndMarkerSize, NewValue) then Exit;
  FLineMifEndMarkerSize := NewValue;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineMifStartMarker(
  const Value: TVectArtMifLineMarker);
begin
  if FLineMifStartMarker = Value then
    Exit;
  FLineMifStartMarker := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineMifStartMarkerSize(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := Max(Value, 1.0);
  if SameValue(FLineMifStartMarkerSize, NewValue) then Exit;
  FLineMifStartMarkerSize := NewValue;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TVectArtEditorState.SetLineJoin(const Value: TVectArtLineJoin);
begin
  if FLineJoin = Value then
    Exit;
  FLineJoin := Value;
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

procedure TVectArtEditorState.SetRectangleStrokeColor(const Value: TColor);
begin
  if FRectangleStrokeColor = Value then
    Exit;
  FRectangleStrokeColor := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetRectangleMifStrokeStyle(
  const Value: TVectArtMifStrokeStyle);
begin
  if FRectangleMifStrokeStyle = Value then
    Exit;
  FRectangleMifStrokeStyle := Value;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtEditorState.SetRectangleStrokeWidth(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := Max(Value, 0.0);
  if SameValue(FRectangleStrokeWidth, NewValue) then
    Exit;
  FRectangleStrokeWidth := NewValue;
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
