require_relative '../spec_helper'

describe "Hello World for Node v19.x" do
  context "a single-process Node v19.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-19")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
      end
    end
  end

  context "on an incompatible stack (heroku-18)" do
    it "should log a stack compatibility message" do
      Hatchet::Runner.new(
        "spec/fixtures/repos/node-19",
        stack: "heroku-18",
        allow_failure: true
      ).deploy do |app|
        expect(app.output).to match("Node.js version is not compatible with the current stack")
      end
    end
  end
end
