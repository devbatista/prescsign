require "rails_helper"
require "securerandom"

RSpec.describe Organizations::ResponsibleInvitationService do
  it "sends signup invitation for unconfirmed responsible user" do
    user = build_unconfirmed_user
    organization = Organization.create!(
      name: "Clinica Convite",
      kind: "clinica",
      legal_name: "Clinica Convite LTDA",
      cnpj: unique_cnpj
    )

    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    expect(OrganizationResponsibleMailer).to receive(:with).with(
      organization: organization,
      user: user,
      confirmation_token: kind_of(String)
    ).and_return(double(signup_invitation: delivery))

    described_class.new(organization: organization, user: user).call

    expect(user.reload.confirmation_token).to be_present
    expect(user.confirmation_sent_at).to be_present
  end

  it "sends existing-account invitation for confirmed responsible user" do
    user = build_confirmed_user
    organization = Organization.create!(
      name: "Clinica Convite 2",
      kind: "clinica",
      legal_name: "Clinica Convite 2 LTDA",
      cnpj: unique_cnpj
    )

    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    expect(OrganizationResponsibleMailer).to receive(:with).with(
      organization: organization,
      user: user
    ).and_return(double(existing_account_invitation: delivery))

    described_class.new(organization: organization, user: user).call
  end

  def build_unconfirmed_user
    suffix = SecureRandom.hex(4)
    password = "password123"
    User.create!(
      email: "invite.unconfirmed.#{suffix}@example.com",
      password: password,
      password_confirmation: password,
      status: "active"
    )
  end

  def build_confirmed_user
    user = build_unconfirmed_user
    user.update!(confirmed_at: Time.current)
    user
  end

  def unique_cnpj
    SecureRandom.random_number(10**14).to_s.rjust(14, "0")
  end
end
