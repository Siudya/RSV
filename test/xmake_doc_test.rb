# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"

class XmakeDocTest < Minitest::Test
  PROJECT_ROOT = File.expand_path("..", __dir__)
  XMAKE_LUA = File.join(PROJECT_ROOT, "xmake.lua")
  DOC_PDF = File.join(PROJECT_ROOT, "build", "rsv_doc.pdf")

  def test_top_level_xmake_lua_only_includes_script_tasks
    assert File.exist?(XMAKE_LUA), "expected xmake.lua to exist"
    assert_equal 'includes("scripts/xmake/*.lua")', File.read(XMAKE_LUA).strip
  end

  def test_xmake_doc_builds_rsv_pdf_under_build_directory
    FileUtils.rm_f(DOC_PDF)

    stdout, stderr, status = Open3.capture3("xmake", "doc", chdir: PROJECT_ROOT)

    assert status.success?, "expected `xmake doc` to succeed\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
    assert File.exist?(DOC_PDF), "expected #{DOC_PDF} to be generated"
    assert_operator File.size(DOC_PDF), :>, 0
  end
end
