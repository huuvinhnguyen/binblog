# spec/factories/reminders.rb
FactoryBot.define do
  factory :reminder do
    device
    relay_index { 1 }
    start_time { 1.day.ago.change(hour: Time.zone.now.hour, min: Time.zone.now.min - 1) }
    repeat_type { "daily" }
    duration { 60 } # in seconds
    enabled { true }
  end
end

  