# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"

class XmakeRtlTest < Minitest::Test
  PROJECT_ROOT = File.expand_path("..", __dir__)
  COUNTER_SV = File.join(PROJECT_ROOT, "build", "rtl", "counter.sv")

  def test_xmake_rtl_runs_example_script_from_examples_by_default
    FileUtils.rm_f(COUNTER_SV)

    stdout, stderr, status = Open3.capture3("xmake", "rtl", "-f", "counter", chdir: PROJECT_ROOT)

    assert status.success?, "expected `xmake rtl -f counter` to succeed\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
    assert File.exist?(COUNTER_SV), "expected #{COUNTER_SV} to be generated"
    assert_operator File.size(COUNTER_SV), :>, 0
  end

  def test_xmake_rtl_accepts_a_custom_directory
    stdout, stderr, status = Open3.capture3("xmake", "rtl", "-f", "custom_demo", "-d", "test/fixtures/rtltask", chdir: PROJECT_ROOT)

    assert status.success?, "expected `xmake rtl -f custom_demo -d test/fixtures/rtltask` to succeed\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
    assert_includes stdout, "rtl fixture ok"
  end
end
