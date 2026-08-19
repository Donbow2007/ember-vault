require "open3"

class LocalAiRuntime
  class Error < StandardError; end
  class TimeoutError < Error; end
  class CancelledError < Error; end

  MAX_TIMEOUT_SECONDS = 4
  TIMEOUT_SECONDS = ENV.fetch("EMBER_VAULT_AI_TIMEOUT", MAX_TIMEOUT_SECONDS).to_i.clamp(1, MAX_TIMEOUT_SECONDS)
  MODEL_FILES = {
    "smollm2-135m" => "smollm2-135m.gguf",
    "smollm2-360m" => "smollm2-360m.gguf"
  }.freeze
  GROUNDING_STOP_WORDS = %w[a an and are as at be by for from has have in is it of on or that the this to was were will with you your].to_set.freeze

  attr_reader :profile

  def initialize(profile: nil)
    @profile = profile.presence || SetupConfiguration.order(created_at: :desc).pick(:ai_profile) || "source-assistant"
  end

  def available?
    executable_path.present? && model_path&.file?
  end

  def status
    return :source_only unless MODEL_FILES.key?(profile)
    return :runtime_missing if executable_path.blank?
    return :model_missing unless model_path&.file?

    :ready
  end

  def generate(prompt, cancelled: -> { false })
    raise Error, "Local model runtime is not ready" unless available?

    stdout, stderr, process_status = capture(command(prompt), cancelled:)
    raise Error, stderr.to_s.squish.presence || "Local model exited with status #{process_status.exitstatus}" unless process_status.success?

    output = clean_output(stdout)
    if output.exclude?("[1]") && prompt.source_count == 1 && output != AssistantPrompt::INSUFFICIENT_MESSAGE
      output = "#{output} [1]"
    end
    raise Error, "Local model returned an unusable response" if unusable_output?(output, prompt)

    output
  end

  def model_path
    configured = ENV["EMBER_VAULT_MODEL_PATH"].presence
    return Pathname.new(configured).expand_path if configured

    filename = MODEL_FILES[profile]
    Rails.root.join("storage", "models", filename) if filename
  end

  private

  def executable_path
    @executable_path ||= begin
      configured = ENV["LLAMA_COMPLETION_PATH"].presence || ENV["LLAMA_CLI_PATH"].presence
      executable = Gem.win_platform? ? "llama-completion.exe" : "llama-completion"
      bundled = Rails.root.join("vendor", "llama.cpp", "build", "bin", executable)
      configured || (bundled.to_s if bundled.file? && File.executable?(bundled)) ||
        find_executable(Gem.win_platform? ? %w[llama-completion.exe llama-completion] : %w[llama-completion])
    end
  end

  def find_executable(names)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
      names.each do |name|
        candidate = File.join(directory, name)
        return candidate if File.file?(candidate) && File.executable?(candidate)
      end
    end
    nil
  end

  def command(prompt)
    [ executable_path,
      "--model", model_path.to_s,
      "--prompt", prompt.completion_prompt,
      "--no-conversation",
      "--threads", ENV.fetch("EMBER_VAULT_AI_THREADS", "2"),
      "--threads-batch", ENV.fetch("EMBER_VAULT_AI_THREADS", "2"),
      "--ctx-size", ENV.fetch("EMBER_VAULT_AI_CONTEXT", "1024"),
      "--predict", ENV.fetch("EMBER_VAULT_AI_TOKENS", "96"),
      "--batch-size", "128", "--ubatch-size", "128",
      "--gpu-layers", "0", "--prio", "-1", "--poll", "0",
      "--temp", "0", "--seed", "42", "--repeat-penalty", "1.08",
      "--no-display-prompt", "--simple-io" ]
  end

  def capture(command, cancelled: -> { false })
    spawn_options = Gem.win_platform? ? {} : { pgroup: true }
    stdin, stdout, stderr, wait_thread = Open3.popen3(*command, **spawn_options)
    stdin.close
    stdout_reader = Thread.new { stdout.read }
    stderr_reader = Thread.new { stderr.read }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECONDS

    loop do
      break if wait_thread.join(0.2)

      if cancelled.call
        terminate(wait_thread.pid)
        wait_thread.join(2)
        raise CancelledError, "Local model response was stopped"
      end

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        terminate(wait_thread.pid)
        wait_thread.join(2)
        raise TimeoutError, "Local model exceeded the #{TIMEOUT_SECONDS}-second limit"
      end
    end

    [ stdout_reader.value, stderr_reader.value, wait_thread.value ]
  ensure
    stdin&.close unless stdin&.closed?
    stdout&.close unless stdout&.closed?
    stderr&.close unless stderr&.closed?
  end

  def terminate(pid)
    target = Gem.win_platform? ? pid : -pid
    Process.kill("TERM", target)
    sleep 0.25
    Process.kill("KILL", target)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def clean_output(output)
    output.to_s
      .gsub(/\e\[[0-9;]*[A-Za-z]/, "")
      .sub(/\A\s*assistant\s*[:>]\s*/i, "")
      .sub(/\s*\[end of text\]\s*\z/i, "")
      .strip
      .first(8_000)
  end

  def unusable_output?(output, prompt)
    output.blank? || output.match?(/\A(?:Question|Format|Sources):/i) ||
      !output.match?(/\[\d+\]/) || !grounded_output?(output, prompt.source_text)
  end

  def grounded_output?(output, source_text)
    source_words = source_text.downcase.scan(/[[:alnum:]]+/)
    output_words = output.downcase.gsub(/\[\d+\]/, "").scan(/[[:alnum:]]+/)
    source_numbers = source_words.grep(/\A\d/).to_set
    return false unless output_words.grep(/\A\d/).all? { |number| source_numbers.include?(number) }

    meaningful = output_words.reject { |word| word.length < 3 || GROUNDING_STOP_WORDS.include?(word) }
    return true if meaningful.empty?

    supported = meaningful.count do |word|
      source_words.any? { |source_word| source_word.start_with?(word) || word.start_with?(source_word) }
    end
    supported.fdiv(meaningful.size) >= 0.58
  end
end
