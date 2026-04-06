# frozen_string_literal: true
# examples/global_dedup.rb
#
# 综合演示模块去重与子模块自动布线。
#
# 特性：
# - 自动去重: 同参数 .new() 实例化 → 同一份 SV 模板
# - 手动去重: definition() + instance() 显式共享定义句柄
# - 多参数变体: 不同参数 → 自动后缀 _1, _2, ...
# - 子模块间自动布线: 子模块输出直连另一子模块输入，父模块自动生成中间 wire
# - 左赋值 (<=) 与右赋值 (>=) 两种端口连接语法
# - 未连接端口标注: /* unused port */
# - 全局 ElaborationRegistry + RSV.export_all 一键导出
#
# Run:
#   xmake rtl -f glb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# ---------- 参数化计数器 ----------

class DedupCounter < ModuleDef
  def build(width: 8)
    let :clk, input(clock)
    let :rst, input(reset)
    let :en, input(bit)
    let :din, input(uint(width))
    let :dout, output(uint(width))

    let :r, reg(uint(width), init: 0)
    dout <= r

    with_clk_and_rst(clk, rst)
    always_ff do
      svif(en) { r <= din }
    end
  end
end

# ---------- 简单加法器 ----------

class DedupAdder < ModuleDef
  def build(width: 8)
    let :a, input(uint(width))
    let :b, input(uint(width))
    let :sum, output(uint(width))

    sum <= a + b
  end
end

# ---------- 顶层模块 ----------

class DedupTop < ModuleDef
  def build
    let :clk, input(clock)
    let :rst, input(reset)
    let :en, input(bit)
    let :data_in, input(uint(8))
    let :wide_in, input(uint(16))
    let :result, output(uint(8))

    # ── 自动去重 ─────────────────────────────────────────────
    # 两个 width=8 counter → 同一份 SV 模板（自动去重）
    cnt_a = DedupCounter.new(inst_name: "u_cnt_a", width: 8)
    cnt_b = DedupCounter.new(inst_name: "u_cnt_b", width: 8)

    # ── 手动去重: definition() + instance() ──────────────────
    # width=16 变体，通过显式定义句柄创建 → DedupCounter_1
    cnt_def_16 = DedupCounter.definition(width: 16)
    cnt_c = instance(cnt_def_16, inst_name: "u_cnt_c")

    add = DedupAdder.new(inst_name: "u_add", width: 8)

    # ── 左赋值连接端口 ──────────────────────────────────────
    cnt_a.clk <= clk
    cnt_a.rst <= rst
    cnt_a.en  <= en
    cnt_a.din <= data_in

    # ── 右赋值连接端口 ──────────────────────────────────────
    clk >= cnt_b.clk
    rst >= cnt_b.rst
    en  >= cnt_b.en

    # ── 子模块间自动布线 ────────────────────────────────────
    # cnt_a.dout → cnt_b.din: 父模块自动生成中间 wire u_cnt_a_dout
    cnt_b.din <= cnt_a.dout

    add.a <= cnt_a.dout
    add.b <= cnt_b.dout
    add.sum >= result

    # ── 未连接端口: cnt_c.dout → /* unused port */ ──────────
    cnt_c.clk <= clk
    cnt_c.rst <= rst
    cnt_c.en  <= en
    cnt_c.din <= wide_in
  end
end

# ---------- 构建与导出 ----------

top = DedupTop.new

RSV::App.main(top)
