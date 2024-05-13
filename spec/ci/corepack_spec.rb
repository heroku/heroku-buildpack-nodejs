require_relative '../spec_helper'

describe "corepack support" do
  it "should be able to run an app that installs pnpm using corepack" do
    app = Hatchet::Runner.new("spec/fixtures/repos/corepack-pnpm")
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from corepack-pnpm")
    end
  end

  it "should be able to run an app that installs yarn using corepack" do
    app = Hatchet::Runner.new("spec/fixtures/repos/corepack-yarn")
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from corepack-yarn")
    end
  end
end

