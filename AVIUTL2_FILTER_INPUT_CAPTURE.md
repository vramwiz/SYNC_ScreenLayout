# AviUtl2 の設定ボタンからフィルター入力を1枚取得する

## 採用方式

タイムライン停止中に設定欄のボタンを押したら、対象を識別できる1回分の要求を登録し、同じコールバック内で現在と同じレイヤー・フレームを `EDIT_SECTION::set_cursor_layer_frame()` に渡す。対象の `func_proc_video` が実行されたら、重ね描きの前に `FILTER_PROC_VIDEO::get_image_data()` で入力 RGBA を1枚取得する。

この方法は AviUtl ExEdit2 **v2.1.18b**（初期化引数 `2011802`）と **2026-11-14 公開の公式 SDK** で動作を確認した。異なる本体バージョンでは、同じ位置の指定でフィルターが再実行されるかを再検証する。[AviUtl のお部屋・公式 SDK 配布元](https://spring-fragrance.mints.ne.jp/aviutl/)

## 別プロジェクトへ移植する手順

1. `FILTER_ITEM_BUTTON::callback2` を使い、ボタンに渡されたオブジェクトとエフェクトを対象にする。`edit->info` からシーン ID、カーソルのレイヤーとフレームを、`get_object_layer_frame()` から対象オブジェクトのレイヤーと区間を取得する。`get_object_id()` と `get_effect_id()` で対象を識別し、ハンドルの代わりに ID を保存する。SDK のフレーム番号とレイヤー番号は 0 始まり。
2. 停止中で、カーソルが対象オブジェクトの有効区間内にあるときに、要求 ID と対象情報を共有状態に登録する。要求は複数の描画スレッドから同時に消費されないようにする。**要求のロックを解放してから** `edit->set_cursor_layer_frame(edit->info->layer, edit->info->frame)` 相当を呼ぶ。呼び出し前にコピーした値を使う。エフェクトの所属レイヤーとカーソルのレイヤーにはそれぞれ別の値を保持する。
3. `func_proc_video` の入口で、未処理の要求があるときだけ、シーン・起点シーン・起点フレーム（`OBJECT_INFO::origin_frame`）・対象レイヤー・オブジェクト ID・エフェクト ID を照合する。参照フレームは除外する。一致した要求をロック内で一度だけ消費し、ロックを解放してから画像を読む。
4. `OBJECT_INFO::width / height` を検証し、`width × height × sizeof(PIXEL_RGBA)` の所有バッファを確保する。`get_image_data()` は、自分の描画、シェーダー実行、`set_image_data()` より先に呼ぶ。ホストが渡したポインターはコールバックをまたいで保持しない。
5. コピーした画像と要求 ID を `PostMessage` などで UI スレッドへ渡す。UI は現在の要求 ID と一致する画像だけ採用する。失効やウィンドウ破棄時には未処理要求を取り消し、到着済みの古い画像を破棄する。ボタン内で描画完了を待たない。タイムアウトを置く場合は要求の破棄にのみ使う。

Delphi ではボタンとフィルター入口を次の順序にできる。`Arm` と `Claim` が内部でロックを管理する。

```pascal
// FILTER_ITEM_BUTTON.callback2
if ReadTarget(Edit, Obj, Effect, Target, EffectHandle) then
begin
  Capture.Arm(Target, RequestID);
  Edit^.SetCursorLayerFrame(Target.CursorLayer, Target.Frame);
end;

// func_proc_video の入口
Token := Capture.Claim(Video);
if Token <> 0 then
  if CopyFilterInput(Video, Token, Frame) then
    PublishToUi(Frame);
```

既存の素材に適用したフィルターでは、その素材に対する直前の処理結果を取得できる。全画面の下位レイヤーを基準に描く用途では、フィルタオブジェクトに配置し、そのフィルターに実際に渡された入力を使う。メディア入力オブジェクトの `get_image_data()` で下位レイヤー全体を取得できるという根拠にはならない。

共有処理は [DrawMarker_Capture.pas](Source/Plugin/Filter/DrawMarker_Capture.pas)、実機検証用ボタンの実装は [DrawMarker_CaptureProbe.dpr](Tests/DrawMarker_CaptureProbe.dpr) を参照。

## 実機結果

2026-11-19。ポータブル版を別の `data` フォルダーで起動し、320 × 180 の PNG の画像オブジェクトに前段フィルターと検証フィルターを適用した。前段は全画素を RGBA `16,192,32,255`、検証フィルターは取得後に `220,24,24,255` に変更した。停止位置は Layer 1・16 フレーム目（SDK 上は `layer=0, frame=15`）。同一位置で各ボタンを続けて押し、画素数、UI 受信回数、タイトルの編集済みマーク、編集メニューと Undo 後の値を確認した。

| 方式 | 再実行と入力取得 | カーソル位置 | 編集済み状態・Undo |
| --- | --- | --- | --- |
| A　要求登録のみ | 2回とも到達・取得なし | 同じ | 編集済みマークなし。Undo 項目は無効 |
| B　同じレイヤー・フレームを指定 | 2回とも1枚。57,600画素すべて前段の色。クリックから UI 受信まで約7・9 ms | 同じ | 編集済みマークなし。Undo 項目は無効 |
| C　`set_effect_item_value()` で同じ値を再設定 | 2回とも1枚。全画素一致 | 同じ | 編集済みマークなし。Undo 項目は無効 |
| C　`set_effect_item_value()` で値を変更 | 2回とも1枚。全画素一致 | 同じ | 編集済みマークあり。Undo で検証値が 0 → 1 → 0 の逆順に戻った |
| D　`set_effect_data_value()` で非表示データを変更 | 連続2回と保存直後の追加1回でそれぞれ1枚。全画素一致 | 同じ | 保存直後の更新で編集済みマークが付いた。連続更新後の Undo で値が 2 → 1 → 0 に戻った |
| E　ボタン終了後に `rendering_scene_video()` を要求 | 編集操作を挟まない2回とも1枚。フィルター入口は全画素一致。シーン完了側では処理後の赤を確認 | 同じ | 編集済みマークなし。Undo 項目は無効 |

A の初回は約2.2秒の観測枠を満了した。2回目は約2.0秒後に次の B の要求へ切り替えた。B、C、D、E の取得成功時は UI スレッドで要求番号ごとに1枚受信した。詳細の時刻、スレッド ID、取得枚数は [capture-probe.log](Win64/HostVerification/AviUtl2/capture-probe.log)。

| 検証したファイル | SHA-256 |
| --- | --- |
| 公式 v2.1.18b の `aviutl2.exe` | `4BBFC63F457016799408E202C50A5F7330D73E71551A412CC3F9A1906F66D64A` |
| 公式 2026-11-14 版の `aviutl2_sdk.zip` | `29B1478C9C63648798B3F637E9C0A6AFD3057DFA4B71813623C33AD30471A0C0` |

## SDK の記載と観測の区別

- `plugin2.h` は `set_cursor_layer_frame()` を編集カーソルの指定 API として定義している。同じ位置を指定したときのキャッシュ無効化やフィルターの再実行は、今回の v2.1.18b で観測した挙動。
- `filter2.h` は `get_image_data()` を、現在のオブジェクト画像を VRAM から RGBA で取得する API として定義している。前段の色を取得し、後段の赤が含まれなかったことを実測した。
- `rendering_scene_video()` は非同期にシーン描画を依頼する API。完了時の画像はシーン合成後になる。同じ停止フレームを続けて要求しても対象フィルターに2回到達したことは実測結果。この方式を使う場合も入力の採取箇所はフィルター入口とする。
- B は設定値を更新する必要がなく、シーン画像の完了バッファも不要。別バージョンで B の再実行が確認できない場合は E を候補とし、フィルター入口への到達と副作用を確認する。[AviUtl ExEdit2 公式 SDK](https://spring-fragrance.mints.ne.jp/aviutl/)
