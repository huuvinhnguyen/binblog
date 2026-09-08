# Release Production Guide

## Tổng quan

Tài liệu này mô tả quy trình deploy và release code lên môi trường production cho ứng dụng Binblog.

## Yêu cầu

- Quyền truy cập SSH vào production server
- Quyền sudo để restart services
- Git access đến repository

## Services cần kiểm tra/restart

- **sidekiq** - Background job processor và MQTT listener
- **nginx** - Web server / Reverse proxy  
- **myapp** - Rails application (Puma/Passenger)
- **mosquitto** - MQTT broker (chỉ restart khi có thay đổi cấu hình hoặc sự cố)

---

## Release Checklist

### Pre-deployment

- [ ] Code đã được review và approve
- [ ] Tests đã pass trên CI/CD
- [ ] Database migrations đã được kiểm tra
- [ ] Backup database hiện tại
- [ ] Thông báo cho team về thời gian deploy
- [ ] Kiểm tra disk space trên server

### Deployment Steps

#### 1. Kết nối đến Production Server

```bash
ssh user@production-server
cd /path/to/binblog
```

#### 2. Pull Code mới nhất

```bash
# Stash local changes (if any)
git stash

# Pull latest code
git pull origin main

# Check current commit
git log -1 --oneline
```

#### 3. Install Dependencies

```bash
# Install Ruby gems
bundle install --deployment --without development test

# Install Node packages (if using)
yarn install --check-files
```

#### 4. Database Migration

```bash
# Check pending migrations
RAILS_ENV=production bundle exec rails db:migrate:status

# Run migrations
RAILS_ENV=production bundle exec rails db:migrate

# Rollback command (if needed)
# RAILS_ENV=production bundle exec rails db:rollback STEP=1
```

#### 5. Precompile Assets

```bash
# Clean old assets
RAILS_ENV=production bundle exec rails assets:clobber

# Precompile new assets
RAILS_ENV=production bundle exec rails assets:precompile
```

#### 6. Restart Services

**Thứ tự khuyến nghị:**

```bash
# 1. Stop Sidekiq first (no new jobs)
sudo systemctl stop sidekiq

# 2. Restart application
sudo systemctl restart myapp

# 3. Restart Sidekiq
sudo systemctl restart sidekiq

# 4. Reload Nginx (zero-downtime)
sudo systemctl reload nginx
# Or restart if config changed
sudo systemctl restart nginx
```

#### 7. Verify Services

```bash
# Check all services status
sudo systemctl status sidekiq
sudo systemctl status myapp
sudo systemctl status nginx
sudo systemctl status mosquitto --no-pager -l

# Check application logs
tail -f /path/to/binblog/log/production.log

# Check Nginx logs
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# Check Sidekiq is processing
# Visit: https://yourdomain.com/sidekiq
```

### Post-deployment

- [ ] Kiểm tra trang chủ load thành công
- [ ] Test các chức năng chính
- [ ] Kiểm tra API endpoints
- [ ] Monitor error logs trong 15-30 phút
- [ ] Kiểm tra Sidekiq jobs đang chạy
- [ ] Kiểm tra Mosquitto đang `active` và port `1883` có thể kết nối
- [ ] Xác nhận MQTT listener đã subscribe topic `device` trong log Sidekiq
- [ ] Thông báo deploy thành công cho team
- [ ] Tag release version trong Git

---

## Systemctl Commands Reference

### Check Service Status

```bash
# Check if service is running
sudo systemctl is-active sidekiq

# Check service status
sudo systemctl status sidekiq

# Check service logs
sudo journalctl -u sidekiq -f
sudo journalctl -u myapp -f
sudo journalctl -u nginx -f
sudo journalctl -u mosquitto -f
```

### Check Production Logs

Chạy tại thư mục deploy của ứng dụng:

```bash
# Xem 100 dòng log gần nhất
tail -n 100 log/production.log

# Theo dõi log production theo thời gian thực
tail -f log/production.log

# Chỉ theo dõi log MQTT
tail -f log/production.log | grep --line-buffered '\[MQTT\]'
```

### Check Mosquitto Status

```bash
# Check if Mosquitto is running
sudo systemctl is-active mosquitto
sudo systemctl status mosquitto --no-pager -l

# Check if the broker is listening on the standard MQTT port
sudo ss -lntp | grep ':1883'

# Check recent logs
sudo journalctl -u mosquitto -n 100 --no-pager

# Follow logs in real time
sudo journalctl -u mosquitto -f

# Check connectivity from the application server
nc -vz -w 5 103.9.77.155 1883
```

### MQTT Publish/Subscribe Example

Mở terminal thứ nhất để subscribe topic:

```bash
mosquitto_sub -h khuonvien.vn -t test/topic -v
```

Mở terminal thứ hai để publish một message thử nghiệm:

```bash
mosquitto_pub -h khuonvien.vn -t test/topic -m "Hello MQTT"
```

Terminal subscribe sẽ nhận được:

```text
test/topic Hello MQTT
```

Có thể bật debug để xem chi tiết kết nối MQTT:

```bash
mosquitto_sub -h khuonvien.vn -t test/topic -v -d
```

Ví dụ trên sử dụng topic `test/topic`, tránh tác động đến topic `device` của production.

Kết quả mong đợi của `systemctl is-active` là `active`. Mosquitto chỉ nên được restart khi thay đổi cấu hình hoặc khi broker gặp sự cố, vì restart sẽ ngắt các MQTT client đang kết nối.

### Start/Stop/Restart Services

```bash
# Start service
sudo systemctl start sidekiq

# Stop service
sudo systemctl stop sidekiq

# Restart service (stop + start)
sudo systemctl restart sidekiq

# Reload service config (zero-downtime for nginx)
sudo systemctl reload nginx

# Enable service on boot
sudo systemctl enable sidekiq

# Disable service on boot
sudo systemctl disable sidekiq
```

---

## Troubleshooting

### Service Failed to Start

```bash
# Check detailed error
sudo systemctl status myapp -l

# Check recent logs
sudo journalctl -u myapp -n 100 --no-pager

# Check if port is already in use
sudo lsof -i :3000

# Check disk space
df -h
```

### Database Connection Issues

```bash
# Check database.yml
cat config/database.yml

# Test database connection
RAILS_ENV=production bundle exec rails runner "puts ActiveRecord::Base.connection.active?"

# Check MySQL/PostgreSQL is running
sudo systemctl status mysql
# or
sudo systemctl status postgresql
```

### Sidekiq Not Processing Jobs

```bash
# Check Redis is running
redis-cli ping

# Check Sidekiq queue
RAILS_ENV=production bundle exec rails console
> Sidekiq::Queue.new.size
> Sidekiq::Workers.new.size

# Clear failed jobs (if needed)
> Sidekiq::Queue.new.clear
```

### Mosquitto/MQTT Connection Issues

```bash
# Check broker service
sudo systemctl status mosquitto --no-pager -l

# Check whether port 1883 is listening locally
sudo ss -lntp | grep ':1883'

# Check recent broker errors
sudo journalctl -u mosquitto -n 100 --no-pager

# Test the production broker from the application server
nc -vz -w 5 103.9.77.155 1883

# Check the MQTT listener started by Sidekiq
sudo journalctl -u sidekiq --since "30 minutes ago" --no-pager \
  | grep -E '\[MQTT\]|Protocol error|Unexpected error'
```

MQTT hoạt động bình thường khi:

- `mosquitto` có trạng thái `active`.
- Port `1883` đang lắng nghe hoặc lệnh `nc` kết nối thành công.
- Log Sidekiq có dòng `[MQTT][Listener] Subscribed to 'device' topic`.

Nếu đã xác nhận broker gặp sự cố, restart và kiểm tra lại:

```bash
sudo systemctl restart mosquitto
sudo systemctl status mosquitto --no-pager -l
sudo journalctl -u mosquitto -n 100 --no-pager
```

### Nginx 502 Bad Gateway

```bash
# Check if myapp is running
sudo systemctl status myapp

# Check Nginx config syntax
sudo nginx -t

# Check upstream socket/port
cat /etc/nginx/sites-available/myapp

# Check application logs
tail -f log/production.log
```

---

## Rollback Procedure

### Nếu deploy có vấn đề:

1. **Rollback Code**
   ```bash
   git log --oneline -5  # Find previous commit
   git reset --hard <previous-commit-hash>
   ```

2. **Rollback Database** (nếu đã migrate)
   ```bash
   RAILS_ENV=production bundle exec rails db:rollback STEP=1
   ```

3. **Restart Services**
   ```bash
   sudo systemctl restart myapp
   sudo systemctl restart sidekiq
   sudo systemctl reload nginx
   ```

4. **Verify**
   - Kiểm tra application hoạt động bình thường
   - Check logs không có errors

---

## Quick Commands

### One-liner Restart All Services

```bash
sudo systemctl stop sidekiq && \
sudo systemctl restart myapp && \
sudo systemctl restart sidekiq && \
sudo systemctl reload nginx && \
echo "All services restarted!"
```

### Check All Services Status

```bash
for service in sidekiq myapp nginx mosquitto; do
  echo "=== $service ==="
  sudo systemctl status $service | head -n 3
  echo ""
done
```

---

## Notes

- Luôn restart Sidekiq **sau** khi restart application
- MQTT listener được khởi động cùng Sidekiq; kiểm tra log Sidekiq để xác nhận đã subscribe topic `device`
- Không restart Mosquitto trong mỗi lần deploy; chỉ restart khi thay đổi cấu hình hoặc broker gặp sự cố
- Dùng `reload` cho Nginx thay vì `restart` để tránh downtime
- Monitor logs trong ít nhất 15 phút sau deploy
- Có kế hoạch rollback sẵn sàng
- Deploy trong giờ thấp điểm nếu có thể

## Contacts

- **DevOps Lead:** [Name] - [Email]
- **Backend Lead:** [Name] - [Email]
- **On-call Engineer:** [Phone]

---

**Last Updated:** 2026-09-08
**Version:** 1.1
