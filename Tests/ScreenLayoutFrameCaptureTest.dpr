program ScreenLayoutFrameCaptureTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, Winapi.DXGIFormat, Winapi.D3D11, Winapi.D3DCommon,
  AviUtl2FilterTypes in '..\Lib\AviUtl2\AviUtl2FilterTypes.pas',
  ScreenLayoutFrameCapture in '..\Source\PlacementPlugin\ScreenLayoutFrameCapture.pas';

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
end;

procedure TestConversion;
const
  Formats: array[0..5] of DXGI_FORMAT = (
    DXGI_FORMAT_R8G8B8A8_UNORM, DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
    DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
    DXGI_FORMAT_R16G16B16A16_UNORM, DXGI_FORMAT_R16G16B16A16_FLOAT);
var
  Raw, Pixels: TBytes;
  F, P, C, Size: Integer;
  W: Word;
begin
  for F := 0 to High(Formats) do
  begin
    Size := 4;
    if F >= 4 then Size := 8;
    SetLength(Raw, 4 * Size);
    for P := 0 to 3 do
      for C := 0 to 3 do
        if Size = 4 then
          Raw[P * Size + C] := P * 40 + C * 10
        else
        begin
          if F = 4 then W := (P * 40 + C * 10) * 257
          else if (P + C) mod 2 = 0 then W := $3C00 else W := $0000;
          Move(W, Raw[P * Size + C * 2], 2);
        end;
    Check(ConvertScreenLayoutFramebufferToRgba(Raw, 2, 2, Formats[F], Pixels), 'convert');
    Check(Length(Pixels) = 16, 'size');
    for P := 0 to 3 do
      for C := 0 to 3 do
      begin
        if F = 5 then
        begin
          if (P + C) mod 2 = 0 then W := 255 else W := 0;
        end
        else if (F in [2, 3]) and (C in [0, 2]) then W := P * 40 + (2 - C) * 10
        else W := P * 40 + C * 10;
        Check(Pixels[P * 4 + C] = W, 'pixel order / alpha');
      end;
    W := Raw[0];
    Pixels[0] := Pixels[0] xor $FF;
    Check(Raw[0] = W, 'independent output');
  end;
  Raw := TBytes.Create($00, $BC, $00, $40, $00, $38, $00, $38);
  Check(ConvertScreenLayoutFramebufferToRgba(Raw, 1, 1,
    DXGI_FORMAT_R16G16B16A16_FLOAT, Pixels), 'float');
  Check((Pixels[0] = 0) and (Pixels[1] = 255) and
    (Pixels[2] = 128) and (Pixels[3] = 128), 'float clamp / alpha');
  Check(not ConvertScreenLayoutFramebufferToRgba(Raw, 0, 1, Formats[0], Pixels), 'zero');
  Check(not ConvertScreenLayoutFramebufferToRgba(Raw, -1, 1, Formats[0], Pixels), 'negative');
  Check(not ConvertScreenLayoutFramebufferToRgba(Raw, 16385, 1, Formats[0], Pixels), 'oversize');
  Check(not ConvertScreenLayoutFramebufferToRgba(Raw, 2, 2, Formats[0], Pixels), 'short');
  Check(not ConvertScreenLayoutFramebufferToRgba(Raw, 1, 1, DXGI_FORMAT_UNKNOWN, Pixels), 'format');
  Check(Pixels = nil, 'invalid output');
end;

var
  TestTexture: ID3D11Texture2D;
  FramebufferRequested: Boolean;

function GetTestTexture: Pointer; cdecl;
begin
  FramebufferRequested := True;
  Result := Pointer(TestTexture);
end;

procedure TestGpuCapture;
const
  Formats: array[0..5] of DXGI_FORMAT = (
    DXGI_FORMAT_R8G8B8A8_UNORM, DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
    DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
    DXGI_FORMAT_R16G16B16A16_UNORM, DXGI_FORMAT_R16G16B16A16_FLOAT);
var
  Device: ID3D11Device;
  Context: ID3D11DeviceContext;
  Level: D3D_FEATURE_LEVEL;
  Desc: D3D11_TEXTURE2D_DESC;
  Data: D3D11_SUBRESOURCE_DATA;
  Video: TFILTER_PROC_VIDEO;
  Capture: TScreenLayoutFrameCapture;
  Raw, Pixels, Expected: TBytes;
  F, N, Size, Width, Height: Integer;
  Status: string;
begin
  Check(D3D11CreateDevice(nil, D3D_DRIVER_TYPE_WARP, 0, 0, nil, 0,
    D3D11_SDK_VERSION, Device, Level, Context) >= 0, 'WARP device');
  Capture := TScreenLayoutFrameCapture.Create;
  try
    FillChar(Video, SizeOf(Video), 0);
    Video.GetFramebufferTexture2D := GetTestTexture;
    for F := 0 to High(Formats) do
    begin
      Size := 4;
      if F >= 4 then Size := 8;
      FillChar(Desc, SizeOf(Desc), 0);
      Desc.Width := 3;
      Desc.Height := 2;
      Desc.MipLevels := 1;
      Desc.ArraySize := 1;
      Desc.Format := Formats[F];
      Desc.SampleDesc.Count := 1;
      Desc.Usage := D3D11_USAGE_DEFAULT;
      Desc.BindFlags := D3D11_BIND_SHADER_RESOURCE;
      SetLength(Raw, 6 * Size);
      for N := 0 to High(Raw) do Raw[N] := N mod 60;
      FillChar(Data, SizeOf(Data), 0);
      Data.pSysMem := @Raw[0];
      Data.SysMemPitch := 3 * Size;
      TestTexture := nil;
      Check(Device.CreateTexture2D(Desc, @Data, TestTexture) >= 0, 'texture');
      Check(ConvertScreenLayoutFramebufferToRgba(Raw, 3, 2, Formats[F], Expected), 'expected');
      for N := 0 to 1 do
      begin
        FramebufferRequested := False;
        Capture.Capture(@Video);
        Check(FramebufferRequested, 'capture framebuffer');
        Check(Capture.CopyRgba(Pixels, Width, Height, Status), 'capture: ' + Status);
        Check((Width = 3) and (Height = 2), 'capture dimensions');
        Check(CompareMem(@Pixels[0], @Expected[0], Length(Expected)), 'GPU roundtrip');
      end;

    end;
    Capture.Capture(nil);
    Check(not Capture.CopyRgba(Pixels, Width, Height, Status), 'clear old frame');
  finally
    Capture.Free;
    TestTexture := nil;
  end;
end;

procedure TestUnavailable;
var
  Capture: TScreenLayoutFrameCapture;
  Pixels: TBytes;
  Width, Height: Integer;
  Status: string;
begin
  Capture := TScreenLayoutFrameCapture.Create;
  try
    Check(not Capture.CopyRgba(Pixels, Width, Height, Status), 'initial');
    Capture.Capture(nil);
    Check(not Capture.CopyRgba(Pixels, Width, Height, Status), 'unavailable');
    Check((Width = 0) and (Height = 0) and (Pixels = nil) and (Status <> ''), 'cleared');
  finally
    Capture.Free;
  end;
end;

begin
  try
    TestConversion;
    TestGpuCapture;
    TestUnavailable;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln(E.Message);
      Halt(1);
    end;
  end;
end.
