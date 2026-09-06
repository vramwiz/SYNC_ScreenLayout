// 変形の四隅固定、制約、履歴、保存、描画と当たり判定の一致を検証する。
program ScreenLayoutFreeTransformTest;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Math, System.Types, System.Classes, Vcl.Graphics, Vcl.Forms, Vcl.Controls,
  ScreenLayoutDocument, ScreenLayoutEditorState, ScreenLayoutEditHistory,
  ScreenLayoutTransformInteraction, ScreenLayoutSelectionGeometry,
  ScreenLayoutProjectiveTransform, ScreenLayoutLayerGeometry,
  ScreenLayoutCanvasInteraction, ScreenLayoutDocumentJson, ScreenLayoutRenderer,
  ScreenLayoutGroupCommands, TextRendererSkiaRuntime,
  ScreenLayoutKeyboardMovement, ScreenLayoutLayerFlipOperations, Winapi.Windows,
  ScreenLayoutCanvas, ScreenLayoutShapeOperations;

type
  TTestCanvas = class(TVectArtCanvasControl)
  public
    procedure Drag(const StartPoint, EndPoint: TPoint);
    procedure MoveAndPaint(const StartPoint, EndPoint: TPoint);
    procedure ZoomAndPaint(WheelDelta: Integer);
  end;
  TChangeCounter = class
  public
    Count: Integer;
    procedure Changed(Sender: TObject);
  end;

procedure TTestCanvas.Drag(const StartPoint, EndPoint: TPoint);
begin
  MouseDown(mbLeft,[ssCtrl],StartPoint.X,StartPoint.Y);
  MouseMove([ssCtrl,ssLeft],EndPoint.X,EndPoint.Y);
  MouseUp(mbLeft,[ssCtrl],EndPoint.X,EndPoint.Y);
end;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure Near(const A,B: TPointF; const MessageText: string);
begin
  Check((Abs(A.X-B.X)<0.001) and (Abs(A.Y-B.Y)<0.001),MessageText);
end;

procedure CheckCanvasRouting;
var Form: TForm; Control: TTestCanvas; Doc: TVectArtDocument;
  State: TVectArtEditorState; History: TVectArtEditHistory;
  Layout: TScreenLayoutTransformInteraction; G: TVectArtSelectionGeometry;
  Start: TPoint; Layer: TVectArtLayer;
begin
  Application.Initialize;
  Form := TForm.Create(nil); Doc := TVectArtDocument.Create;
  State := TVectArtEditorState.Create; History := TVectArtEditHistory.Create;
  Layout := TScreenLayoutTransformInteraction.Create;
  try
    Doc.SetCanvasSize(400,400);
    Layer := TVectArtRectangleLayer.Create('Canvas rectangle',TRectF.Create(-50,-50,50,50),clRed);
    Doc.InsertLayer(1,Layer); Doc.SelectedIndex := 1; State.CurrentTool := vetSelect;
    Form.SetBounds(-10000,-10000,600,600);
    Control := TTestCanvas.Create(Form); Control.Parent := Form;
    Control.SetBounds(0,0,550,550); Control.Document := Doc;
    Control.EditorState := State; Control.EditHistory := History;
    Form.Show; Application.ProcessMessages;
    Layout.Configure(Doc,History,State,Control.CanvasBounds,Control.Zoom);
    Check(Layout.Geometry(G),'Actual canvas selection frame missing');
    Start := G.Handles[vshTopLeft].CenterPoint;
    Control.Drag(Start,Point(Start.X-20,Start.Y+10));
    Check(not Layer.Transform.IsIdentity,'Actual canvas did not route Ctrl drag to transform');
    Check(Doc.SelectionCount=1,'Ctrl handle drag toggled selection');
    History.Undo;
    Check(Layer.Transform.IsIdentity,'Actual canvas transform undo failed');
  finally
    Layout.Free; Form.Free; History.Free; State.Free; Doc.Free;
  end;
end;

procedure TTestCanvas.MoveAndPaint(const StartPoint, EndPoint: TPoint);
var
  Bitmap: Vcl.Graphics.TBitmap;
begin
  Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    Bitmap.SetSize(Width,Height);
    MouseDown(mbLeft,[],StartPoint.X,StartPoint.Y);
    MouseMove([ssLeft],EndPoint.X,EndPoint.Y);
    PaintTo(Bitmap.Canvas.Handle,0,0);
    MouseUp(mbLeft,[],EndPoint.X,EndPoint.Y);
  finally
    Bitmap.Free;
  end;
end;

procedure TTestCanvas.ZoomAndPaint(WheelDelta: Integer);
var
  Bitmap: Vcl.Graphics.TBitmap;
  MousePoint: TPoint;
begin
  Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    Bitmap.SetSize(Width,Height);
    MousePoint := ClientToScreen(ClientRect.CenterPoint);
    DoMouseWheel([],WheelDelta,MousePoint);
    PaintTo(Bitmap.Canvas.Handle,0,0);
  finally
    Bitmap.Free;
  end;
end;

procedure TChangeCounter.Changed(Sender: TObject);
begin
  Inc(Count);
end;

procedure CheckCanvasMovePreview;
var
  Center: TPoint;
  Contours: TArray<TScreenLayoutContour>;
  Control: TTestCanvas;
  Doc: TVectArtDocument;
  Form: TForm;
  G: TVectArtSelectionGeometry;
  History: TVectArtEditHistory;
  I: Integer;
  Layout: TScreenLayoutTransformInteraction;
  Matrix: TScreenLayoutTransform;
  MappedBefore: TPointF;
  Shape: TScreenLayoutShapeLayer;
  State: TVectArtEditorState;
begin
  Form := TForm.Create(nil);
  Doc := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Layout := TScreenLayoutTransformInteraction.Create;
  try
    Doc.SetCanvasSize(400,400);
    SetLength(Contours,1);
    SetLength(Contours[0].Vertices,64);
    for I := 0 to High(Contours[0].Vertices) do
    begin
      Contours[0].Vertices[I].Position := TPointF.Create(
        Cos(I*2*Pi/Length(Contours[0].Vertices))*50,
        Sin(I*2*Pi/Length(Contours[0].Vertices))*50);
      Contours[0].Vertices[I].OutgoingSegment := slskLine;
    end;
    Shape := TScreenLayoutShapeLayer.Create('Closed path',Contours);
    Doc.InsertLayer(1,Shape);
    Doc.SelectedIndex := 1;
    State.CurrentTool := vetSelect;
    Form.SetBounds(-10000,-10000,600,600);
    Control := TTestCanvas.Create(Form);
    Control.Parent := Form;
    Control.SetBounds(0,0,550,550);
    Control.Document := Doc;
    Control.EditorState := State;
    Control.EditHistory := History;
    Form.Show;
    Application.ProcessMessages;
    Layout.Configure(Doc,History,State,Control.CanvasBounds,Control.Zoom);
    Check(Layout.Geometry(G),'Move preview selection frame missing');
    Center := G.FrameRect.CenterPoint;
    Control.MoveAndPaint(Center,Center+Point(20,10));
    Check(TScreenLayoutShapeLayer(Doc[1]).Contours[0].Vertices[0].Position.X>60,
      'Move preview did not commit the shape movement');
    Check(History.CanUndo,'Move preview did not create undo history');
    Matrix := TScreenLayoutTransform.Identity;
    Matrix.Values[0] := 1.2;
    Shape.Transform := Matrix;
    Doc.Changed;
    Layout.Configure(Doc,History,State,Control.CanvasBounds,Control.Zoom);
    Check(Layout.Geometry(G),'Transformed move preview frame missing');
    Center := G.FrameRect.CenterPoint;
    MappedBefore := Shape.Transform.Map(Shape.Contours[0].Vertices[0].Position);
    Control.MoveAndPaint(Center,Center+Point(15,8));
    Near(Shape.Transform.Map(Shape.Contours[0].Vertices[0].Position),
      MappedBefore+TPointF.Create(15,8),
      'Transformed move preview did not commit the movement');
    Control.ZoomAndPaint(-120);
    Check(Control.Zoom<1,'Zoom preview did not update the displayed scale');
  finally
    Layout.Free;
    Form.Free;
    History.Free;
    State.Free;
    Doc.Free;
  end;
end;

procedure CheckMovePreviewComposition;
var
  Actual: TVectArtRenderBuffer;
  Contours: TArray<TScreenLayoutContour>;
  Doc: TVectArtDocument;
  Expected: TVectArtRenderBuffer;
  I: Integer;
  Lower: TVectArtRenderBuffer;
  Shape: TScreenLayoutShapeLayer;
  Selected: TVectArtRenderBuffer;
  Upper: TVectArtRenderBuffer;
begin
  Doc := TVectArtDocument.Create;
  Lower := TVectArtRenderBuffer.Create;
  Selected := TVectArtRenderBuffer.Create;
  Upper := TVectArtRenderBuffer.Create;
  Actual := TVectArtRenderBuffer.Create;
  Expected := TVectArtRenderBuffer.Create;
  try
    Doc.SetCanvasSize(100,100);
    Doc.CanvasLayer.Transparent := True;
    Doc.InsertLayer(1,TVectArtRectangleLayer.Create('Lower',
      TRectF.Create(-45,-45,45,45),clRed));
    SetLength(Contours,1);
    SetLength(Contours[0].Vertices,3);
    Contours[0].Vertices[0].Position := TPointF.Create(-20,-20);
    Contours[0].Vertices[1].Position := TPointF.Create(20,-20);
    Contours[0].Vertices[2].Position := TPointF.Create(0,20);
    for I := 0 to 2 do
      Contours[0].Vertices[I].OutgoingSegment := slskLine;
    Shape := TScreenLayoutShapeLayer.Create('Selected',Contours);
    Shape.FillColor := clLime;
    Doc.InsertLayer(2,Shape);
    Doc.InsertLayer(3,TVectArtRectangleLayer.Create('Upper',
      TRectF.Create(5,-10,35,10),clBlue));
    RenderVectArtDocumentRange(Doc,Lower,100,100,1,1);
    RenderVectArtDocumentRange(Doc,Selected,100,100,2,2);
    RenderVectArtDocumentRange(Doc,Upper,100,100,3,3);
    Doc.SetShapeContours(2,
      TranslateScreenLayoutShapeContours(Contours,10,0));
    RenderVectArtDocument(Doc,Expected,100,100);
    Actual.SetSize(100,100);
    Move(Lower.Data^,Actual.Data^,
      Actual.PixelCount*SizeOf(TVectArtRgbaPixel));
    CompositeVectArtRgbaOffset(Selected,Actual.Data,100,100,10,0);
    CompositeVectArtRgba(Upper,Actual.Data,100,100);
    for I := 0 to Actual.PixelCount-1 do
      Check((Actual.Pixels[I].R=Expected.Pixels[I].R) and
        (Actual.Pixels[I].G=Expected.Pixels[I].G) and
        (Actual.Pixels[I].B=Expected.Pixels[I].B) and
        (Actual.Pixels[I].A=Expected.Pixels[I].A),
        'Move preview composition changed pixels or layer order');
  finally
    Expected.Free;
    Actual.Free;
    Upper.Free;
    Selected.Free;
    Lower.Free;
    Doc.Free;
  end;
end;

procedure CheckMoveNotificationBatch;
var
  Counter: TChangeCounter;
  Contours: TArray<TScreenLayoutContour>;
  Doc: TVectArtDocument;
  I: Integer;
  Interaction: TVectArtCanvasInteraction;
begin
  Doc := TVectArtDocument.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  Counter := TChangeCounter.Create;
  try
    Doc.SetCanvasSize(100,100);
    SetLength(Contours,1);
    SetLength(Contours[0].Vertices,4);
    Contours[0].Vertices[0].Position := TPointF.Create(-10,-10);
    Contours[0].Vertices[1].Position := TPointF.Create(10,-10);
    Contours[0].Vertices[2].Position := TPointF.Create(10,10);
    Contours[0].Vertices[3].Position := TPointF.Create(-10,10);
    for I := 0 to 3 do
      Contours[0].Vertices[I].OutgoingSegment := slskLine;
    Doc.InsertLayer(1,TScreenLayoutShapeLayer.Create('Shape',Contours));
    Doc.SelectedIndex := 1;
    Interaction.Configure(Doc,Rect(0,0,100,100),1);
    Doc.OnChanged := Counter.Changed;
    Check(Interaction.MouseDown(mbLeft,[],50,50),
      'Shape move did not begin');
    Interaction.MouseMove([ssLeft],70,50);
    Check(Counter.Count=0,
      'Interactive move refreshed external controls during drag');
    Interaction.MouseUp(mbLeft);
    Check(Counter.Count=1,
      'Interactive move did not send one completion notification');
  finally
    Interaction.Free;
    Counter.Free;
    Doc.Free;
  end;
end;

var Doc, Loaded: TVectArtDocument; State: TVectArtEditorState;
  History: TVectArtEditHistory; Interaction: TScreenLayoutTransformInteraction;
  Hit: TVectArtCanvasInteraction; Layer, CopyLayer: TVectArtLayer;
  G: TVectArtSelectionGeometry; P: TPoint; Q, Before: TScreenLayoutQuad;
  Buffer: TVectArtRenderBuffer; ErrorText, Json: string; I: Integer;
  Inverse: TScreenLayoutTransform;
  Group: TScreenLayoutGroupLayer; Child: TVectArtLayer;
  Vertices: TArray<TScreenLayoutVertex>; PathLayer: TVectArtPathLayer;
  Matrix: TScreenLayoutTransform; CaptureNeeded: Boolean;
  RemovedRectangle: TVectArtRectangleData;
  CornerHandles: TArray<TScreenLayoutRoundedCornerHandle>;
  Radii: TScreenLayoutCornerRadii;
  RadiusHandle: TRect;
  RoundedLayer: TScreenLayoutRoundedRectangleLayer;
begin
  Doc := TVectArtDocument.Create; Loaded := TVectArtDocument.Create;
  State := TVectArtEditorState.Create; History := TVectArtEditHistory.Create;
  Interaction := TScreenLayoutTransformInteraction.Create;
  Hit := TVectArtCanvasInteraction.Create; Buffer := TVectArtRenderBuffer.Create;
  try
    Doc.SetCanvasSize(400,400); Doc.CanvasLayer.Transparent := True;
    Layer := TVectArtRectangleLayer.Create('Rectangle',TRectF.Create(-50,-50,50,50),clRed);
    Doc.InsertLayer(Doc.LayerCount,Layer); Doc.SelectedIndex := 1; State.CurrentTool := vetSelect;
    Interaction.Configure(Doc,History,State,Rect(0,0,400,400),1);
    Hit.Configure(Doc,Rect(0,0,400,400),1);
    Check(Interaction.Geometry(G),'No selection frame');
    Before := ScreenLayoutRectQuad(TRectF.Create(-50,-50,50,50));
    P := G.Handles[vshTopLeft].CenterPoint;
    Check(Interaction.MouseDown([ssCtrl],P.X,P.Y),'Ctrl drag did not begin');
    Interaction.MouseMove([ssCtrl,ssLeft],P.X-30,P.Y+20);
    Interaction.Finish;
    Check(TryGetScreenLayoutLayerQuad(Layer,Q),'No transformed quad');
    Near(Q[0],Before[0]+TPointF.Create(-30,20),'Dragged corner mismatch');
    for I := 1 to 3 do Near(Q[I],Before[I],'Stationary corner moved');
    Check(Layer.Transform.Inverse(Inverse),'No inverse');
    Near(Inverse.Map(Layer.Transform.Map(TPointF.Create(10,20))),TPointF.Create(10,20),'Inverse mismatch');
    Check(Hit.LayerAt(127,172)=1,'Transformed protrusion cannot be selected');
    Json := SerializeVectArtDocument(Doc);
    Check(TryDeserializeVectArtDocument(Json,Loaded,ErrorText),ErrorText);
    Near(Loaded[1].Transform.Map(Before[0]),Q[0],'JSON lost transform');
    CopyLayer := CloneScreenLayoutLayer(Layer, 'Copy');
    try Near(CopyLayer.Transform.Map(Before[0]),Q[0],'Clone lost transform') finally CopyLayer.Free end;
    Check(Doc.RemoveRectangle(1,RemovedRectangle),'Could not remove transformed rectangle');
    Doc.InsertRectangle(1,RemovedRectangle); Layer := Doc[1]; Doc.SelectedIndex := 1;
    Near(Layer.Transform.Map(Before[0]),Q[0],'Delete/restore lost transform');
    History.Undo;
    Check(Layer.Transform.IsIdentity,'Undo did not restore identity');
    History.Redo;
    Near(Layer.Transform.Map(Before[0]),Q[0],'Redo mismatch');
    Interaction.Geometry(G); P := G.Handles[vshTopRight].CenterPoint;
    Interaction.MouseDown([ssCtrl],P.X,P.Y);
    Interaction.MouseMove([ssCtrl,ssLeft],P.X+20,P.Y-10);
    Interaction.Finish(True);
    Near(Layer.Transform.Map(Before[0]),Q[0],'Cancel changed original transform');
    History.Undo;
    Interaction.Geometry(G); P := G.Handles[vshTop].CenterPoint;
    Interaction.MouseDown([ssCtrl],P.X,P.Y);
    Interaction.MouseMove([ssCtrl,ssLeft],P.X+30,P.Y+20);
    Interaction.Finish;
    TryGetScreenLayoutLayerQuad(Layer,Q);
    Near(Q[0],Before[0]+TPointF.Create(30,0),'Shear moved wrong edge');
    Near(Q[2],Before[2],'Shear moved opposite edge');
    History.Undo;
    Interaction.Geometry(G); P := G.Handles[vshTopLeft].CenterPoint;
    Interaction.MouseDown([ssCtrl,ssAlt],P.X,P.Y);
    Interaction.MouseMove([ssCtrl,ssAlt,ssLeft],P.X+20,P.Y);
    Interaction.Finish;
    TryGetScreenLayoutLayerQuad(Layer,Q);
    Near(Q[0],Before[0]+TPointF.Create(20,0),'Perspective first corner');
    Near(Q[1],Before[1]-TPointF.Create(20,0),'Perspective symmetric corner');
    TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0))+'..\Lib\Skia\Win64\sk4d.dll');
    try
      CheckCanvasRouting;
      CheckCanvasMovePreview;
      CheckMovePreviewComposition;
      RenderVectArtDocument(Doc,Buffer,400,400);
      Check(Buffer.Pixels[160*400+160].A=0,'Perspective rendered outside trapezoid');
      Check(Buffer.Pixels[200*400+200].A>200,'Perspective did not render center');
    finally TTextRendererSkiaRuntime.Release end;
    Check(HandleSelectionNudge(Doc,History,VK_RIGHT,[]),'Transformed keyboard nudge rejected');
    Near(Layer.Transform.Map(Before[0]),Q[0]+TPointF.Create(1,0),'Nudge changed local rather than display coordinates');
    History.Undo;
    Near(Layer.Transform.Map(Before[0]),Q[0],'Nudge undo mismatch');
    FlipScreenLayoutSelection(Doc,History,State,slfdHorizontal);
    Near(Layer.Transform.Map(Before[0]),TPointF.Create(-Q[0].X,Q[0].Y),'Transformed horizontal flip');
    History.Undo;
    Near(Layer.Transform.Map(Before[0]),Q[0],'Flip undo lost transform');
    History.Undo;
    Interaction.Geometry(G); P := G.Handles[vshBottomRight].CenterPoint;
    Interaction.MouseDown([ssShift,ssAlt],P.X,P.Y);
    Interaction.MouseMove([ssShift,ssAlt,ssLeft],P.X+40,P.Y+20);
    Interaction.Finish;
    TryGetScreenLayoutLayerQuad(Layer,Q);
    Near((Q[0]+Q[2])*0.5,TPointF.Create(0,0),'Centered resize moved center');
    Check(Abs((Q[1].X-Q[0].X)-(Q[3].Y-Q[0].Y))<0.001,'Shift resize lost aspect ratio');
    History.Undo;
    Interaction.Geometry(G); P := G.Handles[vshTopLeft].CenterPoint;
    Interaction.MouseDown([ssCtrl],P.X,P.Y);
    Interaction.MouseMove([ssCtrl,ssLeft],P.X+200,P.Y+200);
    Interaction.Finish;
    Check(Layer.Transform.IsIdentity,'Crossing corners produced an invalid transform');
    Group := TScreenLayoutGroupLayer.Create('Group');
    Child := TVectArtRectangleLayer.Create('Child',TRectF.Create(-50,-50,50,50),clBlue);
    Group.AddChild(Child); Doc.InsertLayer(Doc.LayerCount,Group); Doc.SelectedIndex := 2;
    Interaction.Geometry(G); P := G.Handles[vshTopLeft].CenterPoint;
    Interaction.MouseDown([ssCtrl],P.X,P.Y);
    Interaction.MouseMove([ssCtrl,ssLeft],P.X-20,P.Y);
    Interaction.Finish;
    Near(Child.Transform.Map(Before[0]),Before[0]+TPointF.Create(-20,0),'Group did not transform child');
    Check(Group.Transform.IsIdentity,'Group transformation was applied twice');
    History.Undo;
    Check(Child.Transform.IsIdentity,'Group undo did not restore child');
    State.OpenGroupInDocument(Doc,Group); State.SetOpenGroupChildren([Child]);
    Interaction.Geometry(G); P := G.Handles[vshTopLeft].CenterPoint;
    Interaction.MouseDown([ssCtrl,ssShift],P.X,P.Y);
    Interaction.MouseMove([ssCtrl,ssShift,ssLeft],P.X-30,P.Y+2);
    Interaction.Finish;
    Near(Child.Transform.Map(Before[0]),Before[0]+TPointF.Create(-30,0),'Open group constrained transform');
    State.OpenGroup := nil;
    SetLength(Vertices,3);
    Vertices[0].Position := TPointF.Create(-40,-20);
    Vertices[1].Position := TPointF.Create(0,10);
    Vertices[2].Position := TPointF.Create(40,20);
    PathLayer := TVectArtPathLayer.Create('Transformed path',Vertices,False);
    Matrix := TScreenLayoutTransform.Identity; Matrix.Values[0] := 1.5; Matrix.Values[2] := 20;
    PathLayer.Transform := Matrix;
    Doc.InsertLayer(Doc.LayerCount,PathLayer); Doc.SelectedIndex := 3;
    Hit.EditHistory := History; Hit.Configure(Doc,Rect(0,0,400,400),1);
    Check(Hit.SelectedPathVertexRects[1].CenterPoint=Point(220,210),'Vertex overlay ignored transform');
    Check(Hit.MouseDownSelectedVertex(mbLeft,[],220,210,CaptureNeeded),'Transformed vertex cannot be selected');
    Hit.MouseMove([ssLeft],235,220); Hit.MouseUp(mbLeft);
    Near(PathLayer.Vertices[1].Position,TPointF.Create(10,20),'Vertex drag did not inverse-map display coordinates');
    Radii := Default(TScreenLayoutCornerRadii);
    Radii.TopLeft := 15;
    Radii.TopRight := 15;
    Radii.BottomRight := 15;
    Radii.BottomLeft := 15;
    RoundedLayer := TScreenLayoutRoundedRectangleLayer.Create(
      'Transformed rounded rectangle', TRectF.Create(-50,-30,50,30),
      clRed, Radii);
    Matrix := TScreenLayoutTransform.Identity;
    Matrix.Values[2] := 40;
    RoundedLayer.Transform := Matrix;
    Doc.InsertLayer(Doc.LayerCount, RoundedLayer);
    Doc.SelectedIndex := Doc.LayerCount - 1;
    Hit.Configure(Doc,Rect(0,0,400,400),1);
    CornerHandles := Hit.RoundedRectangleCornerHandles;
    Check(Length(CornerHandles)=0,
      'Transformed rounded rectangle retained stale corner handles');
    Check(not Hit.RoundedRectangleRadiusHandle(RadiusHandle),
      'Transformed rounded rectangle retained stale radius handle');
    CheckMoveNotificationBatch;
    Writeln('PASS free transform, shear, perspective, undo, cancel, JSON, clone, hit-test and rendering');
  finally
    Buffer.Free; Hit.Free; Interaction.Free; History.Free; State.Free; Loaded.Free; Doc.Free;
  end;
end.
