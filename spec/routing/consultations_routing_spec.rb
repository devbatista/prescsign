require "rails_helper"

RSpec.describe "Consultations routing", type: :routing do
  it "routes nested index to patients/consultations#index" do
    expect(get: "/v1/patients/patient-1/consultations").to route_to(
      controller: "v1/patients/consultations",
      action: "index",
      patient_id: "patient-1"
    )
  end

  it "routes nested create to patients/consultations#create" do
    expect(post: "/v1/patients/patient-1/consultations").to route_to(
      controller: "v1/patients/consultations",
      action: "create",
      patient_id: "patient-1"
    )
  end

  it "routes show to consultations#show" do
    expect(get: "/v1/consultations/consultation-1").to route_to(
      controller: "v1/consultations",
      action: "show",
      id: "consultation-1"
    )
  end

  it "routes patch update to consultations#update" do
    expect(patch: "/v1/consultations/consultation-1").to route_to(
      controller: "v1/consultations",
      action: "update",
      id: "consultation-1"
    )
  end

  it "routes cancel to consultations#cancel" do
    expect(post: "/v1/consultations/consultation-1/cancel").to route_to(
      controller: "v1/consultations",
      action: "cancel",
      id: "consultation-1"
    )
  end

  it "does not route delete for consultation resource" do
    expect(delete: "/v1/consultations/consultation-1").not_to be_routable
  end
end
