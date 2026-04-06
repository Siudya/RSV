# frozen_string_literal: true

require "optparse"

module RSV
  # 程序主入口类，提供统一的命令行界面。
  #
  # 内置选项:
  #   -o, --out-dir DIR   SV 文件输出目录
  #
  # 用法:
  #   # 最简形式 — 一行完成
  #   RSV::App.main(MyTop.new)
  #
  #   # 自定义命令行参数与构建逻辑
  #   RSV::App.main do |app|
  #     app.option(:width, "-w", "--width WIDTH", Integer, "Data width", default: 8)
  #     app.build { |opts| MyTop.new(width: opts[:width]) }
  #   end
  #
  #   # 导出后回调（如生成 Verilog wrapper）
  #   RSV::App.main do |app|
  #     app.build { |opts| [ModA.new, ModB.new] }
  #     app.after_export do |opts, tops|
  #       tops.each { |t| t.v_wrapper(File.join(opts[:out_dir], "#{t.module_name}_wrapper.sv")) } if opts[:out_dir]
  #     end
  #   end
  class App
    attr_reader :opts

    def self.main(top = nil, &block)
      app = new
      block&.call(app)
      app.execute(top)
    end

    def initialize
      @opts = {}
      @custom_opts = []
      @build_block = nil
      @after_block = nil
    end

    # 注册自定义命令行选项
    #   key:     opts 哈希中的键名 (Symbol)
    #   args:    传给 OptionParser#on 的参数
    #   default: 默认值
    def option(key, *args, default: nil)
      @opts[key] = default
      @custom_opts << { key: key, args: args }
    end

    # 设置构建回调，在命令行解析完成后调用
    def build(&block)
      @build_block = block
    end

    # 设置导出后回调
    def after_export(&block)
      @after_block = block
    end

    def execute(top = nil)
      parse_argv!
      top = @build_block.call(@opts) if @build_block
      raise ArgumentError, "no top module provided" unless top

      tops = Array(top)
      tops.each(&:to_sv)

      out_dir = @opts[:out_dir]
      if out_dir
        exported = RSV.export_all(out_dir)
        @after_block&.call(@opts, tops)
        $stderr.puts "#{exported.size} modules → #{out_dir}/"
      else
        tops.each do |t|
          sv = ElaborationRegistry.fetch(t.module_name)
          $stdout.puts sv if sv
        end
        @after_block&.call(@opts, tops)
      end
    end

    private

    def parse_argv!
      parser = OptionParser.new do |p|
        p.banner = "Usage: ruby #{$PROGRAM_NAME} [options]"
        p.on("-o", "--out-dir DIR", "SV output directory") do |v|
          @opts[:out_dir] = v
        end

        @custom_opts.each do |opt|
          p.on(*opt[:args]) { |v| @opts[opt[:key]] = v }
        end
      end
      parser.parse!(ARGV)
    end
  end
end
