require "rails_helper"
require "securerandom"

RSpec.describe User, type: :model do
  it "normalizes email and status" do
    user = described_class.new(
      email: "  USER.TEST@EXAMPLE.COM ",
      encrypted_password: "encrypted-token",
      status: "  ACTIVE "
    )

    user.validate

    expect(user.email).to eq("user.test@example.com")
    expect(user.status).to eq("active")
  end

  it "enforces case-insensitive unique email" do
    described_class.create!(
      email: "duplicate@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )

    user = described_class.new(
      email: "DUPLICATE@EXAMPLE.COM",
      encrypted_password: "encrypted-token",
      status: "active"
    )

    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("has already been taken")
  end
end
