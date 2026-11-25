# frozen_string_literal: true

describe VagrantPlugins::Noderings::Config do
  subject(:config) { described_class.new }

  it "has sensible defaults" do
    config.finalize!
    expect([config.distro, config.billing_type, config.sort, config.tags, config.ssh_keys, config.wait_timeout])
      .to eq ["ubuntu_24_04", "usage", "price", ["vagrant"], [], 900]
  end

  it "reads the token from the environment" do
    ENV["NODERINGS_TOKEN"] = "env-token"
    config.finalize!
    expect(config.token).to eq "env-token"
  ensure
    ENV.delete("NODERINGS_TOKEN")
  end

  it "explains what is missing" do
    ENV.delete("NODERINGS_TOKEN")
    config.finalize!
    errors = config.validate(nil)["NodeRings provider"]
    expect(errors.join).to include("token is required").and include("set plan, country and city")
  end

  it "accepts an exact plan and region instead of an offer" do
    config.token = "t"
    config.plan_id = "p"
    config.region_id = "r"
    config.finalize!
    expect(config.validate(nil)["NodeRings provider"]).to be_empty
  end

  it "rejects a hostname that is not one DNS label" do
    config.token = "t"
    config.plan_id = "p"
    config.region_id = "r"
    config.hostname = "web_1.example"
    config.finalize!
    expect(config.validate(nil)["NodeRings provider"].join).to include("one DNS label")
  end
end
