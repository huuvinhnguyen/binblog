require 'rails_helper'
require 'webmock/rspec'

RSpec.describe SocialLogin::GoogleJwks do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(key.public_key, { kid: 'first', use: 'sig', alg: 'RS256' }).export }
  let(:claims) do
    { iss: 'https://accounts.google.com', aud: 'client-one', exp: 10.minutes.from_now.to_i,
      sub: 'verified-subject', email: 'owner@gmail.com', email_verified: true }
  end
  let(:verifier) { SocialLogin::GoogleIdentityVerifier.new(audiences: ['client-one']) }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  def google_keys(keys, max_age: 300)
    { status: 200, headers: { 'Cache-Control' => "public, max-age=#{max_age}" },
      body: { keys: keys }.to_json }
  end

  def token(kid: 'first', signing_key: key)
    JWT.encode(claims, signing_key, 'RS256', kid: kid)
  end

  it 'fetches usable signing RSA keys and caches them' do
    request = stub_request(:get, described_class::URL.to_s).to_return(
      google_keys([jwk, { kty: 'oct', kid: 'unsafe', k: 'secret', use: 'sig' }])
    )
    set = described_class.new.call
    expect(set.fetch('keys').map { |entry| entry.fetch('kid') }).to eq(['first'])
    expect(described_class.new.call).to eq(set)
    expect(request).to have_been_requested.once
  end

  it 'bounds repeated unknown-kid refreshes while allowing later rotation' do
    first = stub_request(:get, described_class::URL.to_s).to_return(google_keys([jwk]))
    expect(verifier.call(credential: token).provider_uid).to eq('verified-subject')
    unknown = token(kid: 'unknown')

    travel(described_class::FETCH_COOLDOWN + 1.second) do
      4.times do
        expect { verifier.call(credential: unknown) }
          .to raise_error(SocialLogin::GoogleIdentityVerifier::InvalidCredential)
      end
      expect(first).to have_been_requested.twice
    end
  end

  it 'preserves cached keys after failed refresh and still verifies old tokens' do
    stub_request(:get, described_class::URL.to_s).to_return(google_keys([jwk]))
    expect(verifier.call(credential: token).provider_uid).to eq('verified-subject')
    original = cache.read(described_class::CACHE_KEY)

    travel(described_class::FETCH_COOLDOWN + 1.second) do
      stub_request(:get, described_class::URL.to_s).to_timeout
      expect { verifier.call(credential: token(kid: 'new')) }
        .to raise_error(SocialLogin::GoogleIdentityVerifier::Unavailable)
      expect(cache.read(described_class::CACHE_KEY)).to eq(original)
      expect(verifier.call(credential: token).provider_uid).to eq('verified-subject')
    end
  end

  it 'accepts a newly published signing key after a successful rotation refresh' do
    stub_request(:get, described_class::URL.to_s).to_return(google_keys([jwk]))
    expect(verifier.call(credential: token).provider_uid).to eq('verified-subject')
    next_key = OpenSSL::PKey::RSA.generate(2048)
    next_jwk = JWT::JWK.new(next_key.public_key, { kid: 'next', use: 'sig', alg: 'RS256' }).export

    travel(described_class::FETCH_COOLDOWN + 1.second) do
      stub_request(:get, described_class::URL.to_s).to_return(google_keys([jwk, next_jwk]))
      expect(verifier.call(credential: token(kid: 'next', signing_key: next_key)).provider_uid)
        .to eq('verified-subject')
      expect(cache.read(described_class::CACHE_KEY).fetch('keys').map { |entry| entry.fetch('kid') })
        .to contain_exactly('first', 'next')
    end
  end

  it 'serializes concurrent unknown-kid refreshes within this process' do
    request = stub_request(:get, described_class::URL.to_s).to_return(google_keys([jwk]))
    described_class.new.call

    travel(described_class::FETCH_COOLDOWN + 1.second) do
      stub_request(:get, described_class::URL.to_s).to_return do
        sleep 0.05
        google_keys([jwk])
      end
      unknown = token(kid: 'unknown')
      results = 8.times.map do
        Thread.new do
          begin
            verifier.call(credential: unknown)
          rescue SocialLogin::GoogleIdentityVerifier::InvalidCredential
            :invalid
          end
        end
      end.map(&:value)
      expect(results).to eq([:invalid] * 8)
      expect(request).to have_been_requested.twice
    end
  end

  it 'uses zero-TTL keys only for the current verification and retains the fetch cooldown' do
    request = stub_request(:get, described_class::URL.to_s).to_return(google_keys([jwk], max_age: 0))
    credential = token
    expect(verifier.call(credential: credential).provider_uid).to eq('verified-subject')
    expect(cache.read(described_class::CACHE_KEY)).to be_nil
    expect(cache.read(described_class::FETCH_COOLDOWN_KEY)).to eq(true)

    expect { verifier.call(credential: credential) }
      .to raise_error(SocialLogin::GoogleIdentityVerifier::Unavailable)
    expect(request).to have_been_requested.once

    travel(described_class::FETCH_COOLDOWN + 1.second) do
      expect(verifier.call(credential: credential).provider_uid).to eq('verified-subject')
      expect(cache.read(described_class::CACHE_KEY)).to be_nil
      expect(request).to have_been_requested.twice
    end
  end

  it 'bounds distinct unknown kids with zero-TTL keys and discovers rotation after cooldown' do
    next_key = OpenSSL::PKey::RSA.generate(2048)
    next_jwk = JWT::JWK.new(next_key.public_key, { kid: 'unknown-0', use: 'sig', alg: 'RS256' }).export
    credentials = 4.times.map { |i| token(kid: "unknown-#{i}", signing_key: next_key) }
    request = stub_request(:get, described_class::URL.to_s).to_return(
      google_keys([jwk], max_age: 0), google_keys([next_jwk], max_age: 0)
    )

    credentials.each do |credential|
      expect { verifier.call(credential: credential) }
        .to raise_error(SocialLogin::GoogleIdentityVerifier::Unavailable)
    end
    expect(request).to have_been_requested.once
    expect(cache.read(described_class::CACHE_KEY)).to be_nil
    expect(cache.read(described_class::FETCH_COOLDOWN_KEY)).to eq(true)

    travel(described_class::FETCH_COOLDOWN + 1.second) do
      expect(verifier.call(credential: credentials.first).provider_uid).to eq('verified-subject')
      expect(request).to have_been_requested.twice
      expect(cache.read(described_class::CACHE_KEY)).to be_nil
      expect(cache.read(described_class::FETCH_COOLDOWN_KEY)).to eq(true)
    end
  end

  it 'rejects malformed RSA components before publishing any keyset' do
    malformed = [
      jwk.merge(n: 123), jwk.merge(e: []), jwk.reject { |name, _| name == :n },
      jwk.reject { |name, _| name == :e }, jwk.merge(n: '!'),
      jwk.merge(n: 'AQ', e: 'AQ')
    ]
    malformed.each do |bad_key|
      cache.clear
      stub_request(:get, described_class::URL.to_s).to_return(google_keys([bad_key]))
      expect { described_class.new.call }.to raise_error(described_class::Unavailable)
      expect(cache.read(described_class::CACHE_KEY)).to be_nil
    end
  end

  it 'reports unavailable keys for malformed JSON, shape, HTTP failures, and protocol errors' do
    responses = [
      { status: 200, body: 'invalid json' },
      { status: 200, body: { keys: 'not-an-array' }.to_json },
      { status: 503 },
      Net::HTTPBadResponse.new('malformed upstream HTTP')
    ]
    responses.each do |upstream|
      cache.clear
      if upstream.is_a?(Exception)
        stub_request(:get, described_class::URL.to_s).to_raise(upstream)
      else
        stub_request(:get, described_class::URL.to_s).to_return(upstream)
      end
      expect { described_class.new.call }.to raise_error(described_class::Unavailable)
      expect(cache.read(described_class::CACHE_KEY)).to be_nil
    end
  end
end
