require 'rails_helper'

RSpec.describe BuzzerLinks do
  let(:user) { User.create!(username: 'link_service', email: 'link_service@example.com', password: 'password123') }
  let(:buzzer) { Device.create!(chip_id: 'link_target', device_type: 'buzzer') }
  let(:pir) do
    Device.create!(chip_id: 'link_source', device_type: 'pir', trigger: '{broken').tap { |device| device.users << user }
  end
  subject(:service) { described_class.new(buzzer: buzzer, user: user) }

  before do
    expect(MQTT::Client).not_to receive(:connect)
    expect_any_instance_of(MQTT::Client).not_to receive(:publish)
    expect(BuzzerTestService).not_to receive(:new)
  end

  it 'leaves stored data intact when persistence fails' do
    pir
    allow_any_instance_of(Device).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
    expect { service.link(pir_id: pir.id, relay_index: 0, longlast: 1000) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(pir.reload.trigger).to eq('{broken')
  end

  it 'rechecks the stored target under the row lock before unlinking' do
    pir.update!(trigger: { chip_id: buzzer.chip_id, longlast: 1000 }.to_json)
    allow_any_instance_of(Device).to receive(:with_lock).and_wrap_original do |method, &block|
      # Simulate a relink committed between the initial read and lock acquisition.
      Device.where(id: pir.id).update_all(trigger: { chip_id: 'new_target', longlast: 2000 }.to_json)
      method.call(&block)
    end
    service.unlink(pir_id: pir.id.to_s)
    expect(JSON.parse(pir.reload.trigger)).to eq('chip_id' => 'new_target', 'longlast' => 2000)
  end

  it 'safely lists malformed stored triggers without exposing their contents' do
    pir
    expect(service.available_pirs).to eq([
      { id: pir.id, name: nil, chip_id: pir.chip_id, linked_buzzer: nil, requires_confirmation: true }
    ])
  end
end
