namespace :update do
  desc "Update project_id of all attendances to 1"
  task update_project_id: :environment do
    Attendance.where(project_id: nil).update_all(project_id: 1)
  end
end

