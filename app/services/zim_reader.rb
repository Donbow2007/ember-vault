require "open3"

class ZimReader
  Entry = Data.define(:index, :path, :title, :mime_type)

  BUNDLED_ROOT = Rails.root.join("vendor", "zim_tools", "root")
  BUNDLED_BINARY = BUNDLED_ROOT.join("usr", "bin", "zimdump")
  BUNDLED_LIBRARY_PATH = BUNDLED_ROOT.join("usr", "lib", "x86_64-linux-gnu")
  READABLE_TYPES = %w[text/html application/pdf].freeze

  def initialize(path)
    @path = Pathname(path)
  end

  def each_readable_entry
    return enum_for(__method__) unless block_given?

    current = {}
    run("list", "--details", @path.to_s) do |line|
      if line.start_with?("path: ")
        yield_entry(current) { |entry| yield entry }
        current = { path: line.delete_prefix("path: ").strip }
      elsif line.match?(/^\* (title|idx|mime-type):/)
        key, value = line.delete_prefix("* ").split(":", 2)
        current[key.tr("-", "_").to_sym] = value.strip
      end
    end
    yield_entry(current) { |entry| yield entry }
  end

  def content(entry)
    content_by_index(entry.index)
  end

  def content_by_index(index)
    output, error, status = Open3.capture3(environment, binary, "show", "--idx=#{index}", @path.to_s, binmode: true)
    raise "Could not read ZIM entry #{index}: #{error.to_s.first(200)}" unless status.success?

    output
  end

  def content_by_path(path)
    output, error, status = Open3.capture3(environment, binary, "show", "--url=#{path}", @path.to_s, binmode: true)
    raise "Could not read ZIM asset: #{error.to_s.first(200)}" unless status.success?

    output
  end

  private

  def run(*arguments)
    Open3.popen3(environment, binary, *arguments) do |stdin, stdout, stderr, thread|
      stdin.close
      stdout.each_line { |line| yield line }
      error = stderr.read
      raise "ZIM reader failed: #{error.to_s.first(300)}" unless thread.value.success?
    end
  end

  def yield_entry(attributes)
    return unless READABLE_TYPES.include?(attributes[:mime_type]) && attributes[:idx].present?

    yield Entry.new(index: attributes[:idx].to_i, path: attributes[:path],
      title: attributes[:title].presence || attributes[:path], mime_type: attributes[:mime_type])
  end

  def environment
    BUNDLED_BINARY.executable? ? { "LD_LIBRARY_PATH" => BUNDLED_LIBRARY_PATH.to_s } : {}
  end

  def binary
    return BUNDLED_BINARY.to_s if BUNDLED_BINARY.executable?

    executable = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, "zimdump") }
      .find { |candidate| File.executable?(candidate) }
    raise "ZIM indexing requires zimdump from the zim-tools package" unless executable

    executable
  end
end
