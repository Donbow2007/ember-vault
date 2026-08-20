require "test_helper"
require "tmpdir"

class EmberVault::PathsTest < ActiveSupport::TestCase
  setup do
    @original_data_path = ENV["EMBER_VAULT_DATA_PATH"]
    @original_data_dir = ENV["EMBER_VAULT_DATA_DIR"]
    @temporary_root = Dir.mktmpdir("ember-vault-portable")
    ENV["EMBER_VAULT_DATA_PATH"] = @temporary_root
    ENV.delete("EMBER_VAULT_DATA_DIR")
  end

  teardown do
    ENV["EMBER_VAULT_DATA_PATH"] = @original_data_path
    ENV["EMBER_VAULT_DATA_DIR"] = @original_data_dir
    FileUtils.remove_entry(@temporary_root) if File.directory?(@temporary_root)
  end

  test "derives every persistent directory from one portable data root" do
    EmberVault::Paths.prepare!

    assert_equal Pathname.new(@temporary_root), EmberVault::Paths.data_root
    %w[archive_files content models backups config logs run].each do |directory|
      assert File.directory?(Pathname.new(@temporary_root).join(directory)), "expected #{directory} to be created"
    end
  end

  test "stores new paths relative to the data root and resolves them after a mount point change" do
    source = EmberVault::Paths.content_for("zim").join("water-guide.zim")

    assert_equal "content/zim/water-guide.zim", EmberVault::Paths.relative(source)
    assert_equal source, EmberVault::Paths.resolve("content/zim/water-guide.zim")
  end

  test "maps legacy storage paths into the configured portable root" do
    expected = Pathname.new(@temporary_root).join("content/map/arkansas.pmtiles")

    assert_equal expected, EmberVault::Paths.resolve("storage/content/map/arkansas.pmtiles")
  end

  test "rejects absolute and escaping stored paths" do
    assert_raises(ArgumentError) { EmberVault::Paths.resolve("/tmp/not-portable.pdf") }
    assert_raises(ArgumentError) { EmberVault::Paths.resolve("../../outside.pdf") }
  end
end
