require 'net/http'
require 'json'

module SocialLogin
  class GoogleJwks
    URL = URI('https://www.googleapis.com/oauth2/v3/certs')
    CACHE_KEY = 'social_login/google_jwks'
    FETCH_COOLDOWN_KEY = 'social_login/google_jwks_fetch_cooldown'
    FETCH_COOLDOWN = 30.seconds
    FETCH_MUTEX = Mutex.new

    class Unavailable < StandardError; end

    def call(force_refresh: false)
      cached = Rails.cache.read(CACHE_KEY)
      return cached if cached && !force_refresh

      # ruby-jwt asks for a forced refresh when a kid is absent. Serialize
      # fetches within this process; the cache cooldown also bounds later misses.
      FETCH_MUTEX.synchronize do
        cached = Rails.cache.read(CACHE_KEY)
        return cached if cached && !force_refresh
        return cached if cached && Rails.cache.read(FETCH_COOLDOWN_KEY)
        raise Unavailable if Rails.cache.read(FETCH_COOLDOWN_KEY)

        Rails.cache.write(FETCH_COOLDOWN_KEY, true, expires_in: FETCH_COOLDOWN)
        set, lifetime = fetch_validated_set
        if lifetime.positive?
          Rails.cache.write(CACHE_KEY, set, expires_in: lifetime)
        else
          Rails.cache.delete(CACHE_KEY)
          # Key freshness and fetch throttling have independent lifetimes.
          # Keep the cooldown even when this response cannot be cached.
        end
        set
      end
    end

    private

    def fetch_validated_set
      response = Net::HTTP.start(URL.host, URL.port, use_ssl: true,
                                 open_timeout: 3, read_timeout: 3) do |http|
        http.get(URL.request_uri)
      end
      raise Unavailable unless response.is_a?(Net::HTTPSuccess)

      document = JSON.parse(response.body)
      raise Unavailable unless document.is_a?(Hash) && document['keys'].is_a?(Array)

      keys = document['keys'].select do |key|
        key.is_a?(Hash) && key['kty'] == 'RSA' && key['kid'].present? &&
          [nil, 'sig'].include?(key['use']) && [nil, 'RS256'].include?(key['alg'])
      end
      raise Unavailable if keys.empty?
      validate_keys!(keys)

      max_age = response['Cache-Control'].to_s[/\bmax-age=(\d+)/, 1]
      [{ 'keys' => keys }, max_age ? max_age.to_i : 300]
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout,
           Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
           Timeout::Error, SocketError, IOError,
           SystemCallError, OpenSSL::SSL::SSLError
      raise Unavailable
    end

    def validate_keys!(keys)
      keys.each do |key|
        unless [key['kid'], key['n'], key['e']].all? { |value| value.is_a?(String) && value.present? } &&
               [key['n'], key['e']].all? { |value| value.match?(/\A[A-Za-z0-9_-]+\z/) }
          raise Unavailable
        end
      end
      JWT::JWK::Set.new('keys' => keys).each do |jwk|
        public_key = jwk.verify_key
        raise Unavailable unless public_key.n.num_bits >= 2048 &&
          public_key.n.to_i.odd? && public_key.e.to_i >= 3 && public_key.e.to_i.odd?
      end
    rescue JWT::JWKError, JWT::DecodeError, OpenSSL::PKey::PKeyError,
           OpenSSL::ASN1::ASN1Error, ArgumentError, TypeError
      raise Unavailable
    end
  end
end
