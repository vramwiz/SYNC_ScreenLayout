unit ScreenLayoutOverlayPrimitives;

interface

uses
  System.Types, System.UITypes, Vcl.Direct2D, Vcl.Graphics;

const
  SCREEN_LAYOUT_OVERLAY_HALO_COLOR = clWhite;
  SCREEN_LAYOUT_OVERLAY_CORE_COLOR = clBlack;
  SCREEN_LAYOUT_OVERLAY_HALO_WIDTH = 2;
  SCREEN_LAYOUT_OVERLAY_CORE_WIDTH = 1;

procedure DrawOverlayLine(Target: TCanvas; const StartPoint,
  EndPoint: TPoint; CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;
procedure DrawOverlayLine(Target: TDirect2DCanvas; const StartPoint,
  EndPoint: TPoint; CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;
procedure DrawOverlayPolyline(Target: TCanvas; const Points: array of TPoint;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;
procedure DrawOverlayPolyline(Target: TDirect2DCanvas;
  const Points: array of TPoint;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;
procedure DrawOverlayFrameRect(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = 1); overload;
procedure DrawOverlayFrameRect(Target: TDirect2DCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = 1); overload;
procedure DrawOverlayEllipse(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = 1); overload;
procedure DrawOverlayEllipse(Target: TDirect2DCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = 1); overload;
procedure DrawOverlayRoundRect(Target: TCanvas; const Bounds: TRect;
  Radius: Integer; CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = 1); overload;
procedure DrawOverlayRoundRect(Target: TDirect2DCanvas; const Bounds: TRect;
  Radius: Integer; CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = 1); overload;
procedure DrawOverlayPie(Target: TCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor: TColor;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;
procedure DrawOverlayPie(Target: TDirect2DCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor: TColor;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;
procedure DrawOverlayHandleRect(Target: TCanvas; const Bounds: TRect;
  FillColor: TColor = clWhite;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;
procedure DrawOverlayHandleRect(Target: TDirect2DCanvas;
  const Bounds: TRect; FillColor: TColor = clWhite;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;
procedure DrawOverlayHandleEllipse(Target: TCanvas; const Bounds: TRect;
  FillColor: TColor; BorderColor: TColor); overload;
procedure DrawOverlayHandleEllipse(Target: TDirect2DCanvas;
  const Bounds: TRect; FillColor: TColor; BorderColor: TColor); overload;
procedure DrawOverlayHandlePolygon(Target: TCanvas;
  const Points: array of TPoint; FillColor, BorderColor: TColor;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
procedure DrawOverlayHandlePolygon(Target: TDirect2DCanvas;
  const Points: array of TPoint; FillColor, BorderColor: TColor;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;

implementation

procedure DrawOverlayLine(Target: TCanvas; const StartPoint,
  EndPoint: TPoint; CoreColor: TColor; Style: TPenStyle;
  HaloWidth, CoreWidth: Integer; HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

procedure DrawOverlayLine(Target: TDirect2DCanvas; const StartPoint,
  EndPoint: TPoint; CoreColor: TColor; Style: TPenStyle;
  HaloWidth, CoreWidth: Integer; HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

procedure DrawOverlayPolyline(Target: TCanvas; const Points: array of TPoint;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer;
  HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 2 then
    Exit;
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.Polyline(Points);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Polyline(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

procedure DrawOverlayPolyline(Target: TDirect2DCanvas;
  const Points: array of TPoint; CoreColor: TColor; Style: TPenStyle;
  HaloWidth, CoreWidth: Integer; HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 2 then
    Exit;
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.Polyline(Points);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Polyline(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

procedure DrawOverlayFrameRect(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer);
var
  Bottom: Integer;
  Points: array[0..4] of TPoint;
  Right: Integer;
begin
  if Bounds.IsEmpty then
    Exit;
  Right := Bounds.Right - 1;
  Bottom := Bounds.Bottom - 1;
  Points[0] := Bounds.TopLeft;
  Points[1] := Point(Right, Bounds.Top);
  Points[2] := Point(Right, Bottom);
  Points[3] := Point(Bounds.Left, Bottom);
  Points[4] := Points[0];
  DrawOverlayPolyline(Target, Points, CoreColor, Style, HaloWidth,
    CoreWidth);
end;

procedure DrawOverlayFrameRect(Target: TDirect2DCanvas;
  const Bounds: TRect; CoreColor: TColor; Style: TPenStyle;
  HaloWidth, CoreWidth: Integer);
var
  Bottom: Integer;
  Points: array[0..4] of TPoint;
  Right: Integer;
begin
  if Bounds.IsEmpty then
    Exit;
  Right := Bounds.Right - 1;
  Bottom := Bounds.Bottom - 1;
  Points[0] := Bounds.TopLeft;
  Points[1] := Point(Right, Bounds.Top);
  Points[2] := Point(Right, Bottom);
  Points[3] := Point(Bounds.Left, Bottom);
  Points[4] := Points[0];
  DrawOverlayPolyline(Target, Points, CoreColor, Style, HaloWidth,
    CoreWidth);
end;

procedure DrawOverlayEllipse(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.Ellipse(Bounds);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Ellipse(Bounds);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayEllipse(Target: TDirect2DCanvas; const Bounds: TRect;
  CoreColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayRoundRect(Target: TCanvas; const Bounds: TRect;
  Radius: Integer; CoreColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayRoundRect(Target: TDirect2DCanvas;
  const Bounds: TRect; Radius: Integer; CoreColor: TColor;
  HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayPie(Target: TCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayPie(Target: TDirect2DCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandleRect(Target: TCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
begin
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.FillRect(Bounds);
    DrawOverlayFrameRect(Target, Bounds, BorderColor);
  finally
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandleRect(Target: TDirect2DCanvas;
  const Bounds: TRect; FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
begin
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.FillRect(Bounds);
    DrawOverlayFrameRect(Target, Bounds, BorderColor);
  finally
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandleEllipse(Target: TCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
    Target.Ellipse(Bounds);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Ellipse(Bounds);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandleEllipse(Target: TDirect2DCanvas;
  const Bounds: TRect; FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandlePolygon(Target: TCanvas;
  const Points: array of TPoint; FillColor, BorderColor: TColor;
  HaloWidth, CoreWidth: Integer);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 3 then
    Exit;
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.Polygon(Points);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := CoreWidth;
    Target.Polygon(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandlePolygon(Target: TDirect2DCanvas;
  const Points: array of TPoint; FillColor, BorderColor: TColor;
  HaloWidth, CoreWidth: Integer);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 3 then
    Exit;
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.Polygon(Points);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := CoreWidth;
    Target.Polygon(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

end.
