require 'uri'
$stdout.sync = true

# This runner intentionally refuses normal application database configuration.
abort 'RAILS_ENV must explicitly be test' unless ENV['RAILS_ENV'] == 'test'
url = URI.parse(ENV.fetch('DATABASE_URL', ''))
unless url.scheme == 'mysql2' && %w[127.0.0.1 localhost].include?(url.host) &&
       url.path == '/binblog_switch_api_test'
  abort 'Use a disposable local mysql2 database named binblog_switch_api_test'
end

require_relative 'switch_verification_no_mqtt'
require_relative '../config/environment'
require_relative '../db/migrate/20261027000000_add_switch_statistics_index_to_relay_logs'
require 'timeout'

def verify!(condition, message)
  raise message unless condition

  puts "PASS: #{message}"
end

def statistics_index(connection)
  connection.indexes(:relay_logs).find { |index| index.name == 'index_relay_logs_for_switch_statistics' }
end

pool = ActiveRecord::Base.connection_pool
connection = pool.connection
abort 'A real Mysql2 adapter is required' unless connection.adapter_name == 'Mysql2'
abort 'Unexpected database' unless connection.select_value('SELECT DATABASE()') == 'binblog_switch_api_test'
puts "Ruby: #{RUBY_VERSION}; Rails: #{Rails.version}; MySQL: #{connection.select_value('SELECT VERSION()')}"
puts "SHA: #{IO.popen(%w[git rev-parse HEAD], &:read).strip}; TZ: #{ENV.fetch('TZ', '(system)')}"
puts "ActiveRecord storage timezone: #{ActiveRecord.default_timezone}"
verify!(connection.select_value("SELECT ENGINE FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'devices'") == 'InnoDB',
        'device row locking uses InnoDB')

suffix = SecureRandom.hex(8)
user = device = foreign = nil
threads = []
release = Queue.new

begin
  user = User.create!(username: "mysql_switch_#{suffix}", password: 'test-password-123', email: "#{suffix}@example.com")
  device = Device.create!(chip_id: "mysql_switch_#{suffix}", device_type: 'switch',
                          device_info: { relays: [{ switch_value: 0 }, {}] }.to_json)
  device.users << user
  foreign = Device.create!(chip_id: "mysql_foreign_#{suffix}", device_type: 'switch',
                           device_info: { relays: [{}] }.to_json)
  [
    [device, 0, '2020-06-25T23:59:59+07:00'],
    [device, 0, '2020-06-26T00:00:00+07:00'],
    [device, 0, '2020-06-26T23:59:59+07:00'],
    [device, 0, '2020-06-27T00:00:00+07:00'],
    [device, 1, '2020-06-26T12:00:00+07:00'],
    [foreign, 0, '2020-06-26T12:00:00+07:00']
  ].each { |row, index, timestamp| row.relay_logs.create!(relay_index: index, created_at: Time.iso8601(timestamp)) }

  before_rows = RelayLog.where(device_id: [device.id, foreign.id]).order(:id).pluck(:id, :created_at)
  verify!(statistics_index(connection)&.columns == %w[device_id relay_index created_at], 'schema contains expected ordered index')
  AddSwitchStatisticsIndexToRelayLogs.new.migrate(:down)
  verify!(statistics_index(connection).nil?, 'migration down removes only the statistics index')
  AddSwitchStatisticsIndexToRelayLogs.new.migrate(:up)
  verify!(statistics_index(connection)&.columns == %w[device_id relay_index created_at], 'migration up restores the ordered index')
  verify!(RelayLog.where(device_id: [device.id, foreign.id]).order(:id).pluck(:id, :created_at) == before_rows,
          'migration round trip preserves existing log rows and timestamps')

  original_zone = connection.select_value('SELECT @@session.time_zone')
  begin
    %w[+00:00 +07:00].each do |zone|
      connection.execute("SET SESSION time_zone = #{connection.quote(zone)}")
      result = SwitchRelayStatisticsQuery.new(device: device, relay_index: 0, from: '2020-06-25', to: '2020-06-27').call
      verify!(result[:days].map { |day| day[:count] } == [1, 2, 1], "scoped +07 midnight counts with MySQL session #{zone}")
      verify!(result[:total_records] == 4 && result[:physical_runtime_seconds].nil? && !result[:physical_runtime_verified],
              'log counts do not claim physical runtime')
      empty = SwitchRelayStatisticsQuery.new(device: device, relay_index: 0, from: '2020-05-01', to: '2020-05-31').call
      verify!(empty[:days].length == 31 && empty[:total_records].zero?, '31-day empty range is zero-filled')
      begin
        SwitchRelayStatisticsQuery.new(device: device, relay_index: 0, from: '2020-05-01', to: '2020-06-01')
        raise '32-day range was accepted'
      rescue SwitchApi::Error => e
        verify!(e.code == 'invalid_date_range', '32-day range is rejected')
      end
    end
  ensure
    connection.execute("SET SESSION time_zone = #{connection.quote(original_zone)}")
  end

  # A held read transaction owns a metadata lock. Demonstrate that the DDL
  # waits/fails within a bounded session budget, rather than claiming online DDL.
  ddl_error = nil
  connection.transaction do
    connection.select_value("SELECT id FROM relay_logs WHERE device_id = #{device.id} LIMIT 1")
    ddl = Thread.new do
      pool.with_connection do |ddl_connection|
        ddl_connection.execute('SET SESSION lock_wait_timeout = 1')
        begin
          AddSwitchStatisticsIndexToRelayLogs.new.migrate(:down)
        rescue ActiveRecord::StatementInvalid => e
          ddl_error = e
        end
      end
    end
    threads << ddl
    Timeout.timeout(8) { ddl.value }
  end
  verify!(ddl_error&.cause.respond_to?(:error_number) && ddl_error.cause.error_number == 1205,
          'held read transaction blocks index DDL until configured lock timeout')
  verify!(!statistics_index(connection).nil?, 'timed-out DDL preserves the statistics index')
  puts 'DDL evidence is from a small disposable database; production size/locking assessment remains pending.'

  # Two real connections must wait for a holder's row lock before either
  # command reaches its fake publisher. Observe actual InnoDB lock waits.
  held = Queue.new
  started = Queue.new
  published = Queue.new
  snapshot = device.reload.attributes
  holder = Thread.new do
    pool.with_connection do
      Device.find(device.id).with_lock do
        held << true
        release.pop
      end
    end
  end
  threads << holder
  Timeout.timeout(8) { held.pop }
  publisher = Object.new
  publisher.define_singleton_method(:call) do |topic:, payload:|
    raise 'Publish occurred inside a database transaction' unless pool.connection.open_transactions.zero?

    published << [topic, payload]
  end
  workers = 2.times.map do |number|
    Thread.new do
      pool.with_connection do |worker_connection|
        worker_connection.execute('SET SESSION innodb_lock_wait_timeout = 15')
        worker_device = Device.find(device.id)
        worker_user = User.find(user.id)
        started << worker_connection.select_value('SELECT CONNECTION_ID()').to_i
        SwitchCommandService.new(device: worker_device, user: worker_user, request_id: "mysql-#{suffix}-#{number}",
                                 publisher: publisher).call(operation: 'state', relay_index: 0, switch_value: number)
      end
    end
  end
  threads.concat(workers)
  ids = Timeout.timeout(8) { 2.times.map { started.pop } }
  begin
    Timeout.timeout(8) do
      loop do
        waiting = ActiveRecord::Base.uncached do
          connection.select_value(<<~SQL).to_i
            SELECT COUNT(DISTINCT threads.PROCESSLIST_ID)
            FROM performance_schema.data_lock_waits AS waits
            JOIN performance_schema.threads AS threads
              ON threads.THREAD_ID = waits.REQUESTING_THREAD_ID
            WHERE threads.PROCESSLIST_ID IN (#{ids.join(',')})
          SQL
        end
        break if waiting == 2

        workers.each { |worker| worker.value unless worker.alive? }
        sleep 0.05
      end
    end
  rescue Timeout::Error
    puts "Observed transactions: #{connection.select_all("SELECT trx_mysql_thread_id, trx_state FROM information_schema.innodb_trx WHERE trx_mysql_thread_id IN (#{ids.join(',')})").to_a.inspect}"
    workers.each_with_index { |worker, index| puts "Worker #{ids[index]}: #{worker.status}; #{worker.backtrace&.first(5)&.join('; ')}" }
    raise
  end
  verify!(published.empty?, 'both commands wait on the device row lock before publishing')
  release << true
  Timeout.timeout(8) { holder.value; workers.each(&:value) }
  verify!(published.size == 2, 'both commands publish once after the row lock is released, outside transactions')
  verify!(device.reload.attributes == snapshot, 'concurrent commands preserve the device snapshot')
  verify!(device.device_events.where(event_type: 'switch_command_requested').count == 2 &&
          device.device_events.where(event_type: 'switch_command_result').count == 2,
          'concurrent commands persist both requested and result audits')
  verify!(device.device_events.where(event_type: 'switch_command_result').all? { |event| event.payload['outcome'] == 'publish_returned' },
          'fake publish results remain unacknowledged publish outcomes')
  puts 'EXECUTED / PASSED: isolated MySQL migration, timezone, statistics and lock verification. No hardware acceptance claimed.'
ensure
  release << true
  threads.each do |thread|
    next if thread.join(20)

    thread.kill
    thread.join
  end
  [device, foreign].compact.each do |row|
    RelayLog.where(device_id: row.id).delete_all
    row.users.clear
    row.destroy!
  end
  user&.destroy!
end
