// 画面レイアウト編集用のCodex指示欄、進捗表示、通信ワーカーの終了を管理する。
unit ScreenLayoutCodexPanel;

interface

uses
  System.Classes, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls,
  ScreenLayoutCodexJob;

type
  TScreenLayoutCodexCommand = function(const Request: string): string of object;

  TScreenLayoutCodexPanel = class(TPanel)
  private
    FAction: TButton;                      // 送信と停止を切り替える。
    FExecuteCommand: TScreenLayoutCodexCommand; // UIスレッドで現在の文書を操作する。
    FJob: TScreenLayoutCodexJob;            // 送信1回に対応する通信ワーカー。
    FPrompt: TMemo;                         // 利用者が入力した複数行の指示。
    FStatus: TLabel;                        // 進捗または結果を表示する。
    FTimer: TTimer;                         // ワーカー稼働中だけコマンドを受け取る。
    procedure ActionClick(Sender: TObject);
    procedure Poll(Sender: TObject);
    procedure PromptChanged(Sender: TObject);
    procedure SetStatus(const Value: string);
  public
    // 編集ホスト下端に入力欄を追加し、同じ画面のコマンド実行口へ接続する。
    constructor CreateForHost(Host: TWinControl; ExecuteCommand: TScreenLayoutCodexCommand);
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils, Vcl.Graphics, Winapi.Windows;

constructor TScreenLayoutCodexPanel.CreateForHost(Host: TWinControl;
  ExecuteCommand: TScreenLayoutCodexCommand);
var
  Ppi: Integer;
  Gap: Integer;
  ButtonHost: TPanel;
begin
  inherited Create(Host);
  FExecuteCommand := ExecuteCommand;
  Host.DisableAlign;
  try
    Parent := Host;
    Ppi := Host.CurrentPPI;
    Gap := MulDiv(6, Ppi, 96);
    Align := alBottom;
    Height := MulDiv(98, Ppi, 96);
    BevelOuter := bvNone;
    Color := $00222222;
    ParentBackground := False;
    Padding.SetBounds(Gap, Gap, Gap, Gap);

    FStatus := TLabel.Create(Self);
    FStatus.Parent := Self;
    FStatus.Align := alBottom;
    FStatus.AutoSize := False;
    FStatus.Height := MulDiv(20, Ppi, 96);
    FStatus.Layout := tlCenter;
    FStatus.EllipsisPosition := epEndEllipsis;
    FStatus.Font.Color := clWhite;
    FStatus.ShowHint := True;

    ButtonHost := TPanel.Create(Self);
    ButtonHost.Parent := Self;
    ButtonHost.Align := alRight;
    ButtonHost.Width := MulDiv(92, Ppi, 96);
    ButtonHost.BevelOuter := bvNone;
    ButtonHost.Padding.Left := Gap;

    FAction := TButton.Create(Self);
    FAction.Parent := ButtonHost;
    FAction.Align := alTop;
    FAction.Height := MulDiv(28, Ppi, 96);
    FAction.Caption := '送信';
    FAction.Enabled := False;
    FAction.OnClick := ActionClick;

    FPrompt := TMemo.Create(Self);
    FPrompt.Parent := Self;
    FPrompt.Align := alClient;
    FPrompt.Color := $00303030;
    FPrompt.Font.Color := clWhite;
    FPrompt.ScrollBars := ssVertical;
    FPrompt.MaxLength := 32000;
    FPrompt.Hint := 'Codexへの指示';
    FPrompt.ShowHint := True;
    FPrompt.OnChange := PromptChanged;
    SetStatus('Codexへの指示');
  finally
    Host.EnableAlign;
  end;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 60;
  FTimer.OnTimer := Poll;
end;

destructor TScreenLayoutCodexPanel.Destroy;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  FreeAndNil(FJob);
  inherited Destroy;
end;

procedure TScreenLayoutCodexPanel.SetStatus(const Value: string);
begin
  if FStatus.Hint = Value then
    Exit;
  FStatus.Caption := Value.Replace(#13, ' ').Replace(#10, ' ');
  FStatus.Hint := Value;
end;

procedure TScreenLayoutCodexPanel.PromptChanged(Sender: TObject);
begin
  if FJob = nil then
    FAction.Enabled := Trim(FPrompt.Text) <> '';
end;

procedure TScreenLayoutCodexPanel.ActionClick(Sender: TObject);
var
  Instruction: string;
begin
  if FJob <> nil then
  begin
    FJob.RequestStop;
    FAction.Enabled := False;
    SetStatus('停止しています');
    Exit;
  end;

  Instruction := Trim(FPrompt.Text);
  if Instruction = '' then
    Exit;
  try
    FJob := TScreenLayoutCodexJob.Create(Instruction);
    FJob.BeginRun;
    FPrompt.ReadOnly := True;
    FAction.Caption := '停止';
    SetStatus(FJob.Stage);
    FTimer.Enabled := True;
  except
    on E: Exception do
    begin
      FreeAndNil(FJob);
      SetStatus(E.Message);
    end;
  end;
end;

procedure TScreenLayoutCodexPanel.Poll(Sender: TObject);
var
  Request: string;
begin
  if FJob = nil then
    Exit;
  if FAction.Enabled then
    SetStatus(FJob.Stage);
  if FJob.TakeRequest(Request) then
    FJob.CompleteRequest(FExecuteCommand(Request));
  if WaitForSingleObject(FJob.Handle, 0) <> WAIT_OBJECT_0 then
    Exit;

  FTimer.Enabled := False;
  if FJob.Success then
    SetStatus(FJob.Answer)
  else if FJob.ErrorText <> '' then
    SetStatus(FJob.ErrorText)
  else
    SetStatus('停止しました');
  FreeAndNil(FJob);
  FPrompt.ReadOnly := False;
  FAction.Caption := '送信';
  PromptChanged(FPrompt);
end;

end.
