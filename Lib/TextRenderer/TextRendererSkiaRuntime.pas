// Skia APIの動的結合とプロセス内参照カウントを管理する。
unit TextRendererSkiaRuntime;

interface

type
  TTextRendererSkiaRuntime = class sealed
  public
    // 指定DLLを初期化する。同じパスへの複数取得は参照数として保持する。
    class procedure Acquire(const ALibraryFileName: string); static;
    // この管理クラスを通してSkiaが取得済みならTrueを返す。
    class function IsAcquired: Boolean; static;
    // 参照数を減らし、最後の利用者が解放した時点でSkiaを終了する。
    class procedure Release; static;
  end;

implementation

uses
  TextRendererSkiaBootstrap,
  System.Skia,
  System.Skia.API,
  System.SysUtils,
  Winapi.Windows;

var
  RuntimeFileName: string;
  RuntimeLibraryHandle: HMODULE;
  RuntimeLock: TRTLCriticalSection;
  RuntimeReferenceCount: Integer;

class procedure TTextRendererSkiaRuntime.Acquire(const ALibraryFileName: string);
var
  ExpandedFileName: string;
  ErrorCode: DWORD;
  ErrorHint: string;
  Stage: string;
  FailureMessage: string;
begin
  ExpandedFileName := ExpandFileName(ALibraryFileName);
  EnterCriticalSection(RuntimeLock);
  try
    if RuntimeReferenceCount > 0 then
    begin
      if not SameText(RuntimeFileName, ExpandedFileName) then
        raise EInvalidOp.CreateFmt(
          'Skia runtime is already loaded from a different path: %s',
          [RuntimeFileName]);
      Inc(RuntimeReferenceCount);
      Exit;
    end;

    RuntimeLibraryHandle := LoadLibrary(PChar(ExpandedFileName));
    if RuntimeLibraryHandle = 0 then
    begin
      ErrorCode := GetLastError;
      case ErrorCode of
        ERROR_MOD_NOT_FOUND:
          ErrorHint := 'sk4d.dll または依存DLLが見つかりません。配布ファイルが揃っているか確認してください。';
        ERROR_BAD_EXE_FORMAT:
          ErrorHint := 'DLLの形式が適合しません。Win64版のsk4d.dllか、ファイルが破損していないか確認してください。';
        ERROR_DLL_INIT_FAILED:
          ErrorHint := 'DLLまたは依存DLLの内部初期化に失敗しました。このコードだけでは原因を特定できません。';
        ERROR_ACCESS_DENIED:
          ErrorHint := 'DLLへのアクセスが拒否されました。アクセス権やセキュリティソフトの履歴を確認してください。';
      else
        ErrorHint := '以下の診断情報を開発者へお知らせください。';
      end;
      raise EOSError.CreateFmt(
        'Skiaランタイムの読み込みに失敗しました。'#13#10 +
        '段階: LoadLibrary'#13#10 + '対象: %s'#13#10 +
        'Windowsエラー: %d (0x%.8x)'#13#10 + '%s'#13#10#13#10 + '%s',
        [ExpandedFileName, ErrorCode, ErrorCode, SysErrorMessage(ErrorCode), ErrorHint]);
    end;
    Stage := 'SkInitialize（Skia APIの接続）';
    try
      // Delphi 37 does not initialize the dynamically bound Skia API from the
      // System.Skia.API unit initialization section. Bind its entry points
      // before TSkGraphics calls sk4d_graphics_init.
      SkInitialize;
      Stage := 'TSkGraphics.Init（描画エンジンの初期化）';
      TSkGraphics.Init;
      RuntimeFileName := ExpandedFileName;
      RuntimeReferenceCount := 1;
    except
      on E: Exception do
      begin
        FailureMessage := Format('Skiaの初期化に失敗しました。'#13#10 +
          '段階: %s'#13#10 + '対象: %s'#13#10 + '例外: %s'#13#10 + '%s',
          [Stage, ExpandedFileName, E.ClassName, E.Message]);
        try
          SkFinalize;
        except
          // 後始末の例外で最初の失敗情報を上書きしない。
        end;
        FreeLibrary(RuntimeLibraryHandle);
        RuntimeLibraryHandle := 0;
        raise EInvalidOp.Create(FailureMessage);
      end;
    end;
  finally
    LeaveCriticalSection(RuntimeLock);
  end;
end;

class function TTextRendererSkiaRuntime.IsAcquired: Boolean;
begin
  EnterCriticalSection(RuntimeLock);
  try
    Result := RuntimeReferenceCount > 0;
  finally
    LeaveCriticalSection(RuntimeLock);
  end;
end;

class procedure TTextRendererSkiaRuntime.Release;
begin
  EnterCriticalSection(RuntimeLock);
  try
    if RuntimeReferenceCount = 0 then
      Exit;
    Dec(RuntimeReferenceCount);
    if RuntimeReferenceCount > 0 then
      Exit;

    try
      TSkGraphics.PurgeAllCaches;
    finally
      SkFinalize;
      FreeLibrary(RuntimeLibraryHandle);
      RuntimeLibraryHandle := 0;
      RuntimeFileName := '';
    end;
  finally
    LeaveCriticalSection(RuntimeLock);
  end;
end;

initialization
  InitializeCriticalSection(RuntimeLock);

finalization
  // DLLのローダーロック中にSkiaの終了やFreeLibraryを実行しない。
  // 利用者が公開終了関数またはフォーム破棄からReleaseする。
  DeleteCriticalSection(RuntimeLock);

end.
