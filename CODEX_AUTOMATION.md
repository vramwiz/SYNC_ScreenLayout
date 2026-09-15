# ScreenDesignMaker Codex操作仕様

この文書は、開いているScreenDesignMaker／「画面レイアウト - 編集」をCodexから操作するための
必須手順とJSON命令を定義する。操作を始めるCodexは最初に本書を最後まで読むこと。

## 目的と前提

- 対象は現在開いている1つのScreenLayout編集画面である。
- 通信先はローカルNamed Pipe `\\.\pipe\ScreenDesignMaker.v1` である。
- 文字コードはUTF-8、通信単位はMessage、要求と応答はJSONオブジェクトである。
- 編集画面が閉じている場合、Pipeは存在しない。
- 同時に操作できる編集画面とクライアントはそれぞれ1つだけである。
- 画像生成や完成PNGの返送は行わない。適用結果はユーザーが開いている編集画面で確認する。
- 最大要求サイズは4 MiBである。

## 絶対に守る操作手順

1. `get_capabilities`で接続先とプロトコルを確認する。
2. `get_document`で最新Documentと`state_token`を取得する。
3. 取得したDocumentを基礎に、依頼された箇所だけを変更する。未知のフィールドを削除しない。
4. 同じ`state_token`と変更後Documentを`preview_replace_document`へ送り、検証成功を確認する。
5. ユーザーが編集を依頼している場合に限り、同じ内容を`replace_document`へ送り、`apply: true`を付ける。
6. `status: "ok"`、`change.applied: true`、新しい`state_token`を確認する。
7. ユーザーに編集画面で結果を確認してもらい、修正指示があれば必ずDocumentを再取得する。

取得後にユーザーまたは別処理がDocumentを変更すると`state_changed`になる。その場合、古いDocumentを
再送して上書きせず、必ず`get_document`からやり直す。

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

## サムネイル制作時の規則

- ユーザーが指定していない既存レイヤーを削除しない。
- キャンバス寸法は依頼がない限り変更しない。
- レイヤー配列の順序が描画の重なり順に影響するため、背景、装飾、画像、文字の順序を確認する。
- 画像レイヤーは実在するローカルファイルを参照し、相対パスを作らない。
- テキストは日本語、明示改行、フォント、字間、行間、塗り、縁取り、影をDocumentの既存形式で指定する。
- 座標と範囲はキャンバスの文書座標で扱い、画面上のズーム座標を混ぜない。
- 1回の依頼に関係する変更は1つのDocumentへまとめ、何度も部分適用しない。
- 初回案の適用後は、ユーザーが編集画面を見て伝えた修正を数値へ反映する。
- 見た目をCodex自身が取得する命令はない。画像内容、顔位置、文字切れ、可読性を見たと断定しない。

## 現在の制限

- 初版はDocument全体の取得・検証・置換であり、レイヤー単位の永続ID操作ではない。
- PNGや画面キャプチャは返さない。
- Pipeのアクセス範囲はローカルWindowsの既定Named Pipeセキュリティに従う。
- 1要求中に複数の独立したUndo単位は作れない。
- 編集画面が複数ある場合、最初にPipeを取得した画面だけが操作対象となる。
- 参照画像の内容解析は行わない。

