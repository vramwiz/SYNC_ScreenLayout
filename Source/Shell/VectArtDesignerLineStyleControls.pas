// Line詳細設定で使うダークボタンと線端・接合・AAの選択アイコンを描画する。
// 線端と接合は共通値、AAボタンはMIF vector qualityとして扱う。
unit VectArtDesignerLineStyleControls;

interface

uses
  System.Classes, Winapi.Messages, Vcl.Controls,
  VectArtDesignerDocument;

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

  TVectArtLineJoinButton = class(TVectArtDarkButton)
  private
    FLineJoin: TVectArtLineJoin;
    FSelected: Boolean;
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
    property LineJoin: TVectArtLineJoin read FLineJoin write FLineJoin;
    property Selected: Boolean read FSelected write SetSelected;
  end;

  TVectArtMifAntiAliasButton = class(TVectArtDarkButton)
  private
    FSelected: Boolean;
    procedure SetSelected(Value: Boolean);
  protected
    procedure Paint; override;
  public
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
  GuideLeft: Integer;
  GuideRight: Integer;
  MidY: Integer;
  StrokeBounds: TRect;
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

  GuideLeft := 11;
  GuideRight := Width - 12;
  MidY := Height div 2;
  Canvas.Pen.Color := TColor($00606060);
  Canvas.Pen.Style := psDot;
  Canvas.MoveTo(GuideLeft, 5);
  Canvas.LineTo(GuideLeft, Height - 5);
  Canvas.MoveTo(GuideRight, 5);
  Canvas.LineTo(GuideRight, Height - 5);
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
    vlcButt:
      StrokeBounds := Rect(GuideLeft, MidY - 1, GuideRight + 1, MidY + 2);
    vlcSquare:
      begin
        StrokeBounds := Rect(GuideLeft, MidY - 1, GuideRight + 1, MidY + 2);
        Canvas.FillRect(StrokeBounds);
        Canvas.FillRect(Rect(GuideLeft - 3, MidY - 3, GuideLeft + 1, MidY + 4));
        Canvas.FillRect(Rect(GuideRight, MidY - 3, GuideRight + 4, MidY + 4));
        Exit;
      end;
  else
    begin
      StrokeBounds := Rect(GuideLeft, MidY - 1, GuideRight + 1, MidY + 2);
      Canvas.FillRect(StrokeBounds);
      Canvas.Ellipse(GuideLeft - 3, MidY - 3, GuideLeft + 4, MidY + 4);
      Canvas.Ellipse(GuideRight - 3, MidY - 3, GuideRight + 4, MidY + 4);
      Exit;
    end;
  end;
  Canvas.FillRect(StrokeBounds);
end;

procedure TVectArtLineCapButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

{ TVectArtLineJoinButton }

procedure TVectArtLineJoinButton.Paint;
var
  BackgroundColor: TColor;
  Bounds: TRect;
  CenterX: Integer;
  Points: array[0..2] of TPoint;
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

  CenterX := Width div 2;
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
  Canvas.Pen.Width := 3;
  Canvas.MoveTo(8, Height - 8);
  Canvas.LineTo(CenterX, 10);
  Canvas.LineTo(Width - 8, Height - 8);
  Canvas.Pen.Width := 1;
  case FLineJoin of
    vljMiter:
      begin
        Points[0] := Point(CenterX - 4, 12);
        Points[1] := Point(CenterX, 4);
        Points[2] := Point(CenterX + 4, 12);
        Canvas.Polygon(Points);
      end;
    vljBevel:
      Canvas.FillRect(Rect(CenterX - 4, 7, CenterX + 5, 13));
    vljRound:
      Canvas.Ellipse(CenterX - 5, 5, CenterX + 6, 16);
  end;
end;

procedure TVectArtLineJoinButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

{ TVectArtMifAntiAliasButton }

procedure TVectArtMifAntiAliasButton.Paint;
var
  Bounds: TRect;
begin
  inherited Paint;
  if not FSelected then
    Exit;
  Bounds := ClientRect;
  Dec(Bounds.Right);
  Dec(Bounds.Bottom);
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := COLOR_BUTTON_SELECTED_BORDER;
  Canvas.Rectangle(Bounds);
  InflateRect(Bounds, -2, -2);
  Canvas.Rectangle(Bounds);
end;

procedure TVectArtMifAntiAliasButton.SetSelected(Value: Boolean);
begin
  if FSelected = Value then
    Exit;
  FSelected := Value;
  Invalidate;
end;

end.
