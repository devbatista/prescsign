# Junção N:N entre produto (Medication) e substância ativa (Substance). Um produto
# pode associar mais de uma substância; a classificação SNCR do produto é derivada
# do conjunto (Medication#effective_sncr_type).
class MedicationSubstance < ApplicationRecord
  belongs_to :medication
  belongs_to :substance

  validates :substance_id, uniqueness: { scope: :medication_id }
end
