// MIFの外側コンテナーを読み書きし、既知・未知を問わず全ブロックをそのまま保持する。
// Documentへの変換やIPNG内部の解釈は担当せず、破損した長さや終端を境界で拒否する。
unit VectArtDesignerMifContainer;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils;

type
  TVectArtMifChunk = class
  private
    FData: TBytes;
    FTag: AnsiString;
  public
    constructor Create(const ATag: AnsiString; const AData: TBytes);
    property Data: TBytes read FData;
    property Tag: AnsiString read FTag;
  end;

  TVectArtMifContainer = class
  private
    FChunks: TObjectList<TVectArtMifChunk>;
    function GetChunk(Index: Integer): TVectArtMifChunk;
    function GetChunkCount: Integer;
    procedure LoadFromStream(Stream: TStream);
    procedure SaveToStream(Stream: TStream);
  public
    constructor Create;
    destructor Destroy; override;
    // 新規MIF生成時に、指定タグとデータを末尾へ追加する。
    procedure AddChunk(const Tag: AnsiString; const Data: TBytes);
    property ChunkCount: Integer read GetChunkCount;
    property Chunks[Index: Integer]: TVectArtMifChunk read GetChunk; default;
  end;

  // MIFの取得元をファイルに固定せず、Container生成を抽象化する。
  IVectArtMifContainerReader = interface
    ['{A4FF6353-5E54-45E1-BD1A-648D284541E8}']
    // Streamを所有せず、成功時のContainer所有権を呼び出し側へ渡す。
    function TryRead(Stream: TStream; out Container: TVectArtMifContainer;
      out ErrorMessage: string): Boolean;
    // 成功時のContainer所有権を呼び出し側へ渡す。
    function TryReadFile(const FileName: string;
      out Container: TVectArtMifContainer;
      out ErrorMessage: string): Boolean;
  end;

  // MIFの保存先をファイルに固定せず、Container出力を抽象化する。
  IVectArtMifContainerWriter = interface
    ['{488936EB-3769-482D-87C1-4C73BF9FDCD1}']
    // ContainerとStreamを所有せず、現在位置からではなくStream全体を書き換える。
    function TryWrite(Container: TVectArtMifContainer; Stream: TStream;
      out ErrorMessage: string): Boolean;
    // Containerを所有せず、指定ファイルへ内容を書き出す。
    function TryWriteFile(Container: TVectArtMifContainer;
      const FileName: string; out ErrorMessage: string): Boolean;
  end;

// 標準MIF Readerをインターフェースとして生成する。
function CreateVectArtMifContainerReader: IVectArtMifContainerReader;
// 標準MIF Writerをインターフェースとして生成する。
function CreateVectArtMifContainerWriter: IVectArtMifContainerWriter;

implementation

uses
  System.IOUtils, Winapi.Windows;

type
  TVectArtMifContainerReader = class(TInterfacedObject,
    IVectArtMifContainerReader)
  public
    function TryRead(Stream: TStream; out Container: TVectArtMifContainer;
      out ErrorMessage: string): Boolean;
    function TryReadFile(const FileName: string;
      out Container: TVectArtMifContainer;
      out ErrorMessage: string): Boolean;
  end;

  TVectArtMifContainerWriter = class(TInterfacedObject,
    IVectArtMifContainerWriter)
  public
    function TryWrite(Container: TVectArtMifContainer; Stream: TStream;
      out ErrorMessage: string): Boolean;
    function TryWriteFile(Container: TVectArtMifContainer;
      const FileName: string; out ErrorMessage: string): Boolean;
  end;

const
  MIF_SIGNATURE: array[0..7] of Byte =
    ($4D, $49, $4D, $47, $0D, $0A, $1A, $00);

function ReadBigEndianUInt32(Stream: TStream): UInt32;
var
  Bytes: array[0..3] of Byte;
begin
  Stream.ReadBuffer(Bytes, SizeOf(Bytes));
  Result := (UInt32(Bytes[0]) shl 24) or (UInt32(Bytes[1]) shl 16) or
    (UInt32(Bytes[2]) shl 8) or UInt32(Bytes[3]);
end;

procedure WriteBigEndianUInt32(Stream: TStream; Value: UInt32);
var
  Bytes: array[0..3] of Byte;
begin
  Bytes[0] := Byte(Value shr 24);
  Bytes[1] := Byte(Value shr 16);
  Bytes[2] := Byte(Value shr 8);
  Bytes[3] := Byte(Value);
  Stream.WriteBuffer(Bytes, SizeOf(Bytes));
end;

{ TVectArtMifChunk }

constructor TVectArtMifChunk.Create(const ATag: AnsiString;
  const AData: TBytes);
begin
  inherited Create;
  FTag := ATag;
  FData := Copy(AData);
end;

{ TVectArtMifContainer }

procedure TVectArtMifContainer.AddChunk(const Tag: AnsiString;
  const Data: TBytes);
begin
  if Length(Tag) <> 4 then
    raise EArgumentException.Create('MIF chunk tag must contain four bytes');
  FChunks.Add(TVectArtMifChunk.Create(Tag, Data));
end;

constructor TVectArtMifContainer.Create;
begin
  inherited Create;
  FChunks := TObjectList<TVectArtMifChunk>.Create(True);
end;

destructor TVectArtMifContainer.Destroy;
begin
  FChunks.Free;
  inherited Destroy;
end;

function TVectArtMifContainer.GetChunk(Index: Integer): TVectArtMifChunk;
begin
  Result := FChunks[Index];
end;

function TVectArtMifContainer.GetChunkCount: Integer;
begin
  Result := FChunks.Count;
end;

function CreateVectArtMifContainerReader: IVectArtMifContainerReader;
begin
  Result := TVectArtMifContainerReader.Create;
end;

function CreateVectArtMifContainerWriter: IVectArtMifContainerWriter;
begin
  Result := TVectArtMifContainerWriter.Create;
end;

procedure TVectArtMifContainer.LoadFromStream(Stream: TStream);
var
  ChunkData: TBytes;
  ChunkLength: UInt32;
  I: Integer;
  Signature: array[0..7] of Byte;
  Tag: AnsiString;
begin
  if Stream = nil then
    raise EArgumentNilException.Create('Stream');
  Stream.Position := 0;
  if Stream.Size < SizeOf(Signature) then
    raise EReadError.Create('MIF header is incomplete');
  Stream.ReadBuffer(Signature, SizeOf(Signature));
  for I := Low(Signature) to High(Signature) do
    if Signature[I] <> MIF_SIGNATURE[I] then
      raise EReadError.Create('MIF signature is invalid');

  FChunks.Clear;
  while Stream.Position < Stream.Size do
  begin
    if Stream.Size - Stream.Position < 8 then
      raise EReadError.Create('MIF chunk header is incomplete');
    ChunkLength := ReadBigEndianUInt32(Stream);
    SetLength(Tag, 4);
    Stream.ReadBuffer(Tag[1], 4);
    if Int64(ChunkLength) > Stream.Size - Stream.Position then
      raise EReadError.CreateFmt('MIF chunk %.4s exceeds the file boundary',
        [string(Tag)]);
    if ChunkLength > UInt32(High(Integer)) then
      raise EReadError.CreateFmt('MIF chunk %.4s is too large', [string(Tag)]);
    SetLength(ChunkData, Integer(ChunkLength));
    if ChunkLength > 0 then
      Stream.ReadBuffer(ChunkData[0], Integer(ChunkLength));
    FChunks.Add(TVectArtMifChunk.Create(Tag, ChunkData));
  end;

  if (FChunks.Count = 0) or (FChunks[0].Tag <> 'MHDR') then
    raise EReadError.Create('MIF MHDR chunk is missing');
  if (FChunks.Last.Tag <> 'MEND') or (Length(FChunks.Last.Data) <> 0) then
    raise EReadError.Create('MIF MEND chunk is missing or invalid');
end;

procedure TVectArtMifContainer.SaveToStream(Stream: TStream);
var
  Chunk: TVectArtMifChunk;
begin
  if Stream = nil then
    raise EArgumentNilException.Create('Stream');
  Stream.Size := 0;
  Stream.Position := 0;
  Stream.WriteBuffer(MIF_SIGNATURE, SizeOf(MIF_SIGNATURE));
  for Chunk in FChunks do
  begin
    if Length(Chunk.Tag) <> 4 then
      raise EWriteError.Create('MIF chunk tag must contain four bytes');
    WriteBigEndianUInt32(Stream, UInt32(Length(Chunk.Data)));
    Stream.WriteBuffer(Chunk.Tag[1], 4);
    if Length(Chunk.Data) > 0 then
      Stream.WriteBuffer(Chunk.Data[0], Length(Chunk.Data));
  end;
end;

{ TVectArtMifContainerReader }

function TVectArtMifContainerReader.TryRead(Stream: TStream;
  out Container: TVectArtMifContainer;
  out ErrorMessage: string): Boolean;
var
  Candidate: TVectArtMifContainer;
begin
  Result := False;
  Container := nil;
  ErrorMessage := '';
  Candidate := nil;
  try
    try
      Candidate := TVectArtMifContainer.Create;
      Candidate.LoadFromStream(Stream);
      Container := Candidate;
      Candidate := nil;
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    Candidate.Free;
  end;
end;

function TVectArtMifContainerReader.TryReadFile(const FileName: string;
  out Container: TVectArtMifContainer;
  out ErrorMessage: string): Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  Container := nil;
  ErrorMessage := '';
  Stream := nil;
  try
    try
      Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
      Result := TryRead(Stream, Container, ErrorMessage);
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    Stream.Free;
  end;
end;

{ TVectArtMifContainerWriter }

function TVectArtMifContainerWriter.TryWrite(
  Container: TVectArtMifContainer; Stream: TStream;
  out ErrorMessage: string): Boolean;
begin
  Result := False;
  ErrorMessage := '';
  try
    if Container = nil then
      raise EArgumentNilException.Create('Container');
    Container.SaveToStream(Stream);
    Result := True;
  except
    on E: Exception do
      ErrorMessage := E.Message;
  end;
end;

function TVectArtMifContainerWriter.TryWriteFile(
  Container: TVectArtMifContainer; const FileName: string;
  out ErrorMessage: string): Boolean;
var
  FullFileName: string;
  Stream: TFileStream;
  TempFileName: string;
begin
  Result := False;
  ErrorMessage := '';
  Stream := nil;
  TempFileName := '';
  try
    try
      if Container = nil then
        raise EArgumentNilException.Create('Container');
      FullFileName := ExpandFileName(FileName);
      TempFileName := TPath.Combine(ExtractFilePath(FullFileName),
        TPath.GetRandomFileName);
      Stream := TFileStream.Create(TempFileName, fmCreate);
      if not TryWrite(Container, Stream, ErrorMessage) then
        Exit;
      FreeAndNil(Stream);
      if not MoveFileEx(PChar(TempFileName), PChar(FullFileName),
        MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
        RaiseLastOSError;
      TempFileName := '';
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    Stream.Free;
    if (TempFileName <> '') and TFile.Exists(TempFileName) then
      TFile.Delete(TempFileName);
  end;
end;

end.
