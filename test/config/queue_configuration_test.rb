require "test_helper"

class QueueConfigurationTest < ActiveSupport::TestCase
  test "worker listens to both application queues" do
    workers = SolidQueue::Configuration.new.configured_processes.select { |process| process.kind == :worker }

    assert_equal 1, workers.size
    assert_equal [ "default", "ai" ], workers.first.attributes.fetch(:queues)
  end
end
