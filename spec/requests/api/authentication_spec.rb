# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API Authentication', type: :request do
  path '/api/login' do
    post 'Login user and return JWT token' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :credentials, in: :body, schema: {
        type: :object,
        required: %w[username password],
        properties: {
          username: { type: :string, example: 'admin' },
          password: { type: :string, example: '123456' }
        }
      }

      response '200', 'successful login' do
        let(:credentials) do
          { username: 'admin', password: '123456' }
        end

        run_test!
      end

      response '401', 'invalid credentials' do
        let(:credentials) do
          { username: 'admin', password: 'wrong-password' }
        end

        run_test!
      end
    end
  end
end
