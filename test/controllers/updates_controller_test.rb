require "test_helper"

class UpdatesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "shows installed version and update controls" do
    get updates_url

    assert_response :success
    assert_select ".update-version", text: /V0.1.0/
    assert_select "form[action='#{check_updates_path}']"
    assert_select "form[action='#{install_updates_path}']"
  end

  test "queues a local update request" do
    assert_enqueued_with(job: ApplicationUpdateJob) do
      post install_updates_url
    end

    assert_redirected_to updates_url
  end

  test "blocks remote update installation by default" do
    post install_updates_url, headers: { "REMOTE_ADDR" => "192.0.2.10" }

    assert_redirected_to updates_url
    assert_no_enqueued_jobs only: ApplicationUpdateJob
  end
end
