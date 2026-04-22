require_relative '../spec_helper'

describe "Hello World for Node v16.x" do
  context "a single-process Node v16.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-16")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   16.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 16.x...
          remote:        Downloading and installing node 16.20.2...
          remote:        Validating checksum
          remote:        Using default npm version: 8.19.4
        OUTPUT
      end
    end
  end
end
