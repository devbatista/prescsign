require "rails_helper"
require "securerandom"

RSpec.describe Consultation, type: :model do
  it "is valid with required attributes" do
    organization = create_organization
    user = create_user(current_organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)

    consultation = described_class.new(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.current,
      status: "scheduled"
    )

    expect(consultation).to be_valid
  end

  it "rejects unsupported status values" do
    expect do
      described_class.new(status: "unknown", scheduled_at: Time.current)
    end.to raise_error(ArgumentError, "'unknown' is not a valid status")
  end

  it "rejects finished_at earlier than scheduled_at" do
    organization = create_organization
    user = create_user(current_organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)

    consultation = described_class.new(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-04-28 10:00:00"),
      finished_at: Time.zone.parse("2026-04-28 09:59:59"),
      status: "completed"
    )

    expect(consultation).not_to be_valid
    expect(consultation.errors[:finished_at]).to include("must be greater than or equal to scheduled_at")
  end

  it "assigns organization_id from patient when missing" do
    organization = create_organization
    user = create_user(current_organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)

    consultation = described_class.new(
      patient: patient,
      user: user,
      scheduled_at: Time.current,
      status: "scheduled"
    )
    consultation.validate

    expect(consultation.organization_id).to eq(organization.id)
  end

  it "returns records ordered by most recent scheduled_at first" do
    organization = create_organization
    user = create_user(current_organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)

    older = described_class.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: 2.days.ago,
      status: "scheduled"
    )
    newer = described_class.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: 1.day.ago,
      status: "scheduled"
    )

    expect(described_class.recent_first).to eq([newer, older])
  end

  it "filters by status" do
    organization = create_organization
    user = create_user(current_organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)

    scheduled = described_class.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.current,
      status: "scheduled"
    )
    _completed = described_class.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.current,
      status: "completed"
    )

    expect(described_class.with_status("scheduled")).to eq([scheduled])
  end

  it "filters by scheduled_at range" do
    organization = create_organization
    user = create_user(current_organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)

    in_range = described_class.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-04-20 10:00:00"),
      status: "scheduled"
    )
    _out_of_range = described_class.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-04-25 10:00:00"),
      status: "scheduled"
    )

    from = Time.zone.parse("2026-04-19 00:00:00")
    to = Time.zone.parse("2026-04-21 23:59:59")
    expect(described_class.scheduled_between(from, to)).to eq([in_range])
  end

  it "rejects when organization does not match patient organization" do
    organization = create_organization
    another_organization = create_organization
    user = create_user(current_organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)

    consultation = described_class.new(
      patient: patient,
      user: user,
      organization: another_organization,
      scheduled_at: Time.current,
      status: "scheduled"
    )

    expect(consultation).not_to be_valid
    expect(consultation.errors[:organization_id]).to include("must match patient and user organization")
  end

  def create_organization
    suffix = SecureRandom.hex(4)
    Organization.create!(
      name: "Org Consulta #{suffix}",
      kind: "autonomo"
    )
  end

  def create_user(current_organization:)
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "consultation.user.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active",
      current_organization: current_organization
    )
  end

  def create_membership(user:, organization:)
    OrganizationMembership.create!(
      user: user,
      organization: organization,
      role: "doctor",
      status: "active"
    )
  end

  def create_patient(user:, organization:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      user: user,
      organization: organization,
      full_name: "Paciente Consulta #{suffix}",
      cpf: "12345#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end
end
