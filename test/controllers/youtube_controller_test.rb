require "test_helper"

class YoutubeControllerTest < ActionDispatch::IntegrationTest
  test "should get download_mp3" do
    get youtube_download_mp3_url
    assert_response :success
  end
end
