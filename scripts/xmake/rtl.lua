local example_catalog = {
  {name = "bundle_and_interface", alias = "bdi", summary = "BundleDef 类型定义与打平展开"},
  {name = "case_demo", alias = "cas", summary = "case/casez/casex、unique/priority 与 ? 通配"},
  {name = "const_demo", alias = "cst", summary = "const 本地参数与带类型常量"},
  {name = "counter", alias = "ctr", summary = "基于 meta 参数的顺序计数器"},
  {name = "curried_params", alias = "cur", summary = "meta 参数模块与复用定义句柄"},
  {name = "generate_demo", alias = "gen", summary = "generate 块、属性与流水线"},
  {name = "global_dedup", alias = "glb", summary = "自动/手动去重、自动布线与未连接端口"},
  {name = "import_demo", alias = "imp", summary = "借助 pyslang 导入外部 SystemVerilog 模块"},
  {name = "macro_demo", alias = "mac", summary = "SystemVerilog 宏指令与宏引用"},
  {name = "mux_cases", alias = "mux", summary = "mux、mux1h、muxp、打平与反转"},
  {name = "pop_count_demo", alias = "pop", summary = "pop_count 与 log2ceil 位宽工具"},
  {name = "storage_streams", alias = "str", summary = "数组/存储器形态、fill 与流式视图"},
  {name = "sv_plugin_demo", alias = "svp", summary = "通过 sv_plugin 内嵌原始 SystemVerilog"},
  {name = "syntax_showcase", alias = "syn", summary = "运算符、切片、类型转换与过程块"},
  {name = "type_conv_demo", alias = "tcv", summary = "as_type 在标量、BundleDef 类型与数组间转换"},
  {name = "verilog_wrapper", alias = "vwr", summary = "为 RSV 模块生成 Verilog 兼容封装层"}
}

local example_by_alias = {}
for _, entry in ipairs(example_catalog) do
  example_by_alias[entry.alias] = entry
end

local function resolve_example_name(name)
  local stem = name:gsub("%.rb$", "")
  local entry = example_by_alias[stem]
  if entry then
    return entry.name
  end
  return name
end

local function list_examples()
  print("名称                    别名   特性摘要")
  print("----------------------  -----  -----------------------------------------------")
  for _, entry in ipairs(example_catalog) do
    print(string.format("%-22s  %-5s  %s", entry.name, entry.alias, entry.summary))
  end
end

task("rtl")
  set_category("plugin")

  on_run(function ()
    import("core.base.option")
    import("lib.detect.find_tool")

    local ruby = find_tool("ruby")
    if not ruby then
      raise("ruby not found in PATH")
    end

    if option.get("list") then
      list_examples()
      return
    end

    local file = option.get("script")
    if not file then
      raise("missing required option: -f/--script")
    end

    local directory = option.get("directory") or "examples"
    if directory == "examples" then
      file = resolve_example_name(file)
    end

    if not file:match("%.rb$") then
      file = file .. ".rb"
    end

    local script = path.join(directory, file)
    if not os.isfile(script) then
      raise("rtl script not found: " .. script)
    end

    local outdir = option.get("outdir") or "build/rtl"

    os.execv(ruby.program, {"-Ilib", script, "-o", outdir})
  end)

  set_menu {
    usage = "xmake rtl -f <名称或别名> [-d 目录] [-o 输出目录] | xmake rtl -l",
    description = "运行内置示例，或列出示例别名与特性摘要",
    options = {
      {"f", "script", "kv", nil, "Ruby 脚本名或内置示例别名"},
      {"d", "directory", "kv", "examples", "包含 Ruby 脚本的目录"},
      {"o", "outdir", "kv", "build/rtl", "生成的 SV 输出目录"},
      {"l", "list", "k", nil, "列出内置示例、别名与特性摘要"}
    }
  }
