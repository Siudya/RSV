= RSV 使用指南

本指南覆盖一条典型的 RSV 工作流：定义模块类、声明信号、搭建表达式、描述过程行为，并导出 SystemVerilog。

== 典型工作流

+ 定义一个继承 `RSV::ModuleDef` 的 Ruby 类。
+ 在 `build(...)` 或 `initialize(...)` 中编写硬件构造逻辑。
+ 如果覆写 `initialize(...)`，请先调用 `super()`，再使用 DSL。
+ 使用 `bit(...)`、`uint(...)`、`vec(...)` 等构造匿名 RSV 数据类型。
+ 通过 `build(**kwargs)` 的关键字参数传入 meta 参数，控制模块展开，例如 `MyMod.new("name", width: 16, mode: 1)`。
+ 端口可通过 `iodecl("name", input(type))` 或 `let :name, input(type)` 声明；局部信号可通过 `wire("name", type)`、`reg("name", type)` 或统一的 `let` 形式声明。
+ `let` 是最推荐的写法，例如 `let :clk, input(clock)`、`let :cnt, reg(uint(8), init: 0)`。它会自动注册访问器，后续赋值和过程块里可以直接按名字引用句柄。
+ `const("name", type)` 用来声明常量，数据类型本身必须带初值，导出时会生成 SV `localparam`。
+ `generate_for` 与 `generate_if` 用于展开期代码生成，可表达 `genvar` 循环和条件块。
+ `vec.fill(...)` 用于构造带形状的复位初值。
+ `expr(...)` 用于把中间表达式实体化为具名线网。
+ 使用 `always_ff`、`always_latch`、`always_comb` 描述时序、锁存与组合逻辑。
+ `svif` / `svelif` / `svelse` 用于过程化条件分支，支持链式写法 `svif(c){}.svelif(c){}.svelse{}`，也支持 `unique:` / `priority:` 限定。
+ `svcase` / `svcasez` / `svcasex` 用于 `case` 语句，分支通过 `is(...)` 声明，默认分支通过 `fallin` 声明；`casez` 的 `?` 模式可直接写成 `is("4'b1??0")`。
+ `log2ceil(n)` 在 Ruby 侧计算位宽；`pop_count(vec)` 用于人口计数。`mux1h`、`muxp` 和 `pop_count` 会即时展开出临时线网，并返回可复用的线网句柄，可在模块级、`always_comb`、`always_ff` 或 `always_latch` 中使用。
+ 如果同一个 Ruby 类需要导出非默认模块名，可在 `build(...)` 中调整 `module_name`。
+ 同一个展开模板需要重复例化时，优先使用 `Counter.definition(...)` 搭配 `instance(...)`，避免重复展开。
+ 用户代码可自由使用左赋值 `<=` 和右赋值 `>=`。
+ 比较运算使用 `eq` / `ne` / `lt` / `le` / `gt` / `ge`，逻辑运算使用 `.and(...)` / `.or(...)`，归约运算使用 `.or_r` / `.and_r`。
+ 位选择和切片可写成 `sig[i]`、`sig[msb, lsb]`、`sig[msb..lsb]`、`sig[base, :+, w]` 和 `sig[base, :-, w]`。
+ 只要信号还保留 `vec(...)` 维度，`sig[...]` 就只接受单个索引。
+ 使用 `to_sv` 或 `to_sv(path)` 导出最终模块。
+ 命令行入口既可以写成一行式 `RSV::App.main(top)`，也可以写成块式 `RSV::App.main { |app| ... }` 注册自定义选项。
+ 运行 `ruby script.rb -o build/rtl` 会把所有去重后的模块导出到目录；省略 `-o` 时则把顶层模块 SV 输出到标准输出。

== 两阶段展开

RSV 会先根据 Ruby DSL 构建 AST，然后在第二阶段完成：

- 表达式位宽推导；
- 模块级 `<=` / `>=` 降级为连续 `assign`；
- 过程块里的赋值在 `always_ff` 中降级为 `<=`，在其他过程块中降级为 `=`；
- `expr(...)` 降级为具名 RSV `wire`，并生成对应的 `assign`；
- 在带时钟域的 `always_ff` 中，为 `reg(..., init: ...)` 自动注入复位分支；
- 在最终发射 SV 文本之前，检查赋值上下文和单驱动规则。

== 完整示例

```ruby
require "rsv"

class Counter < RSV::ModuleDef
  def build(width: 8)
    let :clk,        input(bit)
    let :rst,        input(bit)
    let :en,         input(bit)
    let :count,      output(uint(width))

    let :count_r,    reg(uint(width), init: 0)
    let :count_next, expr(count_r + 1)

    count_r >= count

    with_clk_and_rst(clk, rst)
    always_ff do
      svif(en) do
        count_r <= count_next
      end
    end
  end
end

counter = Counter.new(width: 8)
RSV::App.main(counter)
```

== 生成出的 SystemVerilog

```systemverilog
module Counter (
  input  logic       clk,
  input  logic       rst,
  input  logic       en,
  output logic [7:0] count
);

  logic [7:0] count_r;
  logic [7:0] count_next;

  assign count_next = count_r + 8'd1;
  assign count      = count_r;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      count_r <= 8'h0;
    end else if (en) begin
      count_r <= count_next;
    end
  end

endmodule
```

== 子模块例化

`Counter.new(...)` 在顶层调用时会创建模块对象；在另一个模块内部调用时，会创建子模块实例句柄。端口连接可稍后用 `<=` 或 `>=` 完成。对于会重复出现的模板，也可以先通过 `Counter.definition(...)` 展开一次，再手动用 `instance(...)` 例化。如果多个 `definition(...)` 调用最终得到同一份 SV 模板，RSV 会自动复用同一个缓存句柄。

当一个子模块输出直接连接到另一个子模块输入时，RSV 会在父模块中自动插入中间互连 `wire`。该线网名称按驱动实例与端口路径生成，因此像 `u_src.tx_mem[0][1] <= u_dst.rx_mem[1][2]` 这样的多维索引连接，会生成类似 `u_src_tx_mem_0_1` 的名字。

每个模块对象都带有 `module_name`。默认情况下，它由 Ruby 类名推导而来；如果你覆写它，后续导出会使用新名字。当同一个 `ModuleDef` 子类在保持相同基础名的前提下导出多份不同 SV 模板时，RSV 会保留第一份名称，并为后续变体自动追加 `_1`、`_2` 等后缀，避免例化时发生命名冲突。

```ruby
class Top < RSV::ModuleDef
  def build(counter_def:)
    let :clk,   input(bit)
    let :rst,   input(bit)
    let :count, output(uint(8))

    counter = instance(counter_def, inst_name: "u_counter")
    counter.clk <= clk
    rst >= counter.rst
    counter.count >= count
  end
end

counter_def = Counter.definition(width: 8)
top = Top.new(counter_def: counter_def)
```

== 非打包数组与存储器

使用 `vec(...)` 可以在变量名之后追加非打包维度。它返回匿名数据类型，因此通常会把结果传给 `wire(...)`、`reg(...)` 或端口声明。对于多维数组，可以写成 `vec([i, j, k], uint(8))`，也可以写成变参形式 `vec(i, j, k, uint(8))`。

```ruby
memory = reg("cnt_mem_0", vec([i, j, k], uint(8)))
filled = reg("cnt_init", vec(16, uint(16)), init: vec.fill(16, uint(16, 0x75)))
```

```systemverilog
logic [7:0]  cnt_mem_0[i-1:0][j-1:0][k-1:0];
logic [15:0] cnt_init[15:0];
```

只要一个带形状的信号仍然保留 `vec(...)` 维度，`[]` 就只表示索引选择。等这些维度都被消耗后，普通向量的索引与切片行为才会恢复为常规 SV 写法。

== 流式视图

`uint(...)` 与 `vec(...)` 信号都可以通过 `sv_take`、`sv_select`、`sv_foreach`、`sv_reduce`、`sv_map` 当作可枚举视图来处理。遍历顺序总是沿着当前最外层尚未消费的集合维度，因此混合形状与多维形状都可以逐层展开。

```ruby
always_comb do
  parity <= mask.sv_take(4).sv_reduce { |a, b| a ^ b }
  result <= mask
    .sv_take(8)
    .sv_select { |_, i| i.even? }
    .sv_map { |v, _i| v }
end
```

它会导出左结合的归约表达式，并生成一个打包拼接；第一个被选中的元素会落在结果的最低位槽位：

```systemverilog
always_comb begin
  parity = ((mask[0] ^ mask[1]) ^ mask[2]) ^ mask[3];
  result = {mask[6], mask[4], mask[2], mask[0]};
end
```

== 示例脚本与 xmake

仓库内置示例推荐通过 `xmake` 统一入口运行：

```bash
xmake rtl -l
xmake rtl -f ctr
xmake rtl -f syn
```

- `xmake rtl -l` 会打印全部内置示例名称、3-4 字符别名与一句话特性摘要。
- `xmake rtl -f <名称或别名>` 会运行 `examples/` 目录下的对应示例。
- `xmake rtl -f name -d dir` 可用于执行内置示例目录之外的 `dir/name.rb`。
- 完整的示例目录与特性覆盖矩阵见 `examples.typ`。

== 导入现有 SystemVerilog 模块

`RSV.import_sv` 会把外部 SystemVerilog 模块导入为一个黑盒签名提供者。导入结果会暴露模块名、参数和端口，因此可以像例化 RSV 自己定义的模块一样进行例化。

```ruby
ImportedCounter = RSV.import_sv(
  File.join(__dir__, "imported_counter.sv"),
  top: "ImportedCounter",
  incdirs: [__dir__]
)

class ImportDemo < RSV::ModuleDef
  def build
    let :clk,  input(bit)
    let :dout, output(uint(12))

    counter = ImportedCounter.new(inst_name: "u_imported_counter", WIDTH: 12)
    counter.clk <= clk
    dout <= counter.dout
  end
end
```

这条导入链路依赖 `python3` 与 `pyslang`，当前只导入模块签名，不会把导入模块的实现本体翻译成 RSV。

== Bundle 用法

定义 Bundle 时，需要继承 `RSV::BundleDef`，并在 `build` 中使用 `input` / `output` 声明带方向的字段。该类最终会产出一个可被所有 RSV 声明 API 使用的 `DataType`。Bundle 字段会在声明阶段展开为独立信号。字段方向只对 IO 端口声明（`iodecl` 或 `let :name, input(bundle)`）生效；局部信号声明（`reg` / `wire`）会忽略字段方向。

```ruby
class Pixel < RSV::BundleDef
  def build
    input :r, uint(8)
    input :g, uint(8)
    input :b, uint(8)
  end
end

class PixProc < RSV::ModuleDef
  def build
    let :clk,    input(clock)
    let :rst,    input(reset)
    let :px_in,  input(Pixel.new)          # 字段方向保持原定义
    let :px_out, flip(Pixel.new)           # 整体翻转字段方向
    let :px,     reg(Pixel.new, init: { "r" => 0, "g" => 0, "b" => 0 })
    with_clk_and_rst(clk, rst)
    px_out <= px
    always_ff { px.r <= px_in.r }
  end
end
```

`reg :px, Pixel.new` 这样的声明会展开出三个独立信号：`px_r`、`px_g`、`px_b`。字段访问 `px.r` 会直接映射到 `px_r`。

Bundle 还支持：
- 嵌套 Bundle：`input :inner, OtherBundle.new`，会递归打平；
- 与 `vec` 组合：`vec(4, Pixel.new)` 会为每个字段带上非打包维度；
- meta 参数：例如 `def build(w: 8)` 搭配 `Pixel.new(w: 16)`；
- 局部复位：只有列在 `init` 哈希中的字段会在 `always_ff` 中生成复位逻辑；
- 字段访问：`handler.field_name` 可直接读写展开后的字段句柄；
- 字段句柄：`r = input("r", type)` 会返回字段句柄，Ruby 变量名可与 SV 字段名不同；
- 整体赋值：`out <= reg` 会自动展开为逐字段赋值；
- Bundle 端口声明：`iodecl("name", bundle)` 使用字段方向；`iodecl("name", flip(bundle))` 则整体翻转方向；
- 标量端口声明：`iodecl("name", output(uint(8)))` 或 `iodecl("name", input(type))`。

== 使用 `as_type` 做类型转换

任意信号都可以通过 `.as_type(target)` 转换成另一种数据类型：

```ruby
# 标量 → 标量（截断 / 零扩展）
narrow <= wide.as_type(uint(8))     # 保留低位
wide   <= narrow.as_type(uint(32))  # 高位补零

# Bundle → uint（打平）
flat <= pxl.as_type(uint(24))  # 等价于 pxl.as_uint

# uint → bundle（重组）
pxl = data.as_type(Pixel.new)
out <= pxl.r

# uint → vec（按元素切片）
m = data.as_type(vec(4, uint(8)))
out <= m[2]

# uint → vec（元素为 Bundle）
mb = data.as_type(vec(2, Pixel.new))
out <= mb[1].g
```

位宽不匹配时会自动处理：
- 源信号比目标宽：截断，保留低位；
- 源信号比目标窄：零扩展，在高位补零。

== 命令行入口：`RSV::App`

`RSV::App` 为 RSV 脚本提供统一命令行接口。它内置 `-o/--out-dir DIR` 选项，用来把去重后的 SV 文件导出到目录；同时也允许通过 `app.option(...)` 声明自定义命令行参数。

=== 最简形式

```ruby
counter = Counter.new(width: 8)
RSV::App.main(counter)
```

运行方式：

```bash
ruby counter.rb -o build/rtl      # → writes build/rtl/counter.sv
ruby counter.rb                   # → prints SV to stdout
```

=== 自定义选项与构建逻辑

```ruby
RSV::App.main do |app|
  app.option(:width, "-w", "--width WIDTH", Integer, "Data width", default: 8)
  app.build { |opts| Counter.new(width: opts[:width]) }
end
```

=== 导出后回调

```ruby
RSV::App.main do |app|
  app.build { |opts| [ModA.new, ModB.new] }
  app.after_export do |opts, tops|
    tops.each { |t| t.v_wrapper(File.join(opts[:out_dir], "#{t.module_name}_wrapper.sv")) } if opts[:out_dir]
  end
end
```

=== 多个顶层模块

```ruby
RSV::App.main([PixelProcessor.new, PacketRouter.new])
```

== 自动模块去重

当 `ModuleDef` 子类完成展开后，对应的 SV 模板会自动注册到全局 `ElaborationRegistry`。如果同一个类在相同参数下展开得到完全一致的 SV，仓库里只会保留一份模板。

`RSV.export_all(dir)` 会为每个唯一模块模板写出一个 `.sv` 文件。使用 `RSV::App.main` 搭配 `-o DIR` 时，这一步会自动完成。

如果多个模块模板来自同一个 Ruby 类名，但展开得到的 SV 本体不同，RSV 会自动在模块名后面追加 `_1`、`_2` 等后缀，避免重名冲突。
