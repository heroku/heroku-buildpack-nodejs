require_relative '../spec_helper'

describe "Hello World for Node v10.x" do
  context "a single-process Node v10.x app" do
    let(:app) {
      Hatchet::Runner.new("spec/fixtures/repos/node-10")
    }

    it "should deploy successfully with EOL warning" do
      app.deploy do |app|
        expect(clean_output(app.output)).to include(<<~OUTPUT)
          remote: -----> Installing binaries
          remote:        engines.node (package.json):   10.x
          remote:        engines.npm (package.json):    unspecified (use default)
          remote:
          remote:        Resolving node version 10.x...
          remote:
          remote:  !     Node.js 10.24.1 is now End-of-Life (EOL). It no longer receives security
          remote:  !     updates, bug fixes, or support from the Node.js project and is no longer
          remote:  !     supported on Heroku.
          remote:  !
          remote:  !     In a future buildpack release, this warning will become a build error. Please
          remote:  !     upgrade to a supported version as soon as possible to avoid build failures.
          remote:  !
          remote:  !     https://devcenter.heroku.com/articles/nodejs-support#supported-node-js-versions
          remote:
          remote:        Downloading and installing node 10.24.1...
          remote:        Validating checksum
          remote:        Using default npm version: 6.14.12
        OUTPUT
        expect(successful_body(app).strip).to eq("Hello, world!")
      end
    end

  end
end
