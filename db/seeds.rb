# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

Post.create!(
  title: 'Hướng dẫn kết nối WiFi cho thiết bị cảm biến',
  content: <<~HTML,
    <h2>Bước 1: Mở ứng dụng cấu hình</h2>
    <p>Truy cập ứng dụng trên điện thoại hoặc máy tính để bắt đầu kết nối.</p>

    <h2>Bước 2: Nhập thông tin WiFi</h2>
    <p>Nhập tên WiFi (SSID) và mật khẩu. Sau đó nhấn "Kết nối".</p>

    <h2>Bước 3: Xác nhận kết nối</h2>
    <p>Đợi khoảng 5–10 giây. Thiết bị sẽ hiển thị đèn xanh khi kết nối thành công.</p>
  HTML
  slug: 'huong-dan-ket-noi-wifi-cho-thiet-bi-cam-bien',
  published: true
)
