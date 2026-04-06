# frozen_string_literal: true

require "digest"
require "securerandom"
require "fileutils"

module RSV
  # 全局 elaboration 注册表，自动收集所有已 elaborate 的模块模板。
  # 使用带运行时随机盐的 SHA256 哈希作为签名，相同 SV 代码仅存储一份。
  # 盐在每次 Ruby 进程启动时随机生成，确保哈希冲突时可通过重新运行解决。
  class ElaborationRegistry
    class << self
      # 注册一个模块的 SV 代码。相同签名只存一次。
      def register(module_name, sv_code)
        sig = signature(sv_code)
        @mutex.synchronize do
          return if @entries.key?(module_name) && @signatures[module_name] == sig
          @entries[module_name] = sv_code
          @signatures[module_name] = sig
        end
      end

      # 获取已注册模块的 SV 代码
      def fetch(module_name)
        @mutex.synchronize { @entries[module_name] }
      end

      # 检查模块是否已注册
      def registered?(module_name)
        @mutex.synchronize { @entries.key?(module_name) }
      end

      # 返回所有已注册的模块名
      def module_names
        @mutex.synchronize { @entries.keys.dup }
      end

      # 返回已注册模块数量
      def size
        @mutex.synchronize { @entries.size }
      end

      # 将所有已注册模块导出到指定目录，每个模块一个文件
      def export_all(dir)
        FileUtils.mkdir_p(dir)
        modules = @mutex.synchronize { @entries.dup }
        modules.each do |mod_name, sv_code|
          file_name = underscore(mod_name)
          path = File.join(dir, "#{file_name}.sv")
          File.write(path, "#{sv_code}\n")
        end
        modules.keys
      end

      # 清空注册表（主要用于测试）
      def clear!
        @mutex.synchronize do
          @entries.clear
          @signatures.clear
        end
      end

      # 重新生成盐（主要用于测试或处理极端哈希冲突）
      def reseed!
        @mutex.synchronize do
          @salt = SecureRandom.hex(16)
        end
      end

      private

      def signature(sv_code)
        Digest::SHA256.hexdigest("#{@salt}:#{sv_code}")
      end

      def underscore(name)
        name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end
    end

    # 初始化
    @mutex = Mutex.new
    @entries = {}
    @signatures = {}
    @salt = SecureRandom.hex(16)
  end
end
