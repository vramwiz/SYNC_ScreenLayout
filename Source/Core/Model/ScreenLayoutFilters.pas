// Defines non-destructive visual filters and their editable parameters.
// Rendering, persistence, and UI behavior are intentionally kept elsewhere.
unit ScreenLayoutFilters;

interface

uses
  Vcl.Graphics;

type
  TScreenLayoutFilterKind = (slfkOutline, slfkShadow, slfkBlur);

  TScreenLayoutFilter = class
  private
    FEnabled: Boolean;
    FKind: TScreenLayoutFilterKind;
  protected
    constructor Create(AKind: TScreenLayoutFilterKind);
  public
    function Clone: TScreenLayoutFilter; virtual; abstract;
    function DisplayName: string;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Kind: TScreenLayoutFilterKind read FKind;
  end;

  TScreenLayoutOutlineFilter = class(TScreenLayoutFilter)
  private
    FColor: TColor;
    FWidth: Single;
  public
    constructor Create;
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
    constructor Create;
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
    constructor Create;
    function Clone: TScreenLayoutFilter; override;
    property Radius: Single read FRadius write FRadius;
  end;

// Creates one filter with the defaults used by the add-filter UI.
function CreateDefaultScreenLayoutFilter(
  Kind: TScreenLayoutFilterKind): TScreenLayoutFilter;
// Copies editable values between filters of the same kind.
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
      Result := 'Outline';
    slfkShadow:
      Result := 'Shadow';
    slfkBlur:
      Result := 'Blur';
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
