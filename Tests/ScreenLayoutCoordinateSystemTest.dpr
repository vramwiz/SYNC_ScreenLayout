program ScreenLayoutCoordinateSystemTest;

{$APPTYPE CONSOLE}

uses
  System.JSON,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutGeometry in
    '..\Source\Core\Geometry\ScreenLayoutGeometry.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  ScreenLayoutDocumentJson in
    '..\Source\Persistence\ScreenLayoutDocumentJson.pas',
  ScreenLayoutDocumentJsonReader in
    '..\Source\Persistence\ScreenLayoutDocumentJsonReader.pas',
  ScreenLayoutDocumentJsonWriter in
    '..\Source\Persistence\ScreenLayoutDocumentJsonWriter.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure ReplaceNumber(Root: TJSONObject; const Name: string;
  Value: Integer);
var
  Pair: TJSONPair;
begin
  Pair := Root.RemovePair(Name);
  Pair.Free;
  Root.AddPair(Name, TJSONNumber.Create(Value));
end;

procedure ReplaceString(Root: TJSONObject; const Name, Value: string);
var
  Pair: TJSONPair;
begin
  Pair := Root.RemovePair(Name);
  Pair.Free;
  Root.AddPair(Name, Value);
end;

var
  Bounds: TRectF;
  CanvasJson: TJSONObject;
  Document: TVectArtDocument;
  ErrorMessage: string;
  Json: TJSONValue;
  Loaded: TVectArtDocument;
  Rectangle: TVectArtRectangleLayer;
  RenderBuffer: TVectArtRenderBuffer;
  Root: TJSONObject;
  Serialized: string;
begin
  Document := TVectArtDocument.Create;
  Loaded := TVectArtDocument.Create;
  RenderBuffer := TVectArtRenderBuffer.Create;
  Json := nil;
  try
    Document.SetCanvasSize(200, 100);
    Bounds := TRectF.Create(-10, -5, 10, 5);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Centered', Bounds, clRed));
    Serialized := SerializeVectArtDocument(Document);

    Json := TJSONObject.ParseJSONValue(Serialized);
    Check(Json is TJSONObject, 'Serialized root is not an object');
    Root := TJSONObject(Json);
    Check(Root.GetValue('version').Value = '14',
      'Coordinate format version is not 14');
    CanvasJson := Root.GetValue<TJSONObject>('canvas');
    Check((CanvasJson <> nil) and
      (CanvasJson.GetValue('origin').Value = 'center'),
      'Center coordinate origin was not serialized');

    Check(TryDeserializeVectArtDocument(Serialized, Loaded, ErrorMessage),
      'Center coordinate document was not loaded: ' + ErrorMessage);
    Check((Loaded.LayerCount = 2) and
      (Loaded[1] is TVectArtRectangleLayer),
      'Loaded centered rectangle is missing');
    Rectangle := TVectArtRectangleLayer(Loaded[1]);
    Check(SameValue(Rectangle.Bounds.Left, -10.0) and
      SameValue(Rectangle.Bounds.Top, -5.0) and
      SameValue(Rectangle.Bounds.Right, 10.0) and
      SameValue(Rectangle.Bounds.Bottom, 5.0),
      'Centered coordinates changed during round trip');

    Check(LogicalToScreenX(0, Rect(100, 50, 300, 150), 1, 200) = 200,
      'Logical X origin is not at the canvas center');
    Check(LogicalToScreenY(0, Rect(100, 50, 300, 150), 1, 100) = 100,
      'Logical Y origin is not at the canvas center');
    Check(SameValue(ScreenToLogicalX(100,
      Rect(100, 50, 300, 150), 1, 200), -100.0),
      'Canvas left edge is not negative half width');
    Check(SameValue(ScreenToLogicalY(50,
      Rect(100, 50, 300, 150), 1, 100), -50.0),
      'Canvas top edge is not negative half height');

    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      RenderVectArtDocument(Document, RenderBuffer, 200, 100);
      Check(RenderBuffer.Pixels[50 * 200 + 100].A > 0,
        'Logical origin was not rendered at output center');
      Check(RenderBuffer.Pixels[0].A = 0,
        'Centered object was unexpectedly rendered at output top-left');
    finally
      TTextRendererSkiaRuntime.Release;
    end;

    ReplaceNumber(Root, 'version', 13);
    Check(not TryDeserializeVectArtDocument(Root.ToJSON, Loaded,
      ErrorMessage), 'Version 13 was unexpectedly accepted');
    ReplaceNumber(Root, 'version', 14);
    CanvasJson := Root.GetValue<TJSONObject>('canvas');
    ReplaceString(CanvasJson, 'origin', 'topLeft');
    Check(not TryDeserializeVectArtDocument(Root.ToJSON, Loaded,
      ErrorMessage), 'Top-left coordinate origin was unexpectedly accepted');
  finally
    Json.Free;
    RenderBuffer.Free;
    Loaded.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
