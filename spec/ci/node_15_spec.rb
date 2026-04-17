require_relative '../spec_helper'

describe "Hello World for Node v15.x" do
  context "a single-process Node v15.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-15")
    }

    it "should deploy successfully with EOL warning" do
      app.deploy do |app|
        expect(app.output).to include("End-of-Life")
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   15.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 15.x...
          remote:        Downloading and installing node 15.14.0...
          remote:        Validating checksum
          remote:        Using default npm version: 7.7.6
        OUTPUT
      end
    end

  end
end
