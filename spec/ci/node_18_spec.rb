require_relative '../spec_helper'

describe "Hello World for Node v18.x" do
  context "a single-process Node v18.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-18")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   18.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 18.x...
          remote:        Downloading and installing node 18.20.8...
          remote:        Validating checksum
          remote:        Using default npm version: 10.8.2
        OUTPUT
      end
    end
  end
end
