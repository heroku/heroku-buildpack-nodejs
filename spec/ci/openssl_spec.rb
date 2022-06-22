require_relative '../spec_helper'

describe "openssl-v3-on-stack-22" do
  it "openssl-v3-on-stack-22 should deploy successfully and start the application" do
    app = Hatchet::Runner.new("spec/fixtures/repos/openssl-v3-on-stack-22")
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from openssl-v3-on-stack-22")
    end
  end
end

