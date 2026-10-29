module SwitchApi
  module Features
    module_function

    def enabled?
      %w[true 1].include?(ENV['SWITCH_MOBILE_API_ENABLED'])
    end

    # The execution-owner gate in the architecture handoff is unresolved.
    # An environment variable alone must never enable unimplemented dispatch.
    def reminders_ready?
      false
    end
  end
end
