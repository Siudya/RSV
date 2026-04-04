task("rtl")
  set_category("plugin")

  on_run(function ()
    import("core.base.option")
    import("lib.detect.find_tool")

    local ruby = find_tool("ruby")
    if not ruby then
      raise("ruby not found in PATH")
    end

    local file = option.get("script")
    if not file then
      raise("missing required option: -f/--script")
    end

    local directory = option.get("directory") or "examples"
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
    usage = "xmake rtl -f <name> [-d dir]",
    description = "Run <dir>/<name>.rb with Ruby, defaulting dir to examples",
    options = {
      {"f", "script", "kv", nil, "Ruby script basename, with or without .rb"},
      {"d", "directory", "kv", "examples", "Directory that contains the Ruby script"}
    }
  }
