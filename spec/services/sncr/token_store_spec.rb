require "rails_helper"

RSpec.describe Sncr::TokenStore do
  let(:redis) { instance_double(Redis) }
  subject(:store) { described_class.new(user_id: 42, redis: redis) }

  describe "#write" do
    it "grava o token keyado por usuário com TTL derivado do exp do JWT" do
      exp = Time.current.to_i + 600
      token = jwt_with_exp(exp)
      allow(redis).to receive(:set)

      store.write(token)

      expect(redis).to have_received(:set).with("sncr:token:42", token, ex: be_within(2).of(600))
    end

    it "usa TTL de fallback (15min) quando o JWT não tem exp legível" do
      allow(redis).to receive(:set)

      store.write("nao-e-um-jwt")

      expect(redis).to have_received(:set).with("sncr:token:42", "nao-e-um-jwt", ex: 15 * 60)
    end

    it "limita o TTL ao máximo (1h) mesmo com exp distante" do
      token = jwt_with_exp(Time.current.to_i + 10.hours.to_i)
      allow(redis).to receive(:set)

      store.write(token)

      expect(redis).to have_received(:set).with("sncr:token:42", token, ex: 60 * 60)
    end
  end

  it "lê e limpa pela chave do usuário" do
    allow(redis).to receive(:get).with("sncr:token:42").and_return("jwt")
    allow(redis).to receive(:del)

    expect(store.read).to eq("jwt")

    store.clear
    expect(redis).to have_received(:del).with("sncr:token:42")
  end

  it "exige user_id" do
    expect { described_class.new(user_id: nil, redis: redis) }.to raise_error(ArgumentError)
  end

  def jwt_with_exp(exp)
    header = Base64.urlsafe_encode64({ alg: "none" }.to_json, padding: false)
    payload = Base64.urlsafe_encode64({ exp: exp }.to_json, padding: false)
    "#{header}.#{payload}.sig"
  end
end
