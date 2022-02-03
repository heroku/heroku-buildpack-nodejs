require_relative '../spec_helper'

describe "yarn pnp hello world" do
  context "a single process zero-install app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/yarn-pnp-zero-install")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello from yarn-pnp-zero-install")
      end
    end
  end
end

