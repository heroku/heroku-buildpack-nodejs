require_relative '../spec_helper'

describe "Hello World for Node v22.x" do
  context "a single-process Node v22.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-22")
    }

    it "should deploy successfully without EOL warning" do
      app.deploy do |app|
        expect(successful_body(app).strip).to eq("Hello, world!")
        expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
          remote: -----> Installing binaries
          remote:        engines\.node \(package\.json\):   22\.x
          remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
          remote:
          remote:        Resolving node version 22\.x\.\.\.
          remote:        Downloading and installing node 22\.\d+\.\d+\.\.\.
          remote:        Validating checksum
          remote:        Using default npm version: .+
        REGEX
      end
    end
  end
end
