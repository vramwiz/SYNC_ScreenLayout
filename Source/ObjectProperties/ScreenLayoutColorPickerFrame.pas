// 画面内へ埋め込む色選択UI。オブジェクトへの適用は上位側で接続する。
unit ScreenLayoutColorPickerFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics,
  Vcl.StdCtrls, ColorPickerHueBar, ColorPickerSVArea,
  HorizontalTrackBarControl;

type
  TScreenLayoutColorPickerFrame = class(TFrame)
  private
    FColor: TColor;
    FCurrentHue: Double;
    FHueBar: TColorPickerHueBar;
    FOnChange: TNotifyEvent;
    FOnOpacityChange: TNotifyEvent;
    FOnOpacityGestureEnd: TNotifyEvent;
    FOnOpacityGestureStart: TNotifyEvent;
    FOpacityLabel: TLabel;
    FOpacityTrackBar: THorizontalTrackBarControl;
    FSelectedColorIndicator: TPaintBox;
    FSVArea: TColorPickerSVArea;
    FTitleLabel: TLabel;
    FUpdating: Boolean;
    procedure HueBarChange(Sender: TObject);
    procedure OpacityChanged(Sender: TObject);
    procedure OpacityMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OpacityMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintSelectedColor(Sender: TObject);
    procedure SetSelectedColor(const Value: TColor);
    procedure SetColorEnabled(Value: Boolean);
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
    // VCLのTColor値で現在色を同期する。設定だけではOnChangeを発生させない。
    property SelectedColor: TColor read FColor write SetSelectedColor;
    // 色を持たない選択では色操作だけを無効化し、不透明度操作は独立して維持する。
    property ColorEnabled: Boolean write SetColorEnabled;
    // 0から100の整数で表示・編集する不透明度。
    property Opacity: Integer read GetOpacity write SetOpacity;
    property OpacityEnabled: Boolean write SetOpacityEnabled;
    // ユーザーが色を変更した時だけ発生する。
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
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
  COLOR_PICKER_HEIGHT = 104;
  COLOR_PICKER_MARGIN = 8;
  HUE_BAR_WIDTH = 20;
  INDICATOR_SIZE = 30;
  PICKER_GAP = 5;

constructor TScreenLayoutColorPickerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  Height := 250;

  FTitleLabel := TLabel.Create(Self);
  FTitleLabel.Parent := Self;
  FTitleLabel.AutoSize := False;
  FTitleLabel.Caption := 'Color';
  FTitleLabel.Color := COLOR_HEADER;
  FTitleLabel.Font.Name := 'Segoe UI';
  FTitleLabel.Font.Height := -13;
  FTitleLabel.Font.Style := [fsBold];
  FTitleLabel.Font.Color := COLOR_TEXT;
  FTitleLabel.ParentColor := False;
  FTitleLabel.ParentFont := False;
  FTitleLabel.Layout := tlCenter;

  FSelectedColorIndicator := TPaintBox.Create(Self);
  FSelectedColorIndicator.Parent := Self;
  FSelectedColorIndicator.OnPaint := PaintSelectedColor;

  FOpacityLabel := TLabel.Create(Self);
  FOpacityLabel.Parent := Self;
  FOpacityLabel.AutoSize := False;
  FOpacityLabel.Font.Name := 'Segoe UI';
  FOpacityLabel.Font.Height := -12;
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
  FSVArea := TColorPickerSVArea.Create(Self);
  FSVArea.Parent := Self;
  FSVArea.OnChange := SVAreaChange;

  FColor := clBlack;
  FCurrentHue := 0;
  SyncControls;
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
  FOpacityLabel.Caption := Format('Opacity  %d%%', [FOpacityTrackBar.Position]);
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

procedure TScreenLayoutColorPickerFrame.PaintSelectedColor(Sender: TObject);
var
  IndicatorRect: TRect;
begin
  FSelectedColorIndicator.Canvas.Brush.Style := bsSolid;
  FSelectedColorIndicator.Canvas.Brush.Color := FColor;
  FSelectedColorIndicator.Canvas.Pen.Color := COLOR_TEXT;
  IndicatorRect := FSelectedColorIndicator.ClientRect;
  InflateRect(IndicatorRect, -1, -1);
  FSelectedColorIndicator.Canvas.Ellipse(IndicatorRect);
end;

procedure TScreenLayoutColorPickerFrame.Resize;
var
  HueWidth: Integer;
  IndicatorSize: Integer;
  Margin: Integer;
  PickerGap: Integer;
  PickerHeight: Integer;
  PickerTop: Integer;
begin
  inherited Resize;
  Margin := MulDiv(COLOR_PICKER_MARGIN, CurrentPPI, 96);
  PickerGap := MulDiv(PICKER_GAP, CurrentPPI, 96);
  HueWidth := MulDiv(HUE_BAR_WIDTH, CurrentPPI, 96);
  IndicatorSize := MulDiv(INDICATOR_SIZE, CurrentPPI, 96);
  PickerHeight := Min(MulDiv(COLOR_PICKER_HEIGHT, CurrentPPI, 96),
    Max(ClientHeight - MulDiv(132, CurrentPPI, 96) - Margin, 1));
  FTitleLabel.SetBounds(0, 0, ClientWidth, MulDiv(32, CurrentPPI, 96));
  FOpacityLabel.SetBounds(Margin, MulDiv(35, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(18, CurrentPPI, 96));
  FOpacityTrackBar.SetBounds(Margin, MulDiv(51, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, 1), MulDiv(30, CurrentPPI, 96));
  FSelectedColorIndicator.SetBounds(
    Max((ClientWidth - IndicatorSize) div 2, 0),
    MulDiv(91, CurrentPPI, 96), IndicatorSize, IndicatorSize);
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
    FOpacityLabel.Caption := Format('Opacity  %d%%',
      [FOpacityTrackBar.Position]);
  finally
    FUpdating := False;
  end;
end;

procedure TScreenLayoutColorPickerFrame.SetColorEnabled(Value: Boolean);
begin
  FHueBar.Enabled := Value;
  FSVArea.Enabled := Value;
  FSelectedColorIndicator.Enabled := Value;
end;

procedure TScreenLayoutColorPickerFrame.SetOpacityEnabled(Value: Boolean);
begin
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
    FSelectedColorIndicator.Invalidate;
  finally
    FUpdating := False;
  end;
end;

end.
