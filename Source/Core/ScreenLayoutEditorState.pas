// 編集ツールなど、複数の編集UIが共有する一時状態を管理する。
unit ScreenLayoutEditorState;

interface

uses
  System.Classes, Vcl.Graphics, ScreenLayoutDocument;

type
  TVectArtEditorTool = (vetSelect, vetRectangle, vetLine, vetPath,
    vetShape);

  TVectArtEditorState = class
  private
    FCurrentTool: TVectArtEditorTool;
    FLineCap: TVectArtLineCap;
    FLineJoin: TVectArtLineJoin;
    FLineStrokeColor: TColor;
    FLineMifStrokeStyle: TVectArtMifStrokeStyle;
    FLineStrokeWidth: Single;
    FOnChanged: TNotifyEvent;
    FPathMifAntiAlias: Boolean;
    FRectangleFillColor: TColor;
    FRectangleOpacity: Single;
    procedure SetCurrentTool(const Value: TVectArtEditorTool);
    procedure SetLineCap(const Value: TVectArtLineCap);
    procedure SetLineJoin(const Value: TVectArtLineJoin);
    procedure SetLineStrokeColor(const Value: TColor);
    procedure SetLineMifStrokeStyle(const Value: TVectArtMifStrokeStyle);
    procedure SetLineStrokeWidth(const Value: Single);
    procedure SetPathMifAntiAlias(const Value: Boolean);
    procedure SetRectangleFillColor(const Value: TColor);
    procedure SetRectangleOpacity(const Value: Single);
  public
    constructor Create;
    property CurrentTool: TVectArtEditorTool read FCurrentTool
      write SetCurrentTool;
    property LineCap: TVectArtLineCap read FLineCap write SetLineCap;
    property LineJoin: TVectArtLineJoin read FLineJoin write SetLineJoin;
    property LineStrokeColor: TColor read FLineStrokeColor
      write SetLineStrokeColor;
    property LineMifStrokeStyle: TVectArtMifStrokeStyle read FLineMifStrokeStyle
      write SetLineMifStrokeStyle;
    property LineStrokeWidth: Single read FLineStrokeWidth
      write SetLineStrokeWidth;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property PathMifAntiAlias: Boolean read FPathMifAntiAlias
      write SetPathMifAntiAlias;
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
  FLineCap := vlcButt;
  FLineJoin := vljMiter;
  FLineStrokeColor := clBlack;
  FLineMifStrokeStyle := vssSolid;
  FLineStrokeWidth := 1.0;
  FPathMifAntiAlias := True;
  FRectangleFillColor := DEFAULT_RECTANGLE_COLOR;
  FRectangleOpacity := 1.0;
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
