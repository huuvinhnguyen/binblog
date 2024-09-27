namespace :user do
    desc "Create a new user with email and password"
    task :create => :environment do
      # Đọc email và password từ dòng lệnh
      puts "Enter user email:"
      email = STDIN.gets.chomp
  
      puts "Enter password:"
      password = STDIN.noecho(&:gets).chomp # Nhập password mà không hiện ra dòng lệnh
  
      puts "Confirm password:"
      password_confirmation = STDIN.noecho(&:gets).chomp
  
      # Kiểm tra password
      if password != password_confirmation
        puts "Passwords do not match!"
        exit
      end
  
      # Tạo người dùng
      user = User.new(email: email, password: password, password_confirmation: password_confirmation)
  
      if user.save
        puts "User #{email} was successfully created."
      else
        puts "Failed to create user:"
        puts user.errors.full_messages.join("\n")
      end
    end
  end
  