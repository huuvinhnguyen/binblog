# app/services/add_finger_service.rb
class AddFingerService
    attr_reader :employee, :finger_id, :fingerprint_template, :device_finger_id
  
    def initialize(employee:, finger_id:, fingerprint_template:, device_finger_id:)
      @employee = employee
      @finger_id = finger_id
      @fingerprint_template = fingerprint_template
      @device_finger_id = device_finger_id
    end
  
    def call
      validate_inputs!
      create_finger
    rescue StandardError => e
      # Handle any errors that occur during the process
      Rails.logger.error("Failed to add new finger: #{e.message}")
      false
    end
  
    private
  
    # Validates the inputs to ensure no duplicates or missing values
    def validate_inputs!
      raise 'Invalid employee' unless employee.present?
      raise 'Finger ID is required' if finger_id.blank?
      raise 'Fingerprint template is required' if fingerprint_template.blank?
      raise 'Device finger ID is required' if device_finger_id.blank?
  
      if Finger.exists?(device_finger_id: device_finger_id)
        raise "Device Finger ID #{device_finger_id} already exists"
      end
    end
  
    # Creates the new finger record
    def create_finger
      Finger.create!(
        employee_id: employee.id,
        finger_id: finger_id,
        fingerprint_template: fingerprint_template,
        device_finger_id: device_finger_id
      )
      true
    end
  end
  