// レイヤーツールのFrameを提供し、Documentをレイヤー一覧へ接続する。
unit ScreenLayoutLayerPanelFrame;

interface

uses
  System.Classes, ScreenLayoutContext, ScreenLayoutLayerActions,
  ScreenLayoutLayerList, ScreenLayoutLayerOperations,
  ScreenLayoutToolFrames;

type
  TLayerPanelFrame = class(TToolPlaceholderFrame)
  private
    FLayerList: TVectArtLayerListControl;
    FLayerActions: TVectArtLayerActionsControl;
    FContext: IVectArtDesignerContext;
    procedure SetContext(const Value: IVectArtDesignerContext);
  public
    constructor Create(AOwner: TComponent); override;
    function CanRunLayerAction(Action: TVectArtLayerAction): Boolean;
    procedure RunLayerAction(Action: TVectArtLayerAction);
    procedure RefreshFromDocument;
    // Contextを交換すると、一覧と操作バーへ同じサービス一式を接続する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
    property LayerList: TVectArtLayerListControl read FLayerList;
  end;

implementation

uses
  Vcl.Controls, Vcl.Graphics;

{$R ScreenLayoutLayerPanelFrame.dfm}

const
  COLOR_PANEL_BACKGROUND = TColor($00212121);

function TLayerPanelFrame.CanRunLayerAction(
  Action: TVectArtLayerAction): Boolean;
begin
  Result := FLayerActions.CanRunLayerAction(Action);
end;

constructor TLayerPanelFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConfigureToolAppearance('Layers', 'Layers', COLOR_PANEL_BACKGROUND, 224);
  TitleLabel.Visible := False;
  FLayerList := TVectArtLayerListControl.Create(Self);
  FLayerList.Parent := Self;
  FLayerList.Align := alClient;
  FLayerActions := TVectArtLayerActionsControl.Create(Self);
  FLayerActions.Parent := Self;
  FLayerActions.Align := alBottom;
  FLayerActions.Height := 34;
  FLayerActions.BringToFront;
end;

procedure TLayerPanelFrame.RunLayerAction(Action: TVectArtLayerAction);
begin
  FLayerActions.RunLayerAction(Action);
end;

procedure TLayerPanelFrame.RefreshFromDocument;
begin
  FLayerList.Invalidate;
  FLayerActions.RefreshState;
end;

procedure TLayerPanelFrame.SetContext(const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  if FContext = nil then
  begin
    FLayerActions.EditorState := nil;
    FLayerActions.EditHistory := nil;
    FLayerActions.Document := nil;
    FLayerList.EditHistory := nil;
    FLayerList.EditorState := nil;
    FLayerList.Document := nil;
  end
  else
  begin
    FLayerList.Document := FContext.Document;
    FLayerList.EditHistory := FContext.EditHistory;
    FLayerList.EditorState := FContext.EditorState;
    FLayerActions.Document := FContext.Document;
    FLayerActions.EditHistory := FContext.EditHistory;
    FLayerActions.EditorState := FContext.EditorState;
  end;
end;

end.
