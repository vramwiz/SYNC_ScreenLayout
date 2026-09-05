program ScreenLayoutFilterJsonTest;

{$APPTYPE CONSOLE}

uses
  System.Generics.Collections,
  System.JSON,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutPaintStyles in
    '..\Source\Core\Model\ScreenLayoutPaintStyles.pas',
  ScreenLayoutDocumentJson in '..\Source\Persistence\ScreenLayoutDocumentJson.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function RectangleData(const Name: string): TVectArtRectangleData;
begin
  Result.Bounds := TRectF.Create(-50, -25, 50, 25);
  Result.FillColor := clWhite;
  Result.Locked := False;
  Result.Name := Name;
  Result.Opacity := 1.0;
  Result.RotationDegrees := 0.0;
  Result.Visible := True;
end;

procedure Run;
var
  Blur: TScreenLayoutBlurFilter;
  Child: TVectArtLayer;
  ErrorMessage: string;
  Group: TScreenLayoutGroupLayer;
  Json: TJSONValue;
  Layer: TVectArtLayer;
  LoadedStops: TArray<TScreenLayoutGradientStop>;
  LayersJson: TJSONArray;
  Loaded: TVectArtDocument;
  Outline: TScreenLayoutOutlineFilter;
  Root: TJSONObject;
  Serialized: string;
  Shadow: TScreenLayoutShadowFilter;
  PaintStyle: TScreenLayoutPaintStyle;
  Source: TVectArtDocument;
begin
  Source := TVectArtDocument.Create;
  Loaded := TVectArtDocument.Create;
  try
    Source.InsertRectangle(1, RectangleData('Filtered rectangle'));
    Layer := Source[1];
    PaintStyle := TScreenLayoutPaintStyle.Solid(clRed);
    PaintStyle.Kind := slpkGradient;
    PaintStyle.GradientStartColor := clRed;
    PaintStyle.GradientEndColor := clBlue;
    PaintStyle.LinearStart := TPointF.Create(0.1, 0.2);
    PaintStyle.LinearEnd := TPointF.Create(0.9, 0.8);
    PaintStyle.AddGradientStop(0.35);
    Layer.PaintStyle := PaintStyle;
    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Color := TColor($00112233);
    Outline.Width := 7.5;
    Layer.AddFilter(Outline);
    Shadow := TScreenLayoutShadowFilter.Create;
    Shadow.Enabled := False;
    Shadow.Color := TColor($00445566);
    Shadow.OffsetX := -3.25;
    Shadow.OffsetY := 9.5;
    Shadow.BlurRadius := 12.75;
    Shadow.Opacity := 0.4;
    Layer.AddFilter(Shadow);
    Blur := TScreenLayoutBlurFilter.Create;
    Blur.Radius := 2.5;
    Layer.AddFilter(Blur);

    Group := TScreenLayoutGroupLayer.Create('Filtered group');
    Group.AddFilter(TScreenLayoutOutlineFilter.Create);
    Child := TVectArtRectangleLayer.Create('Child',
      TRectF.Create(-10, -10, 10, 10), clRed);
    Child.AddFilter(TScreenLayoutBlurFilter.Create);
    Group.AddChild(Child);
    Source.InsertLayer(2, Group);

    Serialized := SerializeVectArtDocument(Source);
    Json := TJSONObject.ParseJSONValue(Serialized);
    try
      Check(Json is TJSONObject, 'serialized root is invalid');
      Root := TJSONObject(Json);
      Check(Root.GetValue('version').Value = '15',
        'filter JSON version is not 15');
      LayersJson := Root.GetValue<TJSONArray>('layers');
      Check(LayersJson.Count = 2, 'serialized layer count changed');
      Check(TJSONObject(LayersJson.Items[0]).GetValue<TJSONArray>(
        'filters').Count = 3, 'top-level filters were not serialized');
      Check(TJSONObject(LayersJson.Items[0]).GetValue<TJSONObject>(
        'paint').GetValue('type').Value = 'linearGradient',
        'linear gradient paint was not serialized');
      Check(TJSONObject(LayersJson.Items[1]).GetValue<TJSONArray>(
        'filters').Count = 1, 'group filters were not serialized');
    finally
      Json.Free;
    end;

    Check(TryDeserializeVectArtDocument(Serialized, Loaded, ErrorMessage),
      'filter JSON did not load: ' + ErrorMessage);
    Check(Loaded[1].FilterCount = 3, 'loaded filter count is incorrect');
    LoadedStops := Loaded[1].PaintStyle.GetGradientStops;
    Check((Loaded[1].PaintStyle.Kind = slpkGradient) and
      (ColorToRGB(Loaded[1].PaintStyle.GradientStartColor) =
       ColorToRGB(clRed)) and
      (ColorToRGB(Loaded[1].PaintStyle.GradientEndColor) =
       ColorToRGB(clBlue)) and
      (Abs(Loaded[1].PaintStyle.LinearStart.X - 0.1) < 0.0001) and
      (Abs(Loaded[1].PaintStyle.LinearEnd.Y - 0.8) < 0.0001) and
      (Length(LoadedStops) = 1) and
      (Abs(LoadedStops[0].Offset - 0.35) < 0.0001),
      'linear gradient paint was not restored');
    Check(Loaded[1].Filters[0] is TScreenLayoutOutlineFilter,
      'outline order changed');
    Check(TScreenLayoutOutlineFilter(Loaded[1].Filters[0]).Width = 7.5,
      'outline width changed');
    Check(not Loaded[1].Filters[1].Enabled, 'enabled state changed');
    Check(Abs(TScreenLayoutShadowFilter(
      Loaded[1].Filters[1]).Opacity - 0.4) < 0.0001,
      'shadow opacity changed');
    Check(TScreenLayoutBlurFilter(Loaded[1].Filters[2]).Radius = 2.5,
      'blur radius changed');
    Check(Loaded[2] is TScreenLayoutGroupLayer, 'group was not restored');
    Group := TScreenLayoutGroupLayer(Loaded[2]);
    Check(Group.FilterCount = 1, 'group filter was not restored');
    Check(Group[0].FilterCount = 1, 'child filter was not restored');

    Check(not TryDeserializeVectArtDocument(
      StringReplace(Serialized, '"version":15', '"version":14', []),
      Loaded, ErrorMessage), 'version 14 was unexpectedly accepted');
    Check(not TryDeserializeVectArtDocument(
      StringReplace(Serialized, '"width":7.5', '"width":-1', []),
      Loaded, ErrorMessage), 'negative outline width was accepted');
  finally
    Loaded.Free;
    Source.Free;
  end;
end;

begin
  try
    Run;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
