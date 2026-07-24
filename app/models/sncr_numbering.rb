# Numeracao SNCR (Anvisa) no pool do medico. Cada linha e um numero nacional
# unico obtido da API do SNCR, atrelado ao DoctorProfile (prescritor/CPF) e
# consumido por uma receita controlada na emissao.
#
# Modelagem: uma linha por numero (inclusive expandindo o bloco de 1.000 do
# RCE/RET). Escolhido em vez de faixa+cursor para ter consumo uniforme e
# rastreabilidade por numero (auditoria da dispensacao) — ver desenho na seção 6
# de docs/sncr/SNCR_INTEGRATION.md.
class SncrNumbering < ApplicationRecord
  STATUSES = %w[available consumed].freeze
  # Formato nacional NNNN.N-NN.NNNNNNN — ex.: 2411.1-00.0000001
  NUMBER_FORMAT = /\A\d{4}\.\d-\d{2}\.\d{7}\z/

  class PoolEmpty < StandardError; end

  belongs_to :doctor_profile
  belongs_to :prescription, optional: true

  validates :sncr_type, inclusion: { in: Prescription::SNCR_TYPES }
  validates :number, presence: true, uniqueness: true, format: { with: NUMBER_FORMAT }
  validates :status, inclusion: { in: STATUSES }
  validates :obtained_at, presence: true
  validate :consumption_fields_consistency

  scope :available, -> { where(status: "available") }
  scope :consumed, -> { where(status: "consumed") }
  scope :of_type, ->(type) { where(sncr_type: type) }
  scope :for_doctor, ->(doctor_profile) { where(doctor_profile: doctor_profile) }

  def available?
    status == "available"
  end

  def consumed?
    status == "consumed"
  end

  # Consome atomicamente o proximo numero disponivel do tipo para o medico,
  # vinculando-o a receita. Concorrencia-safe via lock de linha (SKIP LOCKED
  # permite consumidores paralelos pegarem numeros distintos).
  def self.consume_next!(doctor_profile:, sncr_type:, prescription:)
    transaction do
      numbering = available.for_doctor(doctor_profile).of_type(sncr_type)
                           .order(:number)
                           .lock("FOR UPDATE SKIP LOCKED")
                           .first
      raise PoolEmpty, "Sem numeração disponível de #{sncr_type} para o prescritor" if numbering.nil?

      numbering.update!(status: "consumed", prescription: prescription, consumed_at: Time.current)
      numbering
    end
  end

  # Saldo disponivel por tipo: { "NRA" => 5, "RCE" => 1000, ... }.
  def self.balance_for(doctor_profile)
    available.for_doctor(doctor_profile).group(:sncr_type).count
  end

  # Persiste uma lista de numeros (endpoint de Notificacao de Receita).
  # Retorna a quantidade inserida.
  def self.import_numbers!(doctor_profile:, sncr_type:, numbers:, obtained_at: Time.current)
    now = Time.current
    rows = Array(numbers).map do |number|
      {
        doctor_profile_id: doctor_profile.id,
        sncr_type: sncr_type,
        number: number,
        status: "available",
        obtained_at: obtained_at,
        created_at: now,
        updated_at: now
      }
    end
    insert_all!(rows) if rows.any?
    rows.size
  end

  # Persiste um bloco continuo (endpoint RCE/RET: inicio..fim), expandindo a faixa.
  def self.import_range!(doctor_profile:, sncr_type:, first:, last:, obtained_at: Time.current)
    import_numbers!(
      doctor_profile: doctor_profile,
      sncr_type: sncr_type,
      numbers: expand_range(first, last),
      obtained_at: obtained_at
    )
  end

  # Expande "PREFIX.0000001".."PREFIX.0001000" nos numeros individuais.
  def self.expand_range(first, last)
    first_prefix, first_seq = split_number(first)
    last_prefix, last_seq = split_number(last)
    raise ArgumentError, "Faixa com prefixos distintos: #{first} .. #{last}" unless first_prefix == last_prefix
    raise ArgumentError, "Faixa invertida: #{first} .. #{last}" if last_seq < first_seq

    (first_seq..last_seq).map { |seq| "#{first_prefix}.#{seq.to_s.rjust(7, '0')}" }
  end

  def self.split_number(number)
    prefix, _, sequence = number.to_s.rpartition(".")
    raise ArgumentError, "Numero SNCR invalido: #{number}" if prefix.blank? || sequence.blank?

    [ prefix, Integer(sequence, 10) ]
  end

  private

  def consumption_fields_consistency
    if consumed?
      errors.add(:prescription, "deve estar presente quando consumido") if prescription_id.blank?
      errors.add(:consumed_at, "deve estar presente quando consumido") if consumed_at.blank?
    else
      errors.add(:prescription, "deve ser nulo quando disponível") if prescription_id.present?
      errors.add(:consumed_at, "deve ser nulo quando disponível") if consumed_at.present?
    end
  end
end
