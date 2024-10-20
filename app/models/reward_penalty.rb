class RewardPenalty < ActiveRecord::Base
    belongs_to :employee
    validates :description, :amount, :date, presence: true
    validates :amount, numericality: { greater_than_or_equal_to: 0 }
end
