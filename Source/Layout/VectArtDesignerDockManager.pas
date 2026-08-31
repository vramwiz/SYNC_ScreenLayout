// ツールFrameの左右ドッキング、順序、フローティングとの切替を管理する。
// 個別ツールの内容には依存せず、空スロットを残さずにドック領域を再構成する。
unit VectArtDesignerDockManager;

interface

uses
  System.Generics.Collections, System.IniFiles, System.Types, Vcl.ExtCtrls,
  Vcl.Forms, VectArtDesignerToolFrames;

type
  TVectDockSide = (vdsLeft, vdsRight);

  TVectDockManager = class
  private
    FAllTools: TList<TToolPlaceholderFrame>;
    FLastIndices: TDictionary<TToolPlaceholderFrame, Integer>;
    FLastSides: TDictionary<TToolPlaceholderFrame, TVectDockSide>;
    FLayoutEditing: Boolean;
    FLeftArea: TPanel;
    FLeftDropTarget: TPanel;
    FLeftSplitter: TSplitter;
    FLeftTools: TList<TToolPlaceholderFrame>;
    FOwnerForm: TCustomForm;
    FRestoring: Boolean;
    FRightArea: TPanel;
    FRightDropTarget: TPanel;
    FRightSplitter: TSplitter;
    FRightTools: TList<TToolPlaceholderFrame>;
    FWorkspace: TPanel;
    FOnToolVisibilityChanged: TToolFrameNotifyEvent;
    function AreaForSide(Side: TVectDockSide): TPanel;
    procedure DockFrame(Frame: TToolPlaceholderFrame; Side: TVectDockSide;
      Index: Integer);
    function DropSideAt(const ScreenPoint: TPoint; out Side: TVectDockSide): Boolean;
    procedure HideDropTargets;
    function InsertIndexAt(Side: TVectDockSide; const ScreenPoint: TPoint): Integer;
    procedure LayoutDockArea(Side: TVectDockSide);
    procedure LayoutDockAreas;
    function ReadToolSide(Ini: TCustomIniFile;
      Frame: TToolPlaceholderFrame): TVectDockSide;
    function ScreenRect(Control: TPanel): TRect;
    procedure SetLayoutEditing(const Value: Boolean);
    function ToolsForSide(Side: TVectDockSide): TList<TToolPlaceholderFrame>;
    procedure ToolDetached(Sender: TToolPlaceholderFrame);
    procedure ToolDockRequest(Sender: TToolPlaceholderFrame;
      const ScreenPoint: TPoint; var Accepted: Boolean);
    procedure ToolDragMove(Sender: TToolPlaceholderFrame;
      const ScreenPoint: TPoint);
    procedure ToolCloseRequested(Sender: TToolPlaceholderFrame);
    procedure UpdateDropTargets(const ScreenPoint: TPoint);
  public
    constructor Create(AOwnerForm: TCustomForm; AWorkspace, ALeftArea,
      ARightArea, ALeftDropTarget, ARightDropTarget: TPanel;
      ALeftSplitter, ARightSplitter: TSplitter);
    destructor Destroy; override;
    procedure RegisterTool(Frame: TToolPlaceholderFrame; DefaultSide: TVectDockSide;
      DefaultIndex: Integer = -1);
    procedure Resize;
    procedure LoadLayout(Ini: TCustomIniFile);
    procedure SaveLayout(Ini: TCustomIniFile);
    procedure SetToolVisible(Frame: TToolPlaceholderFrame; const Value: Boolean);
    function ToolVisible(Frame: TToolPlaceholderFrame): Boolean;
    property LayoutEditing: Boolean read FLayoutEditing write SetLayoutEditing;
    property OnToolVisibilityChanged: TToolFrameNotifyEvent
      read FOnToolVisibilityChanged write FOnToolVisibilityChanged;
  end;

implementation

uses
  System.Math, System.SysUtils, Vcl.Controls, Vcl.Graphics;

const
  DOCK_GAP          = 4;
  DOCK_TARGET_WIDTH = 64;
  COLOR_TARGET_IDLE = TColor($00302A24);
  COLOR_TARGET_HOT  = TColor($007A4A22);

function ConstrainToolBounds(const Bounds: TRect): TRect;
var
  Monitor: TMonitor;
  WorkArea: TRect;
begin
  Result := Bounds;
  Monitor := Screen.MonitorFromRect(Result, mdNearest);
  WorkArea := Monitor.WorkareaRect;
  if Result.Width > WorkArea.Width then
    Result.Right := Result.Left + WorkArea.Width;
  if Result.Height > WorkArea.Height then
    Result.Bottom := Result.Top + WorkArea.Height;
  if Result.Left < WorkArea.Left then
    OffsetRect(Result, WorkArea.Left - Result.Left, 0);
  if Result.Top < WorkArea.Top then
    OffsetRect(Result, 0, WorkArea.Top - Result.Top);
  if Result.Right > WorkArea.Right then
    OffsetRect(Result, WorkArea.Right - Result.Right, 0);
  if Result.Bottom > WorkArea.Bottom then
    OffsetRect(Result, 0, WorkArea.Bottom - Result.Bottom);
end;

constructor TVectDockManager.Create(AOwnerForm: TCustomForm;
  AWorkspace, ALeftArea, ARightArea, ALeftDropTarget,
  ARightDropTarget: TPanel; ALeftSplitter, ARightSplitter: TSplitter);
begin
  inherited Create;
  FOwnerForm := AOwnerForm;
  FWorkspace := AWorkspace;
  FLeftArea := ALeftArea;
  FRightArea := ARightArea;
  FLeftDropTarget := ALeftDropTarget;
  FRightDropTarget := ARightDropTarget;
  FLeftSplitter := ALeftSplitter;
  FRightSplitter := ARightSplitter;
  FAllTools := TList<TToolPlaceholderFrame>.Create;
  FLeftTools := TList<TToolPlaceholderFrame>.Create;
  FRightTools := TList<TToolPlaceholderFrame>.Create;
  FLastSides := TDictionary<TToolPlaceholderFrame, TVectDockSide>.Create;
  FLastIndices := TDictionary<TToolPlaceholderFrame, Integer>.Create;
  HideDropTargets;
end;

destructor TVectDockManager.Destroy;
var
  Frame: TToolPlaceholderFrame;
begin
  for Frame in FAllTools do
  begin
    Frame.OnDetached := nil;
    Frame.OnCloseRequest := nil;
    Frame.OnDockRequest := nil;
    Frame.OnDragMove := nil;
  end;
  FLastIndices.Free;
  FLastSides.Free;
  FRightTools.Free;
  FLeftTools.Free;
  FAllTools.Free;
  inherited Destroy;
end;

function TVectDockManager.AreaForSide(Side: TVectDockSide): TPanel;
begin
  if Side = vdsLeft then
    Result := FLeftArea
  else
    Result := FRightArea;
end;

procedure TVectDockManager.DockFrame(Frame: TToolPlaceholderFrame;
  Side: TVectDockSide; Index: Integer);
var
  Area: TPanel;
  Slot: TPanel;
  Tools: TList<TToolPlaceholderFrame>;
begin
  Tools := ToolsForSide(Side);
  Index := EnsureRange(Index, 0, Tools.Count);
  Area := AreaForSide(Side);
  Slot := TPanel.Create(FOwnerForm);
  Slot.Parent := Area;
  Slot.BevelOuter := bvNone;
  Slot.Color := Frame.Color;
  Slot.ParentBackground := False;
  Tools.Insert(Index, Frame);
  FLastSides.AddOrSetValue(Frame, Side);
  FLastIndices.AddOrSetValue(Frame, Index);
  Frame.DockToHost(Slot);
  Frame.LayoutEditing := FLayoutEditing;
  LayoutDockAreas;
end;

function TVectDockManager.DropSideAt(const ScreenPoint: TPoint;
  out Side: TVectDockSide): Boolean;
var
  LeftRect: TRect;
  RightRect: TRect;
  WorkspaceRect: TRect;
begin
  Result := False;
  WorkspaceRect := ScreenRect(FWorkspace);
  if not PtInRect(WorkspaceRect, ScreenPoint) then
    Exit;
  if FLeftArea.Visible then
  begin
    LeftRect := ScreenRect(FLeftArea);
    if PtInRect(LeftRect, ScreenPoint) then
    begin
      Side := vdsLeft;
      Exit(True);
    end;
  end;
  if FRightArea.Visible then
  begin
    RightRect := ScreenRect(FRightArea);
    if PtInRect(RightRect, ScreenPoint) then
    begin
      Side := vdsRight;
      Exit(True);
    end;
  end;
  if ScreenPoint.X < WorkspaceRect.Left + DOCK_TARGET_WIDTH then
  begin
    Side := vdsLeft;
    Exit(True);
  end;
  if ScreenPoint.X >= WorkspaceRect.Right - DOCK_TARGET_WIDTH then
  begin
    Side := vdsRight;
    Exit(True);
  end;
end;

procedure TVectDockManager.HideDropTargets;
begin
  FLeftDropTarget.Visible := False;
  FRightDropTarget.Visible := False;
end;

function TVectDockManager.InsertIndexAt(Side: TVectDockSide;
  const ScreenPoint: TPoint): Integer;
var
  Frame: TToolPlaceholderFrame;
  I: Integer;
  SlotRect: TRect;
  Tools: TList<TToolPlaceholderFrame>;
begin
  Tools := ToolsForSide(Side);
  for I := 0 to Tools.Count - 1 do
  begin
    Frame := Tools[I];
    SlotRect := ScreenRect(TPanel(Frame.Parent));
    if ScreenPoint.X < (SlotRect.Left + SlotRect.Right) div 2 then
      Exit(I);
  end;
  Result := Tools.Count;
end;

procedure TVectDockManager.LayoutDockArea(Side: TVectDockSide);
var
  Area: TPanel;
  Frame: TToolPlaceholderFrame;
  I: Integer;
  Slot: TPanel;
  Splitter: TSplitter;
  Tools: TList<TToolPlaceholderFrame>;
  TotalWidth: Integer;
  X: Integer;
begin
  Area := AreaForSide(Side);
  Tools := ToolsForSide(Side);
  if Side = vdsLeft then
    Splitter := FLeftSplitter
  else
    Splitter := FRightSplitter;
  if Tools.Count = 0 then
  begin
    Area.Visible := False;
    Splitter.Visible := False;
    Exit;
  end;
  TotalWidth := DOCK_GAP * (Tools.Count - 1);
  for Frame in Tools do
    Inc(TotalWidth, Frame.PreferredDockWidth);
  Area.Width := TotalWidth;
  Area.Visible := True;
  Splitter.Visible := True;
  X := 0;
  for I := 0 to Tools.Count - 1 do
  begin
    Frame := Tools[I];
    Slot := TPanel(Frame.Parent);
    Slot.SetBounds(X, 0, Frame.PreferredDockWidth, Area.ClientHeight);
    Inc(X, Frame.PreferredDockWidth + DOCK_GAP);
  end;
end;

procedure TVectDockManager.LayoutDockAreas;
begin
  FWorkspace.DisableAlign;
  try
    LayoutDockArea(vdsLeft);
    LayoutDockArea(vdsRight);
  finally
    FWorkspace.EnableAlign;
  end;
  FWorkspace.Realign;
  Resize;
end;

procedure TVectDockManager.LoadLayout(Ini: TCustomIniFile);
var
  BestFrame: TToolPlaceholderFrame;
  BestOrder: Integer;
  Bounds: TRect;
  Frame: TToolPlaceholderFrame;
  Order: Integer;
  Section: string;
  Side: TVectDockSide;
  State: string;
  Visible: Boolean;
begin
  FRestoring := True;
  try
    for Frame in FAllTools do
      if ToolVisible(Frame) then
        SetToolVisible(Frame, False);

    for Frame in FAllTools do
    begin
      Section := 'Tool.' + Frame.ToolId;
      Side := ReadToolSide(Ini, Frame);
      Order := Ini.ReadInteger(Section, 'Order',
        ToolsForSide(Side).Count);
      FLastSides.AddOrSetValue(Frame, Side);
      FLastIndices.AddOrSetValue(Frame, Order);
    end;

    for Side := Low(TVectDockSide) to High(TVectDockSide) do
      while True do
      begin
        BestFrame := nil;
        BestOrder := MaxInt;
        for Frame in FAllTools do
        begin
          Section := 'Tool.' + Frame.ToolId;
          Visible := Ini.ReadBool(Section, 'Visible', True);
          if not Visible or ToolVisible(Frame) or
            (ReadToolSide(Ini, Frame) <> Side) then
            Continue;
          Order := Ini.ReadInteger(Section, 'Order', BestOrder - 1);
          if Order < BestOrder then
          begin
            BestFrame := Frame;
            BestOrder := Order;
          end;
        end;
        if BestFrame = nil then
          Break;
        DockFrame(BestFrame, Side, ToolsForSide(Side).Count);
      end;

    for Frame in FAllTools do
    begin
      Section := 'Tool.' + Frame.ToolId;
      State := Ini.ReadString(Section, 'State', 'Docked');
      if ToolVisible(Frame) and SameText(State, 'Floating') then
      begin
        Bounds := Rect(
          Ini.ReadInteger(Section, 'FloatingLeft', 100),
          Ini.ReadInteger(Section, 'FloatingTop', 100),
          0, 0);
        Bounds.Right := Bounds.Left + Ini.ReadInteger(Section,
          'FloatingWidth', Max(Frame.PreferredDockWidth, 160));
        Bounds.Bottom := Bounds.Top + Ini.ReadInteger(Section,
          'FloatingHeight', 600);
        Bounds.Right := Bounds.Left + Max(Bounds.Width, 160);
        Bounds.Bottom := Bounds.Top + Max(Bounds.Height, 120);
        Frame.FloatAt(ConstrainToolBounds(Bounds));
      end;
    end;
  finally
    FRestoring := False;
  end;
  if Assigned(FOnToolVisibilityChanged) then
    for Frame in FAllTools do
      FOnToolVisibilityChanged(Frame);
end;

function TVectDockManager.ReadToolSide(Ini: TCustomIniFile;
  Frame: TToolPlaceholderFrame): TVectDockSide;
var
  DefaultSide: TVectDockSide;
  SideText: string;
begin
  if not FLastSides.TryGetValue(Frame, DefaultSide) then
    DefaultSide := vdsLeft;
  SideText := Ini.ReadString('Tool.' + Frame.ToolId, 'Side', '');
  if SameText(SideText, 'Right') then
    Result := vdsRight
  else if SameText(SideText, 'Left') then
    Result := vdsLeft
  else
    Result := DefaultSide;
end;

procedure TVectDockManager.SaveLayout(Ini: TCustomIniFile);
var
  Bounds: TRect;
  Frame: TToolPlaceholderFrame;
  Index: Integer;
  Section: string;
  Side: TVectDockSide;
begin
  for Frame in FAllTools do
  begin
    Section := 'Tool.' + Frame.ToolId;
    Ini.WriteBool(Section, 'Visible', ToolVisible(Frame));
    if Frame.IsFloating then
      Ini.WriteString(Section, 'State', 'Floating')
    else if ToolVisible(Frame) then
      Ini.WriteString(Section, 'State', 'Docked')
    else
      Ini.WriteString(Section, 'State', 'Hidden');
    if not FLastSides.TryGetValue(Frame, Side) then
      Side := vdsLeft;
    if Side = vdsLeft then
      Ini.WriteString(Section, 'Side', 'Left')
    else
      Ini.WriteString(Section, 'Side', 'Right');
    Index := ToolsForSide(Side).IndexOf(Frame);
    if (Index < 0) and not FLastIndices.TryGetValue(Frame, Index) then
      Index := ToolsForSide(Side).Count;
    Ini.WriteInteger(Section, 'Order', Index);
    Bounds := Frame.FloatingBounds;
    Ini.WriteInteger(Section, 'FloatingLeft', Bounds.Left);
    Ini.WriteInteger(Section, 'FloatingTop', Bounds.Top);
    Ini.WriteInteger(Section, 'FloatingWidth', Bounds.Width);
    Ini.WriteInteger(Section, 'FloatingHeight', Bounds.Height);
  end;
end;

procedure TVectDockManager.RegisterTool(Frame: TToolPlaceholderFrame;
  DefaultSide: TVectDockSide; DefaultIndex: Integer);
begin
  if FAllTools.Contains(Frame) then
    Exit;
  FAllTools.Add(Frame);
  Frame.ConfigureFloatingOwner(FOwnerForm);
  Frame.OnCloseRequest := ToolCloseRequested;
  Frame.OnDetached := ToolDetached;
  Frame.OnDockRequest := ToolDockRequest;
  Frame.OnDragMove := ToolDragMove;
  if DefaultIndex < 0 then
    DefaultIndex := ToolsForSide(DefaultSide).Count;
  DockFrame(Frame, DefaultSide, DefaultIndex);
end;

procedure TVectDockManager.SetToolVisible(Frame: TToolPlaceholderFrame;
  const Value: Boolean);
var
  Index: Integer;
  Side: TVectDockSide;
  Slot: TWinControl;
begin
  if not FAllTools.Contains(Frame) or (ToolVisible(Frame) = Value) then
    Exit;
  if Value then
  begin
    if not FLastSides.TryGetValue(Frame, Side) then
      Side := vdsLeft;
    if not FLastIndices.TryGetValue(Frame, Index) then
      Index := ToolsForSide(Side).Count;
    DockFrame(Frame, Side, Index);
  end
  else
  begin
    HideDropTargets;
    if Frame.IsFloating then
      Frame.HideToolWindow
    else
    begin
      Slot := Frame.Parent;
      Index := FLeftTools.IndexOf(Frame);
      if Index >= 0 then
      begin
        Side := vdsLeft;
        FLeftTools.Delete(Index);
      end
      else
      begin
        Index := FRightTools.IndexOf(Frame);
        if Index < 0 then
          Exit;
        Side := vdsRight;
        FRightTools.Delete(Index);
      end;
      FLastSides.AddOrSetValue(Frame, Side);
      FLastIndices.AddOrSetValue(Frame, Index);
      Frame.HideToolWindow;
      Slot.Free;
      LayoutDockAreas;
    end;
  end;
  if not FRestoring and Assigned(FOnToolVisibilityChanged) then
    FOnToolVisibilityChanged(Frame);
end;

function TVectDockManager.ToolVisible(Frame: TToolPlaceholderFrame): Boolean;
begin
  Result := FAllTools.Contains(Frame) and
    (Frame.IsFloating or (Frame.Parent <> nil));
end;

procedure TVectDockManager.Resize;
var
  Frame: TToolPlaceholderFrame;
begin
  for Frame in FLeftTools do
    TPanel(Frame.Parent).Height := FLeftArea.ClientHeight;
  for Frame in FRightTools do
    TPanel(Frame.Parent).Height := FRightArea.ClientHeight;
  if FLeftDropTarget.Visible then
    FLeftDropTarget.SetBounds(0, 0, DOCK_TARGET_WIDTH, FWorkspace.ClientHeight);
  if FRightDropTarget.Visible then
    FRightDropTarget.SetBounds(FWorkspace.ClientWidth - DOCK_TARGET_WIDTH, 0,
      DOCK_TARGET_WIDTH, FWorkspace.ClientHeight);
end;

function TVectDockManager.ScreenRect(Control: TPanel): TRect;
var
  BottomRight: TPoint;
  TopLeft: TPoint;
begin
  TopLeft := Control.ClientToScreen(Point(0, 0));
  BottomRight := Control.ClientToScreen(Point(Control.ClientWidth,
    Control.ClientHeight));
  Result := Rect(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y);
end;

procedure TVectDockManager.SetLayoutEditing(const Value: Boolean);
var
  Frame: TToolPlaceholderFrame;
  Side: TVectDockSide;
begin
  if FLayoutEditing = Value then
    Exit;
  FLayoutEditing := Value;
  if not Value then
  begin
    HideDropTargets;
    for Frame in FAllTools do
      if Frame.IsFloating then
      begin
        if not FLastSides.TryGetValue(Frame, Side) then
          Side := vdsLeft;
        DockFrame(Frame, Side, ToolsForSide(Side).Count);
      end;
  end;
  for Frame in FAllTools do
    Frame.LayoutEditing := Value;
end;

function TVectDockManager.ToolsForSide(
  Side: TVectDockSide): TList<TToolPlaceholderFrame>;
begin
  if Side = vdsLeft then
    Result := FLeftTools
  else
    Result := FRightTools;
end;

procedure TVectDockManager.ToolDetached(Sender: TToolPlaceholderFrame);
var
  Index: Integer;
  Side: TVectDockSide;
  Slot: TWinControl;
begin
  Slot := Sender.Parent;
  Index := FLeftTools.IndexOf(Sender);
  if Index >= 0 then
  begin
    Side := vdsLeft;
    FLeftTools.Delete(Index);
  end
  else
  begin
    Index := FRightTools.IndexOf(Sender);
    if Index < 0 then
      Exit;
    Side := vdsRight;
    FRightTools.Delete(Index);
  end;
  FLastSides.AddOrSetValue(Sender, Side);
  FLastIndices.AddOrSetValue(Sender, Index);
  Sender.Parent := nil;
  Slot.Free;
  LayoutDockAreas;
end;

procedure TVectDockManager.ToolCloseRequested(Sender: TToolPlaceholderFrame);
begin
  if FLayoutEditing then
    SetToolVisible(Sender, False);
end;

procedure TVectDockManager.ToolDockRequest(Sender: TToolPlaceholderFrame;
  const ScreenPoint: TPoint; var Accepted: Boolean);
var
  Index: Integer;
  Side: TVectDockSide;
begin
  Accepted := DropSideAt(ScreenPoint, Side);
  if Accepted then
  begin
    Index := InsertIndexAt(Side, ScreenPoint);
    DockFrame(Sender, Side, Index);
  end;
  HideDropTargets;
end;

procedure TVectDockManager.ToolDragMove(Sender: TToolPlaceholderFrame;
  const ScreenPoint: TPoint);
begin
  UpdateDropTargets(ScreenPoint);
end;

procedure TVectDockManager.UpdateDropTargets(const ScreenPoint: TPoint);
var
  Side: TVectDockSide;
begin
  FLeftDropTarget.Visible := True;
  FRightDropTarget.Visible := True;
  FLeftDropTarget.Color := COLOR_TARGET_IDLE;
  FRightDropTarget.Color := COLOR_TARGET_IDLE;
  if DropSideAt(ScreenPoint, Side) then
  begin
    if Side = vdsLeft then
      FLeftDropTarget.Color := COLOR_TARGET_HOT
    else
      FRightDropTarget.Color := COLOR_TARGET_HOT;
  end;
  Resize;
  FLeftDropTarget.BringToFront;
  FRightDropTarget.BringToFront;
end;

end.
