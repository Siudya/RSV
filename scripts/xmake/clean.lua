task("clean")
  set_category("plugin")

  on_run(function ()
    if os.isdir("build") then
      os.rm("build")
    end
  end)

  set_menu {
    usage = "xmake clean",
    description = "Remove the build directory",
    options = {}
  }
