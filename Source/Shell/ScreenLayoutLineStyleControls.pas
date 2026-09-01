// Line詳細設定で使うダークボタンと拡大した線端形状アイコンを描画する。
unit ScreenLayoutLineStyleControls;

interface

uses
  System.Classes, Winapi.Messages, Vcl.Controls,
  ScreenLayoutDocument;

type
  TVectArtDarkButton = class(TCustomControl)
  private
    FMouseOver: Boolean;
    FPressed: Boolean;
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Paint; override;
    procedure WMKillFocus(var Message: TWMKillFocus); message WM_KILLFOCUS;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
  public
    // キーボード操作とフォーカス表示に対応するダークボタンを生成する。
    constructor Create(AOwner: TComponent); override;
    // 無効状態ではイベントを発生させず、有効時だけOnClickを呼び出す。
    procedure Click; override;
    property Caption;
    property OnClick;
  end;

  TVectArtLineCapButton = class(TVectArtDarkButton)
  private
    FLineCap: TVectArtLineCap;
    FSelected: Boolean;
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
    property LineCap: TVectArtLineCap read FLineCap write FLineCap;
    property Selected: Boolean read FSelected write SetSelected;
  end;

implementation

uses
  System.Types, Winapi.Windows, Vcl.Graphics;

const
  COLOR_BUTTON = TColor($00383838);
  COLOR_BUTTON_BORDER = TColor($00606060);
  COLOR_BUTTON_DISABLED = TColor($002E2E2E);
  COLOR_BUTTON_FOCUS = TColor($00D69C4A);
  COLOR_BUTTON_HOVER = TColor($00484848);
  COLOR_BUTTON_PRESSED = TColor($00202020);
  COLOR_BUTTON_SELECTED = TColor($00613D12);
  COLOR_BUTTON_SELECTED_BORDER = TColor($00D69C4A);
  COLOR_TEXT = TColor($00EEEEEE);

{ TVectArtDarkButton }

procedure TVectArtDarkButton.Click;
begin
  if Enabled then
    inherited Click;
end;

procedure TVectArtDarkButton.CMMouseEnter(var Message: TMessage);
begin
  FMouseOver := True;
  Invalidate;
end;

procedure TVectArtDarkButton.CMMouseLeave(var Message: TMessage);
begin
  FMouseOver := False;
  FPressed := False;
  Invalidate;
end;

constructor TVectArtDarkButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  Font.Name := 'Segoe UI';
  Font.Height := -12;
  Font.Color := COLOR_TEXT;
end;

procedure TVectArtDarkButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Enabled and ((Key = VK_RETURN) or (Key = VK_SPACE)) then
  begin
    Click;
    Key := 0;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TVectArtDarkButton.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Enabled and (Button = mbLeft) then
  begin
    SetFocus;
    FPressed := True;
    Invalidate;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TVectArtDarkButton.MouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FPressed := False;
  Invalidate;
  // TControl自身のマウスメッセージ処理がClickを発生させるため、ここでは重複して呼ばない。
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TVectArtDarkButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
begin
  if not Enabled then
    BackgroundColor := COLOR_BUTTON_DISABLED
  else if FPressed then
    BackgroundColor := COLOR_BUTTON_PRESSED
  else if FMouseOver then
    BackgroundColor := COLOR_BUTTON_HOVER
  else
    BackgroundColor := COLOR_BUTTON;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := BackgroundColor;
  Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  Canvas.Rectangle(Bounds);
  if Focused then
  begin
    InflateRect(Bounds, -2, -2);
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := COLOR_BUTTON_FOCUS;
    Canvas.Rectangle(Bounds);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  if not Enabled then
    Canvas.Font.Color := COLOR_BUTTON_BORDER;
  DrawText(Canvas.Handle, PChar(Caption), Length(Caption), Bounds,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TVectArtDarkButton.WMKillFocus(var Message: TWMKillFocus);
begin
  inherited;
  Invalidate;
end;

procedure TVectArtDarkButton.WMSetFocus(var Message: TWMSetFocus);
begin
  inherited;
  Invalidate;
end;

{ TVectArtLineCapButton }

procedure TVectArtLineCapButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
  EndX: Integer;
  MidY: Integer;
  Points: array[0..2] of TPoint;
  ShaftLeft: Integer;
  StrokeHalfWidth: Integer;
begin
  inherited Paint;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  if FSelected then
  begin
    if Enabled then
      BackgroundColor := COLOR_BUTTON_SELECTED
    else
      BackgroundColor := COLOR_BUTTON_DISABLED;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := BackgroundColor;
    Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER;
    Canvas.Rectangle(Bounds);
  end;

  ShaftLeft := 7;
  EndX := Width - 10;
  MidY := Height div 2;
  StrokeHalfWidth := Height div 6;
  if StrokeHalfWidth < 3 then
    StrokeHalfWidth := 3;
  Canvas.Pen.Color := TColor($00606060);
  Canvas.Pen.Style := psDot;
  Canvas.MoveTo(EndX, 4);
  Canvas.LineTo(EndX, Height - 4);
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
  if Enabled then
  begin
    Canvas.Brush.Color := COLOR_TEXT;
    Canvas.Pen.Color := COLOR_TEXT;
  end
  else
  begin
    Canvas.Brush.Color := COLOR_BUTTON_BORDER;
    Canvas.Pen.Color := COLOR_BUTTON_BORDER;
  end;
  case FLineCap of
    vlcSquare:
      Canvas.FillRect(Rect(ShaftLeft, MidY - StrokeHalfWidth, EndX + 1,
        MidY + StrokeHalfWidth + 1));
    vlcRound:
      begin
        Canvas.FillRect(Rect(ShaftLeft, MidY - StrokeHalfWidth, EndX + 1,
          MidY + StrokeHalfWidth + 1));
        Canvas.Ellipse(EndX - StrokeHalfWidth, MidY - StrokeHalfWidth,
          EndX + StrokeHalfWidth + 1, MidY + StrokeHalfWidth + 1);
      end;
    vlcTriangle:
      begin
        Canvas.FillRect(Rect(ShaftLeft, MidY - StrokeHalfWidth, EndX + 1,
          MidY + StrokeHalfWidth + 1));
        Points[0] := Point(EndX, MidY - StrokeHalfWidth);
        Points[1] := Point(EndX + StrokeHalfWidth, MidY);
        Points[2] := Point(EndX, MidY + StrokeHalfWidth);
        Canvas.Polygon(Points);
      end;
  end;
end;

procedure TVectArtLineCapButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

end.
