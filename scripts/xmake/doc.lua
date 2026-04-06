task("doc")
  set_category("plugin")

  on_run(function ()
    import("lib.detect.find_tool")

    local typst = find_tool("typst")
    if not typst then
      raise("typst not found in PATH")
    end

    os.mkdir("build")
    os.execv(typst.program, {"compile", "docs/index.typ", "build/rsv_doc.pdf"})
  end)

  set_menu {
    usage = "xmake doc",
    description = "把 Typst 文档编译为 build/rsv_doc.pdf",
    options = {}
  }
