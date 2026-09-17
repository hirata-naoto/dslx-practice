DSLX RV32I コア
===============

rv32i.x は RISC-V の RV32I（32ビット整数基本命令セット）を実行する、
合成可能な命令単位の状態遷移関数です。rv32i_test.x に回帰テストがあります。
外部メモリ、クロック、状態保持レジスタは含みません。

対応命令
--------
LUI, AUIPC, JAL, JALR
BEQ, BNE, BLT, BGE, BLTU, BGEU
LB, LH, LW, LBU, LHU, SB, SH, SW
ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
FENCE, ECALL, EBREAK

32本の32ビットレジスタと32ビットPCを持ち、x0は常にゼロです。
加減算とアドレス計算は32ビットでラップします。
メモリはリトルエンディアン、命令アラインメントは4バイトです。
JALRは加算後のターゲットのビット0をクリアします。

インターフェース
----------------
reset(entry_pc) -> State
  全レジスタとトラップ情報をクリアし、PCをentry_pcに設定します。
  entry_pcが4バイト境界でなければ、次のstepでトラップします。

memory_request(state, instruction) -> MemoryRequest
  メモリ応答に依存せず、現在の命令のデータメモリアクセスを計算します。

step(state, instruction, load_data) -> StepResult
  現在のPCに対応する32ビット命令を実行し、次のstateとmemoryを返します。
  load_dataは要求アドレスから読み出した32ビットのワード全体です。
  LB/LHでも呼び出し側でシフトや符号拡張をせず、ワードをそのまま渡します。
  ロード以外ではload_dataは無視されます。

State:
  pc             現在の命令のバイトアドレス
  regs           x0..x31
  trapped        トラップ後はtrueのまま停止
  trap_cause     例外原因番号
  trap_value     不正命令、障害アドレスなど

MemoryRequest:
  valid          trueの場合のみメモリアクセスを行う
  write          true: ストア、false: ロード（validの場合）
  address        4バイト境界に整列したバイトアドレス
  write_data     書き込みレーンに合わせてシフト済みのデータ
  byte_enable    対象バイトを示す4ビットマスク（ロード・ストア共通）

byte_enable[k]はaddress+kのバイトに対応し、write_dataのビット
[8*k+7:8*k]を選択します。ストアでは有効なレーンだけを書き換え、
他のバイトを保持してください。無効レーンのwrite_dataは無視します。
例: address+3へのSBはbyte_enable=0b1000になります。

接続手順
--------
1. resetで初期化し、state.pcから命令をフェッチする。
2. memory_requestでデータメモリ要求を取得する。
3. 有効なロードなら要求ワードを読み出す。それ以外はload_data=0でよい。
4. stepで次の状態を計算する。
5. 有効なストアを一度だけ反映し、同時にstateを返された状態へ更新する。

memory_requestとstepに渡すstate/instructionは同一にしてください。
両方の返す要求は同一です。同じストアを二重に発行しないでください。
ロード先がx0でもメモリ読み出しは省略しません。

非同期読み出しメモリと外部状態レジスタを接続すれば、1命令/クロックの
構成にできます。同期RAMや可変レイテンシのバスでは外部コントローラが
応答を待ち、状態更新とストアの確定を制御する必要があります。
このモジュール自体にはready/validハンドシェイクやストール信号はありません。

例外と制約
----------
例外ではPCとレジスタを変更せず、メモリ要求を無効化します。
trapped=trueになった後のstepは状態を保持し、メモリアクセスもしません。
再開するには呼び出し側でresetしてください。

原因番号とtrap_value:
  0  命令アドレス不整列: 現在のPCまたは分岐・ジャンプ先
  2  不正命令: 命令ワード
  3  EBREAK: 現在のPC
  4  ロードアドレス不整列: 実効バイトアドレス
  6  ストアアドレス不整列: 実効バイトアドレス
  11 ECALL: 0（Mモード相当の原因番号）

LH/LHU/SHは2バイト、LW/SWは4バイト境界を要求します。
条件分岐先の不整列は分岐が成立した場合のみ検出します。
FENCEはメモリアクセスを順序どおりに完了させる上記インターフェースでは
追加処理不要なのでNOPとして扱い、予約フィールドを無視します。

M/A/C/F/D、Zicsr、Zifenceiなどの拡張命令は非対応です。
FENCE.I、CSR操作、MRETなどは不正命令として扱います。
特権モード切り替え、CSR、割り込み、例外ベクタへの遷移、MMU、キャッシュ、
メモリアクセス障害の応答には対応していません。アクセス可能なメモリを
外部から提供する前提であり、OS起動用の完全な特権アーキテクチャではありません。

テスト
------
Google XLSのLinux x64リリースに含まれるツールを使用します:
https://github.com/google/xls/releases
検証済みリリース: v0.0.0-10704-g0a7c502cc

以下のROOTはチェックアウトの絶対パス、XLSは展開先の絶対パスです。
実際の環境に合わせて変更してください。

  ROOT=/home/runner/work/dslx-practice/dslx-practice
  XLS=/tmp/xls-rv32i/xls-v0.0.0-10704-g0a7c502cc-linux-x64

  "$XLS/interpreter_main" --dslx_path="$ROOT" "$ROOT/rv32i_test.x"

17個のテストで、全対応命令、符号拡張、オーバーフロー、シフト量、
分岐条件、即値の境界、ロード・ストアの各バイトレーン、不正命令、
不整列、トラップ後の副作用抑制、1から5の和を求めるプログラムを検証します。
DSLX実行とIR JITの比較は同じコマンドに --compare=jit を追加してください。

書式チェック:
  "$XLS/dslx_fmt" --error_on_changes "$ROOT/rv32i.x"
  "$XLS/dslx_fmt" --error_on_changes "$ROOT/rv32i_test.x"

Verilog生成
-----------
  "$XLS/ir_converter_main" --top=step "$ROOT/rv32i.x" > /tmp/rv32i.ir
  "$XLS/opt_main" /tmp/rv32i.ir > /tmp/rv32i.opt.ir
  "$XLS/codegen_main" --generator=combinational \
      --output_verilog_path=/tmp/rv32i.v /tmp/rv32i.opt.ir

生成されるRTLは状態入力と次状態出力を持つ組み合わせ回路であり、
クロック付きの自己完結したCPUではありません。フィードバック用の
状態レジスタ、リセット、命令・データメモリ接続は外部に実装してください。
メモリ要求だけの回路も --top=memory_request で生成できます。
生成物はコミットせず、必要に応じて再生成してください。
RTL生成は検証済みですが、FPGA/ASICでのタイミングや実機動作は未検証です。
