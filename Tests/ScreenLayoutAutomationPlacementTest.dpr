program ScreenLayoutAutomationPlacementTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.JSON, System.Types, System.Math, System.Generics.Collections,
  Vcl.Forms, Vcl.Graphics, ScreenLayoutDocument, ScreenLayoutDocumentJson,
  ScreenLayoutEditHistory, ScreenLayoutCanvas, ScreenLayoutAutomationProtocol,
  ScreenLayoutAutomationArguments, ScreenLayoutTextGeometry, ScreenLayoutFilters,
  ScreenLayoutProjectiveTransform, TextRendererSkiaRuntime;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure Near(A, B: Double; const MessageText: string);
begin
  Check(Abs(A - B) < 0.01, MessageText + ': ' + FloatToStr(A) + ' / ' + FloatToStr(B));
end;

function Call(Request: TJSONObject; Document: TVectArtDocument;
  History: TVectArtEditHistory; Canvas: TVectArtCanvasControl;
  const Status: string = 'ok'): TJSONObject;
begin
  try
    Result := TJSONObject.ParseJSONValue(HandleScreenLayoutAutomationRequest(
      Request.ToJSON, Document, History, nil, Canvas)) as TJSONObject;
  finally
    Request.Free;
  end;
  if Result.GetValue<string>('status') <> Status then
  begin
    try
      raise Exception.Create(Result.ToJSON);
    finally
      Result.Free;
    end;
  end;
end;

function RequestFor(const Command, Token, Background: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('command', Command);
  Result.AddPair('state_token', Token);
  Result.AddPair('background_token', Background);
end;

procedure Run;
var
  Document, Candidate: TVectArtDocument;
  History: TVectArtEditHistory;
  Canvas: TVectArtCanvasControl;
  Text: TScreenLayoutTextLayer;
  Rect: TVectArtRectangleLayer;
  Group: TScreenLayoutGroupLayer;
  Outline: TScreenLayoutOutlineFilter;
  Shadow: TScreenLayoutShadowFilter;
  Request, Response, Entry: TJSONObject;
  Lines: TJSONArray;
  Token, Background, Before, Fitted, ErrorMessage: string;
  Layout: TScreenLayoutTextLayout;
  Transform: TScreenLayoutTransform;
  I: Integer;
begin
  Document := TVectArtDocument.Create;
  Candidate := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Canvas := TVectArtCanvasControl.Create(nil);
  try
    Document.SetCanvasSize(400, 240);
    Canvas.Document := Document;
    Text := TScreenLayoutTextLayer.Create('日本語見出し', TRectF.Create(-150, -80, 150, 80),
      '見出しAB' + #10 + '短文', 'Yu Gothic UI', 40, 0, clYellow);
    Document.InsertLayer(1, Text);
    Text.IndividualLetterSpacingRatios := [0.1, 0.2];
    Text.Alignment := sltaBottomRight;
    Text.RotationDegrees := 90;
    Text.FlipHorizontal := True;
    Transform := TScreenLayoutTransform.Identity;
    Transform.Values[2] := 15;
    Text.Transform := Transform;
    Response := Call(RequestFor('get_document', '', ''), Document, History, Canvas);
    try Token := Response.GetValue<string>('snapshot.state_token'); finally Response.Free; end;
    Background := Canvas.ReferenceBackgroundToken;
    Request := RequestFor('measure_text_layer', Token, Background);
    Request.AddPair('layer_path', '/layers/0');
    Response := Call(Request, Document, History, Canvas);
    try
      Layout := BuildScreenLayoutTextLayout(Text.Text, Text.FontFamily, Text.FontSize, 0,
        Text.FontStyle, Text.LetterSpacingRatio, Text.LineSpacingRatio,
        Text.IndividualLetterSpacingRatios);
      Near(Response.GetValue<Double>('result.scale_x'), 300 / Layout.Width, 'display X scale');
      Near(Response.GetValue<Double>('result.scale_y'), 160 / Layout.Height, 'display Y scale');
      Lines := Response.GetValue<TJSONArray>('result.lines');
      Check(Lines.Count = 2, 'explicit lines');
      Near(Lines[0].GetValue<TJSONArray>('cell_quad')[0].GetValue<Double>('x'), 95,
        'rotation and projective translation');
      Near(Lines[0].GetValue<TJSONArray>('cell_quad')[0].GetValue<Double>('y'), 150,
        'horizontal reflection');
    finally Response.Free; end;
    Request := RequestFor('fit_text', Token, Background);
    Request.AddPair('layer_path', '/layers/0');
    Request.AddPair('target_bounds', AutomationRectJson(TRectF.Create(-100, -50, 100, 50)));
    Response := Call(Request, Document, History, Canvas, 'error');
    try Check(Response.GetValue<string>('error.code') = 'invalid_argument', 'transformed fit rejected');
    finally Response.Free; end;
    Text.Transform := TScreenLayoutTransform.Identity;
    Text.RotationDegrees := 0;
    Text.FlipHorizontal := False;
    Rect := TVectArtRectangleLayer.Create('効果込み範囲', TRectF.Create(170, -20, 195, 20), clRed);
    Document.InsertLayer(2, Rect);
    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Width := 10;
    Rect.AddFilter(Outline);
    Shadow := TScreenLayoutShadowFilter.Create;
    Shadow.OffsetX := 20;
    Shadow.OffsetY := 5;
    Shadow.BlurRadius := 0;
    Rect.AddFilter(Shadow);
    Group := TScreenLayoutGroupLayer.Create('親フィルター');
    Document.InsertLayer(3, Group);
    Group.AddChild(TVectArtRectangleLayer.Create('子', TRectF.Create(-20, -20, 20, 20), clBlue));
    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Width := 6;
    Group.AddFilter(Outline);
    Group.AddChild(TScreenLayoutTextLayer.Create('子の文字', TRectF.Create(-15, -10, 15, 10),
      'A', 'Yu Gothic UI', 20, 0, clWhite));
    Document.SetSelectedLayers([1, 3]);
    Before := SerializeVectArtDocument(Document);
    Response := Call(RequestFor('get_document', '', ''), Document, History, Canvas);
    try Token := Response.GetValue<string>('snapshot.state_token'); finally Response.Free; end;
    Request := RequestFor('fit_text', Token, Background);
    Request.AddPair('layer_path', '/layers/0');
    Request.AddPair('target_bounds', AutomationRectJson(TRectF.Create(-100, -50, 100, 50)));
    Request.AddPair('margin', TJSONNumber.Create(10));
    Request.AddPair('alignment', 'bottomRight');
    Request.AddPair('wrap_width', TJSONNumber.Create(0));
    Response := Call(Request, Document, History, Canvas);
    try
      Check(not Response.GetValue<Boolean>('result.applied'), 'fit must not apply');
      Near(Response.GetValue<Double>('result.scale_x'), Response.GetValue<Double>('result.scale_y'),
        'uniform fit preserves aspect');
      Near(Response.GetValue<Double>('result.frame.right'), 90, 'right alignment');
      Near(Response.GetValue<Double>('result.frame.bottom'), 40, 'bottom alignment');
      Fitted := Response.GetValue<TJSONObject>('result.document').ToJSON;
      Check(TryDeserializeVectArtDocument(Fitted, Candidate, ErrorMessage), ErrorMessage);
      Near(TScreenLayoutTextLayer(Candidate[1]).FontSize, Text.FontSize, 'base size preserved');
      Check(TScreenLayoutTextLayer(Candidate[1]).Alignment = sltaBottomRight, 'alignment preserved');
      Check(Candidate.LayerCount = Document.LayerCount, 'existing layers preserved');
    finally Response.Free; end;
    Request := RequestFor('fit_text', Token, Background);
    Request.AddPair('document', TJSONObject.ParseJSONValue(Fitted));
    Request.AddPair('layer_path', '/layers/0');
    Request.AddPair('target_bounds', AutomationRectJson(TRectF.Create(-100, -50, 100, 50)));
    Request.AddPair('fit_mode', 'frame');
    Response := Call(Request, Document, History, Canvas);
    try
      Near(Response.GetValue<Double>('result.frame.left'), -100, 'frame fit left');
      Near(Response.GetValue<Double>('result.frame.bottom'), 50, 'frame fit bottom');
    finally Response.Free; end;
    Request := RequestFor('analyze_layout', Token, Background);
    Request.AddPair('document', TJSONObject.ParseJSONValue(Fitted));
    Request.AddPair('max_edge', TJSONNumber.Create(1024));
    Request.AddPair('protected_regions', TJSONObject.ParseJSONValue(
      '[{"left":210,"top":-40,"right":230,"bottom":40}]'));
    Response := Call(Request, Document, History, Canvas);
    try
      Entry := Response.GetValue<TJSONArray>('result.layers')[1] as TJSONObject;
      Check(Entry.GetValue<Double>('bounds.right') >= 225, 'shadow and outline expanded bounds');
      Check(Entry.GetValue<Boolean>('outside_canvas'), 'outside canvas');
      Check(Entry.GetValue<TJSONArray>('protected_region_indices').Count = 1, 'protected intersection');
      Entry := Response.GetValue<TJSONArray>('result.layers')[2] as TJSONObject;
      Near(Entry.GetValue<Double>('bounds.left'), -26, 'group outline bounds');
    finally Response.Free; end;
    for I := 0 to 5 do
    begin
      Request := RequestFor('analyze_layout', Token, Background);
      case I of
        0: Request.AddPair('max_edge', TJSONNumber.Create(100.5));
        1: Request.AddPair('protected_regions', TJSONObject.ParseJSONValue('[{"left":0}]'));
        2: Request.AddPair('layer_paths', TJSONObject.ParseJSONValue('["/layers/2/layers/0"]'));
        3: Request.AddPair('layer_paths', TJSONObject.ParseJSONValue('["/layers/1","/layers/1"]'));
        4: Request.AddPair('alpha_threshold', TJSONNumber.Create(0));
        5: Request.AddPair('safe_margin', TJSONNumber.Create(120));
      end;
      Response := Call(Request, Document, History, Canvas, 'error');
      try Check(Response.GetValue<string>('error.code') = 'invalid_argument', 'input validation');
      finally Response.Free; end;
    end;
    Request := RequestFor('measure_text_layer', Token, Background);
    Request.AddPair('layer_path', '/layers/2/layers/1');
    Response := Call(Request, Document, History, Canvas);
    try Check(Response.GetValue<Integer>('result.line_count') = 1, 'nested text path');
    finally Response.Free; end;
    Check(TryDeserializeVectArtDocument(Fitted, Candidate, ErrorMessage), ErrorMessage);
    Candidate[3].Locked := True;
    Request := RequestFor('fit_text', Token, Background);
    Request.AddPair('document', TJSONObject.ParseJSONValue(SerializeVectArtDocument(Candidate)));
    Request.AddPair('layer_path', '/layers/2/layers/1');
    Request.AddPair('target_bounds', AutomationRectJson(TRectF.Create(-50, -50, 50, 50)));
    Response := Call(Request, Document, History, Canvas, 'error');
    try Check(Response.GetValue<string>('error.code') = 'invalid_argument', 'parent lock respected');
    finally Response.Free; end;
    Candidate[2].Visible := False;
    Request := RequestFor('analyze_layout', Token, Background);
    Request.AddPair('document', TJSONObject.ParseJSONValue(SerializeVectArtDocument(Candidate)));
    Request.AddPair('layer_paths', TJSONObject.ParseJSONValue('["/layers/1"]'));
    Response := Call(Request, Document, History, Canvas);
    try
      Entry := Response.GetValue<TJSONArray>('result.layers')[0] as TJSONObject;
      Check(not Entry.GetValue<Boolean>('has_sampled_pixels'), 'hidden layer excluded');
      Check(Entry.GetValue('outside_canvas') is TJSONNull, 'no pixels is not a safety guarantee');
    finally Response.Free; end;
    Request := RequestFor('analyze_layout', Token, Background);
    Request.AddPair('analysis_padding', TJSONNumber.Create(0));
    Request.AddPair('layer_paths', TJSONObject.ParseJSONValue('["/layers/1"]'));
    Response := Call(Request, Document, History, Canvas);
    try
      Entry := Response.GetValue<TJSONArray>('result.layers')[0] as TJSONObject;
      Check(Entry.GetValue<Boolean>('touches_analysis_edge'), 'clipped analysis is flagged');
    finally Response.Free; end;
    Response := Call(RequestFor('get_creation_schema', '', ''), Document, History, Canvas);
    try
      Check(TryDeserializeVectArtDocument(
        Response.GetValue<TJSONObject>('schema.additional_example_document').ToJSON,
        Candidate, ErrorMessage), ErrorMessage);
      Check((Candidate.LayerCount = 2) and (Candidate[1] is TScreenLayoutGroupLayer), 'group example');
      Check(TScreenLayoutGroupLayer(Candidate[1]).ChildCount = 2, 'group example children');
    finally Response.Free; end;
    Request := RequestFor('fit_text', 'stale', Background);
    Response := Call(Request, Document, History, Canvas, 'error');
    try Check(Response.GetValue<string>('error.code') = 'state_changed', 'stale state');
    finally Response.Free; end;
    Request := RequestFor('analyze_layout', Token, 'stale');
    Response := Call(Request, Document, History, Canvas, 'error');
    try Check(Response.GetValue<string>('error.code') = 'background_changed', 'stale background');
    finally Response.Free; end;
    Check(SerializeVectArtDocument(Document) = Before, 'planning mutated document');
    Check(not History.CanUndo, 'planning changed undo');
    Check((Document.SelectionCount = 2) and Document.IsLayerSelected(1) and
      Document.IsLayerSelected(3), 'planning changed selection');
    Request := RequestFor('replace_document', Token, Background);
    Request.AddPair('document', TJSONObject.ParseJSONValue(Fitted));
    Request.AddPair('apply', TJSONBool.Create(True));
    Response := Call(Request, Document, History, Canvas);
    Response.Free;
    Check(History.CanUndo, 'fit application history');
    History.Undo;
    Check(SerializeVectArtDocument(Document) = Before, 'fit undo');
    History.Redo;
    Check(SerializeVectArtDocument(Document) = Fitted, 'fit redo');
  finally
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
    try Run; finally TTextRendererSkiaRuntime.Release; end;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
