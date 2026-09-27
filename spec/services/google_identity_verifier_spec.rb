require 'rails_helper'

RSpec.describe SocialLogin::GoogleIdentityVerifier do
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:public_jwk) do
    JWT::JWK.new(key.public_key, { kid: 'test-key', alg: 'RS256', use: 'sig' }).export
  end
  let(:jwks) { double('GoogleJwks', call: { 'keys' => [public_jwk] }) }
  let(:verifier) { described_class.new(jwks: jwks, audiences: ['client-one']) }
  let(:claims) do
    {
      'iss' => 'https://accounts.google.com', 'aud' => 'client-one',
      'exp' => 10.minutes.from_now.to_i, 'sub' => 'Google-Subject',
      'email' => 'owner@gmail.com', 'email_verified' => true
    }
  end

  def token(payload = claims, signing_key: key)
    JWT.encode(payload, signing_key, 'RS256', kid: 'test-key')
  end

  it 'cryptographically verifies a valid token and derives the durable subject' do
    identity = verifier.call(credential: token)
    expect([identity.provider, identity.provider_uid, identity.verified_email])
      .to eq(['google', 'Google-Subject', 'owner@gmail.com'])
  end

  it 'rejects an invalid signature' do
    expect { verifier.call(credential: token(claims, signing_key: OpenSSL::PKey::RSA.generate(2048))) }
      .to raise_error(described_class::InvalidCredential)
  end

  it 'rejects wrong issuer, audience, expiry, and missing subject' do
    [{ 'iss' => 'https://evil.example' }, { 'aud' => 'other-client' },
     { 'exp' => 1.minute.ago.to_i }, { 'sub' => nil }].each do |change|
      expect { verifier.call(credential: token(claims.merge(change))) }
        .to raise_error(described_class::InvalidCredential)
    end
  end

  it 'rejects malformed input and missing server audience configuration' do
    expect { verifier.call(credential: 'not-a-jwt') }.to raise_error(described_class::InvalidCredential)
    expect { described_class.new(jwks: jwks, audiences: []).call(credential: token) }
      .to raise_error(described_class::Unavailable)
  end

  it 'accepts only explicitly supplied nonblank audiences' do
    web_verifier = described_class.new(jwks: jwks, audiences: [' web-client ', ' '])
    web_claims = claims.merge('aud' => 'web-client')

    expect(web_verifier.call(credential: token(web_claims)).provider_uid).to eq('Google-Subject')
    expect { web_verifier.call(credential: token) }.to raise_error(described_class::InvalidCredential)
    expect { described_class.new(jwks: jwks, audiences: [' ']).call(credential: token(web_claims)) }
      .to raise_error(described_class::Unavailable)
  end

  it 'withholds an unverified or missing email while preserving a verified subject' do
    [{ 'email_verified' => false }, { 'email' => nil }].each do |change|
      expect(verifier.call(credential: token(claims.merge(change))).verified_email).to be_nil
    end
  end

  it 'withholds a third-party address without a hosted-domain claim' do
    identity = verifier.call(credential: token(claims.merge('email' => 'person@example.com')))
    expect(identity.verified_email).to be_nil
    hosted = verifier.call(credential: token(claims.merge('email' => 'person@example.com', 'hd' => 'example.com')))
    expect(hosted.verified_email).to eq('person@example.com')
  end
end
