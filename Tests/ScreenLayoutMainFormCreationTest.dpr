program ScreenLayoutMainFormCreationTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Vcl.Forms,
  ScreenLayoutMainForm in '..\Source\Shell\ScreenLayoutMainForm.pas';

type
  TExceptionObserver = class
  public
    procedure HandleException(Sender: TObject; E: Exception);
  end;

procedure TExceptionObserver.HandleException(Sender: TObject; E: Exception);
begin
  Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
  Flush(Output);
  Halt(1);
end;

var
  ExceptionObserver: TExceptionObserver;
  Form: TMainForm;

begin
  Application.Initialize;
  ExceptionObserver := TExceptionObserver.Create;
  Application.OnException := ExceptionObserver.HandleException;
  Form := nil;
  try
    try
      Form := TMainForm.Create(nil);
      Writeln('CREATED');
      Flush(Output);
      Form.Free;
      Form := nil;
      Writeln('PASS');
      Flush(Output);
    except
      on E: Exception do
      begin
        Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
        Halt(1);
      end;
    end;
  finally
    Form.Free;
    Application.OnException := nil;
    ExceptionObserver.Free;
  end;
end.
