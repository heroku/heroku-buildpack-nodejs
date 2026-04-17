require_relative '../spec_helper'

describe "Hello World for Node v22.x" do
  context "a single-process Node v22.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-22")
    }

    it "should deploy successfully without EOL warning" do
      app.deploy do |app|
        expect(app.output).not_to include("End-of-Life")
        expect(successful_body(app).strip).to eq("Hello, world!")
      end
    end
  end
end
