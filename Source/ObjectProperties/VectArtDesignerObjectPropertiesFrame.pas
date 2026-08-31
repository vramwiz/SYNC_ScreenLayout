// 選択オブジェクト設定ツールのFrame外枠を提供する。
unit VectArtDesignerObjectPropertiesFrame;

interface

uses
  System.Classes, VectArtDesignerContext,
  VectArtDesignerObjectPropertiesControl, VectArtDesignerToolFrames;

type
  TObjectPropertiesFrame = class(TToolPlaceholderFrame)
  private
    FPropertiesControl: TVectArtObjectPropertiesControl;
    FContext: IVectArtDesignerContext;
    procedure SetContext(const Value: IVectArtDesignerContext);
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshFromDocument;
    // Contextを交換すると、プロパティ編集Controlへサービス一式を接続する。
    property Context: IVectArtDesignerContext read FContext write SetContext;
  end;

implementation

uses
  Vcl.Controls, Vcl.Graphics;

{$R VectArtDesignerObjectPropertiesFrame.dfm}

const
  COLOR_PANEL_BACKGROUND = TColor($00212121);

constructor TObjectPropertiesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ConfigureToolAppearance('ObjectProperties', 'Object Properties',
    COLOR_PANEL_BACKGROUND, 290);
  TitleLabel.Visible := False;
  FPropertiesControl := TVectArtObjectPropertiesControl.Create(Self);
  FPropertiesControl.Parent := Self;
  FPropertiesControl.Align := alClient;
end;

procedure TObjectPropertiesFrame.RefreshFromDocument;
begin
  FPropertiesControl.RefreshFromDocument;
end;

procedure TObjectPropertiesFrame.SetContext(
  const Value: IVectArtDesignerContext);
begin
  FContext := Value;
  if FContext = nil then
  begin
    FPropertiesControl.EditorState := nil;
    FPropertiesControl.EditHistory := nil;
    FPropertiesControl.Document := nil;
  end
  else
  begin
    FPropertiesControl.Document := FContext.Document;
    FPropertiesControl.EditHistory := FContext.EditHistory;
    FPropertiesControl.EditorState := FContext.EditorState;
  end;
end;

end.
