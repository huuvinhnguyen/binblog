class Device < ActiveRecord::Base
    has_and_belongs_to_many :users
    has_many :reminders, dependent: :destroy
    has_many :relay_logs
    serialize :meta_info, JSON

    def self.id_from_chip(chip_id)
        find_by(chip_id: chip_id)&.id
    end

    def parsed_meta_info
        @parsed_meta_info ||= JSON.parse(meta_info || '{}')
    rescue JSON::ParserError
        {}
    end
end
