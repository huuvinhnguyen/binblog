class Device < ActiveRecord::Base
    has_and_belongs_to_many :users
    has_many :reminders, dependent: :destroy
    has_many :relay_logs
    has_many :device_events, dependent: :destroy
    has_many :trigger_actions,
             class_name: 'DeviceTriggerAction',
             foreign_key: :source_device_id,
             inverse_of: :source_device,
             dependent: :destroy
    has_many :incoming_trigger_actions,
             class_name: 'DeviceTriggerAction',
             foreign_key: :target_device_id,
             inverse_of: :target_device,
             dependent: :destroy
    has_many :incoming_trigger_executions,
             class_name: 'DeviceTriggerActionExecution',
             foreign_key: :target_device_id,
             inverse_of: :target_device,
             dependent: :nullify
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
