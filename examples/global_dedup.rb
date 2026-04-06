# frozen_string_literal: true
# examples/global_dedup.rb
#
# 演示全局自动去重与 RSV.export_all 一键导出。
#
# 特性：
# - 多模块实例化，不同参数产生不同变体
# - 同参数模块仅保留一份（自动去重）
# - 子模块 SV 在 finalize 时自动注册到全局表
# - RSV.export_all(dir) 一次性导出全部去重后的模块
#
# Run:
#   xmake rtl -f glb

$LOAD_PATH.unshift(File.join(__dir__, "..", "lib"))
require "rsv"
include RSV

# ---------- 子模块：参数化计数器 ----------

class GDeCounter < ModuleDef
  def build(width: 8)
    clk   = input("clk", clock)
    rst   = input("rst", reset)
    en    = input("en", bit)
    count = output("count", uint(width))

    r = reg("r", uint(width), init: 0)
    count <= r

    with_clk_and_rst(clk, rst)
    always_ff { r <= mux(en, r + 1, r) }
  end
end

# ---------- 子模块：简单加法器 ----------

class GDeAdder < ModuleDef
  def build(width: 8)
    a   = input("a", uint(width))
    b   = input("b", uint(width))
    sum = output("sum", uint(width))

    sum <= a + b
  end
end

# ---------- 顶层模块 ----------

class GDeTop < ModuleDef
  def build
    clk = input("clk", clock)
    rst = input("rst", reset)
    en  = input("en", bit)
    result = output("result", uint(8))

    # 两个 width=8 的 counter → 自动去重为一份 SV 模板
    cnt_a = GDeCounter.new(inst_name: "u_cnt_a", width: 8)
    cnt_b = GDeCounter.new(inst_name: "u_cnt_b", width: 8)

    # 一个 width=16 的 counter → 独立变体 GDeCounter_1
    cnt_c = GDeCounter.new(inst_name: "u_cnt_c", width: 16)

    # 加法器
    add = GDeAdder.new(inst_name: "u_add", width: 8)

    cnt_a.clk <= clk
    cnt_a.rst <= rst
    cnt_a.en  <= en

    cnt_b.clk <= clk
    cnt_b.rst <= rst
    cnt_b.en  <= en

    # cnt_c 的 count 端口未连接，将自动生成 .count(/* unused port */)
    cnt_c.clk <= clk
    cnt_c.rst <= rst
    cnt_c.en  <= en

    add.a <= cnt_a.count
    add.b <= cnt_b.count
    add.sum >= result
  end
end

# ---------- 构建与导出 ----------

top = GDeTop.new

RSV::App.main(top)
