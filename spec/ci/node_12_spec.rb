require_relative '../spec_helper'

describe "Hello World for Node v12.x" do
  context "a single-process Node v12.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-12")
    }

    it "should deploy successfully with EOL warning" do
      app.deploy do |app|
        expect(app.output).to include("End-of-Life")
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   12.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 12.x...
          remote:        Downloading and installing node 12.22.12...
          remote:        Validating checksum
          remote:        Using default npm version: 6.14.16
        OUTPUT
      end
    end

  end
end
