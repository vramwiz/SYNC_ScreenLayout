// ScreenLayout編集画面の生存期間だけ専用Named Pipeを公開する。
unit ScreenLayoutAutomationPipeServer;

interface

uses
  Winapi.Windows, ScreenLayoutDocument, ScreenLayoutEditHistory,
  ScreenLayoutEditorState, ScreenLayoutCanvas;

function StartScreenLayoutAutomationPipeServer(NotifyWindow: HWND;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl; out ErrorMessage: string): Boolean;
procedure StopScreenLayoutAutomationPipeServer;
procedure ProcessScreenLayoutAutomationPipeMessage(WParam: WPARAM);
// 表示時に確定したForm Handleを通知先として再設定する。
procedure UpdateScreenLayoutAutomationPipeNotifyWindow(NotifyWindow: HWND);

implementation

uses
  System.SysUtils, PipeServerTThread, ScreenLayoutAutomationProtocol;

const
  PIPE_BUFFER_SIZE = 4 * 1024 * 1024;

type
  TScreenLayoutAutomationPipeServer = class
  private
    FDocument: TVectArtDocument;       // MainForm所有。サーバー停止まで生存する。
    FEditHistory: TVectArtEditHistory; // MainForm所有。
    FEditorState: TVectArtEditorState; // MainForm所有。
    FCanvas: TVectArtCanvasControl; // MainForm所有。背景画像の複写に使用する。
    FThread: TPipeServerTThread;
    procedure Receive(Sender: TObject; const ReceivedStr: string;
      var SendStr: string);
  public
    constructor Create(NotifyWindow: HWND; Document: TVectArtDocument;
      EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl);
    destructor Destroy; override;
    procedure ProcessMessage(WParam: WPARAM);
    procedure UpdateNotifyWindow(NotifyWindow: HWND);
  end;

var
  Server: TScreenLayoutAutomationPipeServer;

constructor TScreenLayoutAutomationPipeServer.Create(NotifyWindow: HWND;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl);
begin
  inherited Create;
  FDocument := Document;
  FEditHistory := EditHistory;
  FEditorState := EditorState;
  FCanvas := Canvas;
  FThread := TPipeServerTThread.Create(
    SCREEN_LAYOUT_AUTOMATION_PIPE_SHORT_NAME, PIPE_BUFFER_SIZE, True, 1,
    NotifyWindow);
  FThread.OnReceive := Receive;
  FThread.Start;
end;

destructor TScreenLayoutAutomationPipeServer.Destroy;
var
  PipeHandle: THandle;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.ReleaseWait;
    PipeHandle := CreateFile(PChar(SCREEN_LAYOUT_AUTOMATION_PIPE_NAME),
      GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
    if PipeHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(PipeHandle);
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  inherited Destroy;
end;

procedure TScreenLayoutAutomationPipeServer.Receive(Sender: TObject;
  const ReceivedStr: string; var SendStr: string);
begin
  SendStr := HandleScreenLayoutAutomationRequest(ReceivedStr, FDocument,
    FEditHistory, FEditorState, FCanvas);
end;

procedure TScreenLayoutAutomationPipeServer.ProcessMessage(WParam: WPARAM);
begin
  if (FThread <> nil) and (WParam = NativeUInt(FThread)) then
    FThread.ProcessMainThread;
end;

procedure TScreenLayoutAutomationPipeServer.UpdateNotifyWindow(
  NotifyWindow: HWND);
begin
  if FThread <> nil then
    FThread.SetNotifyWindow(NotifyWindow);
end;

function StartScreenLayoutAutomationPipeServer(NotifyWindow: HWND;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Canvas: TVectArtCanvasControl; out ErrorMessage: string): Boolean;
begin
  Result := False;
  ErrorMessage := '';
  if Server <> nil then
  begin
    ErrorMessage := 'Another ScreenLayout editor already owns the automation pipe.';
    Exit;
  end;
  try
    Server := TScreenLayoutAutomationPipeServer.Create(NotifyWindow,
      Document, EditHistory, EditorState, Canvas);
    Result := True;
  except
    on E: Exception do
    begin
      FreeAndNil(Server);
      ErrorMessage := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure StopScreenLayoutAutomationPipeServer;
begin
  FreeAndNil(Server);
end;

procedure ProcessScreenLayoutAutomationPipeMessage(WParam: WPARAM);
begin
  if Server <> nil then
    Server.ProcessMessage(WParam);
end;

procedure UpdateScreenLayoutAutomationPipeNotifyWindow(NotifyWindow: HWND);
begin
  if Server <> nil then
    Server.UpdateNotifyWindow(NotifyWindow);
end;

end.
