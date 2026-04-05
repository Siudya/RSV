= 示例文件特性覆盖

本文档描述 `examples/` 目录下每一个示例文件所覆盖的 RSV 特性。

== 使用 xmake 运行示例

```bash
xmake rtl -l
xmake rtl -f ctr
xmake rtl -f syn
```

- `xmake rtl -l` 列出所有内置示例、3-4 字符别名与特性摘要。
- `xmake rtl -f <名称或别名>` 运行 `examples/` 目录下的内置示例。
- `xmake rtl -f name -d dir` 可运行自定义目录下的 Ruby 脚本。

== 内置示例目录

#table(
  columns: (auto, auto, auto),
  [*名称*], [*别名*], [*特性摘要*],
  [`auto_dedup`], [`aut`], [自动去重与子模块自动布线],
  [`bundle_and_interface`], [`bdi`], [Bundle (struct) 与 Interface 支持],
  [`const_demo`], [`cst`], [`const` / `localparam` 常量声明],
  [`counter`], [`ctr`], [基础参数化顺序计数器],
  [`curried_params`], [`cur`], [`sv_param` 与柯里化参数],
  [`generate_demo`], [`gen`], [generate 块、属性与多级流水],
  [`import_demo`], [`imp`], [导入外部 SystemVerilog 模块签名],
  [`macro_demo`], [`mac`], [宏定义、条件编译与宏引用],
  [`manual_dedup`], [`man`], [手动 `definition` / `instance` 去重],
  [`mux_cases`], [`mux`], [`mux` / `mux1h` / `muxp`],
  [`pop_count_demo`], [`pop`], [`pop_count` / `log2ceil`],
  [`case_demo`], [`cas`], [`svcase` / `svcasez` / `unique` / `priority`],
  [`storage_streams`], [`str`], [arr/mem 形态、fill 与流式 API],
  [`sv_plugin_demo`], [`svp`], [内嵌原始 SystemVerilog 代码],
  [`syntax_showcase`], [`syn`], [操作符、切片、类型转换与过程块],
  [`verilog_wrapper`], [`vwr`], [Verilog 兼容 wrapper 生成],
)

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
- `mux1h`/`muxp` 使用赋值语法: `out <= mux1h(sel, dats)`, `lsb_first:`
- 组合逻辑: `always_comb`

== pop_count_demo.rb

population count 与 log2ceil 位宽计算。

- 端口声明: `input`, `output`
- 类型构造: `uint`
- 局部声明: `wire`
- `log2ceil(n)`: 编译期位宽计算（ceil(log2(n))）
- `pop_count(vec)`: 人口计数，展开为 for 循环累加器
- 组合逻辑: `always_comb`

== case_demo.rb

case/casez 语句及 unique/priority 限定符。

- 端口声明: `input`, `output`
- 类型构造: `clock`, `reset`, `uint`, `bit`
- 局部声明: `wire`, `reg`(含初始值)
- `svcase(expr) { is(val) { ... } fallin { ... } }`: case 语句
- `svcasez(expr, unique: true)`: unique casez 语句
- casez `?` 通配符: `is("4'b1??0")`
- 多值匹配: `is(val1, val2) { ... }`
- `svif(cond, unique: true)`: unique if 限定符
- 链式 `svif(...) { }.svelif(...) { }.svelse { }` 紧凑写法
- case 在 `always_ff` 内使用非阻塞赋值
- 赋值: `<=`
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- 组合逻辑: `always_comb`
- 输出: `to_sv(path)`

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

Verilog 兼容 wrapper 产生器，展示所有端口类型的展开。

- 端口声明: `input`, `output`, `intf`
- 类型构造: `clock`, `reset`, `arr`, `mem`, `uint`, `bit`
- Bundle 定义: `BundleDef` + `field` 声明
- Interface 定义: `InterfaceDef` + `output`/`input` 方向声明
- 局部声明: `reg`(含初始值)
- 赋值: `<=`
- 数组/存储器索引: `[]`
- 算术运算: `+`
- 时序逻辑: `always_ff`, `with_clk_and_rst`
- Verilog wrapper: `v_wrapper(path, wrapper_name:)` 生成端口打平的 Verilog 兼容顶层
  - packed 数组端口打平为位向量直连
  - unpacked 数组端口展开为独立标量端口
  - interface 端口展开为各字段的平坦端口，内部例化 interface 连线
  - bundle (struct) 端口展开为各字段的平坦端口，支持嵌套递归展开
  - `mem(N, Bundle)` 端口同时展开维度和字段
  - interface 含 bundle 字段时递归展开 payload
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

== bundle_and_interface.rb

Bundle (struct) 与 Interface 综合演示。

- Bundle 定义: `RSV::BundleDef` 子类，`field` 声明字段
- Bundle 参数化: `sv_param("W", 8)` 与柯里化 `.new.(W: 16)`
- Bundle 嵌套: 在另一个 Bundle 的字段中引用其他 Bundle
- Bundle 作为端口类型: `input("px_in", Pixel.new)`, `output("px_out", Pixel.new)`
- Bundle 作为 reg 类型: `reg("px_r", Pixel.new, init: { ... })`
- Bundle 部分初始化: 仅列出的字段在 `always_ff` 中产生 reset
- Bundle 字段访问: `handler.field_name` 读写
- Bundle 与 mem 组合: `mem(N, BundleType.new)` → unpacked struct 数组
- Bundle 去重: 不同 sv\_param 值产生不同 typedef 名
- Interface 定义: `RSV::InterfaceDef` 子类，`input`/`output` 声明信号方向（从 master 视角）
- Interface 自动 modport: 自动生成 `mst`（按声明方向）和 `slv`（反转方向）
- Interface 含 struct 字段: `output "payload", DataPacket.new.(W: 32)`
- Interface 端口: `intf("bus", StreamIntf.new.slv)` 声明 slave modport 端口
- Interface 整体互联: `mst <= slv` 或 `slv >= mst` 展开为每个字段的 assign
- Interface 字段单独赋值: `bus.data <= signal`
- 元参数 Interface: `build(payload_t:)`, `build(addr_w:, data_w:)`
- 模板化模块: Bundle 类型作为模块元参数传递
- 输出: `to_sv(path)`, `intf_def.to_sv(path)`

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
  [`pop_count`], [pop\_count\_demo],
  [`log2ceil`], [pop\_count\_demo],
  [`cat`/`fill`], [syntax\_showcase, storage\_streams],
  [`expr()`], [counter, syntax\_showcase],
  [`.as_sint` 类型转换], [syntax\_showcase],
  [`always_ff`/`always_comb`/`always_latch`], [syntax\_showcase 覆盖全部三种],
  [`svif`/`svelif`/`svelse` 链式写法], [counter, syntax\_showcase, macro\_demo, case\_demo],
  [`svcase`/`svcasez` case 语句 (`is`/`fallin`)], [case\_demo],
  [`casez ? 通配符`], [case\_demo],
  [`unique`/`priority` 限定符], [case\_demo],
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
  [`v_wrapper` Interface 端口展开], [verilog\_wrapper],
  [`v_wrapper` Bundle 端口展开], [verilog\_wrapper],
  [`v_wrapper` mem(N, Bundle) 展开], [verilog\_wrapper],
  [`v_wrapper` Interface 含 Bundle 展开], [verilog\_wrapper],
  [`sv_plugin` 内嵌 SV 代码], [sv\_plugin\_demo],
  [流式 API (`sv_map` 等)], [storage\_streams],
  [`attr:` 硬件属性], [（见 test/handler\_dsl\_test.rb 中的单元测试）],
  [`BundleDef` struct 定义], [bundle\_and\_interface],
  [Bundle 参数化 (`sv_param`)], [bundle\_and\_interface],
  [Bundle 嵌套], [bundle\_and\_interface],
  [Bundle 部分初始化], [bundle\_and\_interface],
  [Bundle 字段访问], [bundle\_and\_interface],
  [Bundle + `mem`/`arr`], [bundle\_and\_interface],
  [`InterfaceDef` 定义], [bundle\_and\_interface],
  [Interface 自动 modport (`mst`/`slv`)], [bundle\_and\_interface],
  [Interface 含 struct], [bundle\_and\_interface],
  [`intf()` 端口声明与 `.slv`], [bundle\_and\_interface],
  [Interface 整体互联 (`<=`/`>=`)], [bundle\_and\_interface],
  [Interface 字段单独赋值], [bundle\_and\_interface],
)
