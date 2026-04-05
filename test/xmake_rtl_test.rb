# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"

class XmakeRtlTest < Minitest::Test
  PROJECT_ROOT = File.expand_path("..", __dir__)
  BUILD_DIR = File.join(PROJECT_ROOT, "build")
  COUNTER_SV = File.join(PROJECT_ROOT, "build", "rtl", "counter.sv")
  AUTO_DEDUP_TOP_SV = File.join(PROJECT_ROOT, "build", "rtl", "auto_dedup_top.sv")
  MANUAL_DEDUP_TOP_SV = File.join(PROJECT_ROOT, "build", "rtl", "manual_dedup_top.sv")

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

  def test_xmake_rtl_runs_auto_and_manual_dedup_examples
    FileUtils.rm_f(AUTO_DEDUP_TOP_SV)
    FileUtils.rm_f(MANUAL_DEDUP_TOP_SV)

    auto_stdout, auto_stderr, auto_status = Open3.capture3("xmake", "rtl", "-f", "auto_dedup", chdir: PROJECT_ROOT)
    manual_stdout, manual_stderr, manual_status = Open3.capture3("xmake", "rtl", "-f", "manual_dedup", chdir: PROJECT_ROOT)

    assert auto_status.success?, "expected `xmake rtl -f auto_dedup` to succeed\nstdout:\n#{auto_stdout}\nstderr:\n#{auto_stderr}"
    assert manual_status.success?, "expected `xmake rtl -f manual_dedup` to succeed\nstdout:\n#{manual_stdout}\nstderr:\n#{manual_stderr}"
    assert File.exist?(AUTO_DEDUP_TOP_SV), "expected #{AUTO_DEDUP_TOP_SV} to be generated"
    assert File.exist?(MANUAL_DEDUP_TOP_SV), "expected #{MANUAL_DEDUP_TOP_SV} to be generated"
  end

  def test_xmake_clean_removes_build_directory
    stale_file = File.join(BUILD_DIR, "stale.txt")
    FileUtils.mkdir_p(BUILD_DIR)
    File.write(stale_file, "stale build output")

    stdout, stderr, status = Open3.capture3("xmake", "clean", chdir: PROJECT_ROOT)

    assert status.success?, "expected `xmake clean` to succeed\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
    refute Dir.exist?(BUILD_DIR), "expected #{BUILD_DIR} to be removed by `xmake clean`"
  end
end
