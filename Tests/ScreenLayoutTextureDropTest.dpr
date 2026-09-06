// Windows形式のファイルD&Dを属性Controllerへ接続し、適用範囲とUndoを検証する。
program ScreenLayoutTextureDropTest;
{$APPTYPE CONSOLE}
uses
  System.Classes, System.SysUtils, System.Types, System.Win.ComObj, System.IOUtils,
  Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage,
  ScreenLayoutDocument, ScreenLayoutContext, ScreenLayoutEditorState, ScreenLayoutEditHistory,
  ScreenLayoutPaintStyles, ScreenLayoutColorPickerFrame, ScreenLayoutObjectColorController,
  ScreenLayoutTextureDropTarget, ScreenLayoutTextureControl, TextRendererSkiaRuntime;

procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;

function DropData(const FileNames: string): IDataObject;
var
  Format: TFormatEtc;
  Medium: TStgMedium;
  Header: PDropFiles;
  Names: string;
begin
  Result := nil;
  OleCheck(SHCreateDataObject(nil, 0, nil, nil, IDataObject, Pointer(Result)));
  Names := FileNames + #0#0;
  Medium := Default(TStgMedium);
  Medium.tymed := TYMED_HGLOBAL;
  Medium.hGlobal := GlobalAlloc(GHND, SizeOf(TDropFiles) + Length(Names)*SizeOf(Char));
  Header := GlobalLock(Medium.hGlobal);
  Header.pFiles := SizeOf(TDropFiles);
  Header.fWide := True;
  Move(Names[1], (PByte(Header) + SizeOf(TDropFiles))^, Length(Names)*SizeOf(Char));
  GlobalUnlock(Medium.hGlobal);
  Format := Default(TFormatEtc);
  Format.cfFormat := CF_HDROP;
  Format.dwAspect := DVASPECT_CONTENT;
  Format.lindex := -1;
  Format.tymed := TYMED_HGLOBAL;
  try
    OleCheck(Result.SetData(Format, Medium, True));
    Medium.tymed := TYMED_NULL;
  finally
    ReleaseStgMedium(Medium);
  end;
end;

procedure Run;
var
  Doc: TVectArtDocument;
  State: TVectArtEditorState;
  History: TVectArtEditHistory;
  Context: IVectArtDesignerContext;
  Frame: TScreenLayoutColorPickerFrame;
  Controller: TScreenLayoutObjectColorController;
  Control: TScreenLayoutTextureControl;
  Target: IDropTarget;
  Data: IDataObject;
  Effect: Longint;
  I: Integer;
  FileName: string;
  Bitmap: TBitmap;
  Png: TPngImage;
begin
  Doc := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Frame := TScreenLayoutColorPickerFrame.Create(nil);
  Controller := TScreenLayoutObjectColorController.Create(Frame);
  try
    Doc.SetCanvasSize(200, 200);
    Doc.InsertLayer(1, TVectArtRectangleLayer.Create('A', TRectF.Create(-80, -80, 0, 0), clRed));
    Doc.InsertLayer(2, TVectArtRectangleLayer.Create('B', TRectF.Create(0, 0, 80, 80), clBlue));
    Doc.SetSelectedLayers([1, 2]);
    State.CurrentTool := vetSelect;
    Context := TVectArtDesignerContext.Create(Doc, History, State);
    Controller.SetContext(Context);
    Frame.SelectPaintKind(slpkTexture);
    Control := nil;
    for I := 0 to Frame.ComponentCount - 1 do
      if Frame.Components[I] is TScreenLayoutTextureControl then
        Control := TScreenLayoutTextureControl(Frame.Components[I]);
    Check(Control <> nil, 'missing drop control');
    FileName := ExtractFilePath(ParamStr(0)) + 'drop-fixture.png';
    Bitmap := TBitmap.Create;
    Png := TPngImage.Create;
    try
      Bitmap.SetSize(8, 4);
      Bitmap.Canvas.Brush.Color := clFuchsia;
      Bitmap.Canvas.FillRect(Rect(0, 0, 8, 4));
      Png.Assign(Bitmap);
      Png.SaveToFile(FileName);
    finally
      Png.Free;
      Bitmap.Free;
    end;
    Target := TScreenLayoutTextureDropTarget.Create(
      function(const Point: TPoint; Hover: Boolean): Boolean
      begin
        Result := Rect(0, 0, 160, 82).Contains(Point);
      end,
      function(const FileName: string): Boolean
      begin
        Result := Control.LoadFile(FileName);
      end);
    Data := DropData(FileName);
    Effect := DROPEFFECT_COPY;
    Target.DragEnter(Data, 0, Point(10, 10), Effect);
    Check(Effect = DROPEFFECT_COPY, 'valid file rejected');
    Effect := DROPEFFECT_COPY;
    Target.DragOver(0, Point(10, 90), Effect);
    Check(Effect = DROPEFFECT_NONE, 'outside the drop region accepted');
    Effect := DROPEFFECT_COPY;
    Target.Drop(Data, 0, Point(10, 10), Effect);
    Check((Effect = DROPEFFECT_COPY) and (Doc[1].PaintStyle.Texture.Data <> '') and
      (Doc[1].PaintStyle.Texture.Data = Doc[2].PaintStyle.Texture.Data), 'drop did not apply to selection');
    History.Undo;
    Check((Doc[1].PaintStyle.Texture.Data = '') and (Doc[2].PaintStyle.Texture.Data = ''),
      'multi-selection drop was not a single undo');
    History.Redo;
    TFile.Delete(FileName);
    Check(Doc[1].PaintStyle.Texture.Data <> '', 'texture depends on source file');
    Data := DropData('a.png' + #0 + 'b.png');
    Effect := DROPEFFECT_COPY;
    Target.DragEnter(Data, 0, Point(10, 10), Effect);
    Check(Effect = DROPEFFECT_NONE, 'multiple files accepted as one texture');
    Target.DragLeave;
    Data := DropData(FileName);
    Effect := DROPEFFECT_COPY;
    Target.Drop(Data, 0, Point(10, 10), Effect);
    Check((Effect = DROPEFFECT_NONE) and (Doc[1].PaintStyle.Texture.Data <> ''),
      'failed drop reported success or lost image');
    Doc.SetSelectedLayers([]);
    Controller.Refresh;
    Check(State.CreationPaintStyle.Texture.Data <> '', 'creation default lost image');
  finally
    Data := nil;
    Target := nil;
    Controller.Free;
    Frame.Free;
    Context := nil;
    History.Free;
    State.Free;
    Doc.Free;
  end;
end;

begin
  try
    OleCheck(OleInitialize(nil));
    TTextRendererSkiaRuntime.Acquire(ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      Run;
    finally
      TTextRendererSkiaRuntime.Release;
      OleUninitialize;
    end;
    Writeln('PASS texture OLE drop, multi-selection undo, source independence and creation default');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
