// AviUtl2フィルタープラグインの登録、映像コールバック、編集ボタンに必要な最小ABI型を定義する。
unit AviUtl2FilterTypes;

{$ALIGN 8}

interface

type
  LPCWSTR = PWideChar;
  OBJECT_HANDLE = Pointer;
  EFFECT_HANDLE = Pointer;

  PEDIT_INFO = ^TEDIT_INFO;
  TEDIT_INFO = record
    Width, Height, Rate, Scale, SampleRate: Integer;
    Frame, Layer, FrameMax, LayerMax: Integer;
    DisplayFrameStart, DisplayLayerStart, DisplayFrameNum, DisplayLayerNum: Integer;
    SelectRangeStart, SelectRangeEnd: Integer;
    GridBpmTempo: Single;
    GridBpmBeat: Integer;
    GridBpmOffset: Single;
    SceneID: Integer;
    Background: Cardinal;
  end;

  PEDIT_SECTION = ^TEDIT_SECTION;
  TFilterItemButtonCallback = procedure(Edit: PEDIT_SECTION); cdecl;
  TFILTER_ITEM_BUTTON_CALLBACK = TFilterItemButtonCallback;
  TFilterItemButtonCallback2 = procedure(Edit: PEDIT_SECTION;
    Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR); cdecl;
  TOBJECT_LAYER_FRAME = record
    Layer: Integer;
    StartFrame: Integer;
    EndFrame: Integer;
  end;
  TGetObjectLayerFrameFunc = function(
    Obj: OBJECT_HANDLE): TOBJECT_LAYER_FRAME; cdecl;
  TGetFocusObjectFunc = function: OBJECT_HANDLE; cdecl;
  TSetObjectItemValueFunc = function(Obj: OBJECT_HANDLE; Effect: LPCWSTR;
    Item: LPCWSTR; Value: PAnsiChar): LongBool; cdecl;
  TGetObjectItemValueFunc = function(Obj: OBJECT_HANDLE; Effect: LPCWSTR;
    Item: LPCWSTR): PAnsiChar; cdecl;

  // AviUtl2が編集ボタンへ渡す編集API。未使用欄もSDKのレコード配置を保つため保持する。
  TEDIT_SECTION = record
    Info: PEDIT_INFO;
    CreateObjectFromAlias: Pointer;
    FindObject: function(Layer, Frame: Integer): OBJECT_HANDLE; cdecl;
    CountObjectEffect: Pointer;
    GetObjectLayerFrame: TGetObjectLayerFrameFunc;
    GetObjectAlias: Pointer;
    GetObjectItemValue: TGetObjectItemValueFunc;
    SetObjectItemValue: TSetObjectItemValueFunc;
    MoveObject: Pointer;
    DeleteObject: Pointer;
    GetFocusObject: TGetFocusObjectFunc;
    SetFocusObject: Pointer;
    GetProjectFile: Pointer;
    GetSelectedObject: Pointer;
    GetSelectedObjectNum: Pointer;
    GetMouseLayerFrame: Pointer;
    PosToLayerFrame: Pointer;
    IsSupportMediaFile: Pointer;
    GetMediaInfo: Pointer;
    CreateObjectFromMediaFile: Pointer;
    CreateObject: Pointer;
    SetCursorLayerFrame: procedure(Layer, Frame: Integer); cdecl;
    SetDisplayLayerFrame: Pointer;
    SetSelectRange: Pointer;
    SetGridBpm: Pointer;
    GetObjectName: Pointer;
    SetObjectName: Pointer;
    // 使用しない関数ポインターも公式SDKと同じスロットに置く。
    LayerNameThroughDeprecatedSetBpm: array[27..49] of Pointer;
    FindEffect: function(Obj: OBJECT_HANDLE; Effect: LPCWSTR): EFFECT_HANDLE; cdecl;
    GetEffectListThroughSetEffectLock: array[51..56] of Pointer;
    GetEffectItemValue: function(Effect: EFFECT_HANDLE; Item: LPCWSTR): PAnsiChar; cdecl;
    SetEffectItemValue: function(Effect: EFFECT_HANDLE; Item: LPCWSTR;
      Value: PAnsiChar): Boolean; cdecl;
    GetEffectTrackValueThroughSetObjectFlag: array[59..80] of Pointer;
    GetObjectID: function(Obj: OBJECT_HANDLE): Int64; cdecl;
    GetEffectID: function(Effect: EFFECT_HANDLE): Int64; cdecl;
  end;

  PSCENE_INFO = ^TSCENE_INFO;
  TSCENE_INFO = record
    Width: Integer;
    Height: Integer;
    Rate: Integer;
    Scale: Integer;
    SampleRate: Integer;
    ID: Integer;          // 描画対象シーン。
    OriginID: Integer;    // 描画の起点となるシーン。
    Flag: Integer;        // 描画種別。参照フレームのときはビット0が立つ。
  end;

  POBJECT_INFO = ^TOBJECT_INFO;
  TOBJECT_INFO = record
    ID: Int64;
    Frame: Integer;
    FrameTotal: Integer;
    Time: Double;
    TimeTotal: Double;
    Width: Integer;
    Height: Integer;
    SampleIndex: Int64;
    SampleTotal: Int64;
    SampleNum: Integer;
    ChannelNum: Integer;
    EffectID: Int64;
    Flag: Integer;
    Layer: Integer;
    Index: Integer;
    Num: Integer;
    FrameS: Integer;
    FrameE: Integer;
    EffectLayer: Integer; // エフェクトを所有するオブジェクトのレイヤー。
    OriginFrame: Integer; // 描画を開始したシーン基準のフレーム。
  end;

  TPIXEL_RGBA = packed record
    R: Byte;
    G: Byte;
    B: Byte;
    A: Byte;
  end;
  PPIXEL_RGBA = ^TPIXEL_RGBA;

  TFILTER_PROC_VIDEO_GET_TEX2D = function: Pointer; cdecl;
  PFILTER_PROC_VIDEO = ^TFILTER_PROC_VIDEO;
  TFILTER_PROC_VIDEO = record
    Scene: PSCENE_INFO;
    Object_: POBJECT_INFO;
    GetImageData: procedure(Buffer: PPIXEL_RGBA); cdecl;
    SetImageData: procedure(Buffer: PPIXEL_RGBA;
      Width, Height: Integer); cdecl;
    GetImageTexture2D: TFILTER_PROC_VIDEO_GET_TEX2D;
    GetFramebufferTexture2D: TFILTER_PROC_VIDEO_GET_TEX2D;
  end;

  TFuncProcVideo = function(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
  TFuncProcAudio = function(Audio: Pointer): Byte; cdecl;

  TFILTER_ITEM_TRACK = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Double;
    S: Double;
    E: Double;
    Step: Double;
  end;

  TFILTER_ITEM_CHECK = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Byte;
  end;

  TFILTER_ITEM_COLOR = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    B: Byte;
    G: Byte;
    R: Byte;
    X: Byte;
  end;

  TFILTER_ITEM_SELECT_ITEM = record
    Name: LPCWSTR;
    Value: Integer;
  end;

  TFILTER_ITEM_SELECT = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Integer;
    List: ^TFILTER_ITEM_SELECT_ITEM;
  end;

  TFILTER_ITEM_FILE = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: LPCWSTR;
    FileFilter: LPCWSTR;
  end;

  TFILTER_ITEM_DATA = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Pointer;
    Size: Integer;
    DefaultValue: Pointer;
  end;

  TFILTER_ITEM_GROUP = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    DefaultVisible: Byte;
  end;

  // AviUtl2が1行のUnicode文字列として保持する設定項目。
  TFILTER_ITEM_STRING = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: LPCWSTR;
  end;

  TFILTER_ITEM_TEXT = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: LPCWSTR;
  end;

  // SDK順に旧コールバックと対象を特定できるコールバックを保持する。
  TFILTER_ITEM_BUTTON = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Callback: TFilterItemButtonCallback;
    Callback2: TFilterItemButtonCallback2;
  end;

  PFILTER_PLUGIN_TABLE = ^TFILTER_PLUGIN_TABLE;
  TFILTER_PLUGIN_TABLE = record
    Flag: Integer;
    Name: LPCWSTR;
    Label_: LPCWSTR;
    Information: LPCWSTR;
    Items: ^Pointer;
    Func_Proc_Video: TFuncProcVideo;
    Func_Proc_Audio: TFuncProcAudio;
    Func_Create: Pointer;  // ユーザーデータ未使用のためnil。
    Func_Destroy: Pointer; // ユーザーデータ未使用のためnil。
  end;

  TEditSectionParamCallback = procedure(Param: Pointer; Edit: PEDIT_SECTION); cdecl;
  PEDIT_HANDLE = ^TEDIT_HANDLE;
  TEDIT_HANDLE = record
    CallEditSection: Pointer;
    CallEditSectionParam: function(Param: Pointer; Callback: TEditSectionParamCallback): Boolean; cdecl;
    GetEditInfoThroughEnumModuleInfo: array[2..5] of Pointer;
    GetHostAppWindow: Pointer;
    GetEditState: function: Integer; cdecl;
  end;

  PHOST_APP_TABLE = ^THOST_APP_TABLE;
  THOST_APP_TABLE = record
    SetPluginInformation, RegisterInputPlugin, RegisterOutputPlugin: Pointer;
    RegisterFilterPlugin: procedure(Table: PFILTER_PLUGIN_TABLE); cdecl;
    RegisterScriptModuleThroughRegisterWindowClient: array[4..7] of Pointer;
    CreateEditHandle: function: PEDIT_HANDLE; cdecl;
  end;

const
  AVIUTL2_EDIT_STATE_EDIT = 0;
  SCENE_FLAG_REFERENCE_FRAME = 1;
  FILTER_FLAG_VIDEO = 1;
  FILTER_FLAG_FILTER = 8;

implementation

end.
