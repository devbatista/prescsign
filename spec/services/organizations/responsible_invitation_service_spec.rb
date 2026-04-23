require "rails_helper"
require "securerandom"

RSpec.describe Organizations::ResponsibleInvitationService do
  it "issues invitation token and sends signup invitation mail" do
    inviter = create_inviter
    organization = Organization.create!(
      name: "Clinica Convite",
      kind: "clinica",
      legal_name: "Clinica Convite LTDA",
      cnpj: unique_cnpj
    )
    invited_email = "invite.#{SecureRandom.hex(4)}@example.com"

    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    expect(OrganizationResponsibleMailer).to receive(:with).with(
      organization: organization,
      invited_email: invited_email,
      invitation_token: kind_of(String),
      invitation: an_instance_of(OrganizationRegistrationInvitation)
    ).and_return(double(signup_invitation: delivery))

    invitation = described_class.new(
      organization: organization,
      invited_email: invited_email,
      invited_by_user: inviter
    ).call

    expect(invitation).to be_persisted
    expect(invitation.organization_id).to eq(organization.id)
    expect(invitation.invited_by_user_id).to eq(inviter.id)
    expect(invitation.invited_email).to eq(invited_email)
    expect(invitation.accepted_at).to be_nil
    expect(invitation.expires_at).to be > Time.current
  end

  def create_inviter
    suffix = SecureRandom.hex(4)
    user = User.create!(
      email: "inviter.#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123",
      status: "active",
      confirmed_at: Time.current
    )
    user
  end

  def unique_cnpj
    SecureRandom.random_number(10**14).to_s.rjust(14, "0")
  end
end
