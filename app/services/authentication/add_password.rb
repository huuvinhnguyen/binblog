module Authentication
  class AddPassword
    Result = Struct.new(:status, keyword_init: true)

    def call(user:, username:, password:, password_confirmation:, authorization:)
      result = nil
      User.transaction do
        user.lock!
        if user.usable_password_authentication?
          result = Result.new(status: :password_already_set)
          raise ActiveRecord::Rollback
        end
        unless authorization.consume!
          result = Result.new(status: :reauthentication_required)
          raise ActiveRecord::Rollback
        end

        user.assign_attributes(
          username: username.to_s.strip,
          password: password,
          password_confirmation: password_confirmation
        )
        unless user.save
          result = Result.new(status: validation_status(user))
          raise ActiveRecord::Rollback
        end
        result = Result.new(status: :password_added)
      end
      result
    rescue ActiveRecord::RecordNotUnique
      Result.new(status: :username_unavailable)
    end

    private

    def validation_status(user)
      user.errors[:username].present? ? :username_unavailable : :invalid_password
    end
  end
end
