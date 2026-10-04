require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "pathname"
require_relative "../lib/ember_vault/runtime_paths"

class RuntimePathsTest < Minitest::Test
  def test_bundled_node_wins_over_host_and_override
    previous = ENV.to_h
    Dir.mktmpdir do |root|
      node = File.join(root, "runtime/node/bin/node")
      FileUtils.mkdir_p(File.dirname(node))
      File.write(node, "")
      File.chmod(0o755, node)
      ENV["EMBER_VAULT_BUNDLED_RUNTIME"] = "1"
      ENV["EMBER_VAULT_NODE_BIN"] = "/host/node"
      assert_equal node, EmberVault::RuntimePaths.executable("node", root: root)
      Object.const_set(:Rails, Module.new) unless defined?(Rails)
      Rails.define_singleton_method(:root) { Pathname.new(root) } unless Rails.respond_to?(:root)
      original_root = Rails.method(:root)
      begin
        Rails.define_singleton_method(:root) { Pathname.new(root) }
        require_relative "../app/services/map_indexer"
        assert_equal node, MapIndexer.node_binary
      ensure
        Rails.define_singleton_method(:root, original_root)
      end
      FileUtils.rm_f(node)
      assert_raises(RuntimeError) { EmberVault::RuntimePaths.executable("node", root: root) }
    end
  ensure
    ENV.replace(previous)
  end
end

require_relative "../app/services/local_ai_server"
class LocalAiRuntime
  class Error < StandardError; end
end unless defined?(LocalAiRuntime)

class PortableAiFallbackTest < Minitest::Test
  class Server < LocalAiServer
    attr_reader :attempts
    def initialize(log, fail_always: false)
      super(entry: nil)
      @log = log
      @attempts = []
      @fail_always = fail_always
    end
    def healthy? = false
    def stop! = true
    private
    def log_path = @log
    def start = @attempts << gpu_layers
    def wait_until_ready
      raise LocalAiRuntime::Error, "process exited after spawn" if @attempts.size == 1 || @fail_always
      true
    end
  end

  def test_process_failure_after_gpu_spawn_retries_cpu
    previous = ENV["EMBER_VAULT_GPU_LAYERS"]
    ENV["EMBER_VAULT_GPU_LAYERS"] = "auto"
    Dir.mktmpdir do |root|
      server = Server.new(Pathname.new(root).join("ai.log"))
      assert server.start!
      assert_equal [ "999", "0" ], server.attempts
    end
  ensure
    ENV["EMBER_VAULT_GPU_LAYERS"] = previous
  end

  def test_explicit_cpu_failure_is_reported
    previous = ENV["EMBER_VAULT_GPU_LAYERS"]
    ENV["EMBER_VAULT_GPU_LAYERS"] = "0"
    Dir.mktmpdir do |root|
      server = Server.new(Pathname.new(root).join("ai.log"), fail_always: true)
      assert_raises(LocalAiRuntime::Error) { server.start! }
      assert_equal [ "0" ], server.attempts
    end
  ensure
    ENV["EMBER_VAULT_GPU_LAYERS"] = previous
  end
end
