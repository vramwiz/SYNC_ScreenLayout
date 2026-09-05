// 画面内へ埋め込む色選択UI。オブジェクトへの適用は上位側で接続する。
unit ScreenLayoutColorPickerFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics,
  Vcl.StdCtrls, ColorPickerHueBar, ColorPickerSVArea,
  HorizontalTrackBarControl, ScreenLayoutPaintStyles;

type
  TScreenLayoutColorPickerFrame = class(TFrame)
  private
    FColor: TColor;
    FColorEnabled: Boolean;
    FCurrentHue: Double;
    FHueBar: TColorPickerHueBar;
    FOnChange: TNotifyEvent;
    FOnColorGestureEnd: TNotifyEvent;
    FOnColorGestureStart: TNotifyEvent;
    FOnGradientStopSelect: TNotifyEvent;
    FOnOpacityChange: TNotifyEvent;
    FOnOpacityGestureEnd: TNotifyEvent;
    FOnOpacityGestureStart: TNotifyEvent;
    FOpacityLabel: TLabel;
    FOpacityEnabled: Boolean;
    FOpacityTrackBar: THorizontalTrackBarControl;
    FColorTargetSelector: TPaintBox;
    FGradientStop: Integer;
    FModeSelector: TPaintBox;
    FPaintModeEnabled: Boolean;
    FPaintStyle: TScreenLayoutPaintStyle;
    FOnPaintStyleChange: TNotifyEvent;
    FSVArea: TColorPickerSVArea;
    FTitleLabel: TLabel;
    FUpdating: Boolean;
    procedure HueBarChange(Sender: TObject);
    procedure ColorMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ColorMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OpacityChanged(Sender: TObject);
    procedure OpacityMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OpacityMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintColorTargetSelector(Sender: TObject);
    procedure ModeSelectorMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintModeSelector(Sender: TObject);
    procedure ColorTargetMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SetPaintStyle(const Value: TScreenLayoutPaintStyle);
    procedure SetGradientStopId(Value: Integer);
    procedure SetPaintModeEnabled(Value: Boolean);
    procedure SetSelectedColor(const Value: TColor);
    procedure SetColorEnabled(Value: Boolean);
    procedure SetTargetCaption(const Value: string);
    function GetOpacity: Integer;
    procedure SetOpacity(Value: Integer);
    procedure SetOpacityEnabled(Value: Boolean);
    procedure SVAreaChange(Sender: TObject);
    procedure SyncControls;
  protected
    procedure Resize; override;
  public
    // 色選択、選択色表示、不透明度トラックバーを埋め込み可能な状態で生成する。
    constructor Create(AOwner: TComponent); override;
    // 有効な描画モードへ切り替え、保持済みの各モード設定を復元する。
    procedure SelectPaintKind(Value: TScreenLayoutPaintKind);
    // VCLのTColor値で現在色を同期する。設定だけではOnChangeを発生させない。
    property SelectedColor: TColor read FColor write SetSelectedColor;
    property PaintStyle: TScreenLayoutPaintStyle read FPaintStyle
      write SetPaintStyle;
    // 線形グラデーションの開始点、終了点、中間点を安定したIDで指定する。
    property GradientStopId: Integer read FGradientStop write SetGradientStopId;
    // 作成スタイルなど、モード全体を変更できる対象でだけ有効にする。
    property PaintModeEnabled: Boolean read FPaintModeEnabled
      write SetPaintModeEnabled;
    // 色を持たない選択では色操作だけを無効化し、不透明度操作は独立して維持する。
    property ColorEnabled: Boolean read FColorEnabled write SetColorEnabled;
    // 選択中のオブジェクトまたはフィルターなど、現在の色適用先を見出しへ表示する。
    property TargetCaption: string write SetTargetCaption;
    // 0から100の整数で表示・編集する不透明度。
    property Opacity: Integer read GetOpacity write SetOpacity;
    property OpacityEnabled: Boolean read FOpacityEnabled
      write SetOpacityEnabled;
    // ユーザーが色を変更した時だけ発生する。
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnPaintStyleChange: TNotifyEvent read FOnPaintStyleChange
      write FOnPaintStyleChange;
    // 色相またはSVのドラッグ境界を通知し、連続変更を1件の履歴へまとめられるようにする。
    property OnColorGestureEnd: TNotifyEvent read FOnColorGestureEnd
      write FOnColorGestureEnd;
    property OnColorGestureStart: TNotifyEvent read FOnColorGestureStart
      write FOnColorGestureStart;
    property OnGradientStopSelect: TNotifyEvent read FOnGradientStopSelect
      write FOnGradientStopSelect;
    // ユーザーが不透明度を変更するたびに発生し、ドラッグ中は連続して通知する。
    property OnOpacityChange: TNotifyEvent read FOnOpacityChange
      write FOnOpacityChange;
    // ドラッグ終了を通知し、呼び出し側が連続変更を1件の履歴へ確定できるようにする。
    property OnOpacityGestureEnd: TNotifyEvent read FOnOpacityGestureEnd
      write FOnOpacityGestureEnd;
    // ドラッグ開始を通知し、呼び出し側が変更前の値を保存できるようにする。
    property OnOpacityGestureStart: TNotifyEvent read FOnOpacityGestureStart
      write FOnOpacityGestureStart;
  end;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows, ColorPickerColorMath;

{$R *.dfm}

const
  COLOR_BACKGROUND = TColor($00212121);
  COLOR_HEADER = TColor($00292929);
  COLOR_TEXT = TColor($00EEEEEE);
  COLOR_PICKER_HEIGHT = 92;
  COLOR_PICKER_MARGIN = 6;
  COLOR_SELECTOR_SIZE = 26;
  HUE_BAR_WIDTH = 16;
  PICKER_GAP = 4;
  MODE_BUTTON_SIZE = 26;
  MODE_BUTTON_GAP = 4;

constructor TScreenLayoutColorPickerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  Height := 205;

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Caption := '色';
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -12;
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.ParentColor := False;
  FTitleLabel.ParentFont := False;
  FTitleLabel.Layout := tlCenter;

  FColorTargetSelector := TPaintBox.Create(Self);
  FColorTargetSelector.Parent := Self;
  FColorTargetSelector.Hint := '塗りの色';
  FColorTargetSelector.ShowHint := True;
  FColorTargetSelector.OnPaint := PaintColorTargetSelector;
  FColorTargetSelector.OnMouseDown := ColorTargetMouseDown;

  FModeSelector := TPaintBox.Create(Self);
  FModeSelector.Parent := Self;
  FModeSelector.Hint := '単色 / グラデーション / パターン / テクスチャ';
  FModeSelector.ShowHint := True;
  FModeSelector.OnPaint := PaintModeSelector;
  FModeSelector.OnMouseDown := ModeSelectorMouseDown;

  FOpacityLabel := TLabel.Create(Self);
  FOpacityLabel.Parent := Self;
  FOpacityLabel.AutoSize := False;
  FOpacityLabel.Font.Name := 'Segoe UI';
  FOpacityLabel.Font.Height := -11;
  FOpacityLabel.Font.Color := COLOR_TEXT;
  FOpacityLabel.ParentFont := False;

  FOpacityTrackBar := THorizontalTrackBarControl.Create(Self);
  FOpacityTrackBar.Parent := Self;
  FOpacityTrackBar.BackgroundColor := COLOR_BACKGROUND;
  FOpacityTrackBar.ChannelColor := TColor($00505050);
  FOpacityTrackBar.FillColor := TColor($00D77800);
  FOpacityTrackBar.ThumbColor := TColor($00303030);
  FOpacityTrackBar.ThumbBorderColor := COLOR_TEXT;
  FOpacityTrackBar.ShowTicks := False;
  FOpacityTrackBar.SetRange(0, 100);
  FOpacityTrackBar.SmallChange := 1;
  FOpacityTrackBar.LargeChange := 10;
  FOpacityTrackBar.OnChange := OpacityChanged;
  FOpacityTrackBar.OnMouseDown := OpacityMouseDown;
  FOpacityTrackBar.OnMouseUp := OpacityMouseUp;
  FOpacityTrackBar.Position := 100;

  FHueBar := TColorPickerHueBar.Create(Self);
  FHueBar.Parent := Self;
  FHueBar.OnChange := HueBarChange;
  FHueBar.OnMouseDown := ColorMouseDown;
  FHueBar.OnMouseUp := ColorMouseUp;
  FSVArea := TColorPickerSVArea.Create(Self);
  FSVArea.Parent := Self;
  FSVArea.OnChange := SVAreaChange;
  FSVArea.OnMouseDown := ColorMouseDown;
  FSVArea.OnMouseUp := ColorMouseUp;

  FColor := clBlack;
  FPaintStyle := TScreenLayoutPaintStyle.Solid(FColor);
  FPaintModeEnabled := True;
  FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  FColorEnabled := True;
  FCurrentHue := 0;
  FOpacityEnabled := True;
  SyncControls;
end;

procedure TScreenLayoutColorPickerFrame.ColorTargetMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  BestDistance: Single;
  CandidateDistance: Single;
  Ratio: Single;
  Stop: TScreenLayoutGradientStop;
begin
  if (Button <> mbLeft) or (FPaintStyle.Kind <> slpkGradient) then
    Exit;
  Ratio := EnsureRange(X / Max(FColorTargetSelector.ClientWidth - 1, 1),
    0.0, 1.0);
  FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  BestDistance := Ratio;
  CandidateDistance := Abs(1.0 - Ratio);
  if CandidateDistance < BestDistance then
  begin
    BestDistance := CandidateDistance;
    FGradientStop := SCREEN_LAYOUT_GRADIENT_END_STOP_ID;
  end;
  for Stop in FPaintStyle.GetGradientStops do
  begin
    CandidateDistance := Abs(Stop.Offset - Ratio);
    if CandidateDistance < BestDistance then
    begin
      BestDistance := CandidateDistance;
      FGradientStop := Stop.Id;
    end;
  end;
  SetGradientStopId(FGradientStop);
  if Assigned(FOnGradientStopSelect) then
    FOnGradientStopSelect(Self);
end;

procedure TScreenLayoutColorPickerFrame.ColorMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and FColorEnabled and
    Assigned(FOnColorGestureStart) then
    FOnColorGestureStart(Self);
end;

procedure TScreenLayoutColorPickerFrame.ColorMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and Assigned(FOnColorGestureEnd) then
    FOnColorGestureEnd(Self);
end;

procedure TScreenLayoutColorPickerFrame.HueBarChange(Sender: TObject);
var
  Saturation: Double;
  Value: Double;
begin
  if FUpdating then
    Exit;
  FCurrentHue := ColorHue(FHueBar.Color);
  ColorToSv(FColor, Saturation, Value);
  FColor := HsvToColor(FCurrentHue, Saturation, Value);
  if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  SyncControls;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TScreenLayoutColorPickerFrame.GetOpacity: Integer;
begin
  Result := FOpacityTrackBar.Position;
end;

procedure TScreenLayoutColorPickerFrame.OpacityChanged(Sender: TObject);
begin
  FOpacityLabel.Caption := Format('透明度  %d%%', [FOpacityTrackBar.Position]);
  if not FUpdating and Assigned(FOnOpacityChange) then
    FOnOpacityChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.OpacityMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and FOpacityTrackBar.Enabled and
    Assigned(FOnOpacityGestureStart) then
    FOnOpacityGestureStart(Self);
end;

procedure TScreenLayoutColorPickerFrame.OpacityMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and Assigned(FOnOpacityGestureEnd) then
    FOnOpacityGestureEnd(Self);
end;

procedure TScreenLayoutColorPickerFrame.PaintColorTargetSelector(
  Sender: TObject);
var
  IconRect: TRect;
  I: Integer;
  Ratio: Single;
  SelectedOffset: Single;
  SelectorRect: TRect;
  Stop: TScreenLayoutGradientStop;
begin
  SelectorRect := FColorTargetSelector.ClientRect;
  FColorTargetSelector.Canvas.Brush.Style := bsSolid;
  FColorTargetSelector.Canvas.Brush.Color := TColor($00443820);
  FColorTargetSelector.Canvas.Pen.Color := TColor($00D77800);
  FColorTargetSelector.Canvas.Rectangle(SelectorRect);
  IconRect := SelectorRect;
  InflateRect(IconRect, -5, -5);
  if FPaintStyle.Kind = slpkGradient then
  begin
    for I := IconRect.Left to IconRect.Right - 1 do
    begin
      Ratio := (I - IconRect.Left) / Max(IconRect.Width - 1, 1);
      FColorTargetSelector.Canvas.Pen.Color :=
        FPaintStyle.GradientColorAt(Ratio);
      FColorTargetSelector.Canvas.MoveTo(I, IconRect.Top);
      FColorTargetSelector.Canvas.LineTo(I, IconRect.Bottom);
    end;
    FColorTargetSelector.Canvas.Brush.Style := bsClear;
    FColorTargetSelector.Canvas.Pen.Color := COLOR_TEXT;
    FColorTargetSelector.Canvas.Rectangle(IconRect);
    FColorTargetSelector.Canvas.Brush.Style := bsSolid;
    SelectedOffset := 0.0;
    if FGradientStop = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
      SelectedOffset := 1.0
    else
      for Stop in FPaintStyle.GetGradientStops do
        if Stop.Id = FGradientStop then
        begin
          SelectedOffset := Stop.Offset;
          Break;
        end;
    I := IconRect.Left + Round(SelectedOffset * Max(IconRect.Width - 1, 1));
    FColorTargetSelector.Canvas.Pen.Color := clWhite;
    FColorTargetSelector.Canvas.MoveTo(I, IconRect.Top);
    FColorTargetSelector.Canvas.LineTo(I, IconRect.Bottom);
  end
  else
  begin
    FColorTargetSelector.Canvas.Brush.Color := FColor;
    FColorTargetSelector.Canvas.Pen.Color := COLOR_TEXT;
    FColorTargetSelector.Canvas.Rectangle(IconRect);
  end;
end;

procedure TScreenLayoutColorPickerFrame.ModeSelectorMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ButtonSize: Integer;
  Gap: Integer;
  Index: Integer;
begin
  if (Button <> mbLeft) or not FPaintModeEnabled then
    Exit;
  ButtonSize := MulDiv(MODE_BUTTON_SIZE, CurrentPPI, 96);
  Gap := MulDiv(MODE_BUTTON_GAP, CurrentPPI, 96);
  Index := X div (ButtonSize + Gap);
  // パターンとテクスチャは入口だけ先に示し、実装までは選択させない。
  if (Index < 0) or (Index > 1) then
    Exit;
  SelectPaintKind(TScreenLayoutPaintKind(Index));
end;

procedure TScreenLayoutColorPickerFrame.SelectPaintKind(
  Value: TScreenLayoutPaintKind);
begin
  if not FPaintModeEnabled or (Value > slpkGradient) or
    (FPaintStyle.Kind = Value) then
    Exit;
  FPaintStyle.Kind := Value;
  if Value = slpkGradient then
  begin
    FPaintStyle.PrepareLinearGradient(FColor);
    FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
    SelectedColor := FPaintStyle.GradientStartColor;
  end
  else
    SelectedColor := FPaintStyle.SolidColor;
  FModeSelector.Invalidate;
  FColorTargetSelector.Invalidate;
  if Assigned(FOnPaintStyleChange) then
    FOnPaintStyleChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.PaintModeSelector(Sender: TObject);
var
  ButtonSize: Integer;
  Gap: Integer;
  I, X, J: Integer;
  R: TRect;
  C: TCanvas;
begin
  C := FModeSelector.Canvas;
  C.Brush.Color := COLOR_BACKGROUND;
  C.FillRect(FModeSelector.ClientRect);
  ButtonSize := MulDiv(MODE_BUTTON_SIZE, CurrentPPI, 96);
  Gap := MulDiv(MODE_BUTTON_GAP, CurrentPPI, 96);
  for I := 0 to 3 do
  begin
    X := I * (ButtonSize + Gap);
    R := Rect(X, 0, X + ButtonSize, ButtonSize);
    C.Brush.Color := IfThen(I = Ord(FPaintStyle.Kind),
      TColor($00443820), TColor($002E2E2E));
    C.Pen.Color := IfThen(I = Ord(FPaintStyle.Kind),
      TColor($00D77800), TColor($00585858));
    C.Rectangle(R);
    InflateRect(R, -6, -6);
    if (I >= 2) or not FPaintModeEnabled then
      C.Pen.Color := TColor($00666666)
    else
      C.Pen.Color := COLOR_TEXT;
    case I of
      0:
        begin
          C.Brush.Color := FPaintStyle.SolidColor;
          C.Rectangle(R);
        end;
      1:
        for J := R.Left to R.Right - 1 do
        begin
          C.Pen.Color := RGB(255 - MulDiv(190, J - R.Left,
            Max(R.Width - 1, 1)), 255 - MulDiv(190, J - R.Left,
            Max(R.Width - 1, 1)), 255 - MulDiv(190, J - R.Left,
            Max(R.Width - 1, 1)));
          C.MoveTo(J, R.Top);
          C.LineTo(J, R.Bottom);
        end;
      2:
        begin
          C.Brush.Style := bsClear;
          C.Rectangle(R);
          C.MoveTo(R.Left, (R.Top + R.Bottom) div 2);
          C.LineTo(R.Right, (R.Top + R.Bottom) div 2);
          C.MoveTo((R.Left + R.Right) div 2, R.Top);
          C.LineTo((R.Left + R.Right) div 2, R.Bottom);
          C.Brush.Style := bsSolid;
        end;
      3:
        begin
          C.Brush.Style := bsClear;
          C.Rectangle(R);
          C.MoveTo(R.Left, R.Bottom);
          C.LineTo((R.Left + R.Right) div 2, R.Top);
          C.LineTo(R.Right, R.Bottom);
          C.Brush.Style := bsSolid;
        end;
    end;
  end;
end;

procedure TScreenLayoutColorPickerFrame.Resize;
var
  HueWidth: Integer;
  SelectorSize: Integer;
  Margin: Integer;
  PickerGap: Integer;
  PickerHeight: Integer;
  PickerTop: Integer;
begin
  inherited Resize;
  Margin := MulDiv(COLOR_PICKER_MARGIN, CurrentPPI, 96);
  PickerGap := MulDiv(PICKER_GAP, CurrentPPI, 96);
  HueWidth := MulDiv(HUE_BAR_WIDTH, CurrentPPI, 96);
  SelectorSize := MulDiv(COLOR_SELECTOR_SIZE, CurrentPPI, 96);
  PickerHeight := Min(MulDiv(COLOR_PICKER_HEIGHT, CurrentPPI, 96),
    Max(ClientHeight - MulDiv(107, CurrentPPI, 96), 1));
  FTitleLabel.SetBounds(0, 0, ClientWidth, MulDiv(26, CurrentPPI, 96));
  FOpacityLabel.SetBounds(Margin, MulDiv(28, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(15, CurrentPPI, 96));
  FOpacityTrackBar.SetBounds(Margin, MulDiv(42, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(24, CurrentPPI, 96));
  FColorTargetSelector.SetBounds(Margin, MulDiv(72, CurrentPPI, 96),
    Max(MulDiv(72, CurrentPPI, 96), SelectorSize), SelectorSize);
  FModeSelector.SetBounds(Margin, MulDiv(106, CurrentPPI, 96),
    Min(ClientWidth - Margin * 2,
      MulDiv(MODE_BUTTON_SIZE * 4 + MODE_BUTTON_GAP * 3, CurrentPPI, 96)),
    MulDiv(MODE_BUTTON_SIZE, CurrentPPI, 96));
  PickerTop := ClientHeight - Margin - PickerHeight;
  FHueBar.SetBounds(Max(ClientWidth - Margin - HueWidth, Margin),
    PickerTop, HueWidth, PickerHeight);
  FSVArea.SetBounds(Margin, PickerTop,
    Max(FHueBar.Left - PickerGap - Margin, 1), PickerHeight);
end;

procedure TScreenLayoutColorPickerFrame.SetOpacity(Value: Integer);
begin
  FUpdating := True;
  try
    FOpacityTrackBar.Position := EnsureRange(Value, 0, 100);
    FOpacityLabel.Caption := Format('透明度  %d%%',
      [FOpacityTrackBar.Position]);
  finally
    FUpdating := False;
  end;
end;

procedure TScreenLayoutColorPickerFrame.SetColorEnabled(Value: Boolean);
begin
  FColorEnabled := Value;
  FHueBar.Enabled := Value;
  FSVArea.Enabled := Value;
  FColorTargetSelector.Enabled := Value;
  FColorTargetSelector.Invalidate;
end;

procedure TScreenLayoutColorPickerFrame.SetPaintStyle(
  const Value: TScreenLayoutPaintStyle);
begin
  FPaintStyle := Value;
  if FPaintStyle.Kind = slpkGradient then
  begin
    FPaintStyle.PrepareLinearGradient(FPaintStyle.SolidColor);
    if not FPaintStyle.GetGradientStopColor(FGradientStop, FColor) then
    begin
      FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
      FColor := FPaintStyle.GradientStartColor;
    end;
  end
  else
    FColor := FPaintStyle.SolidColor;
  SyncControls;
  FModeSelector.Invalidate;
end;

procedure TScreenLayoutColorPickerFrame.SetGradientStopId(Value: Integer);
var
  ColorValue: TColor;
begin
  if (FPaintStyle.Kind <> slpkGradient) or
    not FPaintStyle.GetGradientStopColor(Value, ColorValue) then
    Value := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  FGradientStop := Value;
  if FPaintStyle.GetGradientStopColor(FGradientStop, ColorValue) then
    SetSelectedColor(ColorValue);
  FColorTargetSelector.Invalidate;
end;

procedure TScreenLayoutColorPickerFrame.SetPaintModeEnabled(Value: Boolean);
begin
  if FPaintModeEnabled = Value then
    Exit;
  FPaintModeEnabled := Value;
  FModeSelector.Invalidate;
end;

procedure TScreenLayoutColorPickerFrame.SetTargetCaption(
  const Value: string);
begin
  FTitleLabel.Caption := Value;
end;

procedure TScreenLayoutColorPickerFrame.SetOpacityEnabled(Value: Boolean);
begin
  FOpacityEnabled := Value;
  FOpacityTrackBar.Enabled := Value;
  FOpacityLabel.Enabled := Value;
end;

procedure TScreenLayoutColorPickerFrame.SetSelectedColor(
  const Value: TColor);
var
  ColorValue: Double;
  Hue: Double;
  Saturation: Double;
begin
  FColor := ColorToRGB(Value);
  if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  ColorToHsv(FColor, Hue, Saturation, ColorValue);
  if (Saturation > 0.000001) and (ColorValue > 0) then
    FCurrentHue := Hue;
  SyncControls;
end;

procedure TScreenLayoutColorPickerFrame.SVAreaChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  FColor := FSVArea.Color;
  if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  SyncControls;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.SyncControls;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    FHueBar.Color := HsvToColor(FCurrentHue, 1, 1);
    FSVArea.BaseColor := HsvToColor(FCurrentHue, 1, 1);
    FSVArea.Color := FColor;
    FColorTargetSelector.Invalidate;
  finally
    FUpdating := False;
  end;
end;

end.
