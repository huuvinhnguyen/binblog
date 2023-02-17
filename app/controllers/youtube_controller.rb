

require 'streamio-ffmpeg'

class YoutubeController < ApplicationController
  def download_mp3
    video_url = params[:video_url]

    if video_url.present? 
      # # Tải xuống video YouTube dưới dạng tệp MP4
      # video = YoutubeDL::Video.new(video_url, { format: 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best' })
      # video_path = video.download
      #
      # # Chuyển đổi tệp MP4 thành tệp MP3
      # movie = FFMPEG::Movie.new(video_path)
      # mp3_path = "#{Rails.root}/tmp/#{SecureRandom.hex}.mp3"
      # movie.transcode(mp3_path, audio_codec: 'libmp3lame')
      #
      # # Gửi tệp MP3 dưới dạng tải xuống
      # send_file mp3_path, type: 'audio/mpeg', disposition: 'attachment', filename: "#{video.title}.mp3"
      #
      # # Xóa các tệp tạm thời
      # File.delete(video_path)
      # File.delete(mp3_path) 

      # Tạo đường dẫn tạm thời để lưu video
      #
      tmp_file_path = "#{Rails.root}/tmp/#{SecureRandom.hex}.mp4"

      # Tải video về
      movie = FFMPEG::Movie.new(video_url)
      movie.transcode(tmp_file_path)

      # Chuyển đổi video sang file audio mp3
      output_path = "#{Rails.root}/tmp/#{SecureRandom.hex}.mp3"
      movie.to_audio(output_path)

      # Trả về file audio mp3 cho người dùng
      send_file output_path, type: 'audio/mp3', disposition: 'attachment'  

    end


  end
end

