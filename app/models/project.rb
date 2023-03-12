class Project < ActiveRecord::Base 
    has_many :attendances
    # has_many :employees, through: :attendances
end
