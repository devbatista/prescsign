require "rails_helper"

RSpec.describe Deliveries::PhoneNumber do
  describe ".to_e164" do
    it "aplica o DDI padrão em número nacional de 10 e 11 dígitos" do
      expect(described_class.to_e164("11987654321")).to eq("+5511987654321")
      expect(described_class.to_e164("1133334444")).to eq("+551133334444")
    end

    it "ignora máscara e espaços" do
      expect(described_class.to_e164("(11) 98765-4321")).to eq("+5511987654321")
    end

    it "preserva número que já traz o DDI" do
      expect(described_class.to_e164("5511987654321")).to eq("+5511987654321")
      expect(described_class.to_e164("+55 11 3333-4444")).to eq("+551133334444")
    end

    # DDD 55 (RS) em número nacional de 11 dígitos não pode ser confundido com
    # DDI 55: o comprimento é o que decide.
    it "trata 11 dígitos iniciados por 55 como número nacional" do
      expect(described_class.to_e164("55987654321")).to eq("+5555987654321")
    end

    it "recusa comprimento fora do reconhecido em vez de adivinhar" do
      expect(described_class.to_e164("987654321")).to be_nil
      expect(described_class.to_e164("123456789012345")).to be_nil
      expect(described_class.to_e164("")).to be_nil
      expect(described_class.to_e164(nil)).to be_nil
    end
  end
end
