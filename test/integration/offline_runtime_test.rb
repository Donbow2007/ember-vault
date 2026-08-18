require "test_helper"

class OfflineRuntimeTest < ActionDispatch::IntegrationTest
  test "browser runtime is restricted to local resources" do
    get root_url
    assert_response :success

    policy = response.headers.fetch("Content-Security-Policy")
    assert_includes policy, "default-src 'self'"
    assert_includes policy, "connect-src 'self'"
    assert_includes policy, "script-src 'self'"
    refute_match(/https?:\/\//, response.body.scan(/<(?:script|link|img)[^>]+>/i).join)
  end

  test "setup UI has no remote browser assets" do
    get setup_url
    assert_response :success
    resource_tags = response.body.scan(/<(?:script|link|img|iframe|video|audio|source)[^>]+>/i).join
    refute_match(/(?:src|href)=["']https?:\/\//i, resource_tags)
  end

  test "primary navigation is shared across application pages" do
    [ root_url, documents_url, downloads_url, maps_url, setup_url ].each do |url|
      get url
      assert_response :success
      assert_select "body > header.topbar nav.primary-nav", count: 1
      assert_select "body > header.topbar a.brand[href='#{root_path}']", count: 1
    end
  end
end
