class Device < ActiveRecord::Base
    has_and_belongs_to_many :users
    has_many :reminders, dependent: :destroy
    has_many :relay_logs

    def self.id_from_chip(chip_id)
        find_by(chip_id: chip_id)&.id
    end
end
