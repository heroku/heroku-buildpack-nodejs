require_relative '../spec_helper'

describe "Hello World for Node v17.x" do
  context "a single-process Node v17.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-17")
    }

    it "should deploy successfully with EOL warning" do
      app.deploy do |app|
        expect(app.output).to include("End-of-Life")
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   17.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 17.x...
          remote:        Downloading and installing node 17.9.1...
          remote:        Validating checksum
          remote:        Using default npm version: 8.11.0
        OUTPUT
      end
    end
  end
end
