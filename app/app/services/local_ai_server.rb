require "etc"
require "fileutils"
require "net/http"
require "open3"

class LocalAiServer
  HOST = "127.0.0.1"
  PORT = ENV.fetch("EMBER_VAULT_AI_PORT", "8082")
  START_TIMEOUT = ENV.fetch("EMBER_VAULT_AI_START_TIMEOUT", "45").to_i

  def initialize(entry:)
    @entry = entry
  end

  def ensure_running!
    return true if healthy?

    start!
  end

  def healthy?
    return false unless process_alive?(stored_pid)

    response = Net::HTTP.start(HOST, PORT.to_i, open_timeout: 1, read_timeout: 2) { |http| http.get("/health") }
    response.is_a?(Net::HTTPSuccess)
  rescue SystemCallError, Timeout::Error
    false
  end

  def running?
    healthy?
  end

  def start!
    return true if healthy?

    stop!
    start
    wait_until_ready
  end

  def stop!
    pid = stored_pid
    if process_alive?(pid)
      Process.kill(Gem.win_platform? ? "KILL" : "TERM", pid)
      50.times do
        break unless process_alive?(pid)
        sleep 0.1
      end
      Process.kill("KILL", pid) if process_alive?(pid)
    end
    FileUtils.rm_f(pid_path)
    true
  rescue Errno::ESRCH
    FileUtils.rm_f(pid_path)
    true
  end

  def restart!
    stop!
    start!
  end

  def endpoint
    URI("http://#{HOST}:#{PORT}/v1/chat/completions")
  end

  private

  def start
    raise LocalAiRuntime::Error, "Model file is not installed: #{model_path}" unless model_path.file?
    raise LocalAiRuntime::Error, "llama-server is not installed" unless executable

    FileUtils.mkdir_p(log_path.dirname)
    log = File.open(log_path, "a")
    options = Gem.win_platform? ? { new_pgroup: true } : { pgroup: true }
    pid = spawn_server(command, log, options)
    Process.detach(pid)
    File.write(pid_path, pid)
  end

  def spawn_server(server_command, log, options)
    Process.spawn(*server_command, out: log, err: log, **options)
  rescue StandardError => error
    raise unless gpu_layers == "999"

    log.puts("GPU launch failed (#{error.message}); retrying CPU-only.")
    cpu_command = server_command.dup
    cpu_command[cpu_command.index("--n-gpu-layers") + 1] = "0"
    Process.spawn(*cpu_command, out: log, err: log, **options)
  end

  def command
    [
      executable, "--model", model_path.to_s, "--host", HOST, "--port", PORT,
      "--ctx-size", @entry.runtime.fetch("context", 2048).to_s,
      "--threads", ENV.fetch("EMBER_VAULT_AI_THREADS", [ Etc.nprocessors - 1, 1 ].max.to_s),
      "--n-gpu-layers", gpu_layers, "--alias", @entry.id
    ]
  end

  def gpu_layers
    ENV.fetch("EMBER_VAULT_GPU_LAYERS", "auto") == "auto" ? "999" : ENV.fetch("EMBER_VAULT_GPU_LAYERS")
  end

  def executable
    @executable ||= begin
      configured = ENV["LLAMA_SERVER_PATH"].presence
      name = Gem.win_platform? ? "llama-server.exe" : "llama-server"
      bundled = Rails.root.join("vendor", "llama.cpp", "build", "bin", name)
      configured || (bundled.to_s if bundled.file? && File.executable?(bundled)) || find_on_path(name)
    end
  end

  def find_on_path(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
      candidate = File.join(directory, name)
      return candidate if File.file?(candidate) && File.executable?(candidate)
    end
    nil
  end

  def model_path
    ModelCatalog.model_path(@entry)
  end

  def pid_path
    EmberVault::PortableStorage.path("tmp", "llama-server.pid")
  end

  def log_path
    EmberVault::PortableStorage.path("logs", "llama-server.log")
  end

  def stop_stale_process
    FileUtils.rm_f(pid_path) unless process_alive?(stored_pid)
  end

  def stored_pid
    Integer(File.read(pid_path))
  rescue Errno::ENOENT, ArgumentError
    nil
  end

  def process_alive?(pid)
    return false unless pid
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EINVAL
    false
  rescue Errno::EPERM
    true
  end

  def wait_until_ready
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + START_TIMEOUT
    until healthy?
      raise LocalAiRuntime::Error, "llama-server failed to start; see #{log_path}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.25
    end
    true
  end
end
