#!/usr/bin/env python3
"""Independent waveform source + Icarus Verilog full receiver / UART tests."""

from pathlib import Path
import subprocess, zlib, json

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
BUILD.mkdir(exist_ok=True)
# USB PDの4b5b符号表。送信側モデルはRTLとは独立に生成する。
ENC = [30, 9, 20, 21, 10, 11, 14, 15, 18, 19, 22, 23, 26, 27, 28, 29]
SOP = [
    [24, 24, 24, 17],
    [24, 24, 6, 6],
    [24, 6, 24, 6],
    [24, 25, 25, 6],
    [24, 25, 6, 17],
    [7, 7, 7, 25],
    [7, 24, 7, 6],
]


def bits(s):
    return [(s >> i) & 1 for i in range(5)]


# Python標準ライブラリのCRC32を期待値に使う。
def packet(body):
    return body + list(zlib.crc32(bytes(body)).to_bytes(4, "little"))


cases = []


def add(name, raw, kind=0, half=45, pol=0, flags=1, tail=None):
    seq = [0, 1] * 32 + sum([bits(s) for s in SOP[kind]], [])
    if kind < 5:
        seq += sum([bits(ENC[b & 15]) + bits(ENC[b >> 4]) for b in raw], [])
        seq += bits(13) if tail is None else tail
    cases.append(
        dict(name=name, raw=raw, kind=kind, half=half, pol=pol, flags=flags, bits=seq)
    )


add("Source capabilities", packet([0x61, 0x11, 0x2C, 0x91, 1, 0]))
for kind in range(5):
    for half in [41, 45, 50]:
        for pol in [0, 1]:
            add(f"kind{kind}-half{half}-pol{pol}", packet([0x81, 0]), kind, half, pol)
add("all nibbles max payload", packet([0x81, 0x70] + list(range(28))))
add("extended chunk", packet([0x81, 0x90, 1, 0x80, 0xAA, 0]))
add("bad CRC", packet([0x81, 0])[:-1] + [0], flags=0)
add("bad length", packet([0x81, 0x10]), flags=9)
add("truncated", packet([0x81, 0]), flags=4, tail=[])
add("illegal 4b5b", packet([0x81, 0]), flags=2, tail=bits(0))
add("hard reset", [], kind=5, flags=0)
add("cable reset", [], kind=6, flags=0)
# Every packet has settling idle; shortened alternating preamble acquisitions are not assumed.
body = []
# 各bitの先頭で反転し、1の場合のみ半UI位置でも反転させる。
for c in cases:
    body.append(f'// {c["name"]}\ncc={c["pol"]}; repeat(250) @(negedge clk);')
    for b in c["bits"]:
        body.append(
            f'cc=~cc; repeat({c["half"]}) @(negedge clk);'
            + ("cc=~cc;" if b else "")
            + f'repeat({c["half"]}) @(negedge clk);'
        )
    body.append("cc=~cc; repeat(20000) @(negedge clk);")
expect = []
for c in cases:
    data = int.from_bytes(bytes(c["raw"]).ljust(34, b"\0"), "little")
    expect.append(f"expected_kind[{len(expect)}]=3'd{c['kind']};")
    # use a separate array index below
checks = []
for i, c in enumerate(cases):
    checks.append(
        f"ek[{i}]={c['kind']};ef[{i}]={c['flags']};el[{i}]={len(c['raw'])};ed[{i}]=272'h{int.from_bytes(bytes(c['raw']).ljust(34,b'\0'),'little'):068x};"
    )
# テストベンチは期待値照合とUARTのビット単位サンプリングを行う。
tb = (
    """`timescale 1ns/1ps
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, cc = 0;
    reg [31:0] ticks = 0;
    always @(posedge clk) ticks <= ticks + 1;

    wire bv, bd, lost, ev, tx;
    wire [2:0] kind;
    wire [7:0] flags;
    wire [5:0] len;
    wire [31:0] stamp, dropped;
    wire [271:0] data;
    bmc_rx b(clk, reset, cc, bv, bd, lost);
    pd_rx p(clk, reset, bv, bd, lost, ticks, ev, kind, flags, len, stamp, data);
    record_tx r(clk, reset, ev, kind, flags, len, stamp, data, tx, dropped);

    integer n = 0, fd, j;
    reg [7:0] octet;
    reg [2:0] ek[0:99];
    reg [7:0] ef[0:99];
    reg [5:0] el[0:99];
    reg [271:0] ed[0:99];

    always @(posedge clk) if (ev) begin
        if (kind !== ek[n] || flags !== ef[n] || len !== el[n] || data !== ed[n]) begin
            $display("FAIL event %0d kind=%h flags=%h len=%d data=%h expected flags=%h",
                     n, kind, flags, len, data, ef[n]);
            $fatal;
        end
        n = n + 1;
    end

    // DIV=29: sample the start bit near its center, then every 29 clocks.
    initial begin
        fd = $fopen("uart.bin", "wb");
        forever begin
            @(negedge tx);
            repeat (14) @(posedge clk);
            if (tx !== 0) $fatal;
            for (j = 0; j < 8; j = j + 1) begin
                repeat (29) @(posedge clk);
                octet[j] = tx;
            end
            repeat (29) @(posedge clk);
            if (tx !== 1) $fatal;
            $fwrite(fd, "%c", octet);
        end
    end

    initial begin
"""
    + "\n".join(checks)
    + """
    repeat (10) @(negedge clk);
    reset = 0;
"""
    + "\n".join(body)
    + f"""
    repeat (20000) @(negedge clk);
    if (n != {len(cases)}) begin
        $display("event count %0d", n);
        $fatal;
    end
    if (dropped != 0) $fatal;
    $fclose(fd);
    $display("PASS {len(cases)} waveform cases, full UART capture");
    $finish;
    end

    initial begin
        #1000000000;
        $fatal;
    end
endmodule
"""
)
(BUILD / "tb.v").write_text(tb)
subprocess.run(
    ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", str(BUILD / "tb")]
    + [str(x) for x in sorted((ROOT / "rtl").glob("*.v"))]
    + [str(BUILD / "tb.v")],
    check=True,
)
subprocess.run(["vvp", str(BUILD / "tb")], cwd=BUILD, check=True)
(BUILD / "expected.json").write_text(
    json.dumps([{k: c[k] for k in ["name", "raw", "kind", "flags"]} for c in cases])
)
# Compile the actual board top as well, catching port/integration mistakes.
subprocess.run(
    ["iverilog", "-g2012", "-Wall", "-s", "top", "-o", str(BUILD / "top")]
    + [str(x) for x in sorted((ROOT / "rtl").glob("*.v"))],
    check=True,
)
subprocess.run(
    ["iverilog", "-g2012", "-s", "fifo_tb", "-o", str(BUILD / "fifo")]
    + [str(ROOT / "rtl" / x) for x in ["uart_tx.v", "record_tx.v"]]
    + [str(ROOT / "sim/fifo_tb.v")],
    check=True,
)
subprocess.run(["vvp", str(BUILD / "fifo")], cwd=BUILD, check=True)
