// Undo／Redo対象となるDocument編集コマンドを提供する。
unit VectArtDesignerEditCommands;

interface

uses
  System.Generics.Collections, System.Types, Vcl.Graphics,
  VectArtDesignerDocument;

type
  TVectArtLayerBooleanProperty = (vlbpVisible, vlbpLocked);

  TVectArtEditCommand = class abstract
  public
    procedure Execute; virtual; abstract;
    procedure Undo; virtual; abstract;
  end;

  TVectArtCompoundCommand = class(TVectArtEditCommand)
  private
    FCommands: TObjectList<TVectArtEditCommand>;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Command: TVectArtEditCommand);
    procedure Execute; override;
    procedure Undo; override;
    property Count: Integer read GetCount;
  end;

  TVectArtBoundsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndices: TArray<Integer>;
    FNewBounds: TArray<TRectF>;
    FOldBounds: TArray<TRectF>;
    procedure ApplyBounds(const Values: TArray<TRectF>);
  public
    constructor Create(ADocument: TVectArtDocument;
      const LayerIndices: TArray<Integer>; const OldBounds,
      NewBounds: TArray<TRectF>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtFillColorCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewColor: TColor;
    FOldColor: TColor;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldColor, NewColor: TColor);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtRotationCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Single;
    FOldValue: Single;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLinePointsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewEndPoint: TPointF;
    FNewStartPoint: TPointF;
    FOldEndPoint: TPointF;
    FOldStartPoint: TPointF;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldStartPoint, OldEndPoint, NewStartPoint,
      NewEndPoint: TPointF);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtPathPointsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewPoints: TArray<TPointF>;
    FOldPoints: TArray<TPointF>;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldPoints, NewPoints: TArray<TPointF>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtImagePointsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewPoints: TVectArtImagePoints;
    FOldPoints: TVectArtImagePoints;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      const OldPoints, NewPoints: TVectArtImagePoints);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtStrokeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewColor: TColor;
    FNewStyle: TVectArtMifStrokeStyle;
    FNewWidth: Single;
    FOldColor: TColor;
    FOldStyle: TVectArtMifStrokeStyle;
    FOldWidth: Single;
    procedure Apply(Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldColor: TColor; OldWidth: Single; OldStyle: TVectArtMifStrokeStyle;
      NewColor: TColor; NewWidth: Single; NewStyle: TVectArtMifStrokeStyle);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLineCapCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TVectArtLineCap;
    FOldValue: TVectArtLineCap;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: TVectArtLineCap);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLineMifAntiAliasCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Boolean;
    FOldValue: Boolean;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLineMifEndMarkerCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TVectArtMifLineMarker;
    FOldValue: TVectArtMifLineMarker;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: TVectArtMifLineMarker);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLineMifStartMarkerCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TVectArtMifLineMarker;
    FOldValue: TVectArtMifLineMarker;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: TVectArtMifLineMarker);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtMifLineMarkerSizeCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Single;
    FOldValue: Single;
    FMifStartMarker: Boolean;
    procedure ApplyValue(Value: Single);
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      MifStartMarker: Boolean; OldValue, NewValue: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLineJoinCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TVectArtLineJoin;
    FOldValue: TVectArtLineJoin;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: TVectArtLineJoin);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtPathLineCapCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TVectArtLineCap;
    FOldValue: TVectArtLineCap;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: TVectArtLineCap);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtPathLineJoinCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: TVectArtLineJoin;
    FOldValue: TVectArtLineJoin;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: TVectArtLineJoin);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtPathMifAntiAliasCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Boolean;
    FOldValue: Boolean;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLayerBooleanCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Boolean;
    FOldValue: Boolean;
    FPropertyKind: TVectArtLayerBooleanProperty;
    procedure ApplyValue(Value: Boolean);
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      PropertyKind: TVectArtLayerBooleanProperty; OldValue,
      NewValue: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtLayerOpacityCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayerIndex: Integer;
    FNewValue: Single;
    FOldValue: Single;
  public
    constructor Create(ADocument: TVectArtDocument; LayerIndex: Integer;
      OldValue, NewValue: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.Math;

procedure TVectArtCompoundCommand.Add(Command: TVectArtEditCommand);
begin
  if Command <> nil then FCommands.Add(Command);
end;

constructor TVectArtCompoundCommand.Create;
begin
  inherited Create;
  FCommands := TObjectList<TVectArtEditCommand>.Create(True);
end;

destructor TVectArtCompoundCommand.Destroy;
begin
  FCommands.Free;
  inherited Destroy;
end;

procedure TVectArtCompoundCommand.Execute;
var
  Command: TVectArtEditCommand;
begin
  for Command in FCommands do Command.Execute;
end;

function TVectArtCompoundCommand.GetCount: Integer;
begin
  Result := FCommands.Count;
end;

procedure TVectArtCompoundCommand.Undo;
var
  I: Integer;
begin
  for I := FCommands.Count - 1 downto 0 do FCommands[I].Undo;
end;

procedure TVectArtBoundsCommand.ApplyBounds(const Values: TArray<TRectF>);
var
  I: Integer;
begin
  if FDocument = nil then Exit;
  for I := 0 to Min(High(FLayerIndices), High(Values)) do
    FDocument.SetRectangleBounds(FLayerIndices[I], Values[I]);
end;

constructor TVectArtBoundsCommand.Create(ADocument: TVectArtDocument;
  const LayerIndices: TArray<Integer>; const OldBounds,
  NewBounds: TArray<TRectF>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndices := Copy(LayerIndices);
  FOldBounds := Copy(OldBounds);
  FNewBounds := Copy(NewBounds);
end;

procedure TVectArtBoundsCommand.Execute;
begin
  ApplyBounds(FNewBounds);
end;

procedure TVectArtBoundsCommand.Undo;
begin
  ApplyBounds(FOldBounds);
end;

constructor TVectArtFillColorCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldColor, NewColor: TColor);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldColor := OldColor;
  FNewColor := NewColor;
end;

procedure TVectArtFillColorCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  if FDocument[FLayerIndex] is TVectArtPathLayer then
    FDocument.SetPathFill(FLayerIndex, FNewColor,
      TVectArtPathLayer(FDocument[FLayerIndex]).Filled)
  else
    FDocument.SetRectangleFillColor(FLayerIndex, FNewColor);
end;

procedure TVectArtFillColorCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  if FDocument[FLayerIndex] is TVectArtPathLayer then
    FDocument.SetPathFill(FLayerIndex, FOldColor,
      TVectArtPathLayer(FDocument[FLayerIndex]).Filled)
  else
    FDocument.SetRectangleFillColor(FLayerIndex, FOldColor);
end;

constructor TVectArtRotationCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtRotationCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetRectangleRotation(FLayerIndex, FNewValue);
end;

procedure TVectArtRotationCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetRectangleRotation(FLayerIndex, FOldValue);
end;

constructor TVectArtLinePointsCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; const OldStartPoint, OldEndPoint, NewStartPoint,
  NewEndPoint: TPointF);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldStartPoint := OldStartPoint;
  FOldEndPoint := OldEndPoint;
  FNewStartPoint := NewStartPoint;
  FNewEndPoint := NewEndPoint;
end;

procedure TVectArtLinePointsCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetLinePoints(FLayerIndex, FNewStartPoint, FNewEndPoint);
end;

procedure TVectArtLinePointsCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetLinePoints(FLayerIndex, FOldStartPoint, FOldEndPoint);
end;

constructor TVectArtPathPointsCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; const OldPoints, NewPoints: TArray<TPointF>);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldPoints := Copy(OldPoints);
  FNewPoints := Copy(NewPoints);
end;

procedure TVectArtPathPointsCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetPathPoints(FLayerIndex, FNewPoints);
end;

procedure TVectArtPathPointsCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetPathPoints(FLayerIndex, FOldPoints);
end;

constructor TVectArtImagePointsCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; const OldPoints, NewPoints: TVectArtImagePoints);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldPoints := OldPoints;
  FNewPoints := NewPoints;
end;

procedure TVectArtImagePointsCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetImagePoints(FLayerIndex, FNewPoints);
end;

procedure TVectArtImagePointsCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetImagePoints(FLayerIndex, FOldPoints);
end;

procedure TVectArtStrokeCommand.Apply(Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle);
begin
  if FDocument = nil then
    Exit;
  if FDocument[FLayerIndex] is TVectArtLineLayer then
    FDocument.SetLineStroke(FLayerIndex, Color, Width, Style)
  else if FDocument[FLayerIndex] is TVectArtPathLayer then
    FDocument.SetPathStroke(FLayerIndex, Color, Width, Style)
  else
    FDocument.SetRectangleStroke(FLayerIndex, Color, Width, Style);
end;

constructor TVectArtStrokeCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldColor: TColor; OldWidth: Single;
  OldStyle: TVectArtMifStrokeStyle; NewColor: TColor; NewWidth: Single;
  NewStyle: TVectArtMifStrokeStyle);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldColor := OldColor;
  FOldWidth := OldWidth;
  FOldStyle := OldStyle;
  FNewColor := NewColor;
  FNewWidth := NewWidth;
  FNewStyle := NewStyle;
end;

procedure TVectArtStrokeCommand.Execute;
begin
  Apply(FNewColor, FNewWidth, FNewStyle);
end;

procedure TVectArtStrokeCommand.Undo;
begin
  Apply(FOldColor, FOldWidth, FOldStyle);
end;

constructor TVectArtLineCapCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: TVectArtLineCap);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLineCapCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetLineCap(FLayerIndex, FNewValue);
end;

procedure TVectArtLineCapCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetLineCap(FLayerIndex, FOldValue);
end;

constructor TVectArtLineJoinCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: TVectArtLineJoin);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

constructor TVectArtLineMifAntiAliasCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLineMifAntiAliasCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetLineMifAntiAlias(FLayerIndex, FNewValue);
end;

procedure TVectArtLineMifAntiAliasCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetLineMifAntiAlias(FLayerIndex, FOldValue);
end;

constructor TVectArtLineMifEndMarkerCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: TVectArtMifLineMarker);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLineMifEndMarkerCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetLineMifEndMarker(FLayerIndex, FNewValue);
end;

procedure TVectArtLineMifEndMarkerCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetLineMifEndMarker(FLayerIndex, FOldValue);
end;

constructor TVectArtLineMifStartMarkerCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer;
  OldValue, NewValue: TVectArtMifLineMarker);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLineMifStartMarkerCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetLineMifStartMarker(FLayerIndex, FNewValue);
end;

procedure TVectArtLineMifStartMarkerCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetLineMifStartMarker(FLayerIndex, FOldValue);
end;

procedure TVectArtMifLineMarkerSizeCommand.ApplyValue(Value: Single);
begin
  if FDocument = nil then Exit;
  if FMifStartMarker then
    FDocument.SetLineMifStartMarkerSize(FLayerIndex, Value)
  else
    FDocument.SetLineMifEndMarkerSize(FLayerIndex, Value);
end;

constructor TVectArtMifLineMarkerSizeCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; MifStartMarker: Boolean; OldValue, NewValue: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FMifStartMarker := MifStartMarker;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtMifLineMarkerSizeCommand.Execute;
begin
  ApplyValue(FNewValue);
end;

procedure TVectArtMifLineMarkerSizeCommand.Undo;
begin
  ApplyValue(FOldValue);
end;

procedure TVectArtLineJoinCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetLineJoin(FLayerIndex, FNewValue);
end;

procedure TVectArtLineJoinCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetLineJoin(FLayerIndex, FOldValue);
end;

constructor TVectArtPathLineCapCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: TVectArtLineCap);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtPathLineCapCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetPathLineCap(FLayerIndex, FNewValue);
end;

procedure TVectArtPathLineCapCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetPathLineCap(FLayerIndex, FOldValue);
end;

constructor TVectArtPathLineJoinCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: TVectArtLineJoin);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtPathLineJoinCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetPathLineJoin(FLayerIndex, FNewValue);
end;

procedure TVectArtPathLineJoinCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetPathLineJoin(FLayerIndex, FOldValue);
end;

constructor TVectArtPathMifAntiAliasCommand.Create(
  ADocument: TVectArtDocument; LayerIndex: Integer; OldValue,
  NewValue: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtPathMifAntiAliasCommand.Execute;
begin
  if FDocument <> nil then
    FDocument.SetPathMifAntiAlias(FLayerIndex, FNewValue);
end;

procedure TVectArtPathMifAntiAliasCommand.Undo;
begin
  if FDocument <> nil then
    FDocument.SetPathMifAntiAlias(FLayerIndex, FOldValue);
end;

procedure TVectArtLayerBooleanCommand.ApplyValue(Value: Boolean);
begin
  if FDocument = nil then Exit;
  case FPropertyKind of
    vlbpVisible: FDocument.SetLayerVisible(FLayerIndex, Value);
    vlbpLocked: FDocument.SetLayerLocked(FLayerIndex, Value);
  end;
end;

constructor TVectArtLayerBooleanCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; PropertyKind: TVectArtLayerBooleanProperty; OldValue,
  NewValue: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FPropertyKind := PropertyKind;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLayerBooleanCommand.Execute;
begin
  ApplyValue(FNewValue);
end;

procedure TVectArtLayerBooleanCommand.Undo;
begin
  ApplyValue(FOldValue);
end;

constructor TVectArtLayerOpacityCommand.Create(ADocument: TVectArtDocument;
  LayerIndex: Integer; OldValue, NewValue: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndex := LayerIndex;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TVectArtLayerOpacityCommand.Execute;
begin
  if FDocument <> nil then FDocument.SetLayerOpacity(FLayerIndex, FNewValue);
end;

procedure TVectArtLayerOpacityCommand.Undo;
begin
  if FDocument <> nil then FDocument.SetLayerOpacity(FLayerIndex, FOldValue);
end;

end.
