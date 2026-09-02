// 編集対象となる用紙とオブジェクトレイヤーを一元管理する。
// レイヤー配列の先頭を最背面、末尾を最前面とする。
unit ScreenLayoutDocument;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  Vcl.Graphics;

type
  TVectArtLayerKind = (vlkCanvas, vlkRectangle, vlkRoundedRectangle,
    vlkPath, vlkImage, vlkShape, vlkEllipse, vlkArc, vlkRectangleLine,
    vlkRoundedRectangleLine, vlkEllipseLine, vlkEllipseArcShape, vlkText,
    vlkGroup);
  TVectArtImageSourceKind = (visImage, visLogo);
  TVectArtImagePoints = array[0..3] of TPointF;
  // WebArt Designerの線種コンボとMIF vector stroke style 0..8を同順で保持する。
  TVectArtMifStrokeStyle = (vssSolid, vssDotted, vssShortDash, vssDashDot,
    vssDashDotDot, vssSparseDotted, vssMediumDash, vssLongDashDot,
    vssLongDash);
  // 線端を四角、丸、先端角90度の三角から選ぶ。
  TVectArtLineCap = (vlcSquare, vlcRound, vlcTriangle);
  // 各頂点から次頂点へ向かう閉輪郭区間の表現形式。
  TScreenLayoutSegmentKind = (slskLine, slskCubicBezier);
  // Shape編集時にユーザーが選ぶ頂点の接続形式。
  TScreenLayoutVertexKind = (slvkSharp, slvkBezier);
  // 穴や重複輪郭を含むShapeの内外判定規則。
  TScreenLayoutFillRule = (slfrEvenOdd, slfrNonZero);

  TScreenLayoutVertex = record
    Position: TPointF;              // 頂点のドキュメント座標。
    IncomingControl: TPointF;       // 頂点から入力側制御点への相対座標。
    OutgoingControl: TPointF;       // 頂点から出力側制御点への相対座標。
    OutgoingSegment: TScreenLayoutSegmentKind; // 次頂点までの区間種別。
    Kind: TScreenLayoutVertexKind;  // 鋭角または滑らかなベジェ接続。
  end;

  TScreenLayoutContour = record
    Vertices: TArray<TScreenLayoutVertex>; // 終端から先頭へ閉じる頂点列。
    // 閉輪郭の区間数を返す。終端から先頭への区間も1本に数える。
    function SegmentCount: Integer;
  end;
  TVectArtLayer = class
  private
    FKind: TVectArtLayerKind;
    FLocked: Boolean;
    FName: string;
    FOpacity: Single;
    FVisible: Boolean;
  protected
    constructor Create(AKind: TVectArtLayerKind; const AName: string);
  public
    property Kind: TVectArtLayerKind read FKind;
    property Locked: Boolean read FLocked write FLocked;
    property Name: string read FName write FName;
    property Opacity: Single read FOpacity write FOpacity;
    property Visible: Boolean read FVisible write FVisible;
  end;

  // 複数レイヤーを積層順のまま所有する。子の座標はDocument座標のまま保持する。
  TScreenLayoutGroupLayer = class(TVectArtLayer)
  private
    FChildren: TObjectList<TVectArtLayer>;
    function GetChild(Index: Integer): TVectArtLayer;
    function GetChildCount: Integer;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    procedure AddChild(Layer: TVectArtLayer);
    function ExtractChild(Index: Integer): TVectArtLayer;
    procedure InsertChild(Index: Integer; Layer: TVectArtLayer);
    property ChildCount: Integer read GetChildCount;
    property Children[Index: Integer]: TVectArtLayer read GetChild; default;
  end;

  TVectArtCanvasLayer = class(TVectArtLayer)
  private
    FBackgroundColor: TColor;
    FHeight: Integer;
    FTransparent: Boolean;
    FWidth: Integer;
  public
    constructor Create(AWidth, AHeight: Integer; AColor: TColor);
    property BackgroundColor: TColor read FBackgroundColor
      write FBackgroundColor;
    property Height: Integer read FHeight write FHeight;
    property Transparent: Boolean read FTransparent write FTransparent;
    property Width: Integer read FWidth write FWidth;
  end;

  TVectArtRectangleLayer = class(TVectArtLayer)
  private
    FBounds: TRectF;
    FFillColor: TColor;
    FRotationDegrees: Single;
  protected
    constructor CreateWithKind(AKind: TVectArtLayerKind;
      const AName: string; const ABounds: TRectF; AFillColor: TColor);
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor);
    property Bounds: TRectF read FBounds write FBounds;
    property FillColor: TColor read FFillColor write FFillColor;
    property RotationDegrees: Single read FRotationDegrees
      write FRotationDegrees;
  end;

  TVectArtRectangleData = record
    Bounds: TRectF;                         // 回転前の基本矩形。
    FillColor: TColor;                      // 内部の塗り色。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single;                // 中心回りの時計回り角度。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TScreenLayoutCornerRadii = record
    TopLeft: Single;     // 左上隅の円弧半径。
    TopRight: Single;    // 右上隅の円弧半径。
    BottomRight: Single; // 右下隅の円弧半径。
    BottomLeft: Single;  // 左下隅の円弧半径。
  end;

  TScreenLayoutRoundedRectangleLayer = class(TVectArtRectangleLayer)
  private
    FCornerRadii: TScreenLayoutCornerRadii;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor; const ACornerRadii: TScreenLayoutCornerRadii);
    property CornerRadii: TScreenLayoutCornerRadii read FCornerRadii
      write FCornerRadii;
  end;

  TScreenLayoutRoundedRectangleData = record
    Bounds: TRectF;                         // 回転前の基本矩形。
    CornerRadii: TScreenLayoutCornerRadii; // 左上から時計回りの角丸半径。
    FillColor: TColor;                      // 内部の塗り色。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single;                // 中心回りの時計回り角度。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TScreenLayoutEllipseLayer = class(TVectArtRectangleLayer)
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor);
  end;

  TScreenLayoutEllipseData = record
    Bounds: TRectF;          // 回転前の楕円へ外接する基本矩形。
    FillColor: TColor;       // 楕円内部の塗り色。
    Locked: Boolean;         // 編集を禁止する状態。
    Name: string;            // レイヤー一覧の表示名。
    Opacity: Single;         // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single; // 楕円中心回りの時計回り角度。
    Visible: Boolean;        // 描画対象に含める状態。
  end;

  TScreenLayoutTextLayer = class(TVectArtRectangleLayer)
  private
    FFontFamily: string;
    FFontSize: Single;
    FText: string;
    FWrapWidth: Single;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      const AText, AFontFamily: string; AFontSize, AWrapWidth: Single;
      ATextColor: TColor);
    property FontFamily: string read FFontFamily write FFontFamily;
    property FontSize: Single read FFontSize write FFontSize;
    property Text: string read FText write FText;
    property WrapWidth: Single read FWrapWidth write FWrapWidth;
  end;

  TScreenLayoutTextData = record
    Bounds: TRectF;          // 文字の組版実寸または変形後の表示範囲。
    FontFamily: string;      // Skiaへ渡す優先フォントファミリー。
    FontSize: Single;        // 変形前の文書座標単位フォントサイズ。
    Locked: Boolean;         // 編集を禁止する状態。
    Name: string;            // レイヤー一覧の表示名。
    Opacity: Single;         // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single; // 中心回りの時計回り角度。
    Text: string;            // 明示改行を含むUnicode文字列。
    TextColor: TColor;       // 本文色。基底のFillColorと同じ値を保持する。
    Visible: Boolean;        // 描画対象に含める状態。
    WrapWidth: Single;       // 入力時の自動折り返し幅。
  end;

  TScreenLayoutRectangleLineLayer = class(TVectArtLayer)
  private
    FBounds: TRectF;
    FRotationDegrees: Single;
    FStrokeColor: TColor;
    FStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
  protected
    constructor CreateWithKind(AKind: TVectArtLayerKind;
      const AName: string; const ABounds: TRectF);
  public
    constructor Create(const AName: string; const ABounds: TRectF);
    property Bounds: TRectF read FBounds write FBounds;
    property RotationDegrees: Single read FRotationDegrees write FRotationDegrees;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property StrokeStyle: TVectArtMifStrokeStyle read FStrokeStyle write FStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
  end;

  TScreenLayoutRectangleLineData = record
    Bounds: TRectF;          // 回転前の四角線へ外接する基本矩形。
    Locked: Boolean;         // 編集を禁止する状態。
    Name: string;            // レイヤー一覧の表示名。
    Opacity: Single;         // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single; // 中心回りの時計回り角度。
    StrokeColor: TColor;     // 四辺へ適用する線色。
    StrokeStyle: TVectArtMifStrokeStyle; // 四辺へ適用する線パターン。
    StrokeWidth: Single;     // 四辺へ適用する線幅。
    Visible: Boolean;        // 描画対象に含める状態。
  end;

  TScreenLayoutRoundedRectangleLineLayer = class(
    TScreenLayoutRectangleLineLayer)
  private
    FCornerRadii: TScreenLayoutCornerRadii;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      const ACornerRadii: TScreenLayoutCornerRadii);
    property CornerRadii: TScreenLayoutCornerRadii read FCornerRadii
      write FCornerRadii;
  end;

  TScreenLayoutRoundedRectangleLineData = record
    Bounds: TRectF;
    CornerRadii: TScreenLayoutCornerRadii;
    Locked: Boolean;
    Name: string;
    Opacity: Single;
    RotationDegrees: Single;
    StrokeColor: TColor;
    StrokeStyle: TVectArtMifStrokeStyle;
    StrokeWidth: Single;
    Visible: Boolean;
  end;

  TScreenLayoutEllipseLineLayer = class(TScreenLayoutRectangleLineLayer)
  public
    constructor Create(const AName: string; const ABounds: TRectF);
  end;

  TScreenLayoutEllipseLineData = record
    Bounds: TRectF;
    Locked: Boolean;
    Name: string;
    Opacity: Single;
    RotationDegrees: Single;
    StrokeColor: TColor;
    StrokeStyle: TVectArtMifStrokeStyle;
    StrokeWidth: Single;
    Visible: Boolean;
  end;

  TScreenLayoutArcLayer = class(TVectArtLayer)
  private
    FBounds: TRectF;
    FLineCap: TVectArtLineCap;
    FRotationDegrees: Single;
    FStartAngleDegrees: Single;
    FStrokeColor: TColor;
    FStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
    FSweepAngleDegrees: Single;
  public
    constructor Create(const AName: string; const ABounds: TRectF);
    property Bounds: TRectF read FBounds write FBounds;
    property LineCap: TVectArtLineCap read FLineCap write FLineCap;
    property RotationDegrees: Single read FRotationDegrees write FRotationDegrees;
    property StartAngleDegrees: Single read FStartAngleDegrees write FStartAngleDegrees;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property StrokeStyle: TVectArtMifStrokeStyle read FStrokeStyle write FStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
    property SweepAngleDegrees: Single read FSweepAngleDegrees write FSweepAngleDegrees;
  end;

  TScreenLayoutArcData = record
    Bounds: TRectF;            // 回転前の基礎楕円へ外接する基本矩形。
    LineCap: TVectArtLineCap;  // 開いた円弧の両端形状。
    Locked: Boolean;           // 編集を禁止する状態。
    Name: string;              // レイヤー一覧の表示名。
    Opacity: Single;           // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single;   // 基礎楕円中心回りの時計回り角度。
    StartAngleDegrees: Single; // 基礎楕円の右向きを0度とする開始角。
    StrokeColor: TColor;       // 円弧の線色。
    StrokeStyle: TVectArtMifStrokeStyle; // 円弧の線パターン。
    StrokeWidth: Single;       // 円弧の線幅。
    SweepAngleDegrees: Single; // 開始角から時計回りへ進む角度。
    Visible: Boolean;          // 描画対象に含める状態。
  end;

  TScreenLayoutEllipseArcShapeLayer = class(TVectArtRectangleLayer)
  private
    FStartAngleDegrees: Single;
    FSweepAngleDegrees: Single;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor);
    property StartAngleDegrees: Single read FStartAngleDegrees
      write FStartAngleDegrees;
    property SweepAngleDegrees: Single read FSweepAngleDegrees
      write FSweepAngleDegrees;
  end;

  TScreenLayoutEllipseArcShapeData = record
    Bounds: TRectF;
    FillColor: TColor;
    Locked: Boolean;
    Name: string;
    Opacity: Single;
    RotationDegrees: Single;
    StartAngleDegrees: Single;
    SweepAngleDegrees: Single;
    Visible: Boolean;
  end;

  TVectArtPathLayer = class(TVectArtLayer)
  private
    FClosed: Boolean;
    FLineCap: TVectArtLineCap;
    FStrokeColor: TColor;
    FMifStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
    FVertices: TArray<TScreenLayoutVertex>;
    function GetVertices: TArray<TScreenLayoutVertex>;
    procedure SetVertices(const Value: TArray<TScreenLayoutVertex>);
  public
    constructor Create(const AName: string;
      const AVertices: TArray<TScreenLayoutVertex>; AClosed: Boolean);
    property Closed: Boolean read FClosed write FClosed;
    property LineCap: TVectArtLineCap read FLineCap write FLineCap;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property MifStrokeStyle: TVectArtMifStrokeStyle read FMifStrokeStyle
      write FMifStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
    property Vertices: TArray<TScreenLayoutVertex> read GetVertices
      write SetVertices;
  end;

  TVectArtPathData = record
    Closed: Boolean;                        // 終点と始点を閉じる状態。
    LineCap: TVectArtLineCap;               // 開いたPathの線端形状。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    StrokeColor: TColor;                    // 開いたPathの線色。
    MifStrokeStyle: TVectArtMifStrokeStyle; // 開いたPathの線パターン。
    StrokeWidth: Single;                    // 開いたPathの線幅。
    Vertices: TArray<TScreenLayoutVertex>;  // 開いたPathを構成するアンカーと区間情報。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TScreenLayoutShapeLayer = class(TVectArtLayer)
  private
    FContours: TArray<TScreenLayoutContour>;
    FFillColor: TColor;
    FFillRule: TScreenLayoutFillRule;
    FStrokeColor: TColor;
    FStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
    function GetContourCount: Integer;
    function GetContours: TArray<TScreenLayoutContour>;
    procedure SetContours(const Value: TArray<TScreenLayoutContour>);
  public
    constructor Create(const AName: string;
      const AContours: TArray<TScreenLayoutContour>);
    property Contours: TArray<TScreenLayoutContour> read GetContours
      write SetContours;
    property ContourCount: Integer read GetContourCount;
    property FillColor: TColor read FFillColor write FFillColor;
    property FillRule: TScreenLayoutFillRule read FFillRule write FFillRule;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property StrokeStyle: TVectArtMifStrokeStyle read FStrokeStyle
      write FStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
  end;

  TScreenLayoutShapeData = record
    Contours: TArray<TScreenLayoutContour>; // 外周、穴、分離領域を含む閉輪郭群。
    FillColor: TColor;                      // Even-Odd等の規則で塗る色。
    FillRule: TScreenLayoutFillRule;        // 複数輪郭の内外判定規則。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    StrokeColor: TColor;                    // 全輪郭へ適用する縁取り色。
    StrokeStyle: TVectArtMifStrokeStyle;    // 全輪郭へ適用する線パターン。
    StrokeWidth: Single;                    // 0の場合は縁取りなし。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TVectArtImageLayer = class(TVectArtLayer)
  private
    FPngData: TBytes;
    FPoints: TVectArtImagePoints;
    FSourceFileName: string;
    FSourceKind: TVectArtImageSourceKind;
  public
    constructor Create(const AName: string; const APngData: TBytes;
      const APoints: TVectArtImagePoints; ASourceKind: TVectArtImageSourceKind;
      const ASourceFileName: string = '');
    property PngData: TBytes read FPngData;
    property Points: TVectArtImagePoints read FPoints write FPoints;
    property SourceFileName: string read FSourceFileName;
    property SourceKind: TVectArtImageSourceKind read FSourceKind;
  end;

  TVectArtImageData = record
    Locked: Boolean;                     // 編集を禁止する状態。
    Name: string;                        // レイヤー一覧の表示名。
    Opacity: Single;                     // 0.0..1.0のレイヤー不透明度。
    PngData: TBytes;                     // Skiaが読める符号化画像の全バイト。名称は旧形式互換。
    Points: TVectArtImagePoints;         // 左上から時計回りの配置4頂点。
    SourceFileName: string;              // JSONから参照する画像ファイルパス。
    SourceKind: TVectArtImageSourceKind; // MIF由来のimage／logo区分。
    Visible: Boolean;                    // 描画対象に含める状態。
  end;

  TVectArtDocument = class
  private
    FLayers: TObjectList<TVectArtLayer>;
    FChangePending: Boolean;
    FInteractiveChanged: Boolean;
    FInteractiveUpdateCount: Integer;
    FOnChanged: TNotifyEvent;
    FRevision: Int64;
    FSelectedIndex: Integer;
    FSelectedLayers: TList<Integer>;
    FUpdateCount: Integer;
    function GetCanvasLayer: TVectArtCanvasLayer;
    function GetLayer(Index: Integer): TVectArtLayer;
    function GetLayerCount: Integer;
    function GetIsInteractiveUpdate: Boolean;
    function GetSelectionCount: Integer;
    procedure SelectionChanged;
    procedure SetSelectedLayersCore(const Indices: array of Integer;
      Notify: Boolean);
    procedure SetSelectedIndex(const Value: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginInteractiveUpdate;
    procedure BeginUpdate;
    procedure Changed;
    procedure EndInteractiveUpdate;
    procedure EndUpdate;
    function GetSelectedLayerIndices: TArray<Integer>;
    // 所有権を呼び出し側へ移し、レイヤーデータを破棄せずDocumentから取り外す。
    function ExtractLayer(Index: Integer): TVectArtLayer;
    // 呼び出し側から所有権を受け取り、既存レイヤーを指定積層位置へ挿入する。
    function InsertLayer(Index: Integer; Layer: TVectArtLayer): Integer;
    function InsertRectangle(Index: Integer;
      const Data: TVectArtRectangleData): Integer;
    // 角丸半径と回転を含む角丸四角を指定位置へ挿入し、実際のレイヤー番号を返す。
    function InsertRoundedRectangle(Index: Integer;
      const Data: TScreenLayoutRoundedRectangleData): Integer;
    // 塗りと回転を持つ楕円を指定位置へ挿入し、実際のレイヤー番号を返す。
    function InsertEllipse(Index: Integer;
      const Data: TScreenLayoutEllipseData): Integer;
    function InsertRectangleLine(Index: Integer;
      const Data: TScreenLayoutRectangleLineData): Integer;
    function InsertRoundedRectangleLine(Index: Integer;
      const Data: TScreenLayoutRoundedRectangleLineData): Integer;
    function InsertEllipseLine(Index: Integer;
      const Data: TScreenLayoutEllipseLineData): Integer;
    // 基礎楕円と角度、線属性を持つ円弧を指定位置へ挿入する。
    function InsertArc(Index: Integer;
      const Data: TScreenLayoutArcData): Integer;
    function InsertEllipseArcShape(Index: Integer;
      const Data: TScreenLayoutEllipseArcShapeData): Integer;
    function InsertPath(Index: Integer; const Data: TVectArtPathData): Integer;
    // 複数の閉輪郭を持つShapeを指定位置へ挿入し、実際のレイヤー番号を返す。
    function InsertShape(Index: Integer;
      const Data: TScreenLayoutShapeData): Integer;
    function InsertImage(Index: Integer; const Data: TVectArtImageData): Integer;
    function InsertText(Index: Integer; const Data: TScreenLayoutTextData): Integer;
    function IsLayerSelected(Index: Integer): Boolean;
    procedure SetCanvasSize(AWidth, AHeight: Integer);
    procedure SetRectangleBounds(Index: Integer; const Value: TRectF);
    procedure SetRectangleFillColor(Index: Integer; Value: TColor);
    procedure SetRectangleRotation(Index: Integer; Value: Single);
    procedure SetRectangleLineBounds(Index: Integer; const Value: TRectF);
    procedure SetRectangleLineRotation(Index: Integer; Value: Single);
    procedure SetRectangleLineStroke(Index: Integer; Color: TColor;
      Width: Single; Style: TVectArtMifStrokeStyle);
    procedure SetRoundedRectangleLineCornerRadii(Index: Integer;
      const Value: TScreenLayoutCornerRadii);
    procedure SetArcBounds(Index: Integer; const Value: TRectF);
    procedure SetArcAngles(Index: Integer; StartAngleDegrees,
      SweepAngleDegrees: Single);
    procedure SetArcLineCap(Index: Integer; Value: TVectArtLineCap);
    procedure SetArcRotation(Index: Integer; Value: Single);
    procedure SetArcStroke(Index: Integer; Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
    procedure SetEllipseArcShapeAngles(Index: Integer; StartAngleDegrees,
      SweepAngleDegrees: Single);
    // 角丸四角の各隅半径を辺内へ収まる値に制限して更新する。
    procedure SetRoundedRectangleCornerRadii(Index: Integer;
      const Value: TScreenLayoutCornerRadii);
    procedure SetImagePoints(Index: Integer;
      const Points: TVectArtImagePoints);
    procedure SetTextData(Index: Integer; const Data: TScreenLayoutTextData);
    procedure SetPathLineCap(Index: Integer; Value: TVectArtLineCap);
    procedure SetLayerLocked(Index: Integer; Value: Boolean);
    procedure SetLayerOpacity(Index: Integer; Value: Single);
    procedure SetLayerVisible(Index: Integer; Value: Boolean);
    procedure MoveLayer(FromIndex, ToIndex: Integer);
    function RemoveRectangle(Index: Integer;
      out Data: TVectArtRectangleData): Boolean;
    // 角丸四角を削除し、Undoで型と全属性を復元できるデータを返す。
    function RemoveRoundedRectangle(Index: Integer;
      out Data: TScreenLayoutRoundedRectangleData): Boolean;
    function RemoveEllipse(Index: Integer;
      out Data: TScreenLayoutEllipseData): Boolean;
    function RemoveRectangleLine(Index: Integer;
      out Data: TScreenLayoutRectangleLineData): Boolean;
    function RemoveRoundedRectangleLine(Index: Integer;
      out Data: TScreenLayoutRoundedRectangleLineData): Boolean;
    function RemoveEllipseLine(Index: Integer;
      out Data: TScreenLayoutEllipseLineData): Boolean;
    function RemoveArc(Index: Integer; out Data: TScreenLayoutArcData): Boolean;
    function RemoveEllipseArcShape(Index: Integer;
      out Data: TScreenLayoutEllipseArcShapeData): Boolean;
    function RemovePath(Index: Integer; out Data: TVectArtPathData): Boolean;
    // Shapeを削除し、Undo用の独立したデータをDataへ返す。
    function RemoveShape(Index: Integer;
      out Data: TScreenLayoutShapeData): Boolean;
    function RemoveImage(Index: Integer; out Data: TVectArtImageData): Boolean;
    function RemoveText(Index: Integer; out Data: TScreenLayoutTextData): Boolean;
    // Pathのアンカー、制御点、区間種別を深いコピーで置換する。
    procedure SetPathVertices(Index: Integer;
      const Vertices: TArray<TScreenLayoutVertex>);
    procedure SetPathStroke(Index: Integer; Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
    // Shapeの輪郭群を深いコピーで置換し、Document変更を通知する。
    procedure SetShapeContours(Index: Integer;
      const Contours: TArray<TScreenLayoutContour>);
    // Shapeの塗り色と複数輪郭の内外判定規則を更新する。
    procedure SetShapeFill(Index: Integer; Color: TColor;
      FillRule: TScreenLayoutFillRule);
    // Shapeの全輪郭へ共通適用する縁取り設定を更新する。
    procedure SetShapeStroke(Index: Integer; Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
    procedure SelectLayerRange(AnchorIndex, TargetIndex: Integer;
      Additive: Boolean);
    procedure SetSelectedLayers(const Indices: array of Integer);
    procedure ToggleSelectedLayer(Index: Integer);
    property CanvasLayer: TVectArtCanvasLayer read GetCanvasLayer;
    property LayerCount: Integer read GetLayerCount;
    property Layers[Index: Integer]: TVectArtLayer read GetLayer; default;
    property IsInteractiveUpdate: Boolean read GetIsInteractiveUpdate;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property Revision: Int64 read FRevision;
    property SelectedIndex: Integer read FSelectedIndex write SetSelectedIndex;
    property SelectionCount: Integer read GetSelectionCount;
  end;

const
  DEFAULT_CANVAS_WIDTH = 1920;
  DEFAULT_CANVAS_HEIGHT = 1080;
  // 旧実装名はMIF style 3（ダッシュ・ドット）として互換維持する。
  vssDashed: TVectArtMifStrokeStyle = vssDashDot;

function VectArtStrokeDashIntervals(Style: TVectArtMifStrokeStyle;
  Width: Single): TArray<Single>;
function VectArtStrokeUsesRoundCaps(Style: TVectArtMifStrokeStyle): Boolean;
// 4隅へ同じ半径を設定した角丸値を返す。
function UniformScreenLayoutCornerRadii(Radius: Single): TScreenLayoutCornerRadii;
// 各辺で隣接半径が重ならない比率へ角丸値を縮小する。
function ClampScreenLayoutCornerRadii(const Bounds: TRectF;
  const Value: TScreenLayoutCornerRadii): TScreenLayoutCornerRadii;

implementation

uses
  System.Math, ScreenLayoutEllipseGeometry, ScreenLayoutGeometry;

{ TScreenLayoutGroupLayer }

procedure TScreenLayoutGroupLayer.AddChild(Layer: TVectArtLayer);
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  FChildren.Add(Layer);
end;

constructor TScreenLayoutGroupLayer.Create(const AName: string);
begin
  inherited Create(vlkGroup, AName);
  FChildren := TObjectList<TVectArtLayer>.Create(True);
end;

destructor TScreenLayoutGroupLayer.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

function TScreenLayoutGroupLayer.ExtractChild(Index: Integer): TVectArtLayer;
begin
  Result := FChildren.Extract(FChildren[Index]);
end;

function TScreenLayoutGroupLayer.GetChild(Index: Integer): TVectArtLayer;
begin
  Result := FChildren[Index];
end;

function TScreenLayoutGroupLayer.GetChildCount: Integer;
begin
  Result := FChildren.Count;
end;

procedure TScreenLayoutGroupLayer.InsertChild(Index: Integer;
  Layer: TVectArtLayer);
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  FChildren.Insert(EnsureRange(Index, 0, FChildren.Count), Layer);
end;

function UniformScreenLayoutCornerRadii(
  Radius: Single): TScreenLayoutCornerRadii;
begin
  Radius := Max(Radius, 0.0);
  Result.TopLeft := Radius;
  Result.TopRight := Radius;
  Result.BottomRight := Radius;
  Result.BottomLeft := Radius;
end;

function ClampScreenLayoutCornerRadii(const Bounds: TRectF;
  const Value: TScreenLayoutCornerRadii): TScreenLayoutCornerRadii;
var
  Height: Single;
  Scale: Single;
  Sum: Single;
  Width: Single;
begin
  Result.TopLeft := Max(Value.TopLeft, 0.0);
  Result.TopRight := Max(Value.TopRight, 0.0);
  Result.BottomRight := Max(Value.BottomRight, 0.0);
  Result.BottomLeft := Max(Value.BottomLeft, 0.0);
  Width := Max(Bounds.Width, 0.0);
  Height := Max(Bounds.Height, 0.0);
  Scale := 1.0;
  Sum := Result.TopLeft + Result.TopRight;
  if Sum > 0 then
    Scale := Min(Scale, Width / Sum);
  Sum := Result.BottomLeft + Result.BottomRight;
  if Sum > 0 then
    Scale := Min(Scale, Width / Sum);
  Sum := Result.TopLeft + Result.BottomLeft;
  if Sum > 0 then
    Scale := Min(Scale, Height / Sum);
  Sum := Result.TopRight + Result.BottomRight;
  if Sum > 0 then
    Scale := Min(Scale, Height / Sum);
  if Scale < 1.0 then
  begin
    Result.TopLeft := Result.TopLeft * Scale;
    Result.TopRight := Result.TopRight * Scale;
    Result.BottomRight := Result.BottomRight * Scale;
    Result.BottomLeft := Result.BottomLeft * Scale;
  end;
end;

function CopyShapeContours(
  const Source: TArray<TScreenLayoutContour>): TArray<TScreenLayoutContour>;
var
  I: Integer;
begin
  SetLength(Result, Length(Source));
  for I := 0 to High(Source) do
    Result[I].Vertices := Copy(Source[I].Vertices);
end;

procedure ValidateShapeContours(
  const Contours: TArray<TScreenLayoutContour>);
var
  I: Integer;
begin
  if Length(Contours) = 0 then
    raise EArgumentException.Create('Shape must contain at least one contour');
  for I := 0 to High(Contours) do
    if Length(Contours[I].Vertices) < 3 then
      raise EArgumentException.CreateFmt(
        'Shape contour %d must contain at least three vertices', [I]);
end;

function ShapeContoursEqual(const Left,
  Right: TArray<TScreenLayoutContour>): Boolean;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for ContourIndex := 0 to High(Left) do
  begin
    if Length(Left[ContourIndex].Vertices) <>
      Length(Right[ContourIndex].Vertices) then
      Exit(False);
    for VertexIndex := 0 to High(Left[ContourIndex].Vertices) do
      with Left[ContourIndex].Vertices[VertexIndex] do
      begin
        if not SameValue(Position.X,
          Right[ContourIndex].Vertices[VertexIndex].Position.X) or
          not SameValue(Position.Y,
          Right[ContourIndex].Vertices[VertexIndex].Position.Y) or
          not SameValue(IncomingControl.X,
          Right[ContourIndex].Vertices[VertexIndex].IncomingControl.X) or
          not SameValue(IncomingControl.Y,
          Right[ContourIndex].Vertices[VertexIndex].IncomingControl.Y) or
          not SameValue(OutgoingControl.X,
          Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.X) or
          not SameValue(OutgoingControl.Y,
          Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.Y) or
          (OutgoingSegment <>
          Right[ContourIndex].Vertices[VertexIndex].OutgoingSegment) or
          (Kind <> Right[ContourIndex].Vertices[VertexIndex].Kind) then
          Exit(False);
      end;
  end;
  Result := True;
end;

{ TScreenLayoutContour }

function TScreenLayoutContour.SegmentCount: Integer;
begin
  Result := Length(Vertices);
end;

function VectArtStrokeDashIntervals(Style: TVectArtMifStrokeStyle;
  Width: Single): TArray<Single>;
begin
  Width := Max(Width, 0.1);
  case Style of
    vssDotted:
      Result := [Width, Width * 2];
    vssShortDash:
      Result := [Width * 3, Width * 3];
    vssDashDot:
      Result := [Width * 6, Width * 2, Width, Width * 2];
    vssDashDotDot:
      Result := [Width * 6, Width * 2, Width, Width * 2,
        Width, Width * 2];
    vssSparseDotted:
      Result := [Width, Width * 4];
    vssMediumDash:
      Result := [Width * 5, Width * 2];
    vssLongDashDot:
      Result := [Width * 9, Width * 2, Width, Width * 2];
    vssLongDash:
      Result := [Width * 9, Width * 3];
  else
    Result := nil;
  end;
end;

function VectArtStrokeUsesRoundCaps(Style: TVectArtMifStrokeStyle): Boolean;
begin
  Result := Style in [vssDotted, vssDashDot, vssDashDotDot,
    vssSparseDotted, vssLongDashDot];
end;

{ TVectArtLayer }

constructor TVectArtLayer.Create(AKind: TVectArtLayerKind;
  const AName: string);
begin
  inherited Create;
  FKind := AKind;
  FLocked := False;
  FName := AName;
  FOpacity := 1.0;
  FVisible := True;
end;

{ TVectArtCanvasLayer }

constructor TVectArtCanvasLayer.Create(AWidth, AHeight: Integer;
  AColor: TColor);
begin
  inherited Create(vlkCanvas, 'Canvas');
  FWidth := Max(AWidth, 1);
  FHeight := Max(AHeight, 1);
  FBackgroundColor := AColor;
  FTransparent := False;
end;

{ TVectArtRectangleLayer }

constructor TVectArtRectangleLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor);
begin
  inherited Create(vlkRectangle, AName);
  FBounds := ABounds;
  FFillColor := AFillColor;
  FRotationDegrees := 0.0;
end;

constructor TVectArtRectangleLayer.CreateWithKind(AKind: TVectArtLayerKind;
  const AName: string; const ABounds: TRectF; AFillColor: TColor);
begin
  inherited Create(AKind, AName);
  FBounds := ABounds;
  FFillColor := AFillColor;
  FRotationDegrees := 0.0;
end;

{ TScreenLayoutRoundedRectangleLayer }

constructor TScreenLayoutRoundedRectangleLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor;
  const ACornerRadii: TScreenLayoutCornerRadii);
begin
  inherited CreateWithKind(vlkRoundedRectangle, AName, ABounds, AFillColor);
  FCornerRadii := ClampScreenLayoutCornerRadii(ABounds, ACornerRadii);
end;

{ TScreenLayoutEllipseLayer }

constructor TScreenLayoutEllipseLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor);
begin
  inherited CreateWithKind(vlkEllipse, AName, ABounds, AFillColor);
end;

{ TScreenLayoutTextLayer }

constructor TScreenLayoutTextLayer.Create(const AName: string;
  const ABounds: TRectF; const AText, AFontFamily: string;
  AFontSize, AWrapWidth: Single; ATextColor: TColor);
begin
  inherited CreateWithKind(vlkText, AName, ABounds, ATextColor);
  FText := AText;
  FFontFamily := AFontFamily;
  FFontSize := Max(AFontSize, 1.0);
  FWrapWidth := Max(AWrapWidth, 1.0);
end;

{ TScreenLayoutRectangleLineLayer }

constructor TScreenLayoutRectangleLineLayer.Create(const AName: string;
  const ABounds: TRectF);
begin
  CreateWithKind(vlkRectangleLine, AName, ABounds);
end;

constructor TScreenLayoutRectangleLineLayer.CreateWithKind(
  AKind: TVectArtLayerKind; const AName: string; const ABounds: TRectF);
begin
  inherited Create(AKind, AName);
  FBounds := ABounds;
  FRotationDegrees := 0.0;
  FStrokeColor := clBlack;
  FStrokeStyle := vssSolid;
  FStrokeWidth := 1.0;
end;

{ TScreenLayoutRoundedRectangleLineLayer }

constructor TScreenLayoutRoundedRectangleLineLayer.Create(
  const AName: string; const ABounds: TRectF;
  const ACornerRadii: TScreenLayoutCornerRadii);
begin
  inherited CreateWithKind(vlkRoundedRectangleLine, AName, ABounds);
  FCornerRadii := ClampScreenLayoutCornerRadii(ABounds, ACornerRadii);
end;

{ TScreenLayoutEllipseLineLayer }

constructor TScreenLayoutEllipseLineLayer.Create(const AName: string;
  const ABounds: TRectF);
begin
  inherited CreateWithKind(vlkEllipseLine, AName, ABounds);
end;

{ TScreenLayoutArcLayer }

constructor TScreenLayoutArcLayer.Create(const AName: string;
  const ABounds: TRectF);
begin
  inherited Create(vlkArc, AName);
  FBounds := ABounds;
  FLineCap := vlcSquare;
  FRotationDegrees := 0.0;
  FStartAngleDegrees := 180.0;
  FStrokeColor := clBlack;
  FStrokeStyle := vssSolid;
  FStrokeWidth := 1.0;
  FSweepAngleDegrees := 180.0;
end;

{ TScreenLayoutEllipseArcShapeLayer }

constructor TScreenLayoutEllipseArcShapeLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor);
begin
  inherited CreateWithKind(vlkEllipseArcShape, AName, ABounds, AFillColor);
  FStartAngleDegrees := 180.0;
  FSweepAngleDegrees := 180.0;
end;

{ TVectArtPathLayer }

constructor TVectArtPathLayer.Create(const AName: string;
  const AVertices: TArray<TScreenLayoutVertex>; AClosed: Boolean);
begin
  inherited Create(vlkPath, AName);
  SetVertices(AVertices);
  FClosed := AClosed;
  FLineCap := vlcSquare;
  FStrokeColor := clBlack;
  FMifStrokeStyle := vssSolid;
  FStrokeWidth := 1.0;
end;

function TVectArtPathLayer.GetVertices: TArray<TScreenLayoutVertex>;
begin
  Result := Copy(FVertices);
end;

procedure TVectArtPathLayer.SetVertices(
  const Value: TArray<TScreenLayoutVertex>);
begin
  FVertices := Copy(Value);
end;

{ TScreenLayoutShapeLayer }

constructor TScreenLayoutShapeLayer.Create(const AName: string;
  const AContours: TArray<TScreenLayoutContour>);
begin
  inherited Create(vlkShape, AName);
  SetContours(AContours);
  FFillColor := clWhite;
  FFillRule := slfrEvenOdd;
  FStrokeColor := clBlack;
  FStrokeStyle := vssSolid;
  FStrokeWidth := 0.0;
end;

function TScreenLayoutShapeLayer.GetContours: TArray<TScreenLayoutContour>;
begin
  Result := CopyShapeContours(FContours);
end;

function TScreenLayoutShapeLayer.GetContourCount: Integer;
begin
  Result := Length(FContours);
end;

procedure TScreenLayoutShapeLayer.SetContours(
  const Value: TArray<TScreenLayoutContour>);
begin
  ValidateShapeContours(Value);
  FContours := CopyShapeContours(Value);
end;

{ TVectArtImageLayer }

constructor TVectArtImageLayer.Create(const AName: string;
  const APngData: TBytes; const APoints: TVectArtImagePoints;
  ASourceKind: TVectArtImageSourceKind; const ASourceFileName: string);
begin
  inherited Create(vlkImage, AName);
  FPngData := Copy(APngData);
  FPoints := APoints;
  FSourceFileName := ASourceFileName;
  FSourceKind := ASourceKind;
end;

{ TVectArtDocument }

constructor TVectArtDocument.Create;
begin
  inherited Create;
  FLayers := TObjectList<TVectArtLayer>.Create(True);
  FSelectedLayers := TList<Integer>.Create;
  FLayers.Add(TVectArtCanvasLayer.Create(DEFAULT_CANVAS_WIDTH,
    DEFAULT_CANVAS_HEIGHT, clWhite));
  FSelectedIndex := -1;
end;

destructor TVectArtDocument.Destroy;
begin
  FSelectedLayers.Free;
  FLayers.Free;
  inherited Destroy;
end;

procedure TVectArtDocument.Changed;
begin
  if FUpdateCount > 0 then
  begin
    FChangePending := True;
    Exit;
  end;
  Inc(FRevision);
  if FInteractiveUpdateCount > 0 then
    FInteractiveChanged := True;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtDocument.BeginInteractiveUpdate;
begin
  Inc(FInteractiveUpdateCount);
end;

procedure TVectArtDocument.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TVectArtDocument.EndInteractiveUpdate;
begin
  if FInteractiveUpdateCount <= 0 then
    Exit;
  Dec(FInteractiveUpdateCount);
  if (FInteractiveUpdateCount = 0) and FInteractiveChanged then
  begin
    FInteractiveChanged := False;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
  end;
end;

procedure TVectArtDocument.EndUpdate;
begin
  if FUpdateCount <= 0 then
    Exit;
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FChangePending then
  begin
    FChangePending := False;
    Changed;
  end;
end;

procedure TVectArtDocument.SelectionChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TVectArtDocument.GetSelectedLayerIndices: TArray<Integer>;
begin
  Result := FSelectedLayers.ToArray;
end;

function TVectArtDocument.ExtractLayer(Index: Integer): TVectArtLayer;
var
  I: Integer;
  Selection: TList<Integer>;
begin
  if (Index <= 0) or (Index >= FLayers.Count) then
    raise EArgumentOutOfRangeException.Create('Index');
  Result := FLayers.Extract(FLayers[Index]);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.InsertLayer(Index: Integer;
  Layer: TVectArtLayer): Integer;
var
  I: Integer;
  Selection: TArray<Integer>;
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  Result := EnsureRange(Index, 1, FLayers.Count);
  Selection := FSelectedLayers.ToArray;
  FLayers.Insert(Result, Layer);
  for I := 0 to High(Selection) do
    if Selection[I] >= Result then
      Inc(Selection[I]);
  SetSelectedLayersCore(Selection, False);
  Changed;
end;

function TVectArtDocument.GetIsInteractiveUpdate: Boolean;
begin
  Result := FInteractiveUpdateCount > 0;
end;

function TVectArtDocument.InsertRectangle(Index: Integer;
  const Data: TVectArtRectangleData): Integer;
var
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  RectangleLayer := TVectArtRectangleLayer.Create(Data.Name, Data.Bounds,
    Data.FillColor);
  RectangleLayer.Locked := Data.Locked;
  RectangleLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  RectangleLayer.RotationDegrees := NormalizeAngleDegrees(
    Data.RotationDegrees);
  RectangleLayer.Visible := Data.Visible;
  FLayers.Insert(Result, RectangleLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertRoundedRectangle(Index: Integer;
  const Data: TScreenLayoutRoundedRectangleData): Integer;
var
  I: Integer;
  RoundedLayer: TScreenLayoutRoundedRectangleLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  RoundedLayer := TScreenLayoutRoundedRectangleLayer.Create(Data.Name,
    Data.Bounds, Data.FillColor, Data.CornerRadii);
  RoundedLayer.Locked := Data.Locked;
  RoundedLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  RoundedLayer.RotationDegrees := NormalizeAngleDegrees(
    Data.RotationDegrees);
  RoundedLayer.Visible := Data.Visible;
  FLayers.Insert(Result, RoundedLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertEllipse(Index: Integer;
  const Data: TScreenLayoutEllipseData): Integer;
var
  EllipseLayer: TScreenLayoutEllipseLayer;
  I: Integer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  EllipseLayer := TScreenLayoutEllipseLayer.Create(Data.Name, Data.Bounds,
    Data.FillColor);
  EllipseLayer.Locked := Data.Locked;
  EllipseLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  EllipseLayer.RotationDegrees := NormalizeAngleDegrees(
    Data.RotationDegrees);
  EllipseLayer.Visible := Data.Visible;
  FLayers.Insert(Result, EllipseLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertArc(Index: Integer;
  const Data: TScreenLayoutArcData): Integer;
var
  ArcLayer: TScreenLayoutArcLayer;
  I: Integer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ArcLayer := TScreenLayoutArcLayer.Create(Data.Name, Data.Bounds);
  ArcLayer.LineCap := Data.LineCap;
  ArcLayer.Locked := Data.Locked;
  ArcLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ArcLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  ArcLayer.StartAngleDegrees := NormalizeScreenLayoutEllipseAngleDegrees(
    Data.StartAngleDegrees);
  ArcLayer.StrokeColor := Data.StrokeColor;
  ArcLayer.StrokeStyle := Data.StrokeStyle;
  ArcLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  ArcLayer.SweepAngleDegrees := EnsureRange(Data.SweepAngleDegrees,
    0.0, 360.0);
  ArcLayer.Visible := Data.Visible;
  FLayers.Insert(Result, ArcLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertEllipseArcShape(Index: Integer;
  const Data: TScreenLayoutEllipseArcShapeData): Integer;
var
  I: Integer;
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ShapeLayer := TScreenLayoutEllipseArcShapeLayer.Create(Data.Name,
    Data.Bounds, Data.FillColor);
  ShapeLayer.Locked := Data.Locked;
  ShapeLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ShapeLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  ShapeLayer.StartAngleDegrees :=
    NormalizeScreenLayoutEllipseAngleDegrees(Data.StartAngleDegrees);
  ShapeLayer.SweepAngleDegrees := EnsureRange(Data.SweepAngleDegrees,
    0.0, 360.0);
  ShapeLayer.Visible := Data.Visible;
  FLayers.Insert(Result, ShapeLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertRectangleLine(Index: Integer;
  const Data: TScreenLayoutRectangleLineData): Integer;
var
  I: Integer;
  LineLayer: TScreenLayoutRectangleLineLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  LineLayer := TScreenLayoutRectangleLineLayer.Create(Data.Name, Data.Bounds);
  LineLayer.Locked := Data.Locked;
  LineLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  LineLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  LineLayer.StrokeColor := Data.StrokeColor;
  LineLayer.StrokeStyle := Data.StrokeStyle;
  LineLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  LineLayer.Visible := Data.Visible;
  FLayers.Insert(Result, LineLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertRoundedRectangleLine(Index: Integer;
  const Data: TScreenLayoutRoundedRectangleLineData): Integer;
var
  I: Integer;
  LineLayer: TScreenLayoutRoundedRectangleLineLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  LineLayer := TScreenLayoutRoundedRectangleLineLayer.Create(Data.Name,
    Data.Bounds, Data.CornerRadii);
  LineLayer.Locked := Data.Locked;
  LineLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  LineLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  LineLayer.StrokeColor := Data.StrokeColor;
  LineLayer.StrokeStyle := Data.StrokeStyle;
  LineLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  LineLayer.Visible := Data.Visible;
  FLayers.Insert(Result, LineLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertEllipseLine(Index: Integer;
  const Data: TScreenLayoutEllipseLineData): Integer;
var
  I: Integer;
  LineLayer: TScreenLayoutEllipseLineLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  LineLayer := TScreenLayoutEllipseLineLayer.Create(Data.Name, Data.Bounds);
  LineLayer.Locked := Data.Locked;
  LineLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  LineLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  LineLayer.StrokeColor := Data.StrokeColor;
  LineLayer.StrokeStyle := Data.StrokeStyle;
  LineLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  LineLayer.Visible := Data.Visible;
  FLayers.Insert(Result, LineLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertPath(Index: Integer;
  const Data: TVectArtPathData): Integer;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  PathLayer := TVectArtPathLayer.Create(Data.Name, Data.Vertices, Data.Closed);
  PathLayer.LineCap := Data.LineCap;
  PathLayer.Locked := Data.Locked;
  PathLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  PathLayer.StrokeColor := Data.StrokeColor;
  PathLayer.MifStrokeStyle := Data.MifStrokeStyle;
  PathLayer.StrokeWidth := Max(Data.StrokeWidth, 0.0);
  PathLayer.Visible := Data.Visible;
  FLayers.Insert(Result, PathLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertShape(Index: Integer;
  const Data: TScreenLayoutShapeData): Integer;
var
  I: Integer;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ShapeLayer := TScreenLayoutShapeLayer.Create(Data.Name, Data.Contours);
  ShapeLayer.FillColor := Data.FillColor;
  ShapeLayer.FillRule := Data.FillRule;
  ShapeLayer.Locked := Data.Locked;
  ShapeLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ShapeLayer.StrokeColor := Data.StrokeColor;
  ShapeLayer.StrokeStyle := Data.StrokeStyle;
  ShapeLayer.StrokeWidth := Max(Data.StrokeWidth, 0.0);
  ShapeLayer.Visible := Data.Visible;
  FLayers.Insert(Result, ShapeLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertImage(Index: Integer;
  const Data: TVectArtImageData): Integer;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ImageLayer := TVectArtImageLayer.Create(Data.Name, Data.PngData,
    Data.Points, Data.SourceKind, Data.SourceFileName);
  ImageLayer.Locked := Data.Locked;
  ImageLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ImageLayer.Visible := Data.Visible;
  FLayers.Insert(Result, ImageLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertText(Index: Integer;
  const Data: TScreenLayoutTextData): Integer;
var
  I: Integer;
  TextLayer: TScreenLayoutTextLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  TextLayer := TScreenLayoutTextLayer.Create(Data.Name, Data.Bounds,
    Data.Text, Data.FontFamily, Data.FontSize, Data.WrapWidth, Data.TextColor);
  TextLayer.Locked := Data.Locked;
  TextLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  TextLayer.RotationDegrees := Data.RotationDegrees;
  TextLayer.Visible := Data.Visible;
  FLayers.Insert(Result, TextLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

procedure TVectArtDocument.MoveLayer(FromIndex, ToIndex: Integer);
var
  I: Integer;
  Layer: TVectArtLayer;
  Selection: TArray<Integer>;
begin
  if (FromIndex <= 0) or (FromIndex >= FLayers.Count) then
    Exit;
  ToIndex := EnsureRange(ToIndex, 1, FLayers.Count - 1);
  if FromIndex = ToIndex then
    Exit;
  Selection := GetSelectedLayerIndices;
  Layer := FLayers.Extract(FLayers[FromIndex]);
  FLayers.Insert(ToIndex, Layer);
  for I := 0 to High(Selection) do
    if Selection[I] = FromIndex then
      Selection[I] := ToIndex
    else if (FromIndex < ToIndex) and (Selection[I] > FromIndex) and
      (Selection[I] <= ToIndex) then
      Dec(Selection[I])
    else if (FromIndex > ToIndex) and (Selection[I] >= ToIndex) and
      (Selection[I] < FromIndex) then
      Inc(Selection[I]);
  SetSelectedLayersCore(Selection, False);
  Changed;
end;

function TVectArtDocument.RemoveRectangle(Index: Integer;
  out Data: TVectArtRectangleData): Boolean;
var
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index].ClassType = TVectArtRectangleLayer);
  if not Result then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  Data.Bounds := RectangleLayer.Bounds;
  Data.FillColor := RectangleLayer.FillColor;
  Data.Locked := RectangleLayer.Locked;
  Data.Name := RectangleLayer.Name;
  Data.Opacity := RectangleLayer.Opacity;
  Data.RotationDegrees := RectangleLayer.RotationDegrees;
  Data.Visible := RectangleLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveRoundedRectangle(Index: Integer;
  out Data: TScreenLayoutRoundedRectangleData): Boolean;
var
  I: Integer;
  RoundedLayer: TScreenLayoutRoundedRectangleLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutRoundedRectangleLayer);
  if not Result then
    Exit;
  RoundedLayer := TScreenLayoutRoundedRectangleLayer(FLayers[Index]);
  Data.Bounds := RoundedLayer.Bounds;
  Data.CornerRadii := RoundedLayer.CornerRadii;
  Data.FillColor := RoundedLayer.FillColor;
  Data.Locked := RoundedLayer.Locked;
  Data.Name := RoundedLayer.Name;
  Data.Opacity := RoundedLayer.Opacity;
  Data.RotationDegrees := RoundedLayer.RotationDegrees;
  Data.Visible := RoundedLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveEllipse(Index: Integer;
  out Data: TScreenLayoutEllipseData): Boolean;
var
  EllipseLayer: TScreenLayoutEllipseLayer;
  I: Integer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutEllipseLayer);
  if not Result then
    Exit;
  EllipseLayer := TScreenLayoutEllipseLayer(FLayers[Index]);
  Data.Bounds := EllipseLayer.Bounds;
  Data.FillColor := EllipseLayer.FillColor;
  Data.Locked := EllipseLayer.Locked;
  Data.Name := EllipseLayer.Name;
  Data.Opacity := EllipseLayer.Opacity;
  Data.RotationDegrees := EllipseLayer.RotationDegrees;
  Data.Visible := EllipseLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveArc(Index: Integer;
  out Data: TScreenLayoutArcData): Boolean;
var
  ArcLayer: TScreenLayoutArcLayer;
  I: Integer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutArcLayer);
  if not Result then
    Exit;
  ArcLayer := TScreenLayoutArcLayer(FLayers[Index]);
  Data.Bounds := ArcLayer.Bounds;
  Data.LineCap := ArcLayer.LineCap;
  Data.Locked := ArcLayer.Locked;
  Data.Name := ArcLayer.Name;
  Data.Opacity := ArcLayer.Opacity;
  Data.RotationDegrees := ArcLayer.RotationDegrees;
  Data.StartAngleDegrees := ArcLayer.StartAngleDegrees;
  Data.StrokeColor := ArcLayer.StrokeColor;
  Data.StrokeStyle := ArcLayer.StrokeStyle;
  Data.StrokeWidth := ArcLayer.StrokeWidth;
  Data.SweepAngleDegrees := ArcLayer.SweepAngleDegrees;
  Data.Visible := ArcLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveRectangleLine(Index: Integer;
  out Data: TScreenLayoutRectangleLineData): Boolean;
var
  I: Integer;
  LineLayer: TScreenLayoutRectangleLineLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index].ClassType = TScreenLayoutRectangleLineLayer);
  if not Result then
    Exit;
  LineLayer := TScreenLayoutRectangleLineLayer(FLayers[Index]);
  Data.Bounds := LineLayer.Bounds;
  Data.Locked := LineLayer.Locked;
  Data.Name := LineLayer.Name;
  Data.Opacity := LineLayer.Opacity;
  Data.RotationDegrees := LineLayer.RotationDegrees;
  Data.StrokeColor := LineLayer.StrokeColor;
  Data.StrokeStyle := LineLayer.StrokeStyle;
  Data.StrokeWidth := LineLayer.StrokeWidth;
  Data.Visible := LineLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveRoundedRectangleLine(Index: Integer;
  out Data: TScreenLayoutRoundedRectangleLineData): Boolean;
var
  I: Integer;
  LineLayer: TScreenLayoutRoundedRectangleLineLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutRoundedRectangleLineLayer);
  if not Result then
    Exit;
  LineLayer := TScreenLayoutRoundedRectangleLineLayer(FLayers[Index]);
  Data.Bounds := LineLayer.Bounds;
  Data.CornerRadii := LineLayer.CornerRadii;
  Data.Locked := LineLayer.Locked;
  Data.Name := LineLayer.Name;
  Data.Opacity := LineLayer.Opacity;
  Data.RotationDegrees := LineLayer.RotationDegrees;
  Data.StrokeColor := LineLayer.StrokeColor;
  Data.StrokeStyle := LineLayer.StrokeStyle;
  Data.StrokeWidth := LineLayer.StrokeWidth;
  Data.Visible := LineLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveEllipseArcShape(Index: Integer;
  out Data: TScreenLayoutEllipseArcShapeData): Boolean;
var
  I: Integer;
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutEllipseArcShapeLayer);
  if not Result then
    Exit;
  ShapeLayer := TScreenLayoutEllipseArcShapeLayer(FLayers[Index]);
  Data.Bounds := ShapeLayer.Bounds;
  Data.FillColor := ShapeLayer.FillColor;
  Data.Locked := ShapeLayer.Locked;
  Data.Name := ShapeLayer.Name;
  Data.Opacity := ShapeLayer.Opacity;
  Data.RotationDegrees := ShapeLayer.RotationDegrees;
  Data.StartAngleDegrees := ShapeLayer.StartAngleDegrees;
  Data.SweepAngleDegrees := ShapeLayer.SweepAngleDegrees;
  Data.Visible := ShapeLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveEllipseLine(Index: Integer;
  out Data: TScreenLayoutEllipseLineData): Boolean;
var
  I: Integer;
  LineLayer: TScreenLayoutEllipseLineLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutEllipseLineLayer);
  if not Result then
    Exit;
  LineLayer := TScreenLayoutEllipseLineLayer(FLayers[Index]);
  Data.Bounds := LineLayer.Bounds;
  Data.Locked := LineLayer.Locked;
  Data.Name := LineLayer.Name;
  Data.Opacity := LineLayer.Opacity;
  Data.RotationDegrees := LineLayer.RotationDegrees;
  Data.StrokeColor := LineLayer.StrokeColor;
  Data.StrokeStyle := LineLayer.StrokeStyle;
  Data.StrokeWidth := LineLayer.StrokeWidth;
  Data.Visible := LineLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemovePath(Index: Integer;
  out Data: TVectArtPathData): Boolean;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TVectArtPathLayer);
  if not Result then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  Data.Closed := PathLayer.Closed;
  Data.LineCap := PathLayer.LineCap;
  Data.Locked := PathLayer.Locked;
  Data.Name := PathLayer.Name;
  Data.Opacity := PathLayer.Opacity;
  Data.Vertices := PathLayer.Vertices;
  Data.StrokeColor := PathLayer.StrokeColor;
  Data.MifStrokeStyle := PathLayer.MifStrokeStyle;
  Data.StrokeWidth := PathLayer.StrokeWidth;
  Data.Visible := PathLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveImage(Index: Integer;
  out Data: TVectArtImageData): Boolean;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TVectArtImageLayer);
  if not Result then
    Exit;
  ImageLayer := TVectArtImageLayer(FLayers[Index]);
  Data.Locked := ImageLayer.Locked;
  Data.Name := ImageLayer.Name;
  Data.Opacity := ImageLayer.Opacity;
  Data.PngData := Copy(ImageLayer.PngData);
  Data.Points := ImageLayer.Points;
  Data.SourceFileName := ImageLayer.SourceFileName;
  Data.SourceKind := ImageLayer.SourceKind;
  Data.Visible := ImageLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveText(Index: Integer;
  out Data: TScreenLayoutTextData): Boolean;
var
  I: Integer;
  Selection: TList<Integer>;
  TextLayer: TScreenLayoutTextLayer;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutTextLayer);
  if not Result then
    Exit;
  TextLayer := TScreenLayoutTextLayer(FLayers[Index]);
  Data.Bounds := TextLayer.Bounds;
  Data.FontFamily := TextLayer.FontFamily;
  Data.FontSize := TextLayer.FontSize;
  Data.Locked := TextLayer.Locked;
  Data.Name := TextLayer.Name;
  Data.Opacity := TextLayer.Opacity;
  Data.RotationDegrees := TextLayer.RotationDegrees;
  Data.Text := TextLayer.Text;
  Data.TextColor := TextLayer.FillColor;
  Data.Visible := TextLayer.Visible;
  Data.WrapWidth := TextLayer.WrapWidth;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveShape(Index: Integer;
  out Data: TScreenLayoutShapeData): Boolean;
var
  I: Integer;
  Selection: TList<Integer>;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TScreenLayoutShapeLayer);
  if not Result then
    Exit;
  ShapeLayer := TScreenLayoutShapeLayer(FLayers[Index]);
  Data.Contours := ShapeLayer.Contours;
  Data.FillColor := ShapeLayer.FillColor;
  Data.FillRule := ShapeLayer.FillRule;
  Data.Locked := ShapeLayer.Locked;
  Data.Name := ShapeLayer.Name;
  Data.Opacity := ShapeLayer.Opacity;
  Data.StrokeColor := ShapeLayer.StrokeColor;
  Data.StrokeStyle := ShapeLayer.StrokeStyle;
  Data.StrokeWidth := ShapeLayer.StrokeWidth;
  Data.Visible := ShapeLayer.Visible;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.GetCanvasLayer: TVectArtCanvasLayer;
begin
  if (FLayers.Count > 0) and (FLayers[0] is TVectArtCanvasLayer) then
    Result := TVectArtCanvasLayer(FLayers[0])
  else
    Result := nil;
end;

function TVectArtDocument.GetLayer(Index: Integer): TVectArtLayer;
begin
  Result := FLayers[Index];
end;

function TVectArtDocument.GetLayerCount: Integer;
begin
  Result := FLayers.Count;
end;

function TVectArtDocument.GetSelectionCount: Integer;
begin
  Result := FSelectedLayers.Count;
end;

function TVectArtDocument.IsLayerSelected(Index: Integer): Boolean;
begin
  Result := FSelectedLayers.Contains(Index);
end;

procedure TVectArtDocument.SetCanvasSize(AWidth, AHeight: Integer);
var
  Canvas: TVectArtCanvasLayer;
begin
  Canvas := GetCanvasLayer;
  if Canvas = nil then
    Exit;
  AWidth := Max(AWidth, 1);
  AHeight := Max(AHeight, 1);
  if (Canvas.Width = AWidth) and (Canvas.Height = AHeight) then
    Exit;
  Canvas.Width := AWidth;
  Canvas.Height := AHeight;
  Changed;
end;

procedure TVectArtDocument.SetSelectedIndex(const Value: Integer);
var
  NewValue: Integer;
begin
  NewValue := EnsureRange(Value, -1, FLayers.Count - 1);
  if (FSelectedIndex = NewValue) and
    (((NewValue < 0) and (FSelectedLayers.Count = 0)) or
     ((FSelectedLayers.Count = 1) and (FSelectedLayers[0] = NewValue))) then
    Exit;
  FSelectedLayers.Clear;
  if NewValue >= 0 then
    FSelectedLayers.Add(NewValue);
  FSelectedIndex := NewValue;
  SelectionChanged;
end;

procedure TVectArtDocument.SetSelectedLayers(const Indices: array of Integer);
begin
  SetSelectedLayersCore(Indices, True);
end;

procedure TVectArtDocument.SelectLayerRange(AnchorIndex,
  TargetIndex: Integer; Additive: Boolean);
var
  FirstIndex: Integer;
  I: Integer;
  LastIndex: Integer;
  Selection: TList<Integer>;
begin
  if FLayers.Count <= 1 then
    Exit;
  AnchorIndex := EnsureRange(AnchorIndex, 1, FLayers.Count - 1);
  TargetIndex := EnsureRange(TargetIndex, 1, FLayers.Count - 1);
  FirstIndex := Min(AnchorIndex, TargetIndex);
  LastIndex := Max(AnchorIndex, TargetIndex);
  Selection := TList<Integer>.Create;
  try
    if Additive then
      Selection.AddRange(FSelectedLayers);
    for I := FirstIndex to LastIndex do
      if not Selection.Contains(I) then
        Selection.Add(I);
    Selection.Sort;
    // レイヤー操作用の昇順選択を保ちつつ、最後に指した範囲端をアクティブにする。
    SetSelectedLayersCore(Selection.ToArray, False);
    FSelectedIndex := TargetIndex;
    SelectionChanged;
  finally
    Selection.Free;
  end;
end;

procedure TVectArtDocument.SetSelectedLayersCore(
  const Indices: array of Integer; Notify: Boolean);
var
  I: Integer;
  Index: Integer;
  HasSelectionChanged: Boolean;
  ValidIndices: TList<Integer>;
begin
  ValidIndices := TList<Integer>.Create;
  try
    for Index in Indices do
      if (Index > 0) and (Index < FLayers.Count) and
        not ValidIndices.Contains(Index) then
        ValidIndices.Add(Index);
    HasSelectionChanged := ValidIndices.Count <> FSelectedLayers.Count;
    if not HasSelectionChanged then
      for I := 0 to ValidIndices.Count - 1 do
        if ValidIndices[I] <> FSelectedLayers[I] then
        begin
          HasSelectionChanged := True;
          Break;
        end;
    if not HasSelectionChanged then
      Exit;
    FSelectedLayers.Clear;
    FSelectedLayers.AddRange(ValidIndices);
    if FSelectedLayers.Count > 0 then
      FSelectedIndex := FSelectedLayers[FSelectedLayers.Count - 1]
    else
      FSelectedIndex := -1;
  finally
    ValidIndices.Free;
  end;
  if Notify then
    SelectionChanged;
end;

procedure TVectArtDocument.ToggleSelectedLayer(Index: Integer);
var
  Added: Boolean;
  Selection: TList<Integer>;
begin
  if (Index <= 0) or (Index >= FLayers.Count) then
    Exit;
  Selection := TList<Integer>.Create;
  try
    Selection.AddRange(FSelectedLayers);
    Added := not Selection.Contains(Index);
    if not Added then
      Selection.Remove(Index)
    else
      Selection.Add(Index);
    Selection.Sort;
    // 選択配列は積層順のまま保ち、Ctrlクリックした対象だけをアクティブとして別管理する。
    SetSelectedLayersCore(Selection.ToArray, False);
    if Added then
      FSelectedIndex := Index
    else if Selection.Count > 0 then
      FSelectedIndex := Selection[Selection.Count - 1]
    else
      FSelectedIndex := -1;
    SelectionChanged;
  finally
    Selection.Free;
  end;
end;

procedure TVectArtDocument.SetRectangleBounds(Index: Integer;
  const Value: TRectF);
var
  CurrentBounds: TRectF;
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  CurrentBounds := RectangleLayer.Bounds;
  if SameValue(CurrentBounds.Left, Value.Left) and
    SameValue(CurrentBounds.Top, Value.Top) and
    SameValue(CurrentBounds.Right, Value.Right) and
    SameValue(CurrentBounds.Bottom, Value.Bottom) then
    Exit;
  RectangleLayer.Bounds := Value;
  if RectangleLayer is TScreenLayoutRoundedRectangleLayer then
    TScreenLayoutRoundedRectangleLayer(RectangleLayer).CornerRadii :=
      ClampScreenLayoutCornerRadii(Value,
        TScreenLayoutRoundedRectangleLayer(RectangleLayer).CornerRadii);
  Changed;
end;

procedure TVectArtDocument.SetRoundedRectangleCornerRadii(Index: Integer;
  const Value: TScreenLayoutCornerRadii);
var
  NewValue: TScreenLayoutCornerRadii;
  RoundedLayer: TScreenLayoutRoundedRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutRoundedRectangleLayer) then
    Exit;
  RoundedLayer := TScreenLayoutRoundedRectangleLayer(FLayers[Index]);
  NewValue := ClampScreenLayoutCornerRadii(RoundedLayer.Bounds, Value);
  if SameValue(RoundedLayer.CornerRadii.TopLeft, NewValue.TopLeft) and
    SameValue(RoundedLayer.CornerRadii.TopRight, NewValue.TopRight) and
    SameValue(RoundedLayer.CornerRadii.BottomRight, NewValue.BottomRight) and
    SameValue(RoundedLayer.CornerRadii.BottomLeft, NewValue.BottomLeft) then
    Exit;
  RoundedLayer.CornerRadii := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleFillColor(Index: Integer;
  Value: TColor);
var
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  if RectangleLayer.FillColor = Value then
    Exit;
  RectangleLayer.FillColor := Value;
  Changed;
end;

procedure TVectArtDocument.SetRectangleRotation(Index: Integer;
  Value: Single);
var
  NewValue: Single;
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  NewValue := NormalizeAngleDegrees(Value);
  if SameValue(RectangleLayer.RotationDegrees, NewValue) then
    Exit;
  RectangleLayer.RotationDegrees := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleLineBounds(Index: Integer;
  const Value: TRectF);
var
  CurrentBounds: TRectF;
  LineLayer: TScreenLayoutRectangleLineLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutRectangleLineLayer) then
    Exit;
  LineLayer := TScreenLayoutRectangleLineLayer(FLayers[Index]);
  CurrentBounds := LineLayer.Bounds;
  if SameValue(CurrentBounds.Left, Value.Left) and
    SameValue(CurrentBounds.Top, Value.Top) and
    SameValue(CurrentBounds.Right, Value.Right) and
    SameValue(CurrentBounds.Bottom, Value.Bottom) then
    Exit;
  LineLayer.Bounds := Value;
  if LineLayer is TScreenLayoutRoundedRectangleLineLayer then
    TScreenLayoutRoundedRectangleLineLayer(LineLayer).CornerRadii :=
      ClampScreenLayoutCornerRadii(Value,
        TScreenLayoutRoundedRectangleLineLayer(LineLayer).CornerRadii);
  Changed;
end;

procedure TVectArtDocument.SetRoundedRectangleLineCornerRadii(Index: Integer;
  const Value: TScreenLayoutCornerRadii);
var
  LineLayer: TScreenLayoutRoundedRectangleLineLayer;
  NewValue: TScreenLayoutCornerRadii;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutRoundedRectangleLineLayer) then
    Exit;
  LineLayer := TScreenLayoutRoundedRectangleLineLayer(FLayers[Index]);
  NewValue := ClampScreenLayoutCornerRadii(LineLayer.Bounds, Value);
  if SameValue(LineLayer.CornerRadii.TopLeft, NewValue.TopLeft) and
    SameValue(LineLayer.CornerRadii.TopRight, NewValue.TopRight) and
    SameValue(LineLayer.CornerRadii.BottomRight, NewValue.BottomRight) and
    SameValue(LineLayer.CornerRadii.BottomLeft, NewValue.BottomLeft) then
    Exit;
  LineLayer.CornerRadii := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleLineRotation(Index: Integer;
  Value: Single);
var
  LineLayer: TScreenLayoutRectangleLineLayer;
  NewValue: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutRectangleLineLayer) then
    Exit;
  LineLayer := TScreenLayoutRectangleLineLayer(FLayers[Index]);
  NewValue := NormalizeAngleDegrees(Value);
  if SameValue(LineLayer.RotationDegrees, NewValue) then
    Exit;
  LineLayer.RotationDegrees := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleLineStroke(Index: Integer;
  Color: TColor; Width: Single; Style: TVectArtMifStrokeStyle);
var
  LineLayer: TScreenLayoutRectangleLineLayer;
  NewWidth: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutRectangleLineLayer) then
    Exit;
  LineLayer := TScreenLayoutRectangleLineLayer(FLayers[Index]);
  NewWidth := Max(Width, 0.1);
  if (LineLayer.StrokeColor = Color) and
    SameValue(LineLayer.StrokeWidth, NewWidth) and
    (LineLayer.StrokeStyle = Style) then
    Exit;
  LineLayer.StrokeColor := Color;
  LineLayer.StrokeWidth := NewWidth;
  LineLayer.StrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetArcBounds(Index: Integer;
  const Value: TRectF);
var
  ArcLayer: TScreenLayoutArcLayer;
  CurrentBounds: TRectF;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutArcLayer) then
    Exit;
  ArcLayer := TScreenLayoutArcLayer(FLayers[Index]);
  CurrentBounds := ArcLayer.Bounds;
  if SameValue(CurrentBounds.Left, Value.Left) and
    SameValue(CurrentBounds.Top, Value.Top) and
    SameValue(CurrentBounds.Right, Value.Right) and
    SameValue(CurrentBounds.Bottom, Value.Bottom) then
    Exit;
  ArcLayer.Bounds := Value;
  Changed;
end;

procedure TVectArtDocument.SetArcAngles(Index: Integer; StartAngleDegrees,
  SweepAngleDegrees: Single);
var
  ArcLayer: TScreenLayoutArcLayer;
  NewStartAngle: Single;
  NewSweepAngle: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutArcLayer) then
    Exit;
  ArcLayer := TScreenLayoutArcLayer(FLayers[Index]);
  NewStartAngle := NormalizeScreenLayoutEllipseAngleDegrees(
    StartAngleDegrees);
  NewSweepAngle := EnsureRange(SweepAngleDegrees, 0.0, 360.0);
  if SameValue(ArcLayer.StartAngleDegrees, NewStartAngle) and
    SameValue(ArcLayer.SweepAngleDegrees, NewSweepAngle) then
    Exit;
  ArcLayer.StartAngleDegrees := NewStartAngle;
  ArcLayer.SweepAngleDegrees := NewSweepAngle;
  Changed;
end;

procedure TVectArtDocument.SetArcLineCap(Index: Integer;
  Value: TVectArtLineCap);
var
  ArcLayer: TScreenLayoutArcLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutArcLayer) then
    Exit;
  ArcLayer := TScreenLayoutArcLayer(FLayers[Index]);
  if ArcLayer.LineCap = Value then
    Exit;
  ArcLayer.LineCap := Value;
  Changed;
end;

procedure TVectArtDocument.SetArcRotation(Index: Integer; Value: Single);
var
  ArcLayer: TScreenLayoutArcLayer;
  NewValue: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutArcLayer) then
    Exit;
  ArcLayer := TScreenLayoutArcLayer(FLayers[Index]);
  NewValue := NormalizeAngleDegrees(Value);
  if SameValue(ArcLayer.RotationDegrees, NewValue) then
    Exit;
  ArcLayer.RotationDegrees := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetEllipseArcShapeAngles(Index: Integer;
  StartAngleDegrees, SweepAngleDegrees: Single);
var
  NewStartAngle: Single;
  NewSweepAngle: Single;
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutEllipseArcShapeLayer) then
    Exit;
  ShapeLayer := TScreenLayoutEllipseArcShapeLayer(FLayers[Index]);
  NewStartAngle := NormalizeScreenLayoutEllipseAngleDegrees(
    StartAngleDegrees);
  NewSweepAngle := EnsureRange(SweepAngleDegrees, 0.0, 360.0);
  if SameValue(ShapeLayer.StartAngleDegrees, NewStartAngle) and
    SameValue(ShapeLayer.SweepAngleDegrees, NewSweepAngle) then
    Exit;
  ShapeLayer.StartAngleDegrees := NewStartAngle;
  ShapeLayer.SweepAngleDegrees := NewSweepAngle;
  Changed;
end;

procedure TVectArtDocument.SetArcStroke(Index: Integer; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  ArcLayer: TScreenLayoutArcLayer;
  NewWidth: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutArcLayer) then
    Exit;
  ArcLayer := TScreenLayoutArcLayer(FLayers[Index]);
  NewWidth := Max(Width, 0.1);
  if (ArcLayer.StrokeColor = Color) and
    SameValue(ArcLayer.StrokeWidth, NewWidth) and
    (ArcLayer.StrokeStyle = Style) then
    Exit;
  ArcLayer.StrokeColor := Color;
  ArcLayer.StrokeWidth := NewWidth;
  ArcLayer.StrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetImagePoints(Index: Integer;
  const Points: TVectArtImagePoints);
var
  ImageLayer: TVectArtImageLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtImageLayer) then
    Exit;
  ImageLayer := TVectArtImageLayer(FLayers[Index]);
  ImageLayer.Points := Points;
  Changed;
end;

procedure TVectArtDocument.SetTextData(Index: Integer;
  const Data: TScreenLayoutTextData);
var
  TextLayer: TScreenLayoutTextLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutTextLayer) then
    Exit;
  TextLayer := TScreenLayoutTextLayer(FLayers[Index]);
  TextLayer.Bounds := Data.Bounds;
  TextLayer.FillColor := Data.TextColor;
  TextLayer.FontFamily := Data.FontFamily;
  TextLayer.FontSize := Max(Data.FontSize, 1.0);
  TextLayer.Locked := Data.Locked;
  TextLayer.Name := Data.Name;
  TextLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  TextLayer.RotationDegrees := Data.RotationDegrees;
  TextLayer.Text := Data.Text;
  TextLayer.Visible := Data.Visible;
  TextLayer.WrapWidth := Max(Data.WrapWidth, 1.0);
  Changed;
end;

procedure TVectArtDocument.SetPathVertices(Index: Integer;
  const Vertices: TArray<TScreenLayoutVertex>);
var
  I: Integer;
  OldVertices: TArray<TScreenLayoutVertex>;
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  OldVertices := PathLayer.Vertices;
  if Length(OldVertices) = Length(Vertices) then
  begin
    if Length(Vertices) = 0 then
      Exit;
    for I := 0 to High(Vertices) do
      if not SameValue(OldVertices[I].Position.X, Vertices[I].Position.X) or
        not SameValue(OldVertices[I].Position.Y, Vertices[I].Position.Y) or
        not SameValue(OldVertices[I].IncomingControl.X,
          Vertices[I].IncomingControl.X) or
        not SameValue(OldVertices[I].IncomingControl.Y,
          Vertices[I].IncomingControl.Y) or
        not SameValue(OldVertices[I].OutgoingControl.X,
          Vertices[I].OutgoingControl.X) or
        not SameValue(OldVertices[I].OutgoingControl.Y,
          Vertices[I].OutgoingControl.Y) or
        (OldVertices[I].OutgoingSegment <> Vertices[I].OutgoingSegment) or
        (OldVertices[I].Kind <> Vertices[I].Kind) then
        Break;
    if I > High(Vertices) then
      Exit;
  end;
  PathLayer.Vertices := Vertices;
  Changed;
end;

procedure TVectArtDocument.SetPathLineCap(Index: Integer;
  Value: TVectArtLineCap);
var
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  if PathLayer.LineCap = Value then
    Exit;
  PathLayer.LineCap := Value;
  Changed;
end;

procedure TVectArtDocument.SetPathStroke(Index: Integer; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  NewWidth: Single;
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  NewWidth := Max(Width, 0.0);
  if (PathLayer.StrokeColor = Color) and
    SameValue(PathLayer.StrokeWidth, NewWidth) and
    (PathLayer.MifStrokeStyle = Style) then
    Exit;
  PathLayer.StrokeColor := Color;
  PathLayer.StrokeWidth := NewWidth;
  PathLayer.MifStrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetShapeContours(Index: Integer;
  const Contours: TArray<TScreenLayoutContour>);
var
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutShapeLayer) then
    Exit;
  ShapeLayer := TScreenLayoutShapeLayer(FLayers[Index]);
  if ShapeContoursEqual(ShapeLayer.FContours, Contours) then
    Exit;
  ShapeLayer.Contours := Contours;
  Changed;
end;

procedure TVectArtDocument.SetShapeFill(Index: Integer; Color: TColor;
  FillRule: TScreenLayoutFillRule);
var
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutShapeLayer) then
    Exit;
  ShapeLayer := TScreenLayoutShapeLayer(FLayers[Index]);
  if (ShapeLayer.FillColor = Color) and
    (ShapeLayer.FillRule = FillRule) then
    Exit;
  ShapeLayer.FillColor := Color;
  ShapeLayer.FillRule := FillRule;
  Changed;
end;

procedure TVectArtDocument.SetShapeStroke(Index: Integer; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  NewWidth: Single;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TScreenLayoutShapeLayer) then
    Exit;
  ShapeLayer := TScreenLayoutShapeLayer(FLayers[Index]);
  NewWidth := Max(Width, 0.0);
  if (ShapeLayer.StrokeColor = Color) and
    SameValue(ShapeLayer.StrokeWidth, NewWidth) and
    (ShapeLayer.StrokeStyle = Style) then
    Exit;
  ShapeLayer.StrokeColor := Color;
  ShapeLayer.StrokeWidth := NewWidth;
  ShapeLayer.StrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetLayerLocked(Index: Integer; Value: Boolean);
begin
  if (Index < 0) or (Index >= FLayers.Count) or
    (FLayers[Index].Locked = Value) then
    Exit;
  FLayers[Index].Locked := Value;
  Changed;
end;

procedure TVectArtDocument.SetLayerOpacity(Index: Integer; Value: Single);
var
  NewValue: Single;
begin
  if (Index < 0) or (Index >= FLayers.Count) then
    Exit;
  NewValue := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FLayers[Index].Opacity, NewValue) then
    Exit;
  FLayers[Index].Opacity := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetLayerVisible(Index: Integer; Value: Boolean);
begin
  if (Index < 0) or (Index >= FLayers.Count) or
    (FLayers[Index].Visible = Value) then
    Exit;
  FLayers[Index].Visible := Value;
  Changed;
end;

end.
