module Api
  module AuthRequestSafety
    extend ActiveSupport::Concern

    MAX_BODY_BYTES = 16.kilobytes

    private

    def reject_oversized_auth_request!
      return if request.content_length.to_i <= MAX_BODY_BYTES

      render json: { status: 'error', code: 'malformed_request' }, status: :bad_request
    end

    def bounded_string?(value, maximum:, allow_blank: false)
      value.is_a?(String) && value.bytesize <= maximum && (allow_blank || value.present?)
    end
  end
end
