= RSV 参考手册

== 类式模块

- 通过继承 `RSV::ModuleDef` 定义模块。
- 硬件构造逻辑写在 `build(...)` 或 `initialize(...)` 中。
- 如果覆写 `initialize(...)`，在使用 DSL 之前必须先调用 `super()`。
- 每个模块对象都暴露 `module_name`。默认值来自类名（或构造函数传入的位置参数），也可以在 `build(...)` 或 `initialize(...)` 中重新赋值。
- 顶层调用 `Counter.new(...)` 会返回模块对象。
- 顶层调用 `Counter.definition(...)` 会返回一个可复用的已展开模块模板句柄；如果后续 `definition(...)` 产生的模板完全相同，RSV 会自动复用同一个句柄。
- 在另一个模块内部调用 `Counter.new(...)`，返回的是子模块实例句柄。
- `RSV::ModuleDef` 本身不能直接例化。
- 当同一个 `ModuleDef` 子类在同一个基础 `module_name` 下导出多份不同的 SV 模板时，RSV 会保留第一份名称，并为后续变体自动追加 `_1`、`_2` 等后缀。

== 声明

/ `bit(init = nil)`: 创建匿名 1 位 RSV 数据类型。
/ `bits(width = 1, init = nil)`: 创建匿名无符号数据类型，与 `uint` 等价。
/ `uint(width = 1, init = nil)`: `bits` 的别名，用来创建匿名无符号数据类型。
/ `sint(width = 1, init = nil)`: 创建匿名有符号数据类型，导出为 SV `logic signed [...]`。
/ `clock(init = nil)`: 创建匿名 1 位时钟类型。返回句柄支持 `.neg`，可用于选择下降沿：`with_clk_and_rst(clk.neg, rst)` 会导出 `always_ff @(negedge clk ...)`。
/ `reset(init = nil)`: 创建匿名 1 位复位类型。返回句柄支持 `.neg`，可用于低有效复位：`with_clk_and_rst(clk, rst.neg)` 会导出 `always_ff @(... negedge rst)` 与 `if (!rst)`。
/ `input(type)`: 方向修饰器，把数据类型包装为输入方向，供 `iodecl` 或 `let` 使用。
/ `output(type)`: 方向修饰器，把数据类型包装为输出方向。
/ `inout(type)`: 方向修饰器，把数据类型包装为双向端口方向。
/ `iodecl(name, directed_type, init:, attr:)`: 声明端口（包括 Bundle 端口）。通常搭配 `input(type)`、`output(type)` 或 `flip(bundle)` 使用。
/ `let(:sym, qualified_type, attr:)`: 统一声明入口，并自动注册访问器。对于带方向类型会委托给 `iodecl`；对于内部信号则委托给 `wire` / `reg` / `const` / `expr`。
/ `wire(name, type, init:, attr:)`: 声明组合信号并返回句柄，导出为 SV `logic`。
/ `reg(name, type, init:, attr:)`: 声明带复位语义的寄存器类信号，导出为 SV `logic`，`init` 会在带时钟域的 `always_ff` 中触发复位注入。
/ `const(name, type, attr:)`: 声明常量。数据类型必须自带初值（例如 `sint(16, 0x57)`），导出为 SV `localparam`。返回句柄可参与表达式，但不能出现在赋值左侧。
/ `vec(dims..., type)` / `vec([dims...], type)`: 创建匿名非打包数组类型。非打包维度会按标准 SV 形式出现在变量名之后，例如 `[n-1:0]`。嵌套调用会自动展平：`vec([i], vec([j], vec([k], t)))` 等价于 `vec([i, j, k], t)`。
/ `vec.fill(...)`: 辅助构造带形状的复位初值，目标匿名数据类型本身需要携带标量初值。
/ `expr(name, rhs, width:)`: 推导线网位宽，声明具名 RSV `wire`（导出为 SV `logic`），并生成 `assign name = rhs;`。

== 表达式与运算

/ `handler.as_sint`: 返回会导出成 `$signed(handler)` 的表达式，常用于把无符号信号转成有符号后再参与算术运算。
/ `cat(*parts)`: 位拼接，导出为 SV `{a, b, c}`。参数可以是标量、Bundle 或 `vec` 信号；Bundle 与 `vec` 会自动通过 `as_uint` 展开。
/ `mux(sel, a, b)`: 三元选择表达式，导出为 `sel ? a : b`。当 `sel` 为 1 时选择 `a`，否则选择 `b`。
/ `mux1h(sel1h, dats)`: 独热选择器。它会即时创建临时线网与 `always_comb` / `unique case`，并直接返回线网句柄。`dats` 必须是最高维长度与 `sel1h` 位宽一致的 `vec`，也可以是用于逐字段选择的 Bundle `vec`。全零选择器会得到 `'0`，默认分支会得到 `'x`。返回句柄可以跨多次赋值复用：`res = mux1h(sel, dats); out <= res`。模块级、`always_comb`、`always_ff` 与 `always_latch` 中都可以使用。
/ `muxp(sel, dats, lsb_first: true)`: 优先级选择器，和 `mux1h` 类似，但导出为 `priority casez`。支持 Bundle `dats` 做逐字段选择，`lsb_first:` 用来控制优先级顺序。
/ `pop_count(vec)`: 人口计数。它会即时创建临时线网和带 `for` 累加器的 `always_comb`，统计 `vec` 中为 1 的位数。输出位宽为 `log2ceil(vec.width + 1)`。返回句柄可重复使用，也可在模块级、`always_comb`、`always_ff` 与 `always_latch` 中调用。
/ `bundle.as_uint` / `vec.as_uint`: 把所有叶子字段或元素拼成一个 `uint`。对 Bundle 而言，最先声明的字段位于最高位；对 `vec` 而言，最高索引位于最高位。返回值是 `CatExpr`，常见写法如 `packed <= pxl.as_uint`、`expr("p", vec.as_uint)`。
/ `bundle.get_width` / `vec.get_width`: 返回包含全部维度在内的总位宽。
/ `vec.reverse`: 创建反转后的 `vec` 副本。它会即时创建临时线网与带 `for` 循环的 `always_comb`。如果是 Bundle `vec`，每个叶子字段都会获得独立的反转线网。返回值是线网句柄（或 `BundleSignalGroup`）。
/ `signal.as_type(target_type)`: 把任意信号转换为另一种数据类型。实现过程是先把源信号打平成 `uint`，再按目标位宽进行截断或零扩展，最后重组为目标类型。支持标量↔标量、Bundle↔uint、`vec`↔uint、Bundle↔Bundle、uint↔`vec`、uint↔`vec(bundle)`。截断时保留低位，零扩展时在高位补零。示例：`pxl.as_type(uint(24))`、`a.as_type(vec(4, uint(8)))`、`a.as_type(MyBundle.new)`。
/ `log2ceil(n)`: 纯 Ruby 工具函数，返回 `ceil(log2(n))`，即表示 `n` 个元素所需的最小地址位宽。既可以在模块 `build` 块里使用，也可以通过 `RSV.log2ceil(n)` 调用。
/ `expr.sv_take(n)`: 开启流式视图，并保留前 `n` 个元素。
/ `expr.sv_select { |elem, i| ... }`: 用 Ruby 布尔谓词过滤流式视图。索引 `i` 表示原始元素索引，过滤后不会重新编号。
/ `expr.sv_foreach { |elem, i| ... }`: 对选中的每个元素即时展开一次代码块。流源既可以是 `uint`，也可以是 `vec(...)`；遍历顺序总是沿着当前最外层仍保留的集合维度。
/ `expr.sv_reduce { |a, b| ... }`: 对选中的元素做左结合归约，并在导出的 SV 中保留明确的折叠顺序。
/ `expr.sv_map { |elem, i| ... }`: 把选中的元素映射成一个打包结果。第一个映射元素会落在结果的最低位槽位，因此最终导出的拼接顺序会表现为逆序。

== 语句与过程块

/ `with_clk_and_rst(clk, rst)`: 为后续 `always_ff` 设置隐式时钟/复位域，支持 `clk.neg` 与 `rst.neg`。
/ `definition(source, ...)`: 返回可复用的模块定义句柄。`source` 可以是 RSV 模块类、导入模块对象，或者已经构建好的模块 / 定义句柄。只要展开模板完全一致，就会自动复用缓存。
/ `instance(def_handle, inst_name:)`: 例化一个可复用定义句柄，并返回常见的镜像风格端口句柄，供后续连线使用。
/ `always_ff { ... }`: 使用当前隐式时钟/复位域生成 `always_ff`。
/ `always_ff(clk, rst) { ... }`: 使用显式时钟/复位域生成 `always_ff`。
/ `always_latch { ... }`: 导出 `always_latch begin ... end`。
/ `always_comb { ... }`: 导出 `always_comb begin ... end`。
/ `svif(cond, unique: false, priority: false) { ... }`: 过程化 `if` 语句。设置 `unique: true` 或 `priority: true` 时，会分别导出 `unique if` 或 `priority if`。返回值支持链式 `.svelif(cond) { ... }` 和 `.svelse { ... }`。
/ `svelif(cond) { ... }`: 追加到前一个 `svif` 后面的 `else if` 分支。
/ `svelse { ... }`: `else` 分支。
/ `svcase(expr, unique: false, priority: false) { ... }`: 过程化 `case` 语句。块中通过 `is(val, ...) { ... }` 声明分支，通过 `fallin { ... }` 声明默认分支。`is` 中可同时传入多个值，导出为逗号分隔匹配。
/ `svcasez(expr, unique: false, priority: false) { ... }`: `casez` 语句，可通过 `is("4'b1??0")` 这类字符串模式使用 `?` 通配。
/ `svcasex(expr, unique: false, priority: false) { ... }`: `casex` 语句。
/ `lhs <= rhs`: 左赋值写法。
/ `rhs >= lhs`: 右赋值写法。
/ `to_sv(path = nil)`: 返回生成后的 SV 文本。`to_sv("-")` 会写到标准输出，`to_sv("build/rtl/foo.sv")` 会写到文件。

== 预处理宏

/ `sv_def(name, value = nil)`: 导出 `` `define NAME VALUE ``；省略 `value` 时导出裸的 `` `define NAME ``。
/ `sv_undef(name)`: 导出 `` `undef NAME ``。
/ `sv_ifdef(name) { ... }`: 开启 `` `ifdef NAME `` 条件块。返回值支持链式 `.sv_elif_def(name) { ... }` 与 `.sv_else_def { ... }`。
/ `sv_ifndef(name) { ... }`: 与 `sv_ifdef` 类似，但导出 `` `ifndef ``。
/ `sv_dref(name)`: 返回引用 `` `NAME `` 的表达式，可在任何普通 RSV 表达式上下文中使用，包括模块级与过程块内部。

== Generate 块

/ `generate_for(genvar_name, start, end, label: nil) { |i| ... }`: 导出 `for (genvar ...)` 循环。块参数 `i` 是可用于数组索引的 `genvar` 引用。块内声明的 `wire` / `reg` / `const` 都会成为块级局部对象，`always_ff`、`always_comb`、`always_latch` 也都可以在块内使用。
/ `generate_if(cond, label: nil) { ... }`: 导出 generate 级别的 `if` 块。条件必须是常量表达式，例如 `localparam` 或 `const` 比较。返回值支持链式 `.generate_elif(cond, label:) { ... }` 与 `.generate_else(label:) { ... }`。

- 两种赋值写法在过程块外都会导出连续 `assign`，在 `always_ff` 内部都会导出 `<=`。
- 在 `always_comb` 与 `always_latch` 内部，赋值会导出阻塞赋值 `=`。
- 比较运算使用 `eq`、`ne`、`lt`、`le`、`gt`、`ge`。
- 逻辑运算使用 `.and(...)`、`.or(...)`、`!`、`~`、`.or_r`、`.and_r`。
- 移位运算使用 `<<` 与 `>>`。
- 位与部分选择可写成 `sig[i]`、`sig[msb, lsb]`、`sig[msb..lsb]`、`sig[base, :+, width]`、`sig[base, :-, width]`。
- 只要信号还带着 `vec(...)` 维度，`sig[...]` 就只接受单个索引。该索引必须是硬件 `uint` 或整数常量；在这些维度被消耗完以后，普通向量切片才会恢复可用。

== Ruby 侧算术

带初值的非硬件 `uint` / `sint` 数据类型可以在 Ruby 侧直接参与算术。运算结果会生成新的 `DataType`，并自动推导位宽与新初值：

- 加法与减法会让位宽扩展 1 位；
- 乘法会把位宽扩展为两侧操作数位宽之和；
- 除法保持左操作数位宽；取模保持右操作数位宽；
- 归约运算（`or_r`、`and_r`）和比较运算（`eq`、`ne`）都会产生 1 位结果。

== 子模块连接

- 在另一个模块内部直接构造模块类即可例化子模块。
- 对会重复出现的模板，推荐使用 `Counter.definition(...)` + `instance(...)`，这样只会展开一次，并重复使用同一份模板。
- `inst_name:` 可用于指定稳定的实例名。
- 连接输入型端口时，可以写 `instance.port <= signal`。
- 如果更偏好右赋值，也可以写 `signal >= instance.port`。
- 连接输出型端口时，可以写 `signal <= instance.port` 或 `instance.port >= signal`。
- 如果把一个实例的输出端口直接连到另一个实例的输入端口，RSV 会自动在父模块中插入中间 `wire`。该线网名称来源于驱动实例与端口，例如 `u_tx_dout`；对于索引 / 多维访问，名称会扩展成 `u_tx_mem_0_1` 这样的形式。

== 表达式行为

- 普通 Ruby 临时变量在被 `expr(...)` 实体化之前，始终只是匿名 RSV 表达式。
- 例如 `tmp = a + b; out = expr("out", tmp + a)` 最终只会导出 `out` 一个具名线网，并保持嵌套表达式结构：`assign out = a + b + a;`。

== 赋值规则

- `reg(...)` 目标只能在 `always_ff` 或 `always_latch` 内赋值。
- `wire(...)` 目标只能通过连续 `assign` 或 `always_comb` 赋值。
- 一个变量只能由一个连续 `assign` 或一个 `always` 块驱动。
- 违反这些规则时，会在导出 SV 之前抛出参数错误。

== 命名与风格

- 对外 DSL 入口统一使用 snake_case。
- 本地 `wire` / `reg` 声明会导出为对齐后的 SV `logic` 声明。
- 连续出现的 `assign` 语句会在 `=` 列上对齐。

== 属性

- 端口声明与局部声明都接受可选的 `attr:` 哈希。
- 哈希键为属性名，值为字符串表达式或 `nil`（表示无值属性）。
- 例如：`wire("sig", uint(8), attr: { "mark_debug" => "\"true\"" })` 会导出：
  ```systemverilog
  (* mark_debug = "true" *)
  logic [7:0] sig;
  ```
- 例如：`iodecl("dout", output(uint(8)), attr: { "keep" => nil })` 会导出：
  ```systemverilog
  (* keep *)
  output logic [7:0] dout
  ```
- 多个属性可以组合：`attr: { "a" => nil, "b" => "1" }` 会导出 `(* a, b = 1 *)`。

== Verilog 兼容封装层

- 对已经构建好的模块调用 `mod.v_wrapper`，可以生成一个端口扁平化的 Verilog 兼容封装层。
- 非打包数组端口（例如 `vec(3, uint(16))`）会展开成多个标量端口（`port_0`、`port_1`……），再通过 SV 数组线网在内部重组。
- Bundle 端口在声明阶段就已经被打平，因此每个字段都会变成独立端口（例如 `port_field`），嵌套 Bundle 会递归展开成 `port_inner_field` 这样的形式。
- `vec(N, BundleType)` 端口会让每个打平字段都保留原来的非打包维度。
- 可以通过 `v_wrapper(wrapper_name: "my_top")` 指定封装层名称。
- 也可以直接把结果写入文件：`v_wrapper("path/to/file.sv")`。
- 为了完成端口打平，所有端口位宽都必须是整数常量，不能是 `SvParamRef`。
- 完整示例见 `examples/verilog_wrapper.rb`。

== 内嵌 SystemVerilog（sv\_plugin）

- `sv_plugin(code)` 会在当前位置直接插入原始 SystemVerilog 代码。
- 它既可以在模块级使用（与 `assign`、`always` 等并列输出），也可以在过程块内部使用（`always_ff`、`always_comb`、`always_latch`）。
- 支持多行字符串（heredoc），每一行都会自动对齐到当前上下文缩进。
- 常见用途包括断言、`$display` 调试语句、`function` / `task` 定义、厂商专用 pragma，以及尚未被 RSV DSL 直接覆盖的任意 SV 结构。
- 例如：`sv_plugin '$display("val=%h", sig);'`
- 完整示例见 `examples/sv_plugin_demo.rb`。

== Bundle

- 通过继承 `RSV::BundleDef` 定义 Bundle 类型。
- 在 `build(...)` 中使用带方向的字段声明完成 Bundle 定义。
- `input(name, type)`：声明一个输入方向的 Bundle 字段。
- `output(name, type)`：声明一个输出方向的 Bundle 字段。返回值是字段句柄，可直接保存在 Ruby 变量中；Ruby 变量名可与 SV 字段名不同。
- `MyBundle.new` 会返回一个 `DataType`，可直接用于 `iodecl`、`wire`、`reg`、`vec` 等所有常见声明。
- Bundle 字段会在声明时打平成独立信号。例如 `reg("px", Pixel.new)` 会展开出 `px_r`、`px_g`、`px_b`。
- 嵌套 Bundle 会递归打平，例如 `outer_inner_field`。
- 参数化 Bundle 使用 `build(**kwargs)` 的 meta 参数，例如 `MyBundle.new(w: 16)`。不同参数值会通过自动去重机制生成不同的类型名。
- 局部复位写法 `reg("r", bundle_t, init: { "field" => 0 })` 只会为列出的字段生成复位赋值。
- 如果想完整复位，需要在 `init` 哈希中提供全部字段名。
- 字段访问 `handler.field_name` 会返回打平后的字段句柄，例如 `r.valid <= 1`、`o <= r.data`。
- 整体赋值 `out <= reg` 会自动展开成逐字段赋值。
- 对 `vec(N, bundle_t)` 这类 Bundle 数组做索引时，会保持字段分组关系，因此 `fifo[0].data` 这样的写法是有效的。

=== 带 Bundle 的 IO 声明

- `iodecl(name, bundle_type)`：按每个字段原本的方向声明 IO 端口。
- `iodecl(name, flip(bundle_type))`：整体翻转所有字段方向（input↔output）。
- `iodecl(name, output(type))`：声明标量输出端口。
- `iodecl(name, input(type))`：声明标量输入端口。
- `iodecl(name, output(vec(N, type)))`：声明带非打包维度的输出端口。
- 本地声明（`reg`、`wire`）会忽略 Bundle 字段方向，所有字段都会变成普通 `logic`。
- 相关示例见 `examples/bundle_and_interface.rb`；该文件名保留了历史命名，当前内容聚焦 Bundle 类型而非接口类型。
