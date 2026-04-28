class Organization < ApplicationRecord
  KINDS = %w[autonomo clinica hospital].freeze

  has_many :organization_memberships, dependent: :restrict_with_exception
  has_many :users, through: :organization_memberships
  has_many :organization_responsibles, dependent: :restrict_with_exception
  has_many :organization_registration_invitations, dependent: :delete_all
  has_many :units, dependent: :restrict_with_exception

  has_many :patients, dependent: :restrict_with_exception
  has_many :prescriptions, dependent: :restrict_with_exception
  has_many :medical_certificates, dependent: :restrict_with_exception
  has_many :documents, dependent: :restrict_with_exception
  has_many :consultations, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :cnpj, uniqueness: true, allow_nil: true, length: { is: 14 }
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :state, length: { is: 2 }, allow_blank: true
  validates :country, length: { is: 2 }, allow_blank: true
  validates :legal_name, presence: true, if: :legal_entity?
  validates :cnpj, presence: true, if: :legal_entity?

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :legal_name, with: ->(value) { value&.strip }
  normalizes :trade_name, with: ->(value) { value&.strip }
  normalizes :cnpj, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :phone, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :zip_code, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :street, with: ->(value) { value&.strip }
  normalizes :number, with: ->(value) { value&.strip }
  normalizes :complement, with: ->(value) { value&.strip }
  normalizes :district, with: ->(value) { value&.strip }
  normalizes :city, with: ->(value) { value&.strip }
  normalizes :state, with: ->(value) { value&.strip&.upcase }
  normalizes :country, with: ->(value) { value&.strip&.upcase }
  normalizes :kind, with: ->(value) { value&.strip&.downcase }

  before_validation :populate_name_from_business_names
  after_create :ensure_default_unit!

  def default_unit
    units.order(created_at: :asc).first
  end

  private

  def populate_name_from_business_names
    return if name.present?

    self.name = trade_name.presence || legal_name.presence
  end

  def legal_entity?
    kind.in?(%w[clinica hospital])
  end

  def ensure_default_unit!
    return if units.exists?

    units.create!(name: "Principal", code: "HQ", active: true)
  end
end
