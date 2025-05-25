class AddConfirmedTurnTimestampsToRelayLogs < ActiveRecord::Migration[7.0]
  def change
    add_column :relay_logs, :confirmed_turn_on_at, :datetime
    add_column :relay_logs, :confirmed_turn_off_at, :datetime
  end
end
