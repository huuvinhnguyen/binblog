# spec/factories/reminders.rb
FactoryBot.define do
  factory :reminder do
    device
    relay_index { 1 }
    start_time { 1.day.ago.advance(minutes: -1) }
    repeat_type { "daily" }
    duration { 60 } # in seconds
    enabled { true }
  end
end

  