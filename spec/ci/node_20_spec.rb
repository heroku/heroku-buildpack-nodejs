require_relative '../spec_helper'

describe "Hello World for Node v20.x" do
  context "a single-process Node v20.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-20")
    }

    it "should deploy successfully without EOL warning" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
          remote: -----> Installing binaries
          remote:        engines\.node \(package\.json\):   20\.x
          remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
          remote:
          remote:        Resolving node version 20\.x\.\.\.
          remote:        Downloading and installing node 20\.\d+\.\d+\.\.\.
          remote:        Validating checksum
          remote:        Using default npm version: .+
        REGEX
      end
    end
  end
end
