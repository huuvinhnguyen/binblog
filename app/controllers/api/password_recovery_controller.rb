module Api
  class PasswordRecoveryController < ApplicationController
    include AuthRequestSafety

    skip_before_action :verify_authenticity_token
    before_action :reject_oversized_auth_request!

    def create
      email = params[:email]
      if bounded_string?(email, maximum: 254) && recovery_request_allowed?(email)
        begin
          Authentication::PasswordRecoveryInitiator.new.call(email: email)
        rescue StandardError => error
          Rails.logger.error("Password recovery delivery failed: #{error.class}")
        end
      end
      render json: { status: 'accepted' }, status: :accepted
    end

    def update
      return recovery_error unless valid_completion_parameters?
      return error(:rate_limited, :too_many_requests) unless completion_allowed?

      outcome = Authentication::PasswordRecoveryCompleter.new.call(
        token: params[:recovery_token],
        recovery_code: params[:recovery_code],
        username: params[:username],
        password: params[:password],
        password_confirmation: params[:password_confirmation]
      )
      if outcome.status == :password_updated
        render json: { status: 'success', code: 'password_updated' }, status: :ok
      else
        recovery_error
      end
    end

    private

    def recovery_request_allowed?(email)
      limiter = Authentication::RateLimiter.new
      limiter.allowed?(
        scope: 'password-recovery-ip', discriminator: request.remote_ip,
        limit: 10, period: 10.minutes
      ) && limiter.allowed?(
        scope: 'password-recovery-email', discriminator: email.to_s.strip.downcase,
        limit: 5, period: 1.hour
      )
    end

    def completion_allowed?
      Authentication::RateLimiter.new.allowed?(
        scope: 'password-recovery-completion', discriminator: request.remote_ip,
        limit: 10, period: 10.minutes
      )
    end

    def valid_completion_parameters?
      bounded_string?(params[:recovery_token], maximum: 2048) &&
        bounded_string?(params[:password], maximum: 128) &&
        bounded_string?(params[:password_confirmation], maximum: 128) &&
        (!params.key?(:username) || bounded_string?(params[:username], maximum: 255)) &&
        (!params.key?(:recovery_code) || bounded_string?(params[:recovery_code], maximum: 128))
    end

    def recovery_error
      error(:invalid_or_expired_recovery, :unprocessable_entity)
    end

    def error(code, http_status)
      render json: { status: 'error', code: code.to_s }, status: http_status
    end
  end
end
