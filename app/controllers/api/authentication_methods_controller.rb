module Api
  class AuthenticationMethodsController < ApplicationController
    include BearerAuthentication
    include AuthRequestSafety

    skip_before_action :verify_authenticity_token
    before_action :reject_oversized_auth_request!
    before_action :authenticate_bearer_user!

    def show
      render json: Authentication::MethodsProjection.new(user: @authenticated_user).as_json, status: :ok
    end
  end
end
