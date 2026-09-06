// 画面内へ埋め込む色選択UI。オブジェクトへの適用は上位側で接続する。
unit ScreenLayoutColorPickerFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics,
  Vcl.StdCtrls, ColorPickerHueBar, ColorPickerSVArea,
  HorizontalTrackBarControl, ScreenLayoutGradientKindCombo,
  ScreenLayoutPaintStyles, ScreenLayoutTextureControl, ScreenLayoutPaintModeSelector,
  ScreenLayoutColorTargetSelector, ScreenLayoutPatternControl, ScreenLayoutPatternStyle;

type
  TScreenLayoutColorPickerFrame = class(TFrame)
  private
    FPatternControl: TScreenLayoutPatternControl; // パターン専用の定義別編集UI。
    FOnPaintGestureStart: TNotifyEvent; // 共通塗り連続編集の開始。
    FOnPaintGestureEnd: TNotifyEvent;   // 共通塗り連続編集の終了。
    FTextureControl: TScreenLayoutTextureControl; // テクスチャモードだけで表示する画像設定。
    FGradientKindSelector: TScreenLayoutGradientKindCombo;
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
    FColorTargetSelector: TScreenLayoutColorTargetSelector; // 色見本とグラデーション点操作を委譲する。
    FGradientStop: Integer;
    FModeSelector: TScreenLayoutPaintModeSelector; // 塗り方式の表示とクリック判定を委譲する。
    FPaintModeEnabled: Boolean;
    FPaintStyle: TScreenLayoutPaintStyle;
    FOnPaintStyleChange: TNotifyEvent;
    FSVArea: TColorPickerSVArea;
    FTitleLabel: TLabel;
    FUpdating: Boolean;
    procedure PatternChanged(Sender: TObject);
    procedure PatternSlotSelected(Sender: TObject);
    procedure PaintGestureStart(Sender: TObject);
    procedure PaintGestureEnd(Sender: TObject);
    procedure UpdatePatternColor;
    procedure GradientKindChanged(Sender: TObject);
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
    procedure ColorTargetPaintStyleChanged(Sender: TObject);
    procedure ColorTargetStopSelected(Sender: TObject);
    procedure PaintModeSelected(Sender: TObject; Kind: TScreenLayoutPaintKind);
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
    procedure TextureChanged(Sender: TObject);
  protected
    procedure Resize; override;
    procedure SetParent(AParent: TWinControl); override;
  public
    property OnPaintGestureStart: TNotifyEvent read FOnPaintGestureStart write FOnPaintGestureStart;
    property OnPaintGestureEnd: TNotifyEvent read FOnPaintGestureEnd write FOnPaintGestureEnd;
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
  MODE_CONTENT_TOP = 122; // この位置より下だけをモード切り替えで変更する。
  PICKER_GAP = 4;

constructor TScreenLayoutColorPickerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Color := COLOR_BACKGROUND;
  ParentBackground := False;
  DoubleBuffered := True;
  Height := MulDiv(538, CurrentPPI, 96);

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

  FColorTargetSelector := TScreenLayoutColorTargetSelector.Create(Self);
  FColorTargetSelector.Parent := Self;
  FColorTargetSelector.Hint := '塗りの色';
  FColorTargetSelector.ShowHint := True;
  FColorTargetSelector.OnPaintStyleChange := ColorTargetPaintStyleChanged;
  FColorTargetSelector.OnStopSelect := ColorTargetStopSelected;

  FModeSelector := TScreenLayoutPaintModeSelector.Create(Self);
  FModeSelector.Parent := Self;
  FModeSelector.OnSelect := PaintModeSelected;

  FGradientKindSelector := TScreenLayoutGradientKindCombo.Create(Self);
  FGradientKindSelector.Parent := Self;
  FGradientKindSelector.Visible := False;
  FGradientKindSelector.OnChange := GradientKindChanged;
  FGradientKindSelector.Hint := '線方向・線幅方向は線オブジェクト用。図形では線形として表示';
  FGradientKindSelector.ShowHint := True;
  FColorTargetSelector.Hint := '点を選択 / Ctrl+クリックで追加 / 右クリックで中間点削除';

  FOpacityLabel := TLabel.Create(Self);
  FOpacityLabel.Parent := Self;
  FOpacityLabel.AutoSize := False;
  FOpacityLabel.Font.Name := 'Segoe UI';
  FOpacityLabel.Font.Height := -11;
  FOpacityLabel.Font.Color := COLOR_TEXT;
  FOpacityLabel.ParentFont := False;
  FOpacityLabel.Caption := '透明度：';

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
  FTextureControl := TScreenLayoutTextureControl.Create(Self);
  FTextureControl.Parent := Self;
  FTextureControl.Visible := False;
  FTextureControl.OnChange := TextureChanged;
  FPatternControl := TScreenLayoutPatternControl.Create(Self);
  FPatternControl.Parent := Self;
  FPatternControl.Visible := False;
  FPatternControl.OnChange := PatternChanged;
  FPatternControl.OnSlotSelect := PatternSlotSelected;
  FPatternControl.OnGestureStart := PaintGestureStart;
  FPatternControl.OnGestureEnd := PaintGestureEnd;
  SyncControls;
end;

procedure TScreenLayoutColorPickerFrame.PaintGestureStart(Sender: TObject);
begin
  if Assigned(FOnPaintGestureStart) then FOnPaintGestureStart(Self);
end;

procedure TScreenLayoutColorPickerFrame.PaintGestureEnd(Sender: TObject);
begin
  if Assigned(FOnPaintGestureEnd) then FOnPaintGestureEnd(Self);
end;

procedure TScreenLayoutColorPickerFrame.PatternChanged(Sender: TObject);
begin
  if FUpdating or not FColorEnabled or not FPaintModeEnabled then Exit;
  FPaintStyle.Pattern := FPatternControl.Pattern;
  SetPaintStyle(FPaintStyle);
  if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.PatternSlotSelected(Sender: TObject);
var Slot: TScreenLayoutPatternColor;
begin
  Slot := FPaintStyle.Pattern.Slot(FPatternControl.SlotId);
  SetSelectedColor(Slot.Color);
  SetOpacity(Round(Slot.Opacity * 100));
end;

procedure TScreenLayoutColorPickerFrame.UpdatePatternColor;
var Pattern: TScreenLayoutPatternStyle; Slot: TScreenLayoutPatternColor;
begin
  Pattern := FPaintStyle.Pattern;
  Slot := Pattern.Slot(FPatternControl.SlotId);
  Slot.Color := FColor;
  Pattern.SetSlot(Slot);
  FPaintStyle.Pattern := Pattern;
  FPatternControl.Pattern := Pattern;
end;

procedure TScreenLayoutColorPickerFrame.TextureChanged(Sender: TObject);
begin
  if FUpdating or not FColorEnabled or not FPaintModeEnabled then Exit;
  FPaintStyle.Texture := FTextureControl.Texture;
  if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.ColorTargetPaintStyleChanged(Sender: TObject);
begin
  FPaintStyle := FColorTargetSelector.PaintStyle;
  FGradientStop := FColorTargetSelector.SelectedStopId;
  if Assigned(FOnPaintStyleChange) then
    FOnPaintStyleChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.ColorTargetStopSelected(Sender: TObject);
begin
  SetGradientStopId(FColorTargetSelector.SelectedStopId);
  if Assigned(FOnGradientStopSelect) then
    FOnGradientStopSelect(Self);
end;

procedure TScreenLayoutColorPickerFrame.GradientKindChanged(Sender: TObject);
begin
  if FUpdating or not FGradientKindSelector.Enabled or (FGradientKindSelector.ItemIndex < 0) then
    Exit;
  if FPaintStyle.GradientKind = TScreenLayoutGradientKind(FGradientKindSelector.ItemIndex) then
    Exit;
  FPaintStyle.GradientKind := TScreenLayoutGradientKind(FGradientKindSelector.ItemIndex);
  FGradientKindSelector.SetPendingItemIndex(FGradientKindSelector.ItemIndex);
  if FPaintStyle.GradientKind in [slgkRadial, slgkRectangle, slgkSweep] then
  begin
    FPaintStyle.LinearStart := TPointF.Create(0.5, 0.5);
    FPaintStyle.LinearEnd := TPointF.Create(1, 0.5);
    FPaintStyle.GradientAspect := 1;
  end;
  FGradientKindSelector.Invalidate;
  if Assigned(FOnPaintStyleChange) then
    FOnPaintStyleChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.ColorMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureStart(Self);
    Exit;
  end;
  if (Button = mbLeft) and FColorEnabled and
    Assigned(FOnColorGestureStart) then
    FOnColorGestureStart(Self);
end;

procedure TScreenLayoutColorPickerFrame.ColorMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureEnd(Self);
    Exit;
  end;
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
  if FPaintStyle.Kind = slpkPattern then
    UpdatePatternColor
  else if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  SyncControls;
  if FPaintStyle.Kind = slpkPattern then
  begin
    if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
  end
  else if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TScreenLayoutColorPickerFrame.GetOpacity: Integer;
begin
  Result := FOpacityTrackBar.Position;
end;

procedure TScreenLayoutColorPickerFrame.OpacityChanged(Sender: TObject);
var Pattern: TScreenLayoutPatternStyle; Slot: TScreenLayoutPatternColor;
begin
  if not FUpdating then
  begin
    if FPaintStyle.Kind = slpkPattern then
    begin
      Pattern := FPaintStyle.Pattern;
      Slot := Pattern.Slot(FPatternControl.SlotId);
      Slot.Opacity := FOpacityTrackBar.Position / 100.0;
      Pattern.SetSlot(Slot);
      FPaintStyle.Pattern := Pattern;
      FPatternControl.Pattern := Pattern;
      if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
      Exit;
    end;
    if FPaintStyle.Kind = slpkGradient then
      FPaintStyle.SetGradientStopOpacity(FGradientStop, FOpacityTrackBar.Position / 100.0);
    FColorTargetSelector.PaintStyle := FPaintStyle;
    if Assigned(FOnOpacityChange) then
      FOnOpacityChange(Self);
  end;
end;

procedure TScreenLayoutColorPickerFrame.OpacityMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureStart(Self);
    Exit;
  end;
  if (Button = mbLeft) and FOpacityTrackBar.Enabled and
    Assigned(FOnOpacityGestureStart) then
    FOnOpacityGestureStart(Self);
end;

procedure TScreenLayoutColorPickerFrame.OpacityMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FPaintStyle.Kind = slpkPattern) and (Button = mbLeft) then
  begin
    PaintGestureEnd(Self);
    Exit;
  end;
  if (Button = mbLeft) and Assigned(FOnOpacityGestureEnd) then
    FOnOpacityGestureEnd(Self);
end;

procedure TScreenLayoutColorPickerFrame.PaintModeSelected(Sender: TObject;
  Kind: TScreenLayoutPaintKind);
begin
  SelectPaintKind(Kind);
end;

procedure TScreenLayoutColorPickerFrame.SelectPaintKind(
  Value: TScreenLayoutPaintKind);
begin
  if not FPaintModeEnabled or
    (FPaintStyle.Kind = Value) then
    Exit;
  FPaintStyle.Kind := Value;
  if Value = slpkPattern then FPaintStyle.PreparePattern;
  if Value = slpkTexture then FPaintStyle.PrepareTexture;
  if Value = slpkGradient then
  begin
    FPaintStyle.PrepareLinearGradient(FColor);
    FGradientStop := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
    SelectedColor := FPaintStyle.GradientStartColor;
  end
  else if Value <> slpkPattern then
    SelectedColor := FPaintStyle.SolidColor;
  SetPaintStyle(FPaintStyle);
  FModeSelector.PaintStyle := FPaintStyle;
  FColorTargetSelector.Invalidate;
  if Assigned(FOnPaintStyleChange) then
    FOnPaintStyleChange(Self);
end;

procedure TScreenLayoutColorPickerFrame.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if (AParent <> nil) and (FGradientKindSelector <> nil) then
  begin
    FGradientKindSelector.SetPendingItemIndex(Ord(FPaintStyle.GradientKind));
    Resize;
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
  ContentTop: Integer;
begin
  inherited Resize;
  if FSVArea = nil then
    Exit;
  Margin := MulDiv(COLOR_PICKER_MARGIN, CurrentPPI, 96);
  PickerGap := MulDiv(PICKER_GAP, CurrentPPI, 96);
  HueWidth := MulDiv(HUE_BAR_WIDTH, CurrentPPI, 96);
  SelectorSize := MulDiv(COLOR_SELECTOR_SIZE, CurrentPPI, 96);
  ContentTop := MulDiv(MODE_CONTENT_TOP, CurrentPPI, 96);
  PickerHeight := Min(MulDiv(COLOR_PICKER_HEIGHT, CurrentPPI, 96),
    Max(ClientHeight - ContentTop - Margin - PickerGap, 1));
  FTitleLabel.SetBounds(0, 0, ClientWidth, MulDiv(26, CurrentPPI, 96));
  FOpacityLabel.SetBounds(Margin, MulDiv(28, CurrentPPI, 96),
    MulDiv(48, CurrentPPI, 96), MulDiv(24, CurrentPPI, 96));
  FOpacityTrackBar.SetBounds(Margin + MulDiv(48, CurrentPPI, 96),
    MulDiv(28, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2 - MulDiv(48, CurrentPPI, 96), 1), MulDiv(24, CurrentPPI, 96));
  FColorTargetSelector.SetBounds(Margin, MulDiv(58, CurrentPPI, 96),
    Max(ClientWidth - Margin * 2, SelectorSize), SelectorSize);
  FModeSelector.SetBounds(Margin, MulDiv(90, CurrentPPI, 96),
    Min(ClientWidth - Margin * 2,
      MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_SIZE * 4 +
      SCREEN_LAYOUT_PAINT_MODE_BUTTON_GAP * 3, CurrentPPI, 96)),
    MulDiv(SCREEN_LAYOUT_PAINT_MODE_BUTTON_SIZE, CurrentPPI, 96));
  FGradientKindSelector.SetBounds(Margin, ContentTop,
    Max(ClientWidth - Margin * 2, 1), MulDiv(24, CurrentPPI, 96));
  PickerTop := ClientHeight - Margin - PickerHeight;
  FHueBar.SetBounds(Max(ClientWidth - Margin - HueWidth, Margin),
    PickerTop, HueWidth, PickerHeight);
  FSVArea.SetBounds(Margin, PickerTop,
    Max(FHueBar.Left - PickerGap - Margin, 1), PickerHeight);
  if FTextureControl <> nil then
    FTextureControl.SetBounds(Margin, ContentTop,
      Max(ClientWidth - Margin * 2, 1), Max(PickerTop - ContentTop - PickerGap, 1));
  if FPatternControl <> nil then
    FPatternControl.SetBounds(Margin, ContentTop,
      Max(ClientWidth - Margin * 2, 1), Max(PickerTop - ContentTop - PickerGap, 1));
end;

procedure TScreenLayoutColorPickerFrame.SetOpacity(Value: Integer);
begin
  FUpdating := True;
  try
    FOpacityTrackBar.Position := EnsureRange(Value, 0, 100);
    FOpacityLabel.Caption := '透明度：';
  finally
    FUpdating := False;
  end;
end;

procedure TScreenLayoutColorPickerFrame.SetColorEnabled(Value: Boolean);
begin
  FColorEnabled := Value;
  FTextureControl.Enabled := Value and FPaintModeEnabled;
  FPatternControl.Enabled := Value and FPaintModeEnabled;
  FGradientKindSelector.Enabled := Value and FPaintModeEnabled and (FPaintStyle.Kind = slpkGradient);
  FGradientKindSelector.Visible := FPaintStyle.Kind = slpkGradient;
  FHueBar.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FSVArea.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FColorTargetSelector.Enabled := Value and (FPaintStyle.Kind <> slpkTexture);
  FColorTargetSelector.Invalidate;
end;

procedure TScreenLayoutColorPickerFrame.SetPaintStyle(
  const Value: TScreenLayoutPaintStyle);
begin
  FPaintStyle := Value;
  if FPaintStyle.Kind = slpkPattern then FPaintStyle.PreparePattern;
  FModeSelector.PaintStyle := FPaintStyle;
  FPatternControl.Pattern := FPaintStyle.Pattern;
  FPatternControl.Visible := Value.Kind = slpkPattern;
  FTextureControl.Texture := Value.Texture;
  FTextureControl.Visible := Value.Kind = slpkTexture;
  FHueBar.Visible := True;
  FSVArea.Visible := True;
  FColorTargetSelector.Visible := True;
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
  if Parent <> nil then
    FGradientKindSelector.SetPendingItemIndex(Ord(FPaintStyle.GradientKind));
  FGradientKindSelector.Enabled := FPaintModeEnabled and FColorEnabled and (FPaintStyle.Kind = slpkGradient);
  FGradientKindSelector.Visible := FPaintStyle.Kind = slpkGradient;
  FHueBar.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  FSVArea.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  FColorTargetSelector.Enabled := FColorEnabled and (FPaintStyle.Kind <> slpkTexture);
  if FPaintStyle.Kind = slpkGradient then
    SetGradientStopId(FGradientStop);
  if FPaintStyle.Kind = slpkPattern then PatternSlotSelected(Self);
  SyncControls;
  FModeSelector.PaintStyle := FPaintStyle;
end;

procedure TScreenLayoutColorPickerFrame.SetGradientStopId(Value: Integer);
var
  ColorValue: TColor;
  OpacityValue: Single;
begin
  if (FPaintStyle.Kind <> slpkGradient) or
    not FPaintStyle.GetGradientStopColor(Value, ColorValue) then
    Value := SCREEN_LAYOUT_GRADIENT_START_STOP_ID;
  FGradientStop := Value;
  FColorTargetSelector.SelectedStopId := FGradientStop;
  if FPaintStyle.GetGradientStopColor(FGradientStop, ColorValue) then
    SetSelectedColor(ColorValue);
  if (FPaintStyle.Kind = slpkGradient) and
    FPaintStyle.GetGradientStopOpacity(FGradientStop, OpacityValue) then
    SetOpacity(Round(OpacityValue * 100));
  FColorTargetSelector.Invalidate;
end;

procedure TScreenLayoutColorPickerFrame.SetPaintModeEnabled(Value: Boolean);
begin
  if FPaintModeEnabled = Value then
    Exit;
  FPaintModeEnabled := Value;
  FModeSelector.Enabled := Value;
  FTextureControl.Enabled := Value and FColorEnabled;
  FPatternControl.Enabled := Value and FColorEnabled;
  FGradientKindSelector.Enabled := Value and FColorEnabled and (FPaintStyle.Kind = slpkGradient);
  FGradientKindSelector.Visible := FPaintStyle.Kind = slpkGradient;
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
  if FPaintStyle.Kind = slpkPattern then
    UpdatePatternColor
  else if FPaintStyle.Kind = slpkGradient then
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
  if FPaintStyle.Kind = slpkPattern then
    UpdatePatternColor
  else if FPaintStyle.Kind = slpkGradient then
    FPaintStyle.SetGradientStopColor(FGradientStop, FColor)
  else
    FPaintStyle.SolidColor := FColor;
  SyncControls;
  if FPaintStyle.Kind = slpkPattern then
  begin
    if Assigned(FOnPaintStyleChange) then FOnPaintStyleChange(Self);
  end
  else if Assigned(FOnChange) then
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
    FColorTargetSelector.ColorValue := FColor;
    FColorTargetSelector.PaintStyle := FPaintStyle;
    FColorTargetSelector.SelectedStopId := FGradientStop;
  finally
    FUpdating := False;
  end;
end;

end.
