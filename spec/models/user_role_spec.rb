require "rails_helper"
require "securerandom"

RSpec.describe UserRole, type: :model do
  it "is valid with supported role and status" do
    role = described_class.new(
      user: create_user,
      role: "support",
      status: "active"
    )

    expect(role).to be_valid
  end

  it "rejects duplicate role for same user" do
    user = create_user
    described_class.create!(user: user, role: "admin", status: "active")

    duplicate = described_class.new(user: user, role: "admin", status: "inactive")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:role]).to include("has already been taken")
  end

  def create_user
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "user.role.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )
  end
end
