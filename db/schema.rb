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

ActiveRecord::Schema[7.0].define(version: 2025_05_28_235716) do
  create_table "attendances", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "employee_id"
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

  create_table "categories", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "devices", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name"
    t.string "chip_id", null: false
    t.integer "status"
    t.boolean "is_payment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "device_type"
    t.text "device_info"
    t.text "trigger"
    t.string "url_firmware", comment: "URL dùng để tải firmware mới cho thiết bị"
    t.text "note", comment: "Ghi chú thêm cho thiết bị"
    t.index ["chip_id"], name: "index_devices_on_chip_id", unique: true
  end

  create_table "devices_users", id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.bigint "user_id", null: false
  end

  create_table "employees", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "daily_salary", precision: 10
  end

  create_table "employees_users", id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "employee_id"
    t.index ["employee_id"], name: "index_employees_users_on_employee_id"
    t.index ["user_id", "employee_id"], name: "index_employees_users_on_user_id_and_employee_id", unique: true
    t.index ["user_id"], name: "index_employees_users_on_user_id"
  end

  create_table "fingers", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.binary "fingerprint_template"
    t.string "device_finger_id"
    t.bigint "finger_id"
    t.index ["device_finger_id"], name: "index_fingers_on_device_finger_id", unique: true
    t.index ["employee_id"], name: "index_fingers_on_employee_id"
    t.index ["finger_id"], name: "index_fingers_on_finger_id"
  end

  create_table "friendly_id_slugs", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true, length: { slug: 70, scope: 70 }
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type", length: { slug: 140 }
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "posts", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "title"
    t.text "content"
    t.string "slug"
    t.boolean "published"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "category_id"
    t.index ["category_id"], name: "index_posts_on_category_id"
    t.index ["slug"], name: "index_posts_on_slug", unique: true
  end

  create_table "projects", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "relay_logs", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.integer "relay_index", null: false, comment: "Chỉ số relay trên thiết bị"
    t.datetime "turn_on_at", comment: "Thời điểm bật relay"
    t.datetime "turn_off_at", comment: "Thời điểm tắt relay"
    t.string "triggered_by", comment: "Ai hoặc cái gì đã kích hoạt (user, schedule, mqtt)"
    t.string "command_source", comment: "Nguồn gửi lệnh thực tế (web_ui, api, fingerprint...)"
    t.boolean "relay_status", comment: "Trạng thái sau khi tác vụ xảy ra (true=bật, false=tắt)"
    t.bigint "user_id", comment: "Nếu có người dùng thao tác"
    t.text "note", comment: "Ghi chú thêm"
    t.boolean "processed", default: false, comment: "Đã xử lý xong chưa (dùng cho đồng bộ)"
    t.text "error_message", comment: "Lưu lỗi nếu có"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "confirmed_turn_on_at"
    t.datetime "confirmed_turn_off_at"
    t.index ["device_id", "relay_index"], name: "index_relay_logs_on_device_id_and_relay_index"
    t.index ["device_id"], name: "index_relay_logs_on_device_id"
    t.index ["user_id"], name: "index_relay_logs_on_user_id"
  end

  create_table "reminders", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "device_id", null: false
    t.integer "relay_index"
    t.datetime "start_time"
    t.integer "duration"
    t.string "repeat_type"
    t.datetime "last_triggered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "job_jid"
    t.boolean "enabled", default: true, null: false
    t.string "turn_off_jid"
    t.index ["device_id"], name: "index_reminders_on_device_id"
  end

  create_table "resumes", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name"
    t.string "attachment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rewards_penalties", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.string "description"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.boolean "penalty", default: false
    t.datetime "date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_rewards_penalties_on_employee_id"
  end

  create_table "roles", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.bigint "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["name"], name: "index_roles_on_name"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "user_devices", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "device_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_user_devices_on_device_id"
    t.index ["user_id"], name: "index_user_devices_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
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

  create_table "users_roles", id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "role_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "widgets", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.integer "stock"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  add_foreign_key "attendances", "employees"
  add_foreign_key "fingers", "employees"
  add_foreign_key "posts", "categories"
  add_foreign_key "relay_logs", "devices"
  add_foreign_key "relay_logs", "users"
  add_foreign_key "reminders", "devices"
  add_foreign_key "rewards_penalties", "employees"
  add_foreign_key "user_devices", "devices"
  add_foreign_key "user_devices", "users"
end
