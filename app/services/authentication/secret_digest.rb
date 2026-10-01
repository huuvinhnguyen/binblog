module Authentication
  class SecretDigest
    def self.call(value, purpose:)
      OpenSSL::HMAC.digest(
        'SHA256', Rails.application.secret_key_base,
        "#{purpose}\0#{value}"
      )
    end

    def self.hex(value, purpose:)
      call(value, purpose: purpose).unpack1('H*')
    end
  end
end
