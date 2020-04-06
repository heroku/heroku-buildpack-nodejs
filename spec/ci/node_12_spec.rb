require_relative '../spec_helper'

describe "Hello World for Node v12.x" do
  context "a single-process Node v12.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-12")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
      end
    end

  end
end
