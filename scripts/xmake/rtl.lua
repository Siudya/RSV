local example_catalog = {
  {name = "auto_dedup", alias = "aut", summary = "automatic dedup and child-to-child auto wiring"},
  {name = "bundle_and_interface", alias = "bdi", summary = "bundle (struct) and interface definitions"},
  {name = "case_demo", alias = "cas", summary = "case/casez/casex with unique/priority and ? wildcards"},
  {name = "const_demo", alias = "cst", summary = "const localparam declarations and typed constants"},
  {name = "counter", alias = "ctr", summary = "parameterized sequential counter"},
  {name = "curried_params", alias = "cur", summary = "sv_param and curried parameter application"},
  {name = "generate_demo", alias = "gen", summary = "generate blocks, attributes, and staged pipelines"},
  {name = "global_dedup", alias = "glb", summary = "global auto dedup registry and RSV.export_all"},
  {name = "import_demo", alias = "imp", summary = "import existing SystemVerilog modules with pyslang"},
  {name = "macro_demo", alias = "mac", summary = "SystemVerilog macro directives and macro references"},
  {name = "manual_dedup", alias = "man", summary = "manual definition/instance dedup and auto wiring"},
  {name = "mux_cases", alias = "mux", summary = "mux, mux1h, muxp, bundle mux, as_uint, cat, reverse"},
  {name = "pop_count_demo", alias = "pop", summary = "pop_count and log2ceil bit-width utilities"},
  {name = "storage_streams", alias = "str", summary = "arr/mem storage shapes, fill helpers, and stream views"},
  {name = "sv_plugin_demo", alias = "svp", summary = "inline SystemVerilog embedding with sv_plugin"},
  {name = "syntax_showcase", alias = "syn", summary = "operators, slices, casts, and procedural blocks"},
  {name = "type_conv_demo", alias = "tcv", summary = "as_type conversion between scalar, bundle, and mem"},
  {name = "verilog_wrapper", alias = "vwr", summary = "Verilog-compatible wrapper generation for RSV modules"}
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
  print("name                    alias  feature summary")
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

    os.execv(ruby.program, {"-Ilib", script})
  end)

  set_menu {
    usage = "xmake rtl -f <name-or-alias> [-d dir] | xmake rtl -l",
    description = "Run a built-in example by name/alias or list built-in example features",
    options = {
      {"f", "script", "kv", nil, "Ruby script basename or built-in example alias"},
      {"d", "directory", "kv", "examples", "Directory that contains the Ruby script"},
      {"l", "list", "k", nil, "List built-in examples, aliases, and feature summaries"}
    }
  }
