# ScreenDesignMaker Codex操作仕様

この文書は、開いているScreenDesignMaker／「画面レイアウト - 編集」をCodexから操作するための
必須手順とJSON命令を定義する。操作を始めるCodexは最初に本書を最後まで読むこと。

## 目的と前提

- 対象は現在開いている1つのScreenLayout編集画面である。
- 通信先はローカルNamed Pipe `\\.\pipe\ScreenDesignMaker.v1` である。
- 文字コードはUTF-8、通信単位はMessage、要求と応答はJSONオブジェクトである。
- 編集画面が閉じている場合、Pipeは存在しない。
- 同時に操作できる編集画面とクライアントはそれぞれ1つだけである。
- 背景・合成結果・未適用案をローカルPNGとして取得できる。文字や装飾は編集可能なDocumentとして作成する。
- PNGはOS一時フォルダーの`ScreenDesignMaker-Automation`へ要求ごとに別名で保存し、絶対パスを返す。
  パス文字列を取得しただけでは画像を見たことにならない。Codexの画像閲覧機能で実際に読むこと。
  一時PNGは自動削除しないため、不要になったファイルは通常の一時ファイル整理の対象になる。
- 最大要求サイズは4 MiBである。

## 絶対に守る操作手順

1. `get_capabilities`で接続先とプロトコルを確認する。
2. 画像に合わせた制作では`get_canvas_snapshot`で最新Document、`state_token`、`background_token`、画像を取得する。
   画像を使わない数値編集だけなら従来の`get_document`も使用できる。
3. 取得したDocumentを基礎に、依頼された箇所だけを変更する。未知のフィールドを削除しない。
4. 画像制作では同じ2つのトークンと変更案を`render_preview`へ送り、返された画像を読み、必要なら案を修正する。
   `render_preview`はJSON検証も行う。画像を使わない編集は従来の`preview_replace_document`で検証する。
5. ユーザーが編集を依頼している場合に限り、検証した内容を`replace_document`へ送り、`apply: true`を付ける。
   画像制作では取得時の`background_token`も必ず付ける。
6. `status: "ok"`、`change.applied: true`、新しい`state_token`を確認する。
7. ユーザーに編集画面で結果を確認してもらい、修正指示があれば必ずDocumentを再取得する。

取得後にユーザーまたは別処理がDocumentを変更すると`state_changed`になる。その場合、古いDocumentを
再送して上書きせず、必ず取得からやり直す。参照背景の更新は`background_changed`となり、
`get_canvas_snapshot`から構図を見直す。`editor_busy`では文字入力や変形の確定を待つ。

## PowerShell接続関数

専用EXEは不要である。Codexは次の関数をPowerShellセッションへ定義して使用する。

```powershell
function Invoke-ScreenDesignMaker {
  param([Parameter(Mandatory)] [hashtable] $Request)

  $json = $Request | ConvertTo-Json -Depth 100 -Compress
  $requestBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
    '.', 'ScreenDesignMaker.v1',
    [System.IO.Pipes.PipeDirection]::InOut,
    [System.IO.Pipes.PipeOptions]::None)
  try {
    $pipe.Connect(5000)
    $pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Message
    $pipe.Write($requestBytes, 0, $requestBytes.Length)
    $pipe.Flush()
    $buffer = [byte[]]::new(65536)
    $response = [System.IO.MemoryStream]::new()
    do {
      $count = $pipe.Read($buffer, 0, $buffer.Length)
      if ($count -gt 0) { $response.Write($buffer, 0, $count) }
    } until ($pipe.IsMessageComplete)
    [System.Text.Encoding]::UTF8.GetString($response.ToArray()) |
      ConvertFrom-Json -Depth 100
  }
  finally {
    if ($null -ne $response) { $response.Dispose() }
    $pipe.Dispose()
  }
}
```

## 共通応答

成功:

```json
{
  "protocol": "ScreenDesignMaker",
  "protocol_version": 1,
  "command": "get_editor_state",
  "status": "ok"
}
```

失敗:

```json
{
  "protocol": "ScreenDesignMaker",
  "protocol_version": 1,
  "command": "replace_document",
  "status": "error",
  "error": {
    "code": "state_changed",
    "message": "The editor document changed. Get a new snapshot before retrying."
  }
}
```

失敗時は内容を推測して再試行せず、`error.code`と`error.message`を確認する。

## 命令

### get_capabilities

利用可能な命令、Pipe名、要求上限を取得する。追加フィールドは不要。

```powershell
Invoke-ScreenDesignMaker @{ command = 'get_capabilities' }
```

### get_editor_state

キャンバス寸法、レイヤー数、選択数、Undo／Redo可否と現在の`state_token`を取得する。

```powershell
Invoke-ScreenDesignMaker @{ command = 'get_editor_state' }
```

### get_document

現在の完全なDocumentを取得する。応答の`snapshot.document`が編集対象、
`snapshot.state_token`が同時編集検出用トークンである。

```powershell
$snapshot = Invoke-ScreenDesignMaker @{ command = 'get_document' }
$document = $snapshot.snapshot.document
$stateToken = $snapshot.snapshot.state_token
```

Documentの現行スキーマはこの応答自体を正本とする。固定のサンプルJSONを新規作成して送らず、必ず取得した
Documentを変更する。これによりバージョン更新、未知のレイヤー属性、グループ、フィルターを保持する。

### preview_replace_document

Document全体を一時Documentへ読み込み、現行スキーマとして妥当か検証する。編集画面は変更しない。

```powershell
$preview = Invoke-ScreenDesignMaker @{
  command = 'preview_replace_document'
  state_token = $stateToken
  document = $document
}
```

成功時は`change.applied=false`、現在との差を示す`change.changed`、正規化後の`state_token`が返る。

### replace_document

検証済みDocumentを開いている編集画面へ反映する。変更全体は1回のUndoになる。

```powershell
$result = Invoke-ScreenDesignMaker @{
  command = 'replace_document'
  state_token = $stateToken
  document = $document
  apply = $true
}
```

`apply: true`がなければ拒否される。適用時はグループ内部の一時編集状態を閉じ、Documentの保存済み選択へ
戻す。内容が現在と同一なら成功するがUndo項目は追加しない。

### undo / redo

現在の編集履歴を1段移動する。直前に`get_editor_state`または`get_document`で取得した`state_token`と
`apply: true`が必要である。

```powershell
Invoke-ScreenDesignMaker @{
  command = 'undo'
  state_token = $currentStateToken
  apply = $true
}
```

Codexが行った一括置換以外に、ユーザーの手操作も同じ履歴へ入る。何を戻すか不明な場合は実行しない。

## 画像と配置を扱う追加命令

### get_canvas_snapshot

```powershell
$result = Invoke-ScreenDesignMaker @{ command = 'get_canvas_snapshot'; max_edge = 1280 }
$snapshot = $result.snapshot
$document = $snapshot.document
$stateToken = $snapshot.state_token
$backgroundToken = $snapshot.background_token
```

`max_edge`は64～2048の整数、既定1280。元のキャンバスより拡大せず、縦横比を維持する。
選択枠、ガイド、ツールパネル、スクロール、編集ズームを含まない。
`snapshot.images`は以下を返す。

- `base_image_path`: AviUtl2参照背景、またはキャンバス背景色／透明画像。
- `overlay_image_path`: Documentの全表示レイヤーを通常レンダラーで描いた透明PNG。
- `composite_image_path`: 上記2画像を合成したPNG。
- `has_reference_background`: AviUtl2等の参照背景の有無。通常の画像レイヤーはoverlay側に含まれる。
- `pixel_width`、`pixel_height`、`canvas_width`、`canvas_height`。
- `mapping`: 左上端を原点とする画像座標から、中央原点・右向きX・下向きYのDocument座標への変換。

`document_x = pixel_x * document_x_per_pixel + document_x_offset`、Yも同じ式を使う。
ピクセル中心を指定するなら整数添字へ0.5を足す。縮小時の丸めがあるためX／Yそれぞれの倍率を使う。
透明部分には市松模様を焼き込まない。参照背景は編集画面と同様にキャンバス全域へ配置する。

### render_preview

```powershell
$preview = Invoke-ScreenDesignMaker @{
  command = 'render_preview'
  state_token = $stateToken
  background_token = $backgroundToken
  document = $document
  max_edge = 1280
}
```

現在の文書、選択、履歴を変えず、検証済みの一時Documentを描画する。
応答形式は`get_canvas_snapshot`と同じで、`snapshot.document`は正規化された変更案。
`snapshot.state_token`は元文書、`candidate_state_token`は変更案のハッシュである。
**適用時の競合検出には元の`state_token`を使い、candidateのトークンに交換しない。**

```powershell
Invoke-ScreenDesignMaker @{
  command = 'replace_document'
  state_token = $stateToken
  background_token = $backgroundToken
  document = $preview.snapshot.document
  apply = $true
}
```

画像・DocumentはVCLスレッド上の同じ要求で取得する。参照背景のトークンは背景設定のたびに変わる。
外部の参照画像ファイルを別アプリで書き換えた場合の検出までは、このトークンには含めない。

### measure_text / list_fonts

```powershell
Invoke-ScreenDesignMaker @{ command = 'list_fonts' }
Invoke-ScreenDesignMaker @{
  command = 'measure_text'; text = "大きな見出し`n補足の文字"
  font_family = 'Yu Gothic UI'; font_size = 80
  max_width = 600; max_height = 240
  bold = $true; italic = $false
  letter_spacing_ratio = 0; line_spacing_ratio = 0
}
```

`list_fonts`はWindowsのフォントファミリー一覧を返す。計測は実際のSkia組版を使い、
`font_family_resolved`に解決されたファミリー、`lines`に表示行・行幅・ベースラインを返す。
`width`、`height`、`line_count`、`fits_width`、`fits_height`で枠への収まりを確認する。
max_width／max_heightは0で無制限。max_widthは実際に折り返しへ使い、max_heightは収まり判定だけに使う。
文字数はUTF-16で4096以下、font_sizeは1～4096、幅と高さは0～100000。
字間比率は-0.5～1、行間比率は-0.5～3で、Documentと同じ範囲とする。
計測対象は変形前の通常横書き文字。個別字間、文字パス、射影変形、縁取り・影の実描画範囲は含めない。
最終的なはみ出しや可読性は必ず合成プレビューで確認する。

### get_layout_geometry / get_creation_schema

- `get_layout_geometry`は`geometry.state_token`と各レイヤーの`layer_path`、名前、可視状態、
  ロック、不透明度、変形後の軸平行外接範囲を返す。パスは`/layers/0/layers/1`のような
  現在のDocument JSON内の位置であり、永続IDではない。縁取りや影は範囲に含めない。
- `get_creation_schema`は完全なJSON Schemaではなく、現行モデルとWriterで生成した作成例を返す。
  `schema.example_document.layers`から必要な文字（縁取り・影付き）、四角、楕円、三角形Shapeを複写して
  最新Documentへ追加する。作成例のDocument全体で既存文書を置き換えてはいけない。
  色の整数値はDelphi TColorの`0x00BBGGRR`で、通常の`0xRRGGBB`とは赤青が逆である。

## サムネイル制作時の規則

- ユーザーが指定していない既存レイヤーを削除しない。
- キャンバス寸法は依頼がない限り変更しない。
- レイヤー配列の順序が描画の重なり順に影響するため、背景、装飾、画像、文字の順序を確認する。
- 画像レイヤーは実在するローカルファイルを参照し、相対パスを作らない。
- テキストは日本語、明示改行、フォント、字間、行間、塗り、縁取り、影をDocumentの既存形式で指定する。
- 座標と範囲はキャンバスの文書座標で扱い、画面上のズーム座標を混ぜない。
- 1回の依頼に関係する変更は1つのDocumentへまとめ、何度も部分適用しない。
- 初回案の適用後は、ユーザーが編集画面を見て伝えた修正を数値へ反映する。
- 背景と合成画像を実際に読み、人物・顔・商品・既存文字の保護領域と、文字を置ける候補領域を判断する。
  単なる単色領域を空きと扱わず、被写体の意味とユーザーの意図を優先する。
- 空き領域の判断はCodex側で行う。アプリ側の顔検出・意味解析エンジンは追加していない。
  AIによる境界推定には余裕を持たせ、文字計測と合成プレビューで確認・修正する。
- プレビューは全体の構図に加え、小さく表示した場合の読みやすさも確認する。
  画像を読み込めない場合は視覚確認済みと報告しない。

## 実制作から得た知識（2026-09-15）

以下は実際のAviUtl2編集画面で確認した事実と、そこから得た制作上の判断である。
画像、座標、フォント、配色を固定プリセットとして扱わず、次の依頼の最新状態へ合わせる。

### 別環境での開始方法

- 本書のPowerShell接続関数を定義して使用する。過去の作業環境にあった
  `Win64/AutomationTests/pipe-helper.ps1`などの一時スクリプトは配布物の前提にしない。
- 掲載の`ConvertFrom-Json -Depth`を使う例はPowerShell 7向けである。実行環境を確認する。
- `get_capabilities`で画像関連命令が利用できることを確認する。未対応なら旧版の可能性を報告し、
  画像を取得・確認できたと装わない。
- PNGの絶対パスは編集アプリが動いているPC上のもの。別PCから操作する場合、パス文字列だけでは
  画像を閲覧できない。画像をモデルへ渡す手段が必要であり、現在のPipe自体もローカル接続である。
- ローカルファイルを読めるCodexでは、返されたPNGを画像閲覧ツールで開く。
  ツール名が異なる環境でも「画像を実際に入力として読む」という手順は省略しない。

### オブジェクトが0件でも背景は存在する

- 実例では`document.layers`が空でも`has_reference_background=true`で、AviUtl2に置いた画像を
  `base_image_path`から取得できた。オブジェクト一覧だけで「画像がない」と判断しない。
- この背景を編集用の画像レイヤーとして追加し直す必要はない。参照背景を見ながら、文字・図形だけを
  Documentに追加する。背景の移動・拡大・トリミングをDocumentの画像操作として試みない。
- 初回は画像の周囲に黒い余白があったが、次の依頼では画像が画面全体へ拡大され、レイヤーも空に
  なっていた。会話が続いていても前回の背景・配置が残っているとは限らない。
  修正依頼ごとに画像とDocumentを再取得し、過去の案をそのまま再送しない。

### 空き領域と人物の保護領域を分ける

- 背景を見て、顔だけでなく髪、身体、手、服まで含めた人物の輪郭を大まかに把握する。
  「人物に重ねない」という指定では、文字本体に加え縁取り・影もこの領域から離す。
- 空き領域は無地の場所に限定しない。初回は黒い余白と壁面を利用した。大きなタイトルを求められた
  次の案では、人物の左右にあるモニターや机の領域を利用した。背景の何を保護するかは依頼次第であり、
  全モニターを常に避ける、といった固定規則にはしない。
- 「余白をなくす」は、人物の上まで文字で埋めることではない。人物の周囲と画面端に必要な余裕を
  残し、利用可能な領域を大きな文字で活用する。元画像の黒帯を消す操作とは区別する。
- 中央に人物がいる構図では、タイトルを左右へ分ける方法が有効だった。
  実例は左に「ふたりの」「編集」、右に「スタ」「ジオ」。これは当該画像での例であり、
  別の文言では意味のまとまりと読む順番を優先して分割する。
- 画像上の候補矩形は毎回`mapping`でDocument座標へ変換する。
  実例の1280×720画像／1920×1080文書では倍率1.5、オフセット(-960, -540)だったが、
  この数値を他のキャンバスや縮小プレビューへ流用しない。

### フォント一覧への掲載と実際の解決先は異なる

- `list_fonts`に名前があっても、Skiaがその名前で同じ書体を使えるとは限らない。
  候補ごとに`measure_text`を呼び、`font_family_requested`と`font_family_resolved`を照合する。
- 実環境では`Noto Sans JP Black`と`AR Gothic1 Heavy`の指定が`Yu Gothic UI`へフォールバックした。
  `Noto Sans JP`は同名に、`ＤＦ特太ゴシック体`は内部名`DFGothic-EB`に解決された。
  日本語名と内部名が違うだけの場合もあるため、名前の不一致だけで失敗とは決めない。
- 最終案では`ＤＦ特太ゴシック体`を使った。別環境での存在は保証されないので、利用可能な太い書体を
  改めて確認する。特定フォントのインストールをこの制作手順の前提にしない。
- 計測値は組版の参考であり、最終的な見た目の大きさではない。Documentのテキスト枠や変形モードに
  よって表示が変わるため、`fontSize`だけで調整を終えず、枠と合成プレビューも確認する。

### 縮小されても読めるタイトルにする

- 長い説明文を並べるより、主要な語を短く分けて大きくする。重要語の面積を増やし、補足は小さくする。
  今回は「編集」を黄色、「スタ」を白、「ジオ」を青緑にして、濃紺の縁取りと影を付けた。
- 実例の縁取り幅13.5、影のX移動4.5／Y移動9、ぼかし4.5は1920×1080のDocument座標値。
  別の寸法・文字サイズでは縮小表示を見ながら調整し、同じ値を無条件に使わない。
- 読みやすさのための四角い背景帯は必要な場所に限る。試案の左右を暗くする大きな矩形は、画像を
  縦に分断して見せたため、適用前に取り除いた。最終案では太い縁取りと影だけでも読めた。
- 通常サイズの`render_preview`で人物への重なり、文字切れ、重なり順を確認した後、
  同じ案を`max_edge=320`でも描画して実際に読む。横長16:9なら320×180になる。
  この縮小描画のためにDocumentのキャンバス寸法や文字座標を変更しない。
- 小さい画像で読めなければ、適用前に文字量、枠、太さ、縁取り、配色を見直す。
  プレビューの修正は何度行ってもよいが、編集画面への適用は完成案を1回にまとめる。

### 適用後の確認と引き継ぎ

- `replace_document`成功後にも`get_canvas_snapshot`を取得する。返された文書のトークンと
  適用結果のトークン、背景トークンを照合し、同じ状態を確認しているか確かめる。
  差があればユーザーの手操作などが入った可能性を考え、古い案で再上書きしない。
- 文字と装飾は別レイヤーとして残す。新規レイヤーに役割が分かる名前を付けるが、名前は永続IDではない。
  次の修正では最新Documentから対象を確認し、無関係な既存レイヤーを保持する。
- ユーザーには配置場所と工夫、編集画面への反映結果を簡潔に伝える。
  今回の一括変更は1件のUndoになるが、後から手操作が入った場合はそれが履歴の先頭になり得る。
- この節は実操作の知識を別のCodexへ渡すための記録であり、モデル自体を再学習したという意味ではない。
  画像・トークン・フォント・座標は次のセッションで再確認する。

## 現在の制限

- 初版はDocument全体の取得・検証・置換であり、レイヤー単位の永続ID操作ではない。
- PNGはローカルファイルで返し、Pipeへ画像のBase64や生ピクセルを詰め込まない。
- Pipeのアクセス範囲はローカルWindowsの既定Named Pipeセキュリティに従う。
- 1要求中に複数の独立したUndo単位は作れない。
- 編集画面が複数ある場合、最初にPipeを取得した画面だけが操作対象となる。
- レイヤー単位の永続ID操作と自動的な被写体マスク生成は未実装。
