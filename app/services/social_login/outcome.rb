module SocialLogin
  # Internal result; transport-specific HTTP/session handling belongs to later tasks.
  class Outcome
    attr_reader :status, :user

    def initialize(status:, user: nil)
      @status = status
      @user = user
      freeze
    end
  end
end
