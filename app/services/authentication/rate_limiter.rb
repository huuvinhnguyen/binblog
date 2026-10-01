module Authentication
  class RateLimiter
    def initialize(cache: Rails.cache)
      @cache = cache
    end

    def allowed?(scope:, discriminator:, limit:, period:)
      key = "authentication-rate:v1:#{scope}:#{Authentication::SecretDigest.hex(discriminator, purpose: 'rate-limit')}"
      @cache.write(key, 0, expires_in: period, unless_exist: true)
      count = @cache.increment(key, 1, expires_in: period)
      count.nil? || count <= limit
    rescue NotImplementedError
      true
    end
  end
end
