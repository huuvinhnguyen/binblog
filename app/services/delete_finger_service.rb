# app/services/delete_finger_service.rb
class DeleteFingerService
    attr_reader :device_finger_id
  
    def initialize(device_finger_id:)
      @device_finger_id = device_finger_id
    end
  
    def call
      validate_input!
      delete_finger
    rescue StandardError => e
      Rails.logger.error("Failed to delete finger: #{e.message}")
      false
    end
  
    private
  
    # Validate input to ensure the device_finger_id is present
    def validate_input!
      raise 'Device Finger ID is required' if device_finger_id.blank?
  
      unless Finger.exists?(device_finger_id: device_finger_id)
        raise "No finger found with Device Finger ID #{device_finger_id}"
      end
    end
  
    # Deletes the finger record
    def delete_finger
      Finger.find_by(device_finger_id: device_finger_id).destroy!
      ActionCable.server.broadcast('fingerprints_channel', { action: 'delete', device_finger_id: device_finger_id })
      Rails.logger.info("Finger with Device Finger ID #{device_finger_id} deleted successfully.")
      true
    end
  end