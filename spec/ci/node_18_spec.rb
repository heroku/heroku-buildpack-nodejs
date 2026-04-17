require_relative '../spec_helper'

describe "Hello World for Node v18.x" do
  context "a single-process Node v18.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-18")
    }

    it "should deploy successfully with EOL warning" do
      app.deploy do |app|
        expect(app.output).to include("End-of-Life")
        expect(successful_body(app).strip).to eq("Hello, world!")
      end
    end
  end
end
