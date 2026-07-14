# frozen_string_literal: true

require "digest"

SEED_PASSWORD = ENV.fetch("SEED_PASSWORD", "password123")
SEED_NOW = Time.zone.parse("2026-05-11 09:00:00")

def upsert_by(model, lookup, attributes)
  record = model.find_or_initialize_by(lookup)
  record.assign_attributes(attributes)
  record.save!
  record
end

def create_once_by(model, lookup, attributes)
  record = model.find_or_initialize_by(lookup)
  return record if record.persisted?

  record.assign_attributes(attributes)
  record.save!
  record
end

def sync_user_roles(user, active_roles)
  active_roles = active_roles.map(&:to_s)
  user.user_roles.where.not(role: active_roles).update_all(status: "inactive", updated_at: Time.current)

  active_roles.each do |role|
    upsert_by(UserRole, { user: user, role: role }, { status: "active" })
  end
end

def reset_seed_data!
  connection = ActiveRecord::Base.connection
  ignored_tables = %w[ar_internal_metadata schema_migrations]
  tables = connection.tables - ignored_tables
  return if tables.empty?

  quoted_tables = tables.map { |table| connection.quote_table_name(table) }.join(", ")
  connection.execute("TRUNCATE TABLE #{quoted_tables} RESTART IDENTITY CASCADE")
end

def seed_digits(key, length)
  digest = Digest::SHA256.hexdigest("prescsign-seed-#{key}")
  digest.chars.map { |char| char.to_i(16).to_s }.join.first(length)
end

def cpf_check_digit(numbers)
  sum = numbers.each_with_index.sum { |digit, index| digit * (numbers.length + 1 - index) }
  remainder = (sum * 10) % 11
  remainder == 10 ? 0 : remainder
end

def seed_cpf(key)
  digits = seed_digits("cpf-#{key}", 9).chars.map(&:to_i)
  first_digit = cpf_check_digit(digits)
  second_digit = cpf_check_digit(digits + [first_digit])
  (digits + [first_digit, second_digit]).join
end

def cnpj_check_digit(numbers, weights)
  remainder = numbers.zip(weights).sum { |digit, weight| digit * weight } % 11
  remainder < 2 ? 0 : 11 - remainder
end

def seed_cnpj(key)
  digits = seed_digits("cnpj-#{key}", 8).chars.map(&:to_i) + [0, 0, 0, 1]
  first_digit = cnpj_check_digit(digits, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
  second_digit = cnpj_check_digit(digits + [first_digit], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
  (digits + [first_digit, second_digit]).join
end

def seed_phone(area_code, key)
  "#{area_code}9#{seed_digits("phone-#{key}", 8)}"
end
