// テクスチャ画像の検証、配置行列とSkiaシェーダーを構築する。モデルはSkiaに依存させない。
unit ScreenLayoutTextureRenderer;

interface

uses
  System.Skia, System.Types, System.Math.Vectors, ScreenLayoutTextureStyle;

// 埋め込み画像を検証して復号する。未設定はnil、不正画像は例外を返す。
function DecodeScreenLayoutTexture(const Data: string): ISkImage;
// ファイルを検証し、外部参照のない埋め込み画像として返す。配置は既定値にする。
function LoadScreenLayoutTexture(const FileName: string): TScreenLayoutTextureStyle;
// 画像中心を原点として拡縮・回転し、オブジェクトの回転を含めた配置行列を返す。
function ScreenLayoutTextureMatrix(const Texture: TScreenLayoutTextureStyle;
  const Bounds: TRectF; Width, Height: Integer; Rotation: Single): TMatrix;
// 空の画像は透明にし、設定済み画像は指定範囲のシェーダーとしてPaintへ反映する。
procedure ApplyScreenLayoutTexture(const Paint: ISkPaint; const Texture: TScreenLayoutTextureStyle;
  const Bounds: TRectF; Rotation, Opacity: Single);

implementation

uses
  System.Classes, System.SysUtils, System.NetEncoding, System.Math, System.UITypes;

function DecodeScreenLayoutTexture(const Data: string): ISkImage;
var
  Bytes: TBytes;
begin
  Result := nil;
  if Data = '' then
    Exit;
  if Length(Data) > 48 * 1024 * 1024 then
    raise EConvertError.Create('Texture image exceeds 32 MiB');
  Bytes := TNetEncoding.Base64.DecodeStringToBytes(Data);
  if Length(Bytes) > 32 * 1024 * 1024 then
    raise EConvertError.Create('Texture image exceeds 32 MiB');
  Result := TSkImage.MakeFromEncoded(Bytes);
  if Result = nil then
    raise EConvertError.Create('Invalid or unsupported texture image');
  if (Result.Width <= 0) or (Result.Height <= 0) or
    (Result.Width > 16384) or (Result.Height > 16384) or
    (Int64(Result.Width) * Result.Height > 64 * 1024 * 1024) then
    raise EConvertError.Create('Texture image dimensions exceed the supported limit');
end;

function LoadScreenLayoutTexture(const FileName: string): TScreenLayoutTextureStyle;
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Result := TScreenLayoutTextureStyle.DefaultStyle;
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if Stream.Size > 32 * 1024 * 1024 then
      raise EConvertError.Create('Texture image exceeds 32 MiB');
    SetLength(Bytes, Stream.Size);
    if Length(Bytes) > 0 then
      Stream.ReadBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
  if Length(Bytes) = 0 then
    raise EConvertError.Create('Empty texture image');
  Result.Data := TNetEncoding.Base64.EncodeBytesToString(Bytes);
  DecodeScreenLayoutTexture(Result.Data);
  Result.FileName := ExtractFileName(FileName);
end;

function ScreenLayoutTextureMatrix(const Texture: TScreenLayoutTextureStyle;
  const Bounds: TRectF; Width, Height: Integer; Rotation: Single): TMatrix;
var
  SX, SY: Single;
  Center: TPointF;
begin
  SX := Max(Bounds.Width, 1) / Max(Width, 1);
  SY := Max(Bounds.Height, 1) / Max(Height, 1);
  case Texture.Fit of
    sltfCover: begin SX := Max(SX, SY); SY := SX; end;
    sltfContain: begin SX := Min(SX, SY); SY := SX; end;
    sltfOriginal: begin SX := 1; SY := 1; end;
  end;
  Center := Bounds.CenterPoint;
  Result := TMatrix.CreateTranslation(-Width / 2, -Height / 2) *
    TMatrix.CreateScaling(SX * Max(Texture.Scale, 0.01), SY * Max(Texture.Scale, 0.01)) *
    TMatrix.CreateRotation(DegToRad(Texture.Angle)) *
    TMatrix.CreateTranslation(Texture.OffsetX * Max(Bounds.Width, 1), Texture.OffsetY * Max(Bounds.Height, 1)) *
    TMatrix.CreateRotation(DegToRad(Rotation)) * TMatrix.CreateTranslation(Center.X, Center.Y);
end;

procedure ApplyScreenLayoutTexture(const Paint: ISkPaint; const Texture: TScreenLayoutTextureStyle;
  const Bounds: TRectF; Rotation, Opacity: Single);
const
  MODES: array[TScreenLayoutTextureRepeat] of TSkTileMode =
    (TSkTileMode.Decal, TSkTileMode.Repeat, TSkTileMode.Mirror);
var
  Img: ISkImage;
begin
  Paint.Shader := nil;
  Paint.Color := TAlphaColorRec.Null;
  Img := DecodeScreenLayoutTexture(Texture.Data);
  if Img = nil then
    Exit;
  Paint.Shader := Img.MakeShader(ScreenLayoutTextureMatrix(Texture, Bounds, Img.Width, Img.Height, Rotation),
    TSkSamplingOptions.Create(TSkFilterMode.Linear, TSkMipmapMode.None),
    MODES[Texture.RepeatMode], MODES[Texture.RepeatMode]);
  Paint.Color := TAlphaColor((Cardinal(EnsureRange(Round(Opacity * 255), 0, 255)) shl 24) or $FFFFFF);
end;

end.
