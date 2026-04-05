= 示例文件特性覆盖

本文档描述 `examples/` 目录下每一个示例文件所覆盖的 RSV 特性。

== counter.rb

基础的参数化顺序计数器。

- 端口声明: `input`, `output`
- 类型构造: `bit`, `uint`
- 参数: `parameter`
- 局部声明: `reg`(含初始值), `expr`
- 赋值: `<=`
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- 条件控制: `svif`
- 算术运算: `+`
- 输出: `to_sv(path)`

== auto_dedup.rb

自动去重与子模块自动布线。

- 端口声明: `input`, `output`
- 类型构造: `uint`
- 赋值: `<=`, `>=`（右赋值）
- 模块实例化: `.new(inst_name:, width:)`
- 端口连接: `instance.port <= signal`, `instance.port >= signal`
- 子模块间自动布线: 子模块输出直连另一子模块输入，自动在父模块生成中间wire
- 模块去重: `.uniq { |d| d.module_name }`
- 输出: `to_sv(path)`

== manual_dedup.rb

手动去重与自动布线。

- 端口声明: `input`, `output`
- 类型构造: `uint`
- 赋值: `<=`, `>=`
- 模块去重: `definition(width:)` 创建共享定义
- 模块实例化: `instance(definition, inst_name:)` 手动实例化
- 端口连接: 实例端口赋值
- 子模块间自动布线
- 输出: `to_sv(path)`

== syntax_showcase.rb

全面的语法展示，覆盖大部分基础 DSL 特性。

- 端口声明: `input`, `output`, `inout`
- 类型构造: `bit`, `bits`, `uint`, `sint`, `clock`, `reset`
- 局部声明: `wire`(含初始值), `reg`(含初始值), `expr`
- 赋值: `<=`, `>=`
- 算术运算: `+`, `-`(取负 `.neg`), `*`, `/`, `%`
- 比较运算: `.eq`, `.ne`, `.lt`, `.le`, `.gt`, `.ge`
- 逻辑运算: `.and`, `.or`, `!`（逻辑非）
- 位运算: `^`, `~`, `&`, `|`
- 归约运算: `.or_r`, `.and_r`
- 移位运算: `<<`, `>>`
- 位切片: `[15, 12]`, `[15..12]`, 索引部分选择 `[4, :+, 4]`, `[11, :-, 4]`
- 表达式: `mux()`, `cat()`, `fill()`
- 类型转换: `.as_sint`
- 组合逻辑: `always_comb`
- 锁存逻辑: `always_latch`
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- 条件控制: `svif`, `svelif`, `svelse`
- 时钟域: `.neg`（下降沿）
- 编译期类型算术: `uint(8, 5) + uint(8, 2)`

== storage_streams.rb

数组/存储器形态与流式操作。

- 端口声明: `input`, `output`
- 类型构造: `clock`, `reset`, `bit`, `uint`, `arr`, `mem`（嵌套混合形态）
- 局部声明: `reg`（含 `arr.fill()`, `mem.fill()`）
- 赋值: `<=`
- 数组索引: `[]`（packed 数组、memory、混合形态）
- 流式 API: `.sv_take()`, `.sv_select()`, `.sv_map()`, `.sv_reduce()`, `.sv_foreach()`
- 块参数: `|a, b|`, `|v, _i|`, `|row, _i|`
- 组合逻辑: `always_comb`
- 时序逻辑: `always_ff`（显式时钟/复位参数）
- 条件控制: `svif`
- 位运算: `^`（在 reduce 中使用）

== mux_cases.rb

选择器与多路复用。

- 端口声明: `input`, `output`
- 类型构造: `bit`, `uint`, `mem`
- 局部声明: `wire`
- 赋值: `<=`
- 选择器表达式: `mux()`（三元选择）, `mux1h()`（独热选择）, `muxp()`（优先级选择）
- `mux1h`/`muxp` 参数: `result:`, `lsb_first:`
- 组合逻辑: `always_comb`

== import_demo.rb

导入外部 SystemVerilog 模块。

- SV 导入: `RSV.import_sv(path, top:, incdirs:)`
- 端口声明: `input`, `output`
- 类型构造: `bit`, `uint`, `mem`
- 模块实例化: 导入模块 `.new(inst_name:, PARAMETER:)`
- 端口连接: `<=`, `>=`
- 输出: `to_sv(path)`

== const_demo.rb

常量（localparam）声明。

- 端口声明: `input`, `output`
- 类型构造: `bit`, `uint`, `sint`
- 局部声明: `reg`(含初始值), `const`（输出为 `localparam`）
- 常量声明: `const("NAME", uint(16, 0xBEEF))`, `const("NAME", sint(8, -3))`
- 赋值: `<=`
- 算术运算: `+`
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- 条件控制: `svif`

== macro_demo.rb

SystemVerilog 预处理宏指令。

- 端口声明: `input`, `output`
- 类型构造: `bit`, `uint`
- 局部声明: `reg`(含初始值)
- 宏定义: `sv_def`（\`define）
- 宏取消: `sv_undef`（\`undef）
- 条件编译: `sv_ifdef`（\`ifdef）, `.sv_else_def`（\`else）
- 宏引用: `sv_dref`（\`MACRO\_NAME）
- 赋值: `<=`
- 比较运算: `.eq`
- 算术运算: `+`（含宏引用作为操作数）
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- 条件控制: `svif`, `svelse`
- 链式调用: `.sv_ifdef().sv_else_def()`

== generate_demo.rb

综合的 generate 块演示，结合 sv\_param、const、attr、definition/instance 等特性。

- 端口声明: `input`, `output`
- 类型构造: `clock`, `reset`, `uint`, `arr`
- 局部声明: `reg`, `wire`, `const`
- 硬件属性: `attr: { "keep" => nil }` 用于端口标注
- sv\_param: `DEPTH`, `DATA_W`, `MODE` 用作 generate 循环上界和条件判断
- 柯里化调用: `.new("name").().(meta_params)` 构造顶层
- generate for + 内联逻辑: `generate_for` 内声明局部 reg，搭配 `always_ff`
- generate for + definition/instance: 使用元参数子模块 `PipeStage.definition(width:)`
  在循环内 `instance()` 例化多个流水级
- generate for + sv\_param 子模块: 使用柯里化 `SvPipeStage.new().(W: DATA_W).()`
  在循环内例化带 SV parameter 的子模块，参数透传
- genvar 索引连接: `chain[i]`, `chain[i + 1]` 组成流水链
- generate if/elif/else: `sv_param MODE` 控制条件生成
- generate if + 局部 const: 在条件块内声明 `localparam`
- 比较运算: `.eq`, `.lt`
- 位运算: `~`（取反）
- 赋值: `<=`, `>=`
- 时序逻辑: `always_ff`, `with_clk_and_rst`

== curried_params.rb

SystemVerilog parameter 与柯里化参数。

- SV 参数声明: `sv_param("WIDTH", 8)`（类级别宏）
- 柯里化调用: `.new("name").(sv_params).(meta_params)`
- SvParamRef: 参数引用作为类型宽度 `uint(WIDTH)`
- 端口声明: `input`, `output`
- 类型构造: `clock`, `reset`, `uint`
- 局部声明: `reg`(含初始值)
- 赋值: `<=`
- 归约运算: `.and_r`
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- 条件控制: `svif`, `svelse`
- Ruby 元编程: 运行时 `if/else` 条件模板裁剪
- 定义注册表: `.definition_handle_registry`
- 模块实例化: 含参数覆盖的子模块实例化
- 输出: `to_sv(path)`

== verilog_wrapper.rb

Verilog 兼容 wrapper 产生器。

- 端口声明: `input`, `output`
- 类型构造: `clock`, `reset`, `arr`, `mem`, `uint`
- 局部声明: `reg`(含初始值)
- 赋值: `<=`
- 数组/存储器索引: `[]`
- 算术运算: `+`
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- Verilog wrapper: `v_wrapper(path, wrapper_name:)` 生成端口打平的 Verilog 兼容顶层
  - packed 数组端口打平为位向量直连
  - unpacked 数组端口展开为独立标量端口
- 输出: `to_sv(path)`, `v_wrapper(path)`

== sv_plugin_demo.rb

内嵌原始 SystemVerilog 代码。

- 端口声明: `input`, `output`
- 类型构造: `clock`, `reset`, `uint`
- 局部声明: `reg`(含初始值)
- sv\_plugin（模块级）: 内嵌 assertion 块、function 定义、assign 语句
- sv\_plugin（过程级）: 在 `always_ff` 内嵌 `$display` 调试语句
- 多行 heredoc: 使用 `<<~SV ... SV` 嵌入多行代码
- 赋值: `<=`
- 时序逻辑: `always_ff`, `with_clk_and_rst`

== imported_counter.sv

供 `import_demo.rb` 使用的外部 SystemVerilog 参考模块，不含 RSV 代码。

提供: 模块参数 (`WIDTH`, `DEPTH`)、时钟/复位端口、unpacked 数组输出、
`always_comb` 组合逻辑、三元表达式、位切片等标准 SV 语法。

== 特性覆盖矩阵

#table(
  columns: (auto, auto),
  [*RSV 特性*], [*覆盖示例*],
  [`input`/`output`/`inout`], [所有示例],
  [`uint`/`sint`/`bit`/`bits`], [counter, syntax\_showcase, const\_demo 等],
  [`clock`/`reset`], [counter, syntax\_showcase, storage\_streams, generate\_demo, curried\_params, verilog\_wrapper],
  [`arr`/`mem`], [storage\_streams, mux\_cases, verilog\_wrapper, generate\_demo],
  [`wire`/`reg`], [counter, syntax\_showcase, storage\_streams, mux\_cases 等],
  [`const`(localparam)], [const\_demo, generate\_demo],
  [`<=`/`>=` 赋值], [所有示例 / auto\_dedup, manual\_dedup, syntax\_showcase],
  [算术/比较/逻辑/位运算], [syntax\_showcase],
  [归约运算 `.or_r`/`.and_r`], [syntax\_showcase, curried\_params],
  [移位运算 `<<`/`>>`], [syntax\_showcase],
  [位切片 `[]`], [syntax\_showcase, storage\_streams, generate\_demo],
  [`mux`/`mux1h`/`muxp`], [mux\_cases, syntax\_showcase],
  [`cat`/`fill`], [syntax\_showcase, storage\_streams],
  [`expr()`], [counter, syntax\_showcase],
  [`.as_sint` 类型转换], [syntax\_showcase],
  [`always_ff`/`always_comb`/`always_latch`], [syntax\_showcase 覆盖全部三种],
  [`svif`/`svelif`/`svelse`], [counter, syntax\_showcase, macro\_demo 等],
  [模块实例化与端口连接], [auto\_dedup, manual\_dedup, import\_demo, curried\_params],
  [子模块间自动布线], [auto\_dedup, manual\_dedup],
  [`definition`/`instance` 手动去重], [manual\_dedup],
  [`RSV.import_sv`], [import\_demo],
  [`sv_def`/`sv_ifdef` 等宏指令], [macro\_demo],
  [`sv_dref` 宏引用], [macro\_demo],
  [`generate_for`/`generate_if`], [generate\_demo],
  [generate-for + definition/instance], [generate\_demo],
  [generate-for + sv\_param 子模块], [generate\_demo],
  [generate-if + 局部 const], [generate\_demo],
  [`sv_param` 柯里化参数], [curried\_params],
  [`v_wrapper` Verilog wrapper], [verilog\_wrapper],
  [`sv_plugin` 内嵌 SV 代码], [sv\_plugin\_demo],
  [流式 API (`sv_map` 等)], [storage\_streams],
  [`attr:` 硬件属性], [（见 test/handler\_dsl\_test.rb 中的单元测试）],
)
