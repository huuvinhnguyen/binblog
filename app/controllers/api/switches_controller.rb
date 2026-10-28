module Api
  class SwitchesController < ApplicationController
    include Api::BearerAuthentication

    skip_before_action :verify_authenticity_token
    before_action :no_store
    before_action :authenticate_bearer_user!
    before_action :require_feature
    before_action :load_switch
    before_action :validate_request

    rescue_from SwitchApi::Error, with: :render_switch_error
    rescue_from ActionDispatch::Http::Parameters::ParseError, JSON::ParserError do
      render_switch_error(SwitchApi::Error.new('malformed_json', status: :bad_request))
    end

    def show
      render json: { status: 'success', switch: SwitchDetailQuery.new(device: @switch, user: @authenticated_user).call,
                     server_time: Time.current.in_time_zone('Asia/Ho_Chi_Minh').iso8601 }
    end

    def state
      command(operation: 'state', switch_value: @body['switch_value'])
    end

    def pulse
      command(operation: 'pulse', duration_ms: @body['duration_ms'])
    end

    def refresh
      command(operation: 'refresh')
    end

    def reminders
      render json: reminder_service.list(after_id: @query['after_id'], limit: @query['limit'])
    end

    def reminder_write
      reminder_service.reject_write!
    end

    def statistics
      render json: SwitchRelayStatisticsQuery.new(device: @switch, relay_index: relay_index,
                                                   from: @query['from'], to: @query['to']).call
    end

    def not_found
      raise SwitchApi::Error.new('not_found', status: :not_found)
    end

    private

    BODY_KEYS = {
      'state' => %w[switch_value], 'pulse' => %w[duration_ms], 'refresh' => [],
      'reminder_write' => %w[start_time duration_ms repeat_type active]
    }.freeze
    QUERY_KEYS = { 'reminders' => %w[after_id limit], 'statistics' => %w[from to] }.freeze

    def no_store
      response.set_header('Cache-Control', 'no-store')
    end

    def require_feature
      raise SwitchApi::Error.new('feature_unavailable', status: :service_unavailable) unless SwitchApi::Features.enabled?
    end

    def load_switch
      return if action_name == 'not_found'

      id = request.path_parameters[:id].to_s
      if /\A[1-9][0-9]{0,18}\z/.match?(id) && id.to_i <= 9_223_372_036_854_775_807
        @switch = @authenticated_user.devices_for_current_user.find_by(id: id, device_type: 'switch')
      end
      raise SwitchApi::Error.new('switch_not_found', status: :not_found) unless @switch
    end

    def validate_request
      @query = request.query_parameters
      allowed_query = QUERY_KEYS.fetch(action_name, [])
      raise SwitchApi::Error.new('unexpected_parameters') unless (@query.keys - allowed_query).empty?

      unless request.accepts.any? { |type| type == Mime[:json] || type == Mime[:all] }
        raise SwitchApi::Error.new('not_acceptable', status: :not_acceptable)
      end
      return if request.get?

      raise SwitchApi::Error.new('request_too_large', status: :payload_too_large) if request.raw_post.bytesize > 16_384

      empty_allowed = action_name == 'refresh' || request.delete?
      if request.raw_post.empty?
        raise SwitchApi::Error.new('invalid_body') unless empty_allowed

        @body = {}
      else
        unless request.media_type == 'application/json'
          raise SwitchApi::Error.new('unsupported_media_type', status: :unsupported_media_type)
        end
        @body = JSON.parse(request.raw_post)
      end
      allowed = request.delete? ? [] : BODY_KEYS.fetch(action_name, [])
      unless @body.is_a?(Hash) && (@body.keys - allowed).empty?
        raise SwitchApi::Error.new('invalid_body')
      end
    end

    def relay_index
      request.path_parameters[:relay_index]
    end

    def command(**attributes)
      result = SwitchCommandService.new(device: @switch, user: @authenticated_user, request_id: request.request_id)
                                   .call(**attributes, relay_index: relay_index)
      render json: result
    end

    def reminder_service
      SwitchReminderService.new(device: @switch, user: @authenticated_user, relay_index: relay_index)
    end

    def authentication_error
      render_switch_error(SwitchApi::Error.new('authentication_required', status: :unauthorized))
    end

    def render_switch_error(error)
      body = { status: 'error', code: error.code, request_id: request.request_id }
      body[:outcome] = error.outcome if error.outcome
      render json: body, status: error.status
    end
  end
end
