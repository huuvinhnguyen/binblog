class AddSwitchStatisticsIndexToRelayLogs < ActiveRecord::Migration[7.0]
  def change
    add_index :relay_logs, [:device_id, :relay_index, :created_at], name: 'index_relay_logs_for_switch_statistics'
  end
end
