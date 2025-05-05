# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2025_05_05_022130) do
  create_table "attendances", force: :cascade do |t|
    t.integer "employee_id"
    t.date "date"
    t.float "weight"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "project_id"
    t.datetime "start_time"
    t.datetime "end_time"
    t.decimal "hourly_wage", precision: 12
    t.index ["employee_id"], name: "index_attendances_on_employee_id"
  end

  create_table "devices", force: :cascade do |t|
    t.string "name"
    t.string "chip_id", null: false
    t.integer "status"
    t.boolean "is_payment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "device_type"
    t.text "device_info"
    t.text "trigger"
    t.index ["chip_id"], name: "index_devices_on_chip_id", unique: true
  end

  create_table "devices_users", id: false, force: :cascade do |t|
    t.integer "device_id", null: false
    t.integer "user_id", null: false
    t.index ["device_id", "user_id"], name: "index_devices_users_on_device_id_and_user_id"
    t.index ["user_id", "device_id"], name: "index_devices_users_on_user_id_and_device_id"
  end

  create_table "employees", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "daily_salary"
  end

  create_table "employees_users", id: false, force: :cascade do |t|
    t.integer "user_id"
    t.integer "employee_id"
    t.index ["employee_id"], name: "index_employees_users_on_employee_id"
    t.index ["user_id", "employee_id"], name: "index_employees_users_on_user_id_and_employee_id", unique: true
    t.index ["user_id"], name: "index_employees_users_on_user_id"
  end

  create_table "fingers", force: :cascade do |t|
    t.integer "employee_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.binary "fingerprint_template"
    t.string "device_finger_id"
    t.integer "finger_id"
    t.index ["device_finger_id"], name: "index_fingers_on_device_finger_id", unique: true
    t.index ["employee_id"], name: "index_fingers_on_employee_id"
    t.index ["finger_id"], name: "index_fingers_on_finger_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reminders", force: :cascade do |t|
    t.integer "device_id", null: false
    t.integer "relay_index"
    t.datetime "start_time"
    t.integer "duration"
    t.string "repeat_type"
    t.datetime "last_triggered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "job_jid"
    t.index ["device_id"], name: "index_reminders_on_device_id"
  end

  create_table "resumes", force: :cascade do |t|
    t.string "name"
    t.string "attachment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rewards_penalties", force: :cascade do |t|
    t.integer "employee_id", null: false
    t.string "description"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.boolean "penalty", default: false
    t.datetime "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_rewards_penalties_on_employee_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.integer "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["name"], name: "index_roles_on_name"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "user_devices", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "device_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_user_devices_on_device_id"
    t.index ["user_id"], name: "index_user_devices_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_url"
    t.string "username"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.integer "user_id"
    t.integer "role_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "widgets", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.integer "stock"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  add_foreign_key "attendances", "employees"
  add_foreign_key "fingers", "employees"
  add_foreign_key "reminders", "devices"
  add_foreign_key "rewards_penalties", "employees"
  add_foreign_key "user_devices", "devices"
  add_foreign_key "user_devices", "users"
end
