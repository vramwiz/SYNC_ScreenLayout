// Codex向けScreenLayout専用JSONプロトコルを解析し、Documentと履歴へ安全に接続する。
unit ScreenLayoutAutomationProtocol;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditHistory, ScreenLayoutEditorState;

const
  SCREEN_LAYOUT_AUTOMATION_PIPE_SHORT_NAME = 'ScreenDesignMaker.v1';
  SCREEN_LAYOUT_AUTOMATION_PIPE_NAME = '\\.\pipe\ScreenDesignMaker.v1';
  SCREEN_LAYOUT_AUTOMATION_PROTOCOL = 'ScreenDesignMaker';
  SCREEN_LAYOUT_AUTOMATION_VERSION = 1;

// VCLスレッド上で1要求を処理し、必ずJSON応答を返す。
function HandleScreenLayoutAutomationRequest(const RequestText: string;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState): string;

implementation

uses
  System.Hash, System.JSON, System.SysUtils,
  ScreenLayoutAutomationDocumentCommand, ScreenLayoutDocumentJson;

const
  MAX_REQUEST_CHARS = 4 * 1024 * 1024;

function StateToken(const JsonText: string): string;
begin
  Result := 'sha256:' + LowerCase(THashSHA2.GetHashString(JsonText));
end;

procedure AddHeader(Root: TJSONObject; const Command, Status: string);
begin
  Root.AddPair('protocol', SCREEN_LAYOUT_AUTOMATION_PROTOCOL);
  Root.AddPair('protocol_version', TJSONNumber.Create(
    SCREEN_LAYOUT_AUTOMATION_VERSION));
  Root.AddPair('command', Command);
  Root.AddPair('status', Status);
end;

function ErrorResponse(const Command, Code, MessageText: string): string;
var
  ErrorJson: TJSONObject;
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Command, 'error');
    ErrorJson := TJSONObject.Create;
    ErrorJson.AddPair('code', Code);
    ErrorJson.AddPair('message', MessageText);
    Root.AddPair('error', ErrorJson);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function OkResponse(const Command: string; Payload: TJSONPair): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    AddHeader(Root, Command, 'ok');
    if Payload <> nil then
      Root.AddPair(Payload);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function JsonString(Root: TJSONObject; const Name: string;
  out Value: string): Boolean;
var
  JsonValue: TJSONValue;
begin
  JsonValue := Root.GetValue(Name);
  Result := JsonValue is TJSONString;
  if Result then
    Value := TJSONString(JsonValue).Value
  else
    Value := '';
end;

function ApplyRequested(Root: TJSONObject): Boolean;
var
  Value: TJSONValue;
begin
  Value := Root.GetValue('apply');
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function ValidateIncomingDocument(Root: TJSONObject;
  out NormalizedJson, ErrorMessage: string): Boolean;
var
  Incoming: TJSONValue;
  TempDocument: TVectArtDocument;
begin
  Result := False;
  NormalizedJson := '';
  ErrorMessage := '';
  Incoming := Root.GetValue('document');
  if not (Incoming is TJSONObject) then
  begin
    ErrorMessage := 'document must be a JSON object.';
    Exit;
  end;
  TempDocument := TVectArtDocument.Create;
  try
    if not TryDeserializeVectArtDocument(Incoming.ToJSON, TempDocument,
      ErrorMessage) then
      Exit;
    NormalizedJson := SerializeVectArtDocument(TempDocument);
    Result := True;
  finally
    TempDocument.Free;
  end;
end;

function BuildCapabilities(const Command: string): string;
var
  Commands: TJSONArray;
  ResultJson: TJSONObject;
begin
  ResultJson := TJSONObject.Create;
  Commands := TJSONArray.Create;
  Commands.Add('get_capabilities');
  Commands.Add('get_editor_state');
  Commands.Add('get_document');
  Commands.Add('preview_replace_document');
  Commands.Add('replace_document');
  Commands.Add('undo');
  Commands.Add('redo');
  ResultJson.AddPair('commands', Commands);
  ResultJson.AddPair('pipe', SCREEN_LAYOUT_AUTOMATION_PIPE_NAME);
  ResultJson.AddPair('max_request_bytes', TJSONNumber.Create(
    MAX_REQUEST_CHARS));
  Result := OkResponse(Command, TJSONPair.Create('capabilities', ResultJson));
end;

function BuildEditorState(const Command: string; Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory): string;
var
  DocumentJson: string;
  State: TJSONObject;
begin
  DocumentJson := SerializeVectArtDocument(Document);
  State := TJSONObject.Create;
  State.AddPair('state_token', StateToken(DocumentJson));
  State.AddPair('canvas_width', TJSONNumber.Create(Document.CanvasLayer.Width));
  State.AddPair('canvas_height', TJSONNumber.Create(Document.CanvasLayer.Height));
  State.AddPair('layer_count', TJSONNumber.Create(Document.LayerCount - 1));
  State.AddPair('selection_count', TJSONNumber.Create(Document.SelectionCount));
  State.AddPair('can_undo', TJSONBool.Create(EditHistory.CanUndo));
  State.AddPair('can_redo', TJSONBool.Create(EditHistory.CanRedo));
  Result := OkResponse(Command, TJSONPair.Create('editor', State));
end;

function BuildDocument(const Command: string;
  Document: TVectArtDocument): string;
var
  DocumentJson: string;
  DocumentValue: TJSONValue;
  Root: TJSONObject;
begin
  DocumentJson := SerializeVectArtDocument(Document);
  DocumentValue := TJSONObject.ParseJSONValue(DocumentJson);
  if DocumentValue = nil then
    Exit(ErrorResponse(Command, 'serialize_failed',
      'The current document could not be encoded as JSON.'));
  Root := TJSONObject.Create;
  Root.AddPair('state_token', StateToken(DocumentJson));
  Root.AddPair('document', DocumentValue);
  Result := OkResponse(Command, TJSONPair.Create('snapshot', Root));
end;

function HandleReplace(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; Apply: Boolean): string;
var
  CurrentJson: string;
  ErrorMessage: string;
  ExpectedToken: string;
  NormalizedJson: string;
  ResultJson: TJSONObject;
  ReplaceCommand: TScreenLayoutAutomationDocumentCommand;
begin
  CurrentJson := SerializeVectArtDocument(Document);
  if not JsonString(Root, 'state_token', ExpectedToken) then
    Exit(ErrorResponse(Command, 'state_token_required',
      'state_token is required.'));
  if ExpectedToken <> StateToken(CurrentJson) then
    Exit(ErrorResponse(Command, 'state_changed',
      'The editor document changed. Get a new snapshot before retrying.'));
  if not ValidateIncomingDocument(Root, NormalizedJson, ErrorMessage) then
    Exit(ErrorResponse(Command, 'invalid_document', ErrorMessage));
  if Apply and not ApplyRequested(Root) then
    Exit(ErrorResponse(Command, 'apply_required',
      'replace_document requires apply: true.'));

  if Apply and (NormalizedJson <> CurrentJson) then
  begin
    if EditorState <> nil then
      EditorState.OpenGroup := nil;
    ReplaceCommand := TScreenLayoutAutomationDocumentCommand.Create(
      Document, CurrentJson, NormalizedJson);
    try
      ReplaceCommand.Execute;
      EditHistory.AddApplied(ReplaceCommand);
      ReplaceCommand := nil;
    finally
      ReplaceCommand.Free;
    end;
    NormalizedJson := SerializeVectArtDocument(Document);
  end;

  ResultJson := TJSONObject.Create;
  ResultJson.AddPair('applied', TJSONBool.Create(Apply));
  ResultJson.AddPair('changed', TJSONBool.Create(NormalizedJson <> CurrentJson));
  ResultJson.AddPair('state_token', StateToken(NormalizedJson));
  Result := OkResponse(Command, TJSONPair.Create('change', ResultJson));
end;

function HandleHistory(const Command: string; Root: TJSONObject;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState; UndoOperation: Boolean): string;
var
  CurrentJson: string;
  ExpectedToken: string;
  ResultJson: TJSONObject;
begin
  CurrentJson := SerializeVectArtDocument(Document);
  if not JsonString(Root, 'state_token', ExpectedToken) or
    (ExpectedToken <> StateToken(CurrentJson)) then
    Exit(ErrorResponse(Command, 'state_changed',
      'Get the current editor state before changing history.'));
  if not ApplyRequested(Root) then
    Exit(ErrorResponse(Command, 'apply_required',
      Command + ' requires apply: true.'));
  if UndoOperation and not EditHistory.CanUndo then
    Exit(ErrorResponse(Command, 'undo_unavailable', 'There is nothing to undo.'));
  if not UndoOperation and not EditHistory.CanRedo then
    Exit(ErrorResponse(Command, 'redo_unavailable', 'There is nothing to redo.'));
  if EditorState <> nil then
    EditorState.OpenGroup := nil;
  if UndoOperation then
    EditHistory.Undo
  else
    EditHistory.Redo;
  CurrentJson := SerializeVectArtDocument(Document);
  ResultJson := TJSONObject.Create;
  ResultJson.AddPair('applied', TJSONBool.Create(True));
  ResultJson.AddPair('state_token', StateToken(CurrentJson));
  Result := OkResponse(Command, TJSONPair.Create('change', ResultJson));
end;

function HandleScreenLayoutAutomationRequest(const RequestText: string;
  Document: TVectArtDocument; EditHistory: TVectArtEditHistory;
  EditorState: TVectArtEditorState): string;
var
  Command: string;
  Json: TJSONValue;
  Root: TJSONObject;
begin
  Command := '';
  if Length(RequestText) > MAX_REQUEST_CHARS then
    Exit(ErrorResponse(Command, 'request_too_large',
      'The request exceeds the 4 MiB limit.'));
  if (Document = nil) or (EditHistory = nil) then
    Exit(ErrorResponse(Command, 'editor_unavailable',
      'The ScreenLayout editor is not ready.'));
  Json := TJSONObject.ParseJSONValue(RequestText);
  try
    try
      if not (Json is TJSONObject) then
        Exit(ErrorResponse(Command, 'invalid_json',
          'Request must be a JSON object.'));
      Root := TJSONObject(Json);
      if not JsonString(Root, 'command', Command) then
        Exit(ErrorResponse(Command, 'invalid_command', 'command is required.'));
      if SameText(Command, 'get_capabilities') then
        Result := BuildCapabilities(Command)
      else if SameText(Command, 'get_editor_state') then
        Result := BuildEditorState(Command, Document, EditHistory)
      else if SameText(Command, 'get_document') then
        Result := BuildDocument(Command, Document)
      else if SameText(Command, 'preview_replace_document') then
        Result := HandleReplace(Command, Root, Document, EditHistory,
          EditorState, False)
      else if SameText(Command, 'replace_document') then
        Result := HandleReplace(Command, Root, Document, EditHistory,
          EditorState, True)
      else if SameText(Command, 'undo') then
        Result := HandleHistory(Command, Root, Document, EditHistory,
          EditorState, True)
      else if SameText(Command, 'redo') then
        Result := HandleHistory(Command, Root, Document, EditHistory,
          EditorState, False)
      else
        Result := ErrorResponse(Command, 'unknown_command',
          'The command is not supported.');
    except
      on E: Exception do
        Result := ErrorResponse(Command, 'internal_error', E.Message);
    end;
  finally
    Json.Free;
  end;
end;

end.
