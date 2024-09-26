class Finger < ActiveRecord::Base
    belongs_to :employee
  
    validates :finger_id, presence: true, uniqueness: true
    # Encode and decode binary data using Base64 for transmission and storage
    def fingerprint_template=(data)
        write_attribute(:fingerprint_template, Base64.decode64(data))  # Decode Base64 to binary before storing
    end

    def fingerprint_template_base64
        Base64.encode64(self.fingerprint_template)  # Encode binary to Base64 when retrieving
    end
end
  