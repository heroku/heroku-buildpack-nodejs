require_relative '../spec_helper'

describe "Hello World for Node v13.x" do
  context "a single-process Node v13.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-13")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
      end
    end

  end
end
