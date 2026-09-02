// 多くのオブジェクトで共通利用する位置・サイズ設定フレーム。
unit ScreenLayoutGeometryPropertiesFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  ScreenLayoutDocument, ScreenLayoutEditHistory, ScreenLayoutEditorState;

type
  TScreenLayoutGeometryPropertiesFrame = class(TFrame)
  private
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    FHeightEdit: TEdit;
    FHeightLabel: TLabel;
    FTitleLabel: TLabel;
    FUpdating: Boolean;
    FWidthEdit: TEdit;
    FWidthLabel: TLabel;
    FXEdit: TEdit;
    FXLabel: TLabel;
    FYEdit: TEdit;
    FYLabel: TLabel;
    procedure ApplyGeometry;
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    function NewDarkEdit: TEdit;
    function NewFieldLabel(const Caption: string): TLabel;
    function SelectedGeometry(out Layers: TArray<TVectArtLayer>;
      out Bounds: TRectF; out Locked: Boolean): Boolean;
    procedure SetDocument(const Value: TVectArtDocument);
    procedure SetEditorState(const Value: TVectArtEditorState);
    procedure SetInputsEnabled(Value: Boolean; SizeEnabled: Boolean);
  protected
    procedure Resize; override;
  public
    // 座標とサイズの共通入力欄を生成し、選択型に応じた表示名へ切り替える。
    constructor Create(AOwner: TComponent); override;
    // 現在選択の外接範囲とロック状態を入力欄へ反映する。
    procedure RefreshFromDocument;
    // 各サービスは非所有参照であり、呼び出し側がFrameより長い寿命を保証する。
    property Document: TVectArtDocument read FDocument write SetDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write SetEditorState;
  end;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils, Winapi.Windows,
  Vcl.Graphics, ScreenLayoutEditCommands, ScreenLayoutGroupTransformCommands,
  ScreenLayoutLayerGeometry;

{$R *.dfm}

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_EDIT = TColor($00303030);
  COLOR_HEADER = TColor($00292929);
  COLOR_LABEL = TColor($00BDBDBD);
  COLOR_TEXT = TColor($00EEEEEE);
  EDIT_HEIGHT = 25;
  MIN_OBJECT_SIZE = 1.0;

constructor TScreenLayoutGeometryPropertiesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  Height := 145;

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Caption := 'Position and Size';
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -13;
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.ParentColor := False;
  FTitleLabel.ParentFont := False;
  FTitleLabel.Layout := tlCenter;

  FXLabel := NewFieldLabel('X');
  FYLabel := NewFieldLabel('Y');
  FWidthLabel := NewFieldLabel('Width');
  FHeightLabel := NewFieldLabel('Height');
  FXEdit := NewDarkEdit;
  FYEdit := NewDarkEdit;
  FWidthEdit := NewDarkEdit;
  FHeightEdit := NewDarkEdit;
  SetInputsEnabled(False, False);
end;

procedure TScreenLayoutGeometryPropertiesFrame.ApplyGeometry;
var
  Bounds: TRectF;
  Command: TVectArtCompoundCommand;
  DegenerateSize: Boolean;
  DX: Single;
  DY: Single;
  HeightValue: Double;
  I: Integer;
  Layers: TArray<TVectArtLayer>;
  Locked: Boolean;
  NewBounds: TRectF;
  WidthValue: Double;
  XValue: Double;
  YValue: Double;
begin
  if FUpdating or not SelectedGeometry(Layers, Bounds, Locked) or Locked then
    Exit;
  if not TryStrToFloat(Trim(FXEdit.Text), XValue) or
    not TryStrToFloat(Trim(FYEdit.Text), YValue) or
    not TryStrToFloat(Trim(FWidthEdit.Text), WidthValue) or
    not TryStrToFloat(Trim(FHeightEdit.Text), HeightValue) then
  begin
    RefreshFromDocument;
    Exit;
  end;

  DegenerateSize := (Bounds.Width <= 0.0001) or
    (Bounds.Height <= 0.0001);
  DX := XValue - Bounds.CenterPoint.X;
  DY := YValue - Bounds.CenterPoint.Y;
  if DegenerateSize then
  begin
    if SameValue(DX, 0.0) and SameValue(DY, 0.0) then
      Exit;
  end
  else
  begin
    WidthValue := Max(WidthValue, MIN_OBJECT_SIZE);
    HeightValue := Max(HeightValue, MIN_OBJECT_SIZE);
    NewBounds := TRectF.Create(XValue - WidthValue * 0.5,
      YValue - HeightValue * 0.5, XValue + WidthValue * 0.5,
      YValue + HeightValue * 0.5);
    if SameValue(Bounds.Left, NewBounds.Left) and
      SameValue(Bounds.Top, NewBounds.Top) and
      SameValue(Bounds.Right, NewBounds.Right) and
      SameValue(Bounds.Bottom, NewBounds.Bottom) then
      Exit;
  end;

  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  FDocument.BeginUpdate;
  try
    for I := 0 to High(Layers) do
      if DegenerateSize then
      begin
        TranslateScreenLayoutLayer(Layers[I], DX, DY);
        if Command <> nil then
          Command.Add(TScreenLayoutTranslateLayerCommand.Create(FDocument,
            Layers[I], DX, DY));
      end
      else
      begin
        ScaleScreenLayoutLayer(Layers[I], Bounds, NewBounds);
        if Command <> nil then
          Command.Add(TScreenLayoutScaleLayerCommand.Create(FDocument,
            Layers[I], Bounds, NewBounds));
      end;
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
  RefreshFromDocument;
end;

procedure TScreenLayoutGeometryPropertiesFrame.EditExit(Sender: TObject);
begin
  ApplyGeometry;
end;

procedure TScreenLayoutGeometryPropertiesFrame.EditKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    ApplyGeometry;
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    RefreshFromDocument;
    Key := 0;
  end;
end;

function TScreenLayoutGeometryPropertiesFrame.NewDarkEdit: TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.AutoSize := False;
  Result.Height := EDIT_HEIGHT;
  Result.Color := COLOR_EDIT;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -12;
  Result.Font.Color := COLOR_TEXT;
  Result.ParentColor := False;
  Result.ParentFont := False;
  Result.OnExit := EditExit;
  Result.OnKeyDown := EditKeyDown;
end;

function TScreenLayoutGeometryPropertiesFrame.NewFieldLabel(
  const Caption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := Caption;
  Result.Font.Name := 'Segoe UI';
  Result.Font.Height := -12;
  Result.Font.Color := COLOR_LABEL;
  Result.ParentFont := False;
end;

procedure TScreenLayoutGeometryPropertiesFrame.RefreshFromDocument;
var
  Bounds: TRectF;
  Layers: TArray<TVectArtLayer>;
  Locked: Boolean;
  SizeEnabled: Boolean;
begin
  FUpdating := True;
  try
    if SelectedGeometry(Layers, Bounds, Locked) then
    begin
      FXEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.X);
      FYEdit.Text := FormatFloat('0.##', Bounds.CenterPoint.Y);
      FWidthEdit.Text := FormatFloat('0.##', Bounds.Width);
      FHeightEdit.Text := FormatFloat('0.##', Bounds.Height);
      SizeEnabled := (Bounds.Width > 0.0001) and
        (Bounds.Height > 0.0001);
      SetInputsEnabled(not Locked, not Locked and SizeEnabled);
    end
    else
    begin
      FXEdit.Text := '';
      FYEdit.Text := '';
      FWidthEdit.Text := '';
      FHeightEdit.Text := '';
      SetInputsEnabled(False, False);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TScreenLayoutGeometryPropertiesFrame.Resize;
var
  ColumnWidth: Integer;
  RightColumn: Integer;
begin
  inherited Resize;
  FTitleLabel.SetBounds(0, 0, ClientWidth, 32);
  ColumnWidth := Max((ClientWidth - 36) div 2, 48);
  RightColumn := (ClientWidth div 2) + 4;
  FXLabel.SetBounds(12, 42, ColumnWidth, 17);
  FYLabel.SetBounds(RightColumn, 42, ColumnWidth, 17);
  FXEdit.SetBounds(12, 59, ColumnWidth, EDIT_HEIGHT);
  FYEdit.SetBounds(RightColumn, 59, ColumnWidth, EDIT_HEIGHT);
  FWidthLabel.SetBounds(12, 91, ColumnWidth, 17);
  FHeightLabel.SetBounds(RightColumn, 91, ColumnWidth, 17);
  FWidthEdit.SetBounds(12, 108, ColumnWidth, EDIT_HEIGHT);
  FHeightEdit.SetBounds(RightColumn, 108, ColumnWidth, EDIT_HEIGHT);
end;

function TScreenLayoutGeometryPropertiesFrame.SelectedGeometry(
  out Layers: TArray<TVectArtLayer>; out Bounds: TRectF;
  out Locked: Boolean): Boolean;
var
  CandidateBounds: TRectF;
  I: Integer;
  Layer: TVectArtLayer;
  LayerList: TList<TVectArtLayer>;
begin
  Result := False;
  Locked := False;
  Bounds := TRectF.Empty;
  Layers := nil;
  if FDocument = nil then
    Exit;
  LayerList := TList<TVectArtLayer>.Create;
  try
    if (FEditorState <> nil) and
      (FEditorState.OpenGroupChildCount = 1) and
      (FEditorState.OpenGroupChild <> nil) then
    begin
      Layer := FEditorState.OpenGroupChild;
      if TryGetScreenLayoutLayerBounds(Layer, CandidateBounds) then
      begin
        LayerList.Add(Layer);
        Bounds := CandidateBounds;
        Locked := Layer.Locked;
        Result := True;
      end;
    end
    else
      for I := 1 to FDocument.LayerCount - 1 do
        if FDocument.IsLayerSelected(I) then
        begin
          Layer := FDocument[I];
          if not TryGetScreenLayoutLayerBounds(Layer, CandidateBounds) then
            Continue;
          LayerList.Add(Layer);
          Locked := Locked or Layer.Locked;
          if not Result then
            Bounds := CandidateBounds
          else
          begin
            Bounds.Left := Min(Bounds.Left, CandidateBounds.Left);
            Bounds.Top := Min(Bounds.Top, CandidateBounds.Top);
            Bounds.Right := Max(Bounds.Right, CandidateBounds.Right);
            Bounds.Bottom := Max(Bounds.Bottom, CandidateBounds.Bottom);
          end;
          Result := True;
        end;
    Layers := LayerList.ToArray;
  finally
    LayerList.Free;
  end;
end;

procedure TScreenLayoutGeometryPropertiesFrame.SetDocument(
  const Value: TVectArtDocument);
begin
  if FDocument = Value then
    Exit;
  FDocument := Value;
  RefreshFromDocument;
end;

procedure TScreenLayoutGeometryPropertiesFrame.SetEditorState(
  const Value: TVectArtEditorState);
begin
  if FEditorState = Value then
    Exit;
  FEditorState := Value;
  RefreshFromDocument;
end;

procedure TScreenLayoutGeometryPropertiesFrame.SetInputsEnabled(
  Value, SizeEnabled: Boolean);
begin
  FXEdit.Enabled := Value;
  FYEdit.Enabled := Value;
  FWidthEdit.Enabled := SizeEnabled;
  FHeightEdit.Enabled := SizeEnabled;
end;

end.
