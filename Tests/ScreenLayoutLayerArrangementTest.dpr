// 複数選択の6方向整列、両端固定の均等間隔配置、履歴、グループ内選択を検証する。
program ScreenLayoutLayerArrangementTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutLayerArrangementOperations in
    '..\Source\Core\Commands\Layer\ScreenLayoutLayerArrangementOperations.pas',
  ScreenLayoutDocumentJson in
    '..\Source\Persistence\ScreenLayoutDocumentJson.pas';

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
end;

procedure CheckSame(A, B: Single; const MessageText: string);
begin
  Check(SameValue(A, B, 0.0001), MessageText);
end;

procedure Run;
var
  A: TVectArtRectangleLayer;
  B: TVectArtRectangleLayer;
  BeforeJson: string;
  C: TVectArtRectangleLayer;
  Document: TVectArtDocument;
  Group: TScreenLayoutGroupLayer;
  GroupA: TVectArtRectangleLayer;
  GroupB: TVectArtRectangleLayer;
  History: TVectArtEditHistory;
  State: TVectArtEditorState;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Document.SetCanvasSize(400, 300);
    A := TVectArtRectangleLayer.Create('A',
      TRectF.Create(0, 0, 10, 10), clRed);
    B := TVectArtRectangleLayer.Create('B',
      TRectF.Create(110, 20, 130, 40), clGreen);
    C := TVectArtRectangleLayer.Create('C',
      TRectF.Create(30, 80, 60, 110), clBlue);
    Document.InsertLayer(1, A);
    Document.InsertLayer(2, B);
    Document.InsertLayer(3, C);
    Document.SetSelectedLayers([1, 2, 3]);
    BeforeJson := SerializeVectArtDocument(Document);

    ArrangeScreenLayoutSelection(Document, History, State,
      slaAlignLeft);
    CheckSame(A.Bounds.Left, 0, 'left anchor moved');
    CheckSame(B.Bounds.Left, 0, 'middle layer was not left-aligned');
    CheckSame(C.Bounds.Left, 0, 'right layer was not left-aligned');
    History.Undo;
    Check(SerializeVectArtDocument(Document) = BeforeJson,
      'alignment Undo did not restore the document');

    ArrangeScreenLayoutSelection(Document, History, State,
      slaAlignHorizontalCenter);
    CheckSame(A.Bounds.CenterPoint.X, 65, 'horizontal center A mismatch');
    CheckSame(B.Bounds.CenterPoint.X, 65, 'horizontal center B mismatch');
    CheckSame(C.Bounds.CenterPoint.X, 65, 'horizontal center C mismatch');
    History.Undo;

    ArrangeScreenLayoutSelection(Document, History, State,
      slaAlignRight);
    CheckSame(A.Bounds.Right, 130, 'right alignment A mismatch');
    CheckSame(B.Bounds.Right, 130, 'right alignment B mismatch');
    History.Undo;

    ArrangeScreenLayoutSelection(Document, History, State, slaAlignTop);
    CheckSame(B.Bounds.Top, 0, 'top alignment B mismatch');
    CheckSame(C.Bounds.Top, 0, 'top alignment C mismatch');
    History.Undo;

    ArrangeScreenLayoutSelection(Document, History, State,
      slaAlignVerticalCenter);
    CheckSame(A.Bounds.CenterPoint.Y, 55, 'vertical center A mismatch');
    CheckSame(B.Bounds.CenterPoint.Y, 55, 'vertical center B mismatch');
    CheckSame(C.Bounds.CenterPoint.Y, 55, 'vertical center C mismatch');
    History.Undo;

    ArrangeScreenLayoutSelection(Document, History, State, slaAlignBottom);
    CheckSame(A.Bounds.Bottom, 110, 'bottom alignment A mismatch');
    CheckSame(B.Bounds.Bottom, 110, 'bottom alignment B mismatch');
    History.Undo;

    ArrangeScreenLayoutSelection(Document, History, State,
      slaDistributeHorizontal);
    CheckSame(A.Bounds.Left, 0, 'horizontal first endpoint moved');
    CheckSame(C.Bounds.Left, 45, 'horizontal middle gap mismatch');
    CheckSame(B.Bounds.Right, 130, 'horizontal last endpoint moved');
    History.Undo;
    ArrangeScreenLayoutSelection(Document, History, State,
      slaDistributeVertical);
    CheckSame(A.Bounds.Top, 0, 'vertical first endpoint moved');
    CheckSame(B.Bounds.Top, 35, 'vertical middle gap mismatch');
    CheckSame(C.Bounds.Bottom, 110, 'vertical last endpoint moved');
    History.Undo;

    Group := TScreenLayoutGroupLayer.Create('Group');
    GroupA := TVectArtRectangleLayer.Create('Group A',
      TRectF.Create(-40, -20, -20, 0), clRed);
    GroupB := TVectArtRectangleLayer.Create('Group B',
      TRectF.Create(10, 20, 40, 40), clBlue);
    Group.AddChild(GroupA);
    Group.AddChild(GroupB);
    Document.InsertLayer(4, Group);
    State.OpenGroupInDocument(Document, Group);
    State.SetOpenGroupChildren([GroupA, GroupB]);
    Check(CanArrangeScreenLayoutSelection(Document, State, slaAlignRight),
      'two open-group children were not alignable');
    Check(not CanArrangeScreenLayoutSelection(Document, State,
      slaDistributeHorizontal),
      'two open-group children enabled distribution');
    ArrangeScreenLayoutSelection(Document, History, State, slaAlignRight);
    CheckSame(GroupA.Bounds.Right, 40,
      'open-group child was not right-aligned');
    GroupB.Locked := True;
    Check(not CanArrangeScreenLayoutSelection(Document, State, slaAlignLeft),
      'locked open-group selection was enabled');
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

begin
  try
    Run;
    Writeln('ScreenLayoutLayerArrangementTest: OK');
  except
    on E: Exception do
    begin
      Writeln('ScreenLayoutLayerArrangementTest: FAILED: ', E.Message);
      Halt(1);
    end;
  end;
end.
