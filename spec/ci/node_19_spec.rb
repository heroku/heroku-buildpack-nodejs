require_relative '../spec_helper'

describe "Hello World for Node v19.x" do
  context "a single-process Node v19.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-19")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   19.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 19.x...
          remote:        Downloading and installing node 19.9.0...
          remote:        Validating checksum
          remote:        Using default npm version: 9.6.3
        OUTPUT
      end
    end
  end
end
