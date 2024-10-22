class ChangeDateToDatetimeInRewardsPenalties < ActiveRecord::Migration[7.0]
  def change
    change_column :rewards_penalties, :date, :datetime
  end
end
