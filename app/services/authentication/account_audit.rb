module Authentication
  class AccountAudit
    def each_broken_account
      return enum_for(:each_broken_account) unless block_given?

      User.find_each do |user|
        next if user.usable_password_authentication?
        next if user.user_identities.any?(&:usable?)

        yield user
      end
    end
  end
end
