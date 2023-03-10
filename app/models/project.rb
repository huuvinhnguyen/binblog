class Project < ActiveRecord::Base 
    has_many :attendances
    has_many :employees, through: :attendances, source: :initialized_employees, class_name: 'Employee'
end
