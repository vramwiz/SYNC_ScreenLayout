// 非破壊フィルターの種類と編集可能な値だけを保持する。
// 描画、永続化、UI操作には依存しない。
unit ScreenLayoutFilters;

interface

uses
  Vcl.Graphics;

type
  TScreenLayoutFilterKind = (slfkOutline, slfkShadow, slfkBlur);

  // 全フィルターに共通する有効状態と、派生型を判別する不変の種類を持つ。
  TScreenLayoutFilter = class
  private
    FEnabled: Boolean;
    FKind: TScreenLayoutFilterKind;
  protected
    constructor Create(AKind: TScreenLayoutFilterKind);
  public
    // 元インスタンスと所有権を共有しない完全な複製を返す。
    function Clone: TScreenLayoutFilter; virtual; abstract;
    // UIへ表示する種類名を返す。
    function DisplayName: string;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Kind: TScreenLayoutFilterKind read FKind;
  end;

  TScreenLayoutOutlineFilter = class(TScreenLayoutFilter)
  private
    FColor: TColor;
    FWidth: Single;
  public
    // UIとJSONで共通使用する初期値を設定する。
    constructor Create;
    // 有効状態、色、幅を独立したインスタンスへ複製する。
    function Clone: TScreenLayoutFilter; override;
    property Color: TColor read FColor write FColor;
    property Width: Single read FWidth write FWidth;
  end;

  TScreenLayoutShadowFilter = class(TScreenLayoutFilter)
  private
    FBlurRadius: Single;
    FColor: TColor;
    FOffsetX: Single;
    FOffsetY: Single;
    FOpacity: Single;
  public
    // UIとJSONで共通使用する初期値を設定する。
    constructor Create;
    // 有効状態を含む影の全パラメーターを複製する。
    function Clone: TScreenLayoutFilter; override;
    property BlurRadius: Single read FBlurRadius write FBlurRadius;
    property Color: TColor read FColor write FColor;
    property OffsetX: Single read FOffsetX write FOffsetX;
    property OffsetY: Single read FOffsetY write FOffsetY;
    property Opacity: Single read FOpacity write FOpacity;
  end;

  TScreenLayoutBlurFilter = class(TScreenLayoutFilter)
  private
    FRadius: Single;
  public
    // UIとJSONで共通使用する初期値を設定する。
    constructor Create;
    // 有効状態と半径を独立したインスタンスへ複製する。
    function Clone: TScreenLayoutFilter; override;
    property Radius: Single read FRadius write FRadius;
  end;

// 指定した種類を追加UIと同じ初期値で生成し、呼び出し側へ所有権を渡す。
function CreateDefaultScreenLayoutFilter(
  Kind: TScreenLayoutFilterKind): TScreenLayoutFilter;
// 同じ種類のフィルター間で、有効状態を含む編集可能値をすべてコピーする。
procedure AssignScreenLayoutFilter(Target, Source: TScreenLayoutFilter);

implementation

uses
  System.SysUtils;

procedure AssignScreenLayoutFilter(Target, Source: TScreenLayoutFilter);
begin
  if (Target = nil) or (Source = nil) then
    raise EArgumentNilException.Create('Filter');
  if Target.Kind <> Source.Kind then
    raise EArgumentException.Create('Filter kinds do not match');
  Target.Enabled := Source.Enabled;
  case Target.Kind of
    slfkOutline:
    begin
      TScreenLayoutOutlineFilter(Target).Color :=
        TScreenLayoutOutlineFilter(Source).Color;
      TScreenLayoutOutlineFilter(Target).Width :=
        TScreenLayoutOutlineFilter(Source).Width;
    end;
    slfkShadow:
    begin
      TScreenLayoutShadowFilter(Target).BlurRadius :=
        TScreenLayoutShadowFilter(Source).BlurRadius;
      TScreenLayoutShadowFilter(Target).Color :=
        TScreenLayoutShadowFilter(Source).Color;
      TScreenLayoutShadowFilter(Target).OffsetX :=
        TScreenLayoutShadowFilter(Source).OffsetX;
      TScreenLayoutShadowFilter(Target).OffsetY :=
        TScreenLayoutShadowFilter(Source).OffsetY;
      TScreenLayoutShadowFilter(Target).Opacity :=
        TScreenLayoutShadowFilter(Source).Opacity;
    end;
    slfkBlur:
      TScreenLayoutBlurFilter(Target).Radius :=
        TScreenLayoutBlurFilter(Source).Radius;
  end;
end;

{ TScreenLayoutFilter }

constructor TScreenLayoutFilter.Create(AKind: TScreenLayoutFilterKind);
begin
  inherited Create;
  FKind := AKind;
  FEnabled := True;
end;

function TScreenLayoutFilter.DisplayName: string;
begin
  case FKind of
    slfkOutline:
      Result := '縁取り';
    slfkShadow:
      Result := '影';
    slfkBlur:
      Result := 'ぼかし';
  else
    raise EArgumentOutOfRangeException.Create('Unknown filter kind');
  end;
end;

{ TScreenLayoutOutlineFilter }

function TScreenLayoutOutlineFilter.Clone: TScreenLayoutFilter;
var
  CopyFilter: TScreenLayoutOutlineFilter;
begin
  CopyFilter := TScreenLayoutOutlineFilter.Create;
  CopyFilter.Enabled := Enabled;
  CopyFilter.Color := Color;
  CopyFilter.Width := Width;
  Result := CopyFilter;
end;

constructor TScreenLayoutOutlineFilter.Create;
begin
  inherited Create(slfkOutline);
  FColor := clBlack;
  FWidth := 4.0;
end;

{ TScreenLayoutShadowFilter }

function TScreenLayoutShadowFilter.Clone: TScreenLayoutFilter;
var
  CopyFilter: TScreenLayoutShadowFilter;
begin
  CopyFilter := TScreenLayoutShadowFilter.Create;
  CopyFilter.Enabled := Enabled;
  CopyFilter.BlurRadius := BlurRadius;
  CopyFilter.Color := Color;
  CopyFilter.OffsetX := OffsetX;
  CopyFilter.OffsetY := OffsetY;
  CopyFilter.Opacity := Opacity;
  Result := CopyFilter;
end;

constructor TScreenLayoutShadowFilter.Create;
begin
  inherited Create(slfkShadow);
  FBlurRadius := 6.0;
  FColor := clBlack;
  FOffsetX := 8.0;
  FOffsetY := 8.0;
  FOpacity := 0.75;
end;

{ TScreenLayoutBlurFilter }

function TScreenLayoutBlurFilter.Clone: TScreenLayoutFilter;
var
  CopyFilter: TScreenLayoutBlurFilter;
begin
  CopyFilter := TScreenLayoutBlurFilter.Create;
  CopyFilter.Enabled := Enabled;
  CopyFilter.Radius := Radius;
  Result := CopyFilter;
end;

constructor TScreenLayoutBlurFilter.Create;
begin
  inherited Create(slfkBlur);
  FRadius := 4.0;
end;

function CreateDefaultScreenLayoutFilter(
  Kind: TScreenLayoutFilterKind): TScreenLayoutFilter;
begin
  case Kind of
    slfkOutline:
      Result := TScreenLayoutOutlineFilter.Create;
    slfkShadow:
      Result := TScreenLayoutShadowFilter.Create;
    slfkBlur:
      Result := TScreenLayoutBlurFilter.Create;
  else
    raise EArgumentOutOfRangeException.Create('Unknown filter kind');
  end;
end;

end.
