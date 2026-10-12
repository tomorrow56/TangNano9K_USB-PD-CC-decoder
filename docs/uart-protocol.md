# TN9K PD UART record v1

バイナリ固定52 byte、8N1。整数・CRC格納はlittle endian。

| Offset | Size | 内容 |
|---:|---:|---|
| 0 | 2 | A5 5A |
| 2 | 1 | version=1 |
| 3 | 1 | kind |
| 4 | 1 | flags |
| 5 | 1 | 有効raw長 0〜34 |
| 6 | 2 | sequence（捨てたイベントでも加算） |
| 8 | 4 | SOP認識時の27 MHz cycles |
| 12 | 4 | FIFO満杯で捨てた累積イベント数 |
| 16 | 34 | raw：header 2byte → data objects → 受信CRC32 4byte、余白0 |
| 50 | 2 | CRC16/CCITT-FALSE：offset 2〜49、poly=1021 init=FFFF xorout=0 refin=false |

kind：0 SOP / 1 SOP′ / 2 SOP″ / 3 SOP′ Debug / 4 SOP″ Debug / 5 Hard Reset / 6 Cable Reset。

flags：bit0=CRC32 residue一致、bit1=不正4b5bまたは最大長超過、bit2=EOP前の信号中断/不正間隔、bit3=ヘッダNDOに対する長さ不一致または半byteでEOP。他は0。

Resetはraw長0、flags=0、CRC32検査なし。エラーでも取得済みbyteを送ります。bit0だけで有効判定せずbit1〜3と長さも確認してください。

USB PD CRC32：反射poly=EDB88320、init=FFFFFFFF、xorout=FFFFFFFF。CRC含む全体の非反転状態DEBB20E3で一致。既知ベクタ123456789はCBF43926。

52byteごとに固定切り出しせず、A5 5A→version/kind/len→CRC16確認で同期してください。不正なら1byte進め再探索します。payloadにもA5 5Aが出現します。WebのStreamParserで実装済み。

時刻uint32周回の差分は `(newTicks-oldTicks)>>>0` を27e6で割ります（1周以内の間隔）。再起動でseq・timestamp・droppedは0へ戻ります。
