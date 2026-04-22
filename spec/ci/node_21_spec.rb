require_relative '../spec_helper'

describe "Hello World for Node v21.x" do
  context "a single-process Node v21.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-21")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   21.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 21.x...
          remote:        Downloading and installing node 21.7.3...
          remote:        Validating checksum
          remote:        Using default npm version: 10.5.0
        OUTPUT
      end
    end
  end
end
