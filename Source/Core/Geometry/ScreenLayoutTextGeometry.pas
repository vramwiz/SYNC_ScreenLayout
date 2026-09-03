// 文字列の折り返し、行送り、実寸範囲をSkiaの文字計測から求める。
unit ScreenLayoutTextGeometry;

interface

uses
  System.Skia, Vcl.Graphics;

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
  FontSize: Single; FontStyle: TFontStyles = []): ISkFont;
// MaxWidthを超えない位置で文字単位に折り返し、空行を含む実寸を返す。
function BuildScreenLayoutTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single;
  FontStyle: TFontStyles = []; LetterSpacingRatio: Single = 0;
  LineSpacingRatio: Single = 0): TScreenLayoutTextLayout;
// UTF-16のサロゲートペアを分割せず、Indexから始まる1文字の長さを返す。
function ScreenLayoutTextUnitLengthAt(const Text: string;
  Index: Integer): Integer;
// Fontによる文字送りへ、文字間ごとの追加幅を加えた行幅を返す。
function MeasureScreenLayoutText(const Text: string; const Font: ISkFont;
  LetterSpacing: Single): Single;

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils;

function ScreenLayoutTextUnitLengthAt(const Text: string;
  Index: Integer): Integer;
begin
  Result := 1;
  if (Index >= 1) and (Index < Length(Text)) and
    (Ord(Text[Index]) >= $D800) and (Ord(Text[Index]) <= $DBFF) and
    (Ord(Text[Index + 1]) >= $DC00) and
    (Ord(Text[Index + 1]) <= $DFFF) then
    Result := 2;
end;

function MeasureScreenLayoutText(const Text: string; const Font: ISkFont;
  LetterSpacing: Single): Single;
var
  I: Integer;
  UnitLength: Integer;
  UnitText: string;
begin
  if (Text = '') or (Font = nil) then
    Exit(0);
  if SameValue(LetterSpacing, 0) then
    Exit(Font.MeasureText(Text));
  Result := 0;
  I := 1;
  while I <= Length(Text) do
  begin
    UnitLength := ScreenLayoutTextUnitLengthAt(Text, I);
    UnitText := Copy(Text, I, UnitLength);
    Result := Result + Font.MeasureText(UnitText);
    Inc(I, UnitLength);
    if I <= Length(Text) then
      Result := Result + LetterSpacing;
  end;
end;

procedure AppendWrappedParagraph(Lines: TList<string>; const Paragraph: string;
  const Font: ISkFont; MaxWidth, LetterSpacing: Single);
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
    CharacterLength := ScreenLayoutTextUnitLengthAt(Paragraph, I);
    NextCharacter := Copy(Paragraph, I, CharacterLength);
    Candidate := CurrentLine + NextCharacter;
    if (CurrentLine <> '') and (MaxWidth > 0) and
      (MeasureScreenLayoutText(Candidate, Font, LetterSpacing) > MaxWidth) then
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
  FontSize: Single; FontStyle: TFontStyles): ISkFont;
var
  SkiaStyle: TSkFontStyle;
  Slant: TSkFontSlant;
  Typeface: ISkTypeface;
  Weight: TSkFontWeight;
begin
  if fsBold in FontStyle then
    Weight := TSkFontWeight.Bold
  else
    Weight := TSkFontWeight.Normal;
  if fsItalic in FontStyle then
    Slant := TSkFontSlant.Italic
  else
    Slant := TSkFontSlant.Upright;
  SkiaStyle := TSkFontStyle.Create(Weight, TSkFontWidth.Normal, Slant);
  Typeface := nil;
  if FontFamily <> '' then
    Typeface := TSkTypeface.MakeFromName(FontFamily, SkiaStyle);
  if Typeface = nil then
    Typeface := TSkTypeface.MakeFromName('Yu Gothic UI',
      SkiaStyle);
  if Typeface = nil then
    Typeface := TSkTypeface.MakeDefault;
  Result := TSkFont.Create(Typeface, Max(FontSize, 1.0));
  Result.Edging := TSkFontEdging.AntiAlias;
end;

function BuildScreenLayoutTextLayout(const Text, FontFamily: string;
  FontSize, MaxWidth: Single;
  FontStyle: TFontStyles; LetterSpacingRatio,
  LineSpacingRatio: Single): TScreenLayoutTextLayout;
var
  Font: ISkFont;
  FontMetrics: TSkFontMetrics;
  I: Integer;
  LetterSpacing: Single;
  Lines: TList<string>;
  NormalizedText: string;
  Paragraphs: TArray<string>;
begin
  Result := Default(TScreenLayoutTextLayout);
  Font := CreateScreenLayoutTextFont(FontFamily, FontSize, FontStyle);
  Font.GetMetrics(FontMetrics);
  LetterSpacing := FontSize * LetterSpacingRatio;
  Result.Ascent := Max(-FontMetrics.Ascent, 1.0);
  Result.LineHeight := Max(Font.Spacing + FontSize * LineSpacingRatio, 1.0);
  NormalizedText := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  NormalizedText := StringReplace(NormalizedText, #13, #10, [rfReplaceAll]);
  Paragraphs := NormalizedText.Split([#10], TStringSplitOptions.None);
  Lines := TList<string>.Create;
  try
    if Length(Paragraphs) = 0 then
      Lines.Add('')
    else
      for I := 0 to High(Paragraphs) do
        AppendWrappedParagraph(Lines, Paragraphs[I], Font, MaxWidth,
          LetterSpacing);
    Result.Lines := Lines.ToArray;
  finally
    Lines.Free;
  end;
  for I := 0 to High(Result.Lines) do
    Result.Width := Max(Result.Width, MeasureScreenLayoutText(
      Result.Lines[I], Font, LetterSpacing));
  Result.Height := Max(Length(Result.Lines), 1) * Result.LineHeight;
end;

end.
