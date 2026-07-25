require "rails_helper"
require "securerandom"

RSpec.describe Sncr::NumberingAssignment do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u.reload
  end
  let(:profile) { user.doctor_profile }
  let(:patient) { create_patient(user: user, organization: organization) }

  def build_prescription(sncr_type:, prescriber: user, prescriber_patient: patient)
    prescriber.prescriptions.create!(
      patient: prescriber_patient, organization: organization,
      code: SecureRandom.alphanumeric(10).upcase, status: "draft",
      content: "Clonazepam 2mg", issued_on: Date.current, sncr_type: sncr_type
    )
  end

  it "consome o próximo número do pool para receita controlada e vincula à receita" do
    SncrNumbering.import_numbers!(doctor_profile: profile, sncr_type: "NRB", numbers: [ "2411.1-00.0000001" ])
    prescription = build_prescription(sncr_type: "NRB")

    numbering = described_class.ensure_for!(prescription)

    expect(numbering).to be_a(SncrNumbering)
    expect(numbering.number).to eq("2411.1-00.0000001")
    expect(numbering.status).to eq("consumed")
    expect(numbering.prescription_id).to eq(prescription.id)
    expect(SncrNumbering.balance_for(profile)["NRB"]).to be_nil
  end

  it "é no-op para receita comum (sem sncr_type)" do
    prescription = build_prescription(sncr_type: nil)
    expect(described_class.ensure_for!(prescription)).to be_nil
  end

  it "é idempotente: não consome outro número se a receita já tem numeração" do
    SncrNumbering.import_numbers!(doctor_profile: profile, sncr_type: "NRB", numbers: [ "2411.1-00.0000001", "2411.1-00.0000002" ])
    prescription = build_prescription(sncr_type: "NRB")
    first = described_class.ensure_for!(prescription)

    again = described_class.ensure_for!(prescription.reload)

    expect(again.id).to eq(first.id)
    expect(SncrNumbering.balance_for(profile)["NRB"]).to eq(1)
  end

  it "levanta PoolEmpty quando não há saldo do tipo" do
    prescription = build_prescription(sncr_type: "RCE")
    expect { described_class.ensure_for!(prescription) }.to raise_error(SncrNumbering::PoolEmpty)
  end

  it "levanta Sncr::Error quando o prescritor não tem perfil de médico" do
    plain = create_user(organization: organization)
    create_membership(user: plain, organization: organization, role: "doctor")
    plain_patient = create_patient(user: plain, organization: organization)
    prescription = build_prescription(sncr_type: "NRB", prescriber: plain, prescriber_patient: plain_patient)

    expect { described_class.ensure_for!(prescription) }.to raise_error(::Sncr::Error, /perfil de médico/)
  end
end
