// SVG／MIFファイルを開く、保存する、別名保存するメニューと標準ファイルダイアログを提供する。
// 実際の読込・保存処理は持たず、選択されたファイル名をホストへ通知する。
unit VectArtDesignerFileActionsUI;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls,
  VectArtDarkPopupMenu;

type
  TVectArtFileNameEvent = procedure(Sender: TObject;
    const FileName: string) of object;

  TVectArtFileActionsUI = class(TComponent)
  private
    FCanSave: Boolean;
    FCurrentFileName: string;
    FMenu: TVectArtDarkPopupMenu;
    FOnOpenFile: TVectArtFileNameEvent;
    FOnSaveFile: TVectArtFileNameEvent;
    FOpenDialog: TOpenDialog;
    FSaveDialog: TSaveDialog;
    FSaveAsItem: TPanel;
    FSaveItem: TPanel;
    function NewMenuItem(const Caption: string; Top: Integer;
      ClickHandler: TNotifyEvent): TPanel;
    procedure OpenClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveTypeChange(Sender: TObject);
    procedure SetCanSave(const Value: Boolean);
  public
    constructor CreateForHosts(AOwner: TComponent; AMainForm,
      AMenuBar: TWinControl);
    procedure ExecuteOpen;
    procedure ExecuteSave;
    procedure ExecuteSaveAs;
    property CanSave: Boolean read FCanSave write SetCanSave;
    property CurrentFileName: string read FCurrentFileName
      write FCurrentFileName;
    property Menu: TVectArtDarkPopupMenu read FMenu;
    property OnOpenFile: TVectArtFileNameEvent read FOnOpenFile
      write FOnOpenFile;
    property OnSaveFile: TVectArtFileNameEvent read FOnSaveFile
      write FOnSaveFile;
  end;

implementation

uses
  System.SysUtils;

constructor TVectArtFileActionsUI.CreateForHosts(AOwner: TComponent;
  AMainForm, AMenuBar: TWinControl);
begin
  inherited Create(AOwner);
  FMenu := TVectArtDarkPopupMenu.CreateForHosts(Self, AMainForm, AMenuBar,
    'ファイル', 0, 56, 240, 96);
  NewMenuItem('開く...               Ctrl+O', 0, OpenClick);
  FSaveItem := NewMenuItem('上書き保存          Ctrl+S', 32, SaveClick);
  FSaveAsItem := NewMenuItem('名前を付けて保存...  Ctrl+Shift+S', 64,
    SaveAsClick);

  FOpenDialog := TOpenDialog.Create(Self);
  FOpenDialog.DefaultExt := '';
  FOpenDialog.Filter := '対応ファイル (*.mif;*.svg)|*.mif;*.svg|' +
    'MIFファイル (*.mif)|*.mif|SVGファイル (*.svg)|*.svg|' +
    'すべてのファイル (*.*)|*.*';
  FOpenDialog.Options := FOpenDialog.Options + [ofFileMustExist, ofPathMustExist];
  FOpenDialog.Title := 'デザインファイルを開く';

  FSaveDialog := TSaveDialog.Create(Self);
  FSaveDialog.DefaultExt := 'svg';
  FSaveDialog.Filter := 'SVGファイル (*.svg)|*.svg|' +
    'MIFファイル (*.mif)|*.mif|すべてのファイル (*.*)|*.*';
  FSaveDialog.Options := FSaveDialog.Options +
    [ofOverwritePrompt, ofPathMustExist];
  FSaveDialog.Title := 'デザインファイルを保存';
  FSaveDialog.OnTypeChange := SaveTypeChange;
  SetCanSave(False);
  FMenu.SetItemEnabled(FSaveAsItem, True);
end;

procedure TVectArtFileActionsUI.ExecuteOpen;
begin
  FMenu.Close;
  if FOpenDialog.Execute and Assigned(FOnOpenFile) then
    FOnOpenFile(Self, FOpenDialog.FileName);
end;

procedure TVectArtFileActionsUI.ExecuteSave;
begin
  FMenu.Close;
  if not FCanSave then
    Exit;
  if FCurrentFileName = '' then
    ExecuteSaveAs
  else if Assigned(FOnSaveFile) then
    FOnSaveFile(Self, FCurrentFileName);
end;

procedure TVectArtFileActionsUI.ExecuteSaveAs;
begin
  FMenu.Close;
  FSaveDialog.FileName := FCurrentFileName;
  if SameText(ExtractFileExt(FCurrentFileName), '.mif') then
    FSaveDialog.FilterIndex := 2
  else
    FSaveDialog.FilterIndex := 1;
  SaveTypeChange(FSaveDialog);
  if FSaveDialog.Execute and Assigned(FOnSaveFile) then
    FOnSaveFile(Self, FSaveDialog.FileName);
end;

function TVectArtFileActionsUI.NewMenuItem(const Caption: string; Top: Integer;
  ClickHandler: TNotifyEvent): TPanel;
begin
  Result := FMenu.AddItem(Caption, Top, ClickHandler);
end;

procedure TVectArtFileActionsUI.OpenClick(Sender: TObject);
begin
  ExecuteOpen;
end;

procedure TVectArtFileActionsUI.SaveAsClick(Sender: TObject);
begin
  ExecuteSaveAs;
end;

procedure TVectArtFileActionsUI.SaveClick(Sender: TObject);
begin
  ExecuteSave;
end;

procedure TVectArtFileActionsUI.SaveTypeChange(Sender: TObject);
begin
  if FSaveDialog.FilterIndex = 2 then
    FSaveDialog.DefaultExt := 'mif'
  else
    FSaveDialog.DefaultExt := 'svg';
end;

procedure TVectArtFileActionsUI.SetCanSave(const Value: Boolean);
begin
  FCanSave := Value;
  FMenu.SetItemEnabled(FSaveItem, Value);
end;

end.
