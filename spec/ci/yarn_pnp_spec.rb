require_relative '../spec_helper'

describe "yarn pnp hello world" do
  it "zero-install with NODE_MODLES_CACHE=false should deploy successfully" do
    app = Hatchet::Runner.new(
      "spec/fixtures/repos/yarn-pnp-zero-install",
      config: { "NODE_MODULES_CACHE": "false" }
    )
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from yarn-pnp-zero-install")
    end
  end

  it "nonzero-install should deploy successfully" do
    app = Hatchet::Runner.new(
      "spec/fixtures/repos/yarn-pnp-nonzero-install",
      config: { "NODE_MODULES_CACHE": "false" }
    )
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from yarn-pnp-nonzero-install")
    end
  end
end

