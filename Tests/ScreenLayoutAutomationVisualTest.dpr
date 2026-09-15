program ScreenLayoutAutomationVisualTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.JSON, System.Types, Vcl.Forms, Vcl.Graphics,
  Vcl.Imaging.pngimage, ScreenLayoutDocument, ScreenLayoutDocumentJson,
  ScreenLayoutEditHistory, ScreenLayoutCanvas, ScreenLayoutAutomationProtocol,
  ScreenLayoutTextGeometry, TextRendererSkiaRuntime;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

function Call(Request: TJSONObject; Document: TVectArtDocument;
  History: TVectArtEditHistory; Canvas: TVectArtCanvasControl): TJSONObject;
begin
  try
    Result := TJSONObject.ParseJSONValue(HandleScreenLayoutAutomationRequest(
      Request.ToJSON, Document, History, nil, Canvas)) as TJSONObject;
  finally
    Request.Free;
  end;
end;

function RequestFor(const Command: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('command', Command);
end;

procedure CheckStatus(Response: TJSONObject; const Expected: string);
begin
  Check(Response.GetValue<string>('status') = Expected, Response.ToJSON);
end;

procedure Run;
var
  Document, Candidate: TVectArtDocument;
  History: TVectArtEditHistory;
  Canvas: TVectArtCanvasControl;
  Request, Response: TJSONObject;
  Png: TPngImage;
  Data: TVectArtRectangleData;
  Pixels: TBytes;
  Token, BackgroundToken, Before, CandidateJson, PreviewPath, ErrorMessage: string;
  I: Integer;
  Layout: TScreenLayoutTextLayout;
begin
  Document := TVectArtDocument.Create;
  Candidate := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Canvas := TVectArtCanvasControl.Create(nil);
  Png := TPngImage.Create;
  try
    Document.SetCanvasSize(200, 100);
    Document.CanvasLayer.Transparent := True;
    Canvas.Document := Document;
    SetLength(Pixels, 200 * 100 * 4);
    for I := 0 to 200 * 100 - 1 do
    begin
      if I < 200 * 50 then Pixels[I * 4] := 255
      else Pixels[I * 4 + 2] := 255;
      Pixels[I * 4 + 3] := 255;
    end;
    Canvas.SetReferenceBackgroundRgba(Pixels, 200, 100);
    Before := SerializeVectArtDocument(Document);
    Request := RequestFor('get_canvas_snapshot');
    Request.AddPair('max_edge', TJSONNumber.Create(100));
    Response := Call(Request, Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      Token := Response.GetValue<string>('snapshot.state_token');
      BackgroundToken := Response.GetValue<string>('snapshot.background_token');
      Png.LoadFromFile(Response.GetValue<string>('snapshot.images.base_image_path'));
      Check((Png.Width = 100) and (Png.Height = 50), 'snapshot dimensions');
      Check(ColorToRGB(Png.Pixels[5, 5]) = ColorToRGB(clRed), 'top red / PNG channel order');
      Check(ColorToRGB(Png.Pixels[5, 45]) = ColorToRGB(clBlue), 'bottom blue / PNG row order');
      Check(Response.GetValue<Double>('snapshot.images.mapping.document_x_per_pixel') = 2, 'pixel scale');
      Check(Response.GetValue<Double>('snapshot.images.mapping.document_x_offset') = -100, 'center origin');
    finally
      Response.Free;
    end;
    Candidate.SetCanvasSize(200, 100);
    Candidate.CanvasLayer.Transparent := True;
    Data := Default(TVectArtRectangleData);
    Data.Bounds := TRectF.Create(-25, -20, 25, 20);
    Data.FillColor := clLime;
    Data.Opacity := 1;
    Data.Visible := True;
    Data.Name := 'Automation test decoration';
    Candidate.InsertRectangle(1, Data);
    CandidateJson := SerializeVectArtDocument(Candidate);
    Request := RequestFor('render_preview');
    Request.AddPair('state_token', Token);
    Request.AddPair('background_token', BackgroundToken);
    Request.AddPair('document', TJSONObject.ParseJSONValue(CandidateJson));
    Response := Call(Request, Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      PreviewPath := Response.GetValue<string>('snapshot.images.composite_image_path');
      Writeln('PREVIEW=', PreviewPath);
      Png.LoadFromFile(PreviewPath);
      Check(ColorToRGB(Png.Pixels[100, 50]) = ColorToRGB(clLime), 'preview decoration');
      Check(ColorToRGB(Png.Pixels[5, 5]) = ColorToRGB(clRed), 'preview background');
      Check(not Response.GetValue<Boolean>('snapshot.applied'), 'preview applied');
    finally
      Response.Free;
    end;
    Check(SerializeVectArtDocument(Document) = Before, 'preview changed Document');
    Check(not History.CanUndo, 'preview changed history');
    Request := RequestFor('render_preview');
    Request.AddPair('state_token', 'stale');
    Request.AddPair('background_token', BackgroundToken);
    Request.AddPair('document', TJSONObject.ParseJSONValue(CandidateJson));
    Response := Call(Request, Document, History, Canvas);
    try
      CheckStatus(Response, 'error');
      Check(Response.GetValue<string>('error.code') = 'state_changed', 'stale document accepted');
    finally
      Response.Free;
    end;
    Request := RequestFor('replace_document');
    Request.AddPair('state_token', Token);
    Request.AddPair('background_token', BackgroundToken);
    Request.AddPair('document', TJSONObject.ParseJSONValue(CandidateJson));
    Request.AddPair('apply', TJSONBool.Create(True));
    Response := Call(Request, Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      Check(Response.GetValue<Boolean>('change.applied'), 'apply failed');
      Check(Response.GetValue<Boolean>('change.changed'), 'changed flag');
    finally
      Response.Free;
    end;
    Check(History.CanUndo and (Document.LayerCount = 2), 'apply history');
    Response := Call(RequestFor('get_layout_geometry'), Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      Check(Response.GetValue<TJSONArray>('geometry.layers').Count = 1, 'geometry layer count');
      Check(Response.GetValue<TJSONArray>('geometry.layers')[0].GetValue<string>('layer_path') =
        '/layers/0', 'geometry JSON path');
      Check(Response.GetValue<TJSONArray>('geometry.layers')[0].GetValue<Double>('bounds.left') =
        -25, 'geometry bounds');
    finally
      Response.Free;
    end;
    History.Undo;
    Check(SerializeVectArtDocument(Document) = Before, 'undo mismatch');
    History.Redo;
    Check(Document.LayerCount = 2, 'redo mismatch');
    History.Undo;
    Canvas.SetReferenceBackgroundRgba(Pixels, 200, 100);
    for I := 0 to 1 do
    begin
      if I = 0 then Request := RequestFor('render_preview')
      else Request := RequestFor('replace_document');
      Request.AddPair('state_token', Token);
      Request.AddPair('background_token', BackgroundToken);
      Request.AddPair('document', TJSONObject.ParseJSONValue(CandidateJson));
      Request.AddPair('apply', TJSONBool.Create(True));
      Response := Call(Request, Document, History, Canvas);
      try
        CheckStatus(Response, 'error');
        Check(Response.GetValue<string>('error.code') = 'background_changed', 'stale background accepted');
      finally
        Response.Free;
      end;
    end;
    Request := RequestFor('measure_text');
    Request.AddPair('text', '日本語サムネイル' + #13#10 + 'ABCD');
    Request.AddPair('font_family', 'Yu Gothic UI');
    Request.AddPair('font_size', TJSONNumber.Create(32));
    Request.AddPair('max_width', TJSONNumber.Create(100));
    Request.AddPair('max_height', TJSONNumber.Create(10));
    Response := Call(Request, Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      Layout := BuildScreenLayoutTextLayout('日本語サムネイル' + #13#10 + 'ABCD', 'Yu Gothic UI', 32, 100);
      Check(Abs(Response.GetValue<Double>('measurement.width') - Layout.Width) < 0.01, 'text width differs');
      Check(Response.GetValue<Integer>('measurement.line_count') = Length(Layout.Lines), 'line wrapping differs');
      Check(not Response.GetValue<Boolean>('measurement.fits_height'), 'height overflow');
    finally
      Response.Free;
    end;
    Request := RequestFor('get_canvas_snapshot');
    Request.AddPair('max_edge', TJSONNumber.Create(100000));
    Response := Call(Request, Document, History, Canvas);
    try
      CheckStatus(Response, 'error');
      Check(Response.GetValue<string>('error.code') = 'invalid_argument', 'size limit');
    finally
      Response.Free;
    end;
    Canvas.SetReferenceBackgroundRgba(nil, 0, 0);
    Response := Call(RequestFor('get_canvas_snapshot'), Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      Png.LoadFromFile(Response.GetValue<string>('snapshot.images.base_image_path'));
      Check(Png.AlphaScanline[0]^[0] = 0, 'transparent canvas alpha');
    finally
      Response.Free;
    end;
    Response := Call(RequestFor('get_creation_schema'), Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      Check(TryDeserializeVectArtDocument(Response.GetValue<TJSONObject>('schema.example_document').ToJSON,
        Candidate, ErrorMessage), ErrorMessage);
      Check(Candidate.LayerCount = 5, 'creation examples missing');
      Check(Candidate[1].FilterCount = 2, 'text effects missing');
    finally
      Response.Free;
    end;
    Response := Call(RequestFor('list_fonts'), Document, History, Canvas);
    try
      CheckStatus(Response, 'ok');
      Check(Response.GetValue<TJSONArray>('fonts').Count > 0, 'font list empty');
    finally
      Response.Free;
    end;
  finally
    Png.Free;
    Canvas.Free;
    History.Free;
    Candidate.Free;
    Document.Free;
  end;
end;

begin
  try
    Application.Initialize;
    TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      Run;
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
