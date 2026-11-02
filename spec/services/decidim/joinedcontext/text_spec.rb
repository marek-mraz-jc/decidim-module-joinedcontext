# frozen_string_literal: true

require "spec_helper"

describe Decidim::Joinedcontext::Text do
  it "strips HTML and entities" do
    expect(described_class.clean("<p>Lav&amp;ička <b>pri</b> rieke</p>")).to eq("Lav&ička pri rieke")
  end

  it "removes e-mail addresses" do
    expect(described_class.clean("Píšte na jana.novak@example.sk, ďakujeme")).to eq("Píšte na , ďakujeme")
  end

  ["+421 905 123 456", "+421905123456", "+420 601 123 456", "0905 123 456", "048/123 45 67"].each do |phone|
    it "removes the phone number #{phone}" do
      expect(described_class.clean("Volajte #{phone} ráno")).to eq("Volajte ráno")
    end
  end

  it "cuts at 2000 characters and drops an empty text" do
    expect(described_class.clean("a" * 2100).size).to eq(2000)
    expect(described_class.clean("<p> </p>")).to be_nil
    expect(described_class.clean(nil)).to be_nil
  end
end
