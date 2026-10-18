module SocialLogin
  class ProviderPolicy
    SUPPORTED_PROVIDERS = %w[google].freeze

    def self.enabled?(provider)
      normalized = provider.to_s.strip.downcase
      SUPPORTED_PROVIDERS.include?(normalized) && !disabled_providers.include?(normalized)
    end

    def self.disabled_providers
      ENV.fetch('DISABLED_SOCIAL_AUTH_PROVIDERS', '').split(',').map { |value| value.strip.downcase }.reject(&:blank?)
    end
  end
end
