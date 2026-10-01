require "test_helper"

class LocalAiRuntimeTest < ActiveSupport::TestCase
  test "uses catalog default when no installed model exists" do
    runtime = LocalAiRuntime.new
    assert_equal ModelCatalog.default.id, runtime.profile
  end

  test "reports a missing model without spawning inference" do
    runtime = LocalAiRuntime.new(profile: ModelCatalog.default.id)
    assert_equal :model_missing, runtime.status unless ModelCatalog.model_path(ModelCatalog.default).file?
  end
end
