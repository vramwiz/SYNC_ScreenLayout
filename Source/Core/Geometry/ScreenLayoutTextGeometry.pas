// 文字列の折り返し、行送り、実寸範囲をSkiaの文字計測から求める。
unit ScreenLayoutTextGeometry;

interface

uses
  System.Skia;

type
  TScreenLayoutTextLayout = record
    Ascent: Single;        // 行上端からベースラインまでの距離。
    Height: Single;        // 全行を含む組版高。
    Lines: TArray<string>; // 明示改行と幅折り返しを反映した表示行。
    LineHeight: Single;    // 連続するベースライン間の距離。
    Width: Single;         // 最長行の文字送り幅。
  end;

// 指定ファミリーを優先し、利用できない場合は既定書体を返す。
function CreateScreenLayoutTextFont(const FontFamily: string;
  FontSize: Single): ISkFont;
// MaxWidthを超えない位置で文字単位に折り返し、空行を含む実寸を返す。
function BuildScreenLayoutTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single): TScreenLayoutTextLayout;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils;

procedure AppendWrappedParagraph(Lines: TList<string>; const Paragraph: string;
  const Font: ISkFont; MaxWidth: Single);
var
  Candidate: string;
  CharacterLength: Integer;
  CurrentLine: string;
  I: Integer;
  NextCharacter: string;
begin
  if Paragraph = '' then
  begin
    Lines.Add('');
    Exit;
  end;
  CurrentLine := '';
  I := 1;
  while I <= Length(Paragraph) do
  begin
    CharacterLength := 1;
    if (Ord(Paragraph[I]) >= $D800) and
      (Ord(Paragraph[I]) <= $DBFF) and
      (I < Length(Paragraph)) and
      (Ord(Paragraph[I + 1]) >= $DC00) and
      (Ord(Paragraph[I + 1]) <= $DFFF) then
      CharacterLength := 2;
    NextCharacter := Copy(Paragraph, I, CharacterLength);
    Candidate := CurrentLine + NextCharacter;
    if (CurrentLine <> '') and (MaxWidth > 0) and
      (Font.MeasureText(Candidate) > MaxWidth) then
    begin
      Lines.Add(CurrentLine);
      CurrentLine := NextCharacter;
    end
    else
      CurrentLine := Candidate;
    Inc(I, CharacterLength);
  end;
  Lines.Add(CurrentLine);
end;

function CreateScreenLayoutTextFont(const FontFamily: string;
  FontSize: Single): ISkFont;
var
  Typeface: ISkTypeface;
begin
  Typeface := nil;
  if FontFamily <> '' then
    Typeface := TSkTypeface.MakeFromName(FontFamily, TSkFontStyle.Normal);
  if Typeface = nil then
    Typeface := TSkTypeface.MakeFromName('Yu Gothic UI',
      TSkFontStyle.Normal);
  if Typeface = nil then
    Typeface := TSkTypeface.MakeDefault;
  Result := TSkFont.Create(Typeface, Max(FontSize, 1.0));
  Result.Edging := TSkFontEdging.AntiAlias;
end;

function BuildScreenLayoutTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single): TScreenLayoutTextLayout;
var
  Font: ISkFont;
  FontMetrics: TSkFontMetrics;
  I: Integer;
  Lines: TList<string>;
  NormalizedText: string;
  Paragraphs: TArray<string>;
begin
  Result := Default(TScreenLayoutTextLayout);
  Font := CreateScreenLayoutTextFont(FontFamily, FontSize);
  Font.GetMetrics(FontMetrics);
  Result.Ascent := Max(-FontMetrics.Ascent, 1.0);
  Result.LineHeight := Max(Font.Spacing, FontSize);
  NormalizedText := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  NormalizedText := StringReplace(NormalizedText, #13, #10, [rfReplaceAll]);
  Paragraphs := NormalizedText.Split([#10], TStringSplitOptions.None);
  Lines := TList<string>.Create;
  try
    if Length(Paragraphs) = 0 then
      Lines.Add('')
    else
      for I := 0 to High(Paragraphs) do
        AppendWrappedParagraph(Lines, Paragraphs[I], Font, MaxWidth);
    Result.Lines := Lines.ToArray;
  finally
    Lines.Free;
  end;
  for I := 0 to High(Result.Lines) do
    Result.Width := Max(Result.Width, Font.MeasureText(Result.Lines[I]));
  Result.Height := Max(Length(Result.Lines), 1) * Result.LineHeight;
end;

end.
