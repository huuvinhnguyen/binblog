# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

# Post.create!(
#   title: 'Hướng dẫn kết nối WiFi cho thiết bị cảm biến',
#   content: <<~HTML,
#     <h2>Bước 1: Mở ứng dụng cấu hình</h2>
#     <p>Truy cập ứng dụng trên điện thoại hoặc máy tính để bắt đầu kết nối.</p>

#     <h2>Bước 2: Nhập thông tin WiFi</h2>
#     <p>Nhập tên WiFi (SSID) và mật khẩu. Sau đó nhấn "Kết nối".</p>

#     <h2>Bước 3: Xác nhận kết nối</h2>
#     <p>Đợi khoảng 5–10 giây. Thiết bị sẽ hiển thị đèn xanh khi kết nối thành công.</p>
#   HTML
#   slug: 'huong-dan-ket-noi-wifi-cho-thiet-bi-cam-bien',
#   published: true
# )

# Post.create!(
#   title: 'Cho Gà Ăn Bằng Thiết Bị Tự Động – Giải Pháp Chăn Nuôi Hiện Đại',
#   content: <<~HTML,
#     <h2>Giới thiệu hệ thống cho ăn tự động</h2>
#     <p>Việc cho gà ăn thủ công mỗi ngày tốn nhiều thời gian và công sức. Với thiết bị cho ăn tự động, người chăn nuôi có thể tiết kiệm đáng kể chi phí và thời gian, đồng thời đảm bảo đàn gà luôn được cung cấp thức ăn đầy đủ.</p>

#     <h2>Ưu điểm nổi bật</h2>
#     <ul>
#       <li>Tự động phân phối thức ăn đúng giờ</li>
#       <li>Giảm lãng phí, tối ưu chi phí</li>
#       <li>Thích hợp cho cả mô hình nhỏ và trang trại lớn</li>
#     </ul>

#     <h2>Video thực tế</h2>
#     <div style="position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden;">
#       <iframe 
#         src="https://www.youtube.com/embed/uZruiC1Ln0w" 
#         frameborder="0" 
#         allowfullscreen 
#         style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;">
#       </iframe>
#     </div>

#     <p>Hệ thống có thể tùy chỉnh theo nhu cầu, dễ dàng lắp đặt và bảo trì.</p>

#     <h2>Kết luận</h2>
#     <p>Thiết bị cho gà ăn tự động là một bước tiến quan trọng trong chăn nuôi thông minh. Hãy áp dụng để nâng cao hiệu quả và chất lượng chăn nuôi của bạn!</p>
#   HTML
#   slug: 'cho-ga-an-tu-dong-giai-phap-chan-nuoi',
#   published: true
# )
puts "Seeding device..."

Device.create!(
  name: "Cho cá ăn",
  chip_id: "esp8266_11367634",
  status: 1, # giả sử 1 là trạng thái đang hoạt động
  is_payment: false,
  device_type: "switch",
  device_info: {
    device_type: "switch",
    topic_type: "switchon",
    device_id: "esp8266_11367634",
    switch_value: nil,
    update_at: 1749784469,
    longlast: nil,
    timetrigger: nil,
    relays: [
      {
        switch_value: 0,
        longlast: 0,
        is_reminders_active: true,
        reminders: [
          {
            start_time: "2025-05-27T07:05:00+07:00",
            duration: 120000,
            repeat_type: "daily"
          },
          {
            start_time: "2025-05-29T09:11:00+07:00",
            duration: 60000,
            repeat_type: "daily"
          }
        ]
      }
    ],
    last_seen: "2025-06-06 11:58:21 +0700",
    local_ip: "192.168.1.249",
    build_version: 0,
    app_version: "1.0.0",
    update_url: "https://khuonvien.com/latest_version.bin"
  }.to_json,
  trigger: nil,
  url_firmware: "https://khuonvien.com/latest_version.bin",
  note: "Cho cá ăn",
  meta_info: {}.to_json
)

puts "Done!"

UserRelayFeature.create!(
  user: User.first,
  device: Device.first,
  feature: "reminder",
  enabled: false,
  note: "Admin đã vô hiệu hoá tạm thời"
)
