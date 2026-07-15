module ApplicationHelper
  # Formats a raw CPF (digits) as 000.000.000-00; returns the input unchanged
  # when it doesn't have 11 digits.
  def number_to_cpf(value)
    digits = value.to_s.gsub(/\D/, "")
    return value.to_s unless digits.length == 11

    digits.gsub(/(\d{3})(\d{3})(\d{3})(\d{2})/, '\1.\2.\3-\4')
  end

  def age_in_years(date)
    return "—" if date.blank?

    today = Date.current
    age = today.year - date.year
    age -= 1 if date.change(year: today.year) > today
    "#{age} anos"
  end

  def user_display_name(user)
    user&.doctor_profile&.full_name.presence || user&.email || "—"
  end
end
