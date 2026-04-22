require_relative '../spec_helper'

describe "Hello World for Node v10.x" do
  context "a single-process Node v10.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-10")
    }

    it "should deploy successfully" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   10.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 10.x...
          remote:        Downloading and installing node 10.24.1...
          remote:        Validating checksum
          remote:        Using default npm version: 6.14.12
        OUTPUT
      end
    end

  end
end
