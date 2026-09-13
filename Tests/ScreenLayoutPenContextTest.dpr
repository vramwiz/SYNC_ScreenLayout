// キャンバスの実入力で、選択メニューとペンの頂点編集の振り分けを検証する。
program ScreenLayoutPenContextTest;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.SysUtils, System.Types, Vcl.Forms, Vcl.Controls,
  ScreenLayoutCanvas, ScreenLayoutDocument, ScreenLayoutEditorState, ScreenLayoutEditHistory, TextRendererSkiaRuntime;
type
  TTestCanvas = class(TVectArtCanvasControl)
  public
    procedure ClickAt(Button: TMouseButton; X, Y: Single);
  end;
  TMenuObserver = class
  public
    Count: Integer;
    procedure ShowMenu(Sender: TObject; const ScreenPoint: TPoint; const Layers: TArray<Integer>);
  end;
procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;
procedure TMenuObserver.ShowMenu(Sender: TObject; const ScreenPoint: TPoint; const Layers: TArray<Integer>);
begin
  Inc(Count);
end;
procedure TTestCanvas.ClickAt(Button: TMouseButton; X, Y: Single);
var P: TPoint;
begin
  P := Point(Round(CanvasBounds.CenterPoint.X + X * Zoom), Round(CanvasBounds.CenterPoint.Y + Y * Zoom));
  MouseDown(Button, [], P.X, P.Y);
  MouseUp(Button, [], P.X, P.Y);
end;
procedure Run;
var
  Form: TForm;
  Canvas: TTestCanvas;
  Document: TVectArtDocument;
  State: TVectArtEditorState;
  History: TVectArtEditHistory;
  Observer: TMenuObserver;
  Vertices: TArray<TScreenLayoutVertex>;
  Contours: TArray<TScreenLayoutContour>;
  Path: TVectArtPathLayer;
  Shape: TScreenLayoutShapeLayer;
  I: Integer;
begin
  Form := TForm.Create(nil);
  Document := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Observer := TMenuObserver.Create;
  try
    Document.SetCanvasSize(200, 200);
    Canvas := TTestCanvas.Create(Form);
    Canvas.Parent := Form;
    Canvas.SetBounds(0, 0, 400, 400);
    Canvas.Document := Document;
    Canvas.EditorState := State;
    Canvas.EditHistory := History;
    Canvas.OnObjectContextMenu := Observer.ShowMenu;
    Form.SetBounds(-10000, -10000, 440, 440);
    Form.Show;
    Application.ProcessMessages;
    SetLength(Vertices, 3);
    for I := 0 to 2 do
    begin
      Vertices[I].Position := TPointF.Create((I-1)*40, 0);
      Vertices[I].Kind := slvkSharp;
      Vertices[I].OutgoingSegment := slskLine;
    end;
    Path := TVectArtPathLayer.Create('Path', Vertices, False);
    Document.InsertLayer(1, Path);
    Document.SelectedIndex := 1;
    State.CurrentTool := vetSelect;
    Canvas.ClickAt(mbRight, 0, 0);
    Check((Observer.Count = 1) and (Length(Path.Vertices) = 3), 'select right click must show menu');
    Canvas.ClickAt(mbLeft, 0, 0);
    Canvas.ClickAt(mbRight, 0, 0);
    Check((Observer.Count = 1) and (Length(Path.Vertices) = 2), 'selected path vertex must delete in select tool');
    History.Undo;
    Check(Length(Path.Vertices) = 3, 'selected vertex delete undo');
    History.Redo;
    Check(Length(Path.Vertices) = 2, 'selected vertex delete redo');
    History.Undo;
    State.CurrentTool := vetPath;
    Canvas.ClickAt(mbLeft, -20, 0);
    Check(Length(Path.Vertices) = 4, 'pen left click must insert');
    Canvas.ClickAt(mbRight, -20, 0);
    Check((Length(Path.Vertices) = 3) and (Observer.Count = 1), 'pen right click must delete without menu');
    History.Undo;
    Check(Length(Path.Vertices) = 4, 'delete undo');
    History.Redo;
    Canvas.ClickAt(mbRight, 80, 80);
    Check(Observer.Count = 1, 'pen empty right click opened menu');
    SetLength(Contours, 1);
    SetLength(Contours[0].Vertices, 4);
    for I := 0 to 3 do
    begin
      Contours[0].Vertices[I].Kind := slvkSharp;
      Contours[0].Vertices[I].OutgoingSegment := slskLine;
    end;
    Contours[0].Vertices[0].Position := TPointF.Create(-40, -40);
    Contours[0].Vertices[1].Position := TPointF.Create(40, -40);
    Contours[0].Vertices[2].Position := TPointF.Create(40, 40);
    Contours[0].Vertices[3].Position := TPointF.Create(-40, 40);
    Shape := TScreenLayoutShapeLayer.Create('Shape', Contours);
    Document.InsertLayer(2, Shape);
    Document.SelectedIndex := 2;
    Canvas.ClickAt(mbLeft, 0, -40);
    Check(Length(Shape.Contours[0].Vertices) = 5, 'pen did not insert on closed shape');
    Canvas.ClickAt(mbRight, 0, -40);
    Check((Length(Shape.Contours[0].Vertices) = 4) and (Observer.Count = 1), 'pen did not delete on closed shape');
    State.CurrentTool := vetSelect;
    Canvas.ClickAt(mbLeft, -40, -40);
    Canvas.ClickAt(mbRight, -40, -40);
    Check((Length(Shape.Contours[0].Vertices) = 3) and (Observer.Count = 1),
      'selected shape vertex must delete in select tool');
    History.Undo;
    Check(Length(Shape.Contours[0].Vertices) = 4, 'selected shape delete undo');
    Canvas.ClickAt(mbLeft, -40, -40);
    Canvas.ClickAt(mbRight, 40, 40);
    Check((Length(Shape.Contours[0].Vertices) = 4) and (Observer.Count = 2),
      'unselected vertex must show menu instead of deleting');
    Writeln('PASS: select menu, pen insert/delete, empty click, closed shape, undo/redo');
  finally
    Form.Free;
    Observer.Free;
    History.Free;
    State.Free;
    Document.Free;
  end;
end;
begin
  Application.Initialize;
  TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
  try Run;
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
  TTextRendererSkiaRuntime.Release;
end.