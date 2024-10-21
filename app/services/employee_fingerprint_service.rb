class EmployeeFingerprintService
    def initialize(device_finger_id)
      @device_finger_id = device_finger_id
    end
  
    def find_employee
      finger = Finger.find_by(device_finger_id: @device_finger_id)
      return nil unless finger
  
      employee = finger.employee
      employee
    end
end