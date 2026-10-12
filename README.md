# Tang Nano 9K / USB PD CC decoder

既存受信回路のデジタルBMC出力を入力し、USB PDパケットをUART経由でWeb Serial画面へ送る受信専用の試作実装です。

**実装・シミュレーション済み。Gowinでの合成・配置配線と実機接続は未検証です。ビットストリームは含みません。**

## 構成

```text
観測対象CC → 既存CC受信回路 → 1.2V BMC
                               ↓
                   SN74AXC1T45等で1.2V → 3.3V
                               ↓
Tang Nano 9K pin 25 → 同期化 → BMC → SOP → 4b5b → CRC32
                                                   ↓
                                         8件FIFO → UART TX
                                                   ↓ pin 17
                                        基板上BL702 USB-UART
                                                   ↓ USB
                                     Chrome / Edge Web Serial
```

CCへの送信、GoodCRC応答、Rp/Rd制御は行いません。PD通信に参加しないスニファです。

## 1. 配線

**0〜1.2VロジックBMC出力**を前提にします。振幅1.2VでもDCオフセットのあるアナログ信号の場合は、そのまま接続せず出力規格を確認してください。

1.2V出力を1.8V I/Oへ直接入れる案は、受信側VIHと送信側VOHの最悪条件が未確認のため採用していません。I/O規格の設定だけでは基板のVCCIO電源は変わりません。本実装は3.3V GPIOを使います。

SN74AXC1T45の接続例（端子番号は使用パッケージのデータシート参照）：

| 信号 | 接続 |
|---|---|
| VCCA | 安定した1.2V電源（既存回路側） |
| VCCB | Tang Nano 9Kの3.3V |
| GND | 既存回路・Tang Nanoと共通 |
| DIR | VCCAへ接続（A→B固定） |
| A | 既存回路の1.2VロジックBMC出力 |
| B | Tang Nano 9Kの基板表示25（FPGA pin 25） |
| デカップリング | VCCA/GND、VCCB/GNDそれぞれ100nFをIC近傍へ |

レベル変換ICは生のCCラインへ接続しません。ユーザー指定の**既存受信回路の出力後段**に入れます。1.2V電源を使用できない場合は回路側の出力電源とVOH/VOLを確認して別方式を選んでください。

- 1ch実装。既存回路で選択したCC1またはCC2の出力を入力します。CC1とCC2を短絡してまとめないでください。
- 基板USB-Cは書き込み・UART用で、観測対象のCC入力ではありません。
- pin 17はFPGA TX→基板上BL702のUART入力。既定では基板USBから受信します。
- 外付け3.3V USB-UARTなら、CSTのTXを空いている3.3V GPIOへ変更し、RXと共通GNDを接続します。

## 2. FPGAビルド

Gowin EDAで新規FPGAプロジェクトを作成します。

1. 実機表示に対応するデバイス（通常GW1NR-LV9QN88PC6/I5、GW1NR-9C系）を選択。
2. `rtl/`の5個のVerilogファイルを追加し、top moduleを`top`に指定。
3. `constraints/tangnano9k.cst`と`constraints/tangnano9k.sdc`を追加。
4. Synthesize → Place & Route → Generate Bitstreamを実行。
5. 27 MHzに対するタイミング、I/Oバンク電圧、リソース使用量を確認。
6. Gowin ProgrammerでまずSRAMへ書き込み。安定動作を確認してから必要に応じFlashへ。

pin 52の27 MHzクロックを使用しPLLは不要。電源投入時のレジスタ初期値で約38µsの内部リセットを生成します。使用合成ツールが初期値を反映することを確認してください。

UARTは**921600 baud / 8N1 / フロー制御なし**が既定。分周29の実速度は931034 baud（+1.02%）。USB-UARTが安定しない場合は`record_tx`のUART_DIVを234にして115200 baud（実115385）で再合成できますが、欠落が増えます。外付けUARTで1000000 baudを使うならDIV=27で誤差0です。**画面の速度選択ではFPGAの速度は変わりません。**

## 3. Webアプリ

Nodeパッケージのインストールは不要。Python 3を使います。

```sh
cd tangnano9k-pd
python3 -m http.server 8000 --bind 127.0.0.1 --directory web/dist
```

Chrome / Edgeのデスクトップ版で `http://127.0.0.1:8000` を開き、921600を選び「シリアルに接続」からポートを選択します。Web SerialはHTTPSまたはlocalhostで利用します。埋め込み画面で接続できない場合は通常のChrome/Edgeタブを使ってください。

- デモ：ハードウェアなしでSource_Capabilities → Request → Accept → PS_RDYを表示。
- 行選択：ヘッダ、メッセージID、役割、PD revision、CRCを含むHEX、PDO/RDO表示。
- PDエラー、FPGA欠落数、UARTフレームCRCエラー表示。
- JSON保存・再読込、UARTバイナリ`.bin`読込（サンプルは`examples/`）。
- 保持・保存は最新2,000件。無制限の長時間収録ではありません。
- アプリコードは受信ログをサーバーへ送信せずブラウザ内で処理します。

## 4. 実装範囲と制限

- BMC 300 kbit/s、SOP / SOP′ / SOP″ / Debug、Hard Reset / Cable Reset。
- 4b5b、LSB-first、ヘッダ＋最大7データオブジェクト＋CRC32（最大34 byte）。
- FPGAとJSの両方でCRC32と長さを検証。
- 制御/データメッセージ名、Fixed/Variable/Battery/PPS PDO、RDO object position。RDO電流値は対応PDO依存なので推測しません。
- Extendedはヘッダとraw。チャンク再構成、26 byteを超える非チャンクExtended、EPR固有PDO詳細、VDM詳細、交渉ステートマシンは未実装。
- 電気的な送信方向判別は行いません。SOPのヘッダ役割を送信元の参考にします。
- 時刻はSOP認識時の27 MHzカウンタ。約159.073秒で周回。絶対時刻ではありません。
- BMCはエッジ間隔分類の簡易方式。PLL・適応等化・厳密な64bitプリアンブル検証はありません。32bit以上の復号履歴後に20bitのordered setを探索します。ノイズで偶然一致する可能性があります。
- FIFOは8件＋送信中1件。満杯時は新規イベントを捨てます。UART上限は約1,790件/秒。高密度通信を無欠落で保証しません。累積欠落値は**次に格納できたイベント**で通知するため、通信停止直前の欠落は次のイベントまで分かりません。
- seqは欠落でも増加（16bit周回）。UART破損はCRC16で検出しますが、丸ごと失われたレコードはUART FRAME ERRORSで数えません。seqの飛びも確認してください。
- 受信回路の帯域・閾値・ノイズ耐性、変換後の波形、BL702のbaud対応は実機確認が必要です。

## 5. 検証

Icarus Verilog (`iverilog`, `vvp`)、Python 3、Node.js 18以上が必要です。

```sh
python3 sim/test.py
node sim/protocol.test.mjs
```

39波形ケース：SOP各種、270/300/約329 kbit/s、両極性、最大長、Extended、CRC不一致、長さ不一致、欠落EOP、不正symbol、Reset。RTLのUART TXをビット単位で受信して、実際のWebパーサで照合します。別途FIFOオーバーフロー/回復、UART分割受信、バイト欠落・破損再同期、既知CRCベクタ、PDO表示を検証。

テストクロックはシミュレーション用ですが、すべてクロック周期数で波形生成・照合し実機と同じ分周比を検証します。

**未検証：実機信号、ジッタ限界、Gowin合成/配置配線、実シリアル接続。**

## ファイル

- `rtl/bmc_rx.v`：入力同期、エッジ→bit
- `rtl/pd_rx.v`：ordered set、4b5b、CRC32
- `rtl/record_tx.v`：FIFO、UARTフレームCRC16
- `rtl/uart_tx.v`：8N1 UART
- `rtl/top.v`：接続とPOR
- `web/dist/`：Web Serial画面
- `docs/uart-protocol.md`：UART仕様
- `sim/`：回帰テスト

## 参照

- [Sipeed Tang Nano 9K](https://wiki.sipeed.com/hardware/zh/tang/Tang-Nano-9K/Nano-9K.html)：ボード/27 MHz/BL702
- [Sipeed UART例](https://wiki.sipeed.com/hardware/zh/tang/Tang-Nano-9K/examples/lushaylabs/2_debugging_uart/debugging_uart.html)：CSTのTX pin 17、clock pin 52。本文にはTX/RXの不一致がありCSTを採用。
- [Sipeed GPIO例](https://wiki.sipeed.com/hardware/zh/tang/Tang-Nano-9K/examples/lushaylabs/3_oled_101/oled_101.html)：pin 25
- [USB-IF仕様](https://www.usb.org/documents?category%5B49%5D=49)：本実装は全仕様準拠を主張しません。
- [sigrok USB PD decoder](https://github.com/sigrokproject/libsigrokdecode/blob/master/decoders/usb_power_delivery/pd.py)：符号表・ordered set照合先。RTL/JSは本プロジェクト用の独立実装。
- [TI SN74AXC1T45](https://www.ti.com/lit/gpn/SN74AXC1T45)：レベル変換・電源・DIR
- [Chrome Web Serial](https://developer.chrome.com/docs/capabilities/serial)：接続と切断
