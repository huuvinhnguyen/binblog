# spec/factories/devices.rb
FactoryBot.define do
    factory :device do
      name { "Test Device" }
      chip_id { SecureRandom.hex(6).upcase }
    end
  end
  
  