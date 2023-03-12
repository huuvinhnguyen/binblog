
RailsAdmin.config do |config|

  ### Popular gems integration

  ### More at https://github.com/sferik/rails_admin/wiki/Base-configuration

  config.model 'User' do
    navigation_label 'User Management'
  end

  config.parent_controller = 'ApplicationController'

  config.authenticate_with do
    false
  end

end

