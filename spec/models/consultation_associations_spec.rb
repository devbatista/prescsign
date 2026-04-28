require "rails_helper"

RSpec.describe "Consultation associations", type: :model do
  it "defines patient has_many consultations with restrict_with_exception" do
    reflection = Patient.reflect_on_association(:consultations)

    expect(reflection).to be_present
    expect(reflection.macro).to eq(:has_many)
    expect(reflection.options[:dependent]).to eq(:restrict_with_exception)
  end

  it "defines user has_many consultations with restrict_with_exception" do
    reflection = User.reflect_on_association(:consultations)

    expect(reflection).to be_present
    expect(reflection.macro).to eq(:has_many)
    expect(reflection.options[:dependent]).to eq(:restrict_with_exception)
  end

  it "defines organization has_many consultations with restrict_with_exception" do
    reflection = Organization.reflect_on_association(:consultations)

    expect(reflection).to be_present
    expect(reflection.macro).to eq(:has_many)
    expect(reflection.options[:dependent]).to eq(:restrict_with_exception)
  end
end
