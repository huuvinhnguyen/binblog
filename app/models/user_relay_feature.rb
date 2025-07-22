class UserRelayFeature < ActiveRecord::Base
    belongs_to :user
    belongs_to :device
  
    validates :feature, presence: true
    validates :feature, uniqueness: { scope: [:user_id, :device_id] }
  
    FEATURES = %w[
        reminder            # Hẹn giờ thông thường
        manual_switch       # Bật/tắt thủ công (ví dụ nút nhấn)
        auto_turn_off       # Tự tắt sau một khoảng thời gian (duration-based)
        schedule_control     # Bật/tắt theo lịch lập sẵn
        ].freeze
  
    def self.feature_enabled?(user, device, feature)
      find_by(user: user, device: device, feature: feature)&.enabled != false
    end
  end
  