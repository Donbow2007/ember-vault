require "test_helper"

class ModelCatalogTest < ActiveSupport::TestCase
  test "catalog contains the three survival benchmark candidates" do
    assert_equal %w[survival-qwen-05b survival-llama-1b survival-gemma-1b], ModelCatalog.entries.map(&:id)
  end

  test "model paths live under portable model storage" do
    entry = ModelCatalog.find("survival-qwen-05b")
    expected_root = EmberVault::PortableStorage.path("models").expand_path
    assert_equal "survival-qwen-05b.gguf", ModelCatalog.model_path(entry).basename.to_s
    assert_equal expected_root.join(entry.filename).to_s, ModelCatalog.model_path(entry).to_s
  end
end
