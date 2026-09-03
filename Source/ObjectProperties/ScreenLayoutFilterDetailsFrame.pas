// Edits the parameters of one selected filter in the fixed lower UI area.
unit ScreenLayoutFilterDetailsFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.StdCtrls, ScreenLayoutContext, ScreenLayoutDocument,
  ScreenLayoutFilters;

type
  TScreenLayoutFilterDetailsFrame = class(TFrame)
  private
    FColorDialog: TColorDialog;
    FColorPanel: TPanel;
    FContext: IVectArtDesignerContext;
    FEdits: array[0..5] of TEdit;
    FFilter: TScreenLayoutFilter;
    FLabels: array[0..5] of TLabel;
    FLayer: TVectArtLayer;
    FOnChanged: TNotifyEvent;
    FRefreshing: Boolean;
    FTitleLabel: TLabel;
    procedure ColorPanelClick(Sender: TObject);
    procedure EditExit(Sender: TObject);
    procedure SetContext(const Value: IVectArtDesignerContext);
    procedure SetFilter(Layer: TVectArtLayer;
      Filter: TScreenLayoutFilter);
    procedure SetRow(Index: Integer; const Caption, Value: string;
      Visible: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    // Rebuilds the visible rows from the current filter kind and values.
    procedure Refresh;
    // Selects the layer/filter pair edited by this frame; neither is owned.
    procedure SelectFilter(Layer: TVectArtLayer;
      Filter: TScreenLayoutFilter);
    property Context: IVectArtDesignerContext read FContext write SetContext;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math, System.SysUtils, Vcl.Graphics, Winapi.Windows,
  ScreenLayoutFilterCommands;

{$R ScreenLayoutFilterDetailsFrame.dfm}

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_DISABLED   = TColor($00606060);
  COLOR_HEADER     = TColor($00292929);
  COLOR_TEXT       = TColor($00EEEEEE);
  EDIT_LEFT        = 82;
  EDIT_WIDTH       = 70;
  ROW_HEIGHT       = 26;
  TITLE_HEIGHT     = 28;

constructor TScreenLayoutFilterDetailsFrame.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.Align := alTop;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Height := MulDiv(TITLE_HEIGHT, CurrentPPI, 96);
  FTitleLabel.Caption := 'Filter settings';
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -12;
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.Layout := tlCenter;
  FTitleLabel.ParentColor := False;
  FTitleLabel.Margins.Left := MulDiv(8, CurrentPPI, 96);
  FTitleLabel.AlignWithMargins := True;

  for I := 0 to High(FEdits) do
  begin
    FLabels[I] := TLabel.Create(Self);
    FLabels[I].Parent := Self;
    FLabels[I].SetBounds(MulDiv(7, CurrentPPI, 96),
      MulDiv(TITLE_HEIGHT + I * ROW_HEIGHT + 5, CurrentPPI, 96),
      MulDiv(72, CurrentPPI, 96), MulDiv(21, CurrentPPI, 96));
    FLabels[I].Font.Name := 'Segoe UI';
    FLabels[I].Font.Height := -12;
    FLabels[I].Font.Color := COLOR_TEXT;

    FEdits[I] := TEdit.Create(Self);
    FEdits[I].Parent := Self;
    FEdits[I].SetBounds(MulDiv(EDIT_LEFT, CurrentPPI, 96),
      MulDiv(TITLE_HEIGHT + I * ROW_HEIGHT + 1, CurrentPPI, 96),
      MulDiv(EDIT_WIDTH, CurrentPPI, 96), MulDiv(23, CurrentPPI, 96));
    FEdits[I].Color := COLOR_HEADER;
    FEdits[I].Font.Name := 'Segoe UI';
    FEdits[I].Font.Height := -12;
    FEdits[I].Font.Color := COLOR_TEXT;
    FEdits[I].Tag := I;
    FEdits[I].OnExit := EditExit;
  end;

  FColorPanel := TPanel.Create(Self);
  FColorPanel.Parent := Self;
  FColorPanel.BevelOuter := bvLowered;
  FColorPanel.Caption := '';
  FColorPanel.ParentBackground := False;
  FColorPanel.OnClick := ColorPanelClick;
  FColorDialog := TColorDialog.Create(Self);
  Refresh;
end;

procedure TScreenLayoutFilterDetailsFrame.ColorPanelClick(Sender: TObject);
var
  Command: TScreenLayoutSetFilterParametersCommand;
  NewValue: TScreenLayoutFilter;
  OldValue: TScreenLayoutFilter;
begin
  if FRefreshing or (FContext = nil) or (FFilter = nil) or
    (FLayer = nil) or FLayer.Locked or
    not (FFilter is TScreenLayoutOutlineFilter) and
    not (FFilter is TScreenLayoutShadowFilter) then
    Exit;
  if FFilter is TScreenLayoutOutlineFilter then
    FColorDialog.Color := TScreenLayoutOutlineFilter(FFilter).Color
  else
    FColorDialog.Color := TScreenLayoutShadowFilter(FFilter).Color;
  if not FColorDialog.Execute then
    Exit;
  OldValue := FFilter.Clone;
  NewValue := FFilter.Clone;
  try
    if NewValue is TScreenLayoutOutlineFilter then
      TScreenLayoutOutlineFilter(NewValue).Color := FColorDialog.Color
    else
      TScreenLayoutShadowFilter(NewValue).Color := FColorDialog.Color;
    Command := TScreenLayoutSetFilterParametersCommand.Create(
      FContext.Document, FFilter, OldValue, NewValue);
    Command.Execute;
    if (FContext <> nil) and (FContext.EditHistory <> nil) then
      FContext.EditHistory.AddApplied(Command)
    else
      Command.Free;
  finally
    NewValue.Free;
    OldValue.Free;
  end;
  Refresh;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TScreenLayoutFilterDetailsFrame.EditExit(Sender: TObject);
var
  Changed: Boolean;
  Command: TScreenLayoutSetFilterParametersCommand;
  Edit: TEdit;
  NewValue: TScreenLayoutFilter;
  OldNumber: Single;
  OldValue: TScreenLayoutFilter;
  Value: Single;
begin
  if FRefreshing or not (Sender is TEdit) or (FFilter = nil) or
    (FLayer = nil) or FLayer.Locked or (FContext = nil) or
    not TryStrToFloat(TEdit(Sender).Text, Value) then
  begin
    Refresh;
    Exit;
  end;
  Edit := TEdit(Sender);
  OldValue := FFilter.Clone;
  NewValue := FFilter.Clone;
  OldNumber := Value;
  try
    case FFilter.Kind of
      slfkShadow:
        case Edit.Tag of
          0:
          begin
            OldNumber := TScreenLayoutShadowFilter(FFilter).Opacity * 100.0;
            Value := EnsureRange(Value, 0.0, 100.0);
            TScreenLayoutShadowFilter(NewValue).Opacity := Value / 100.0;
          end;
        else
          OldNumber := Value;
        end;
      slfkBlur:
      begin
        OldNumber := TScreenLayoutBlurFilter(FFilter).Radius;
        Value := EnsureRange(Value, 0.0, 500.0);
        TScreenLayoutBlurFilter(NewValue).Radius := Value;
      end;
    end;
    Changed := not SameValue(OldNumber, Value);
    if Changed then
    begin
      Command := TScreenLayoutSetFilterParametersCommand.Create(
        FContext.Document, FFilter, OldValue, NewValue);
      Command.Execute;
      if FContext.EditHistory <> nil then
        FContext.EditHistory.AddApplied(Command)
      else
        Command.Free;
    end;
  finally
    NewValue.Free;
    OldValue.Free;
  end;
  Refresh;
  if Changed and Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TScreenLayoutFilterDetailsFrame.Refresh;
var
  ColorRow: Integer;
  Editable: Boolean;
  I: Integer;
begin
  if FRefreshing then
    Exit;
  FRefreshing := True;
  try
    for I := 0 to High(FEdits) do
      SetRow(I, '', '', False);
    FTitleLabel.Caption := 'Filter settings';
    FColorPanel.Visible := False;
    if FFilter = nil then
      Exit;
    FTitleLabel.Caption := 'Filter settings: ' + FFilter.DisplayName;
    Editable := (FLayer <> nil) and not FLayer.Locked;
    case FFilter.Kind of
      slfkOutline:
      begin
        FColorPanel.Color := TScreenLayoutOutlineFilter(FFilter).Color;
        ColorRow := 0;
      end;
      slfkShadow:
      begin
        SetRow(0, 'Opacity', FormatFloat('0.##',
          TScreenLayoutShadowFilter(FFilter).Opacity * 100.0), True);
        FColorPanel.Color := TScreenLayoutShadowFilter(FFilter).Color;
        ColorRow := 1;
      end;
      slfkBlur:
        ColorRow := -1;
    else
      ColorRow := -1;
    end;
    for I := 0 to High(FEdits) do
      FEdits[I].Enabled := Editable and FEdits[I].Visible;
    if ColorRow >= 0 then
    begin
      FLabels[ColorRow].Caption := 'Color';
      FLabels[ColorRow].Visible := True;
      FColorPanel.SetBounds(MulDiv(EDIT_LEFT, CurrentPPI, 96),
        MulDiv(TITLE_HEIGHT + ColorRow * ROW_HEIGHT + 2, CurrentPPI, 96),
        MulDiv(EDIT_WIDTH, CurrentPPI, 96), MulDiv(21, CurrentPPI, 96));
      FColorPanel.Enabled := Editable;
      FColorPanel.Visible := True;
    end;
  finally
    FRefreshing := False;
  end;
end;

procedure TScreenLayoutFilterDetailsFrame.SelectFilter(
  Layer: TVectArtLayer; Filter: TScreenLayoutFilter);
begin
  SetFilter(Layer, Filter);
end;

procedure TScreenLayoutFilterDetailsFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  Refresh;
end;

procedure TScreenLayoutFilterDetailsFrame.SetFilter(Layer: TVectArtLayer;
  Filter: TScreenLayoutFilter);
begin
  FLayer := Layer;
  FFilter := Filter;
  Refresh;
end;

procedure TScreenLayoutFilterDetailsFrame.SetRow(Index: Integer;
  const Caption, Value: string; Visible: Boolean);
begin
  FLabels[Index].Caption := Caption;
  FLabels[Index].Visible := Visible;
  FEdits[Index].Text := Value;
  FEdits[Index].Visible := Visible;
end;

end.
