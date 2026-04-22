require_relative '../spec_helper'

describe "corepack support" do
  it "should be able to run an app that installs pnpm using corepack" do
    app = Hatchet::Runner.new("spec/fixtures/repos/corepack-pnpm")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   unspecified
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.pnpm \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): pnpm@9\.0\.6
        remote:
        remote:        No Node\.js version specified, resolving current LTS version\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing pnpm \(9\.0\.6\)
        remote:        Using pnpm .+
      REGEX
      expect(successful_body(app).strip).to eq("Hello from corepack-pnpm")
    end
  end

  it "should be able to run an app that installs yarn using corepack" do
    app = Hatchet::Runner.new("spec/fixtures/repos/corepack-yarn")
    app.deploy do |app|
      expect(clean_output(app.output)).to match(Regexp.new(<<~'REGEX'))
        remote: -----> Installing binaries
        remote:        engines\.node \(package\.json\):   unspecified
        remote:        engines\.npm \(package\.json\):    unspecified \(use default\)
        remote:        engines\.yarn \(package\.json\):   unspecified \(use default\)
        remote:        packageManager \(package\.json\): yarn@4\.1\.1
        remote:
        remote:        No Node\.js version specified, resolving current LTS version\.\.\.
        remote:        Downloading and installing node .+\.\.\.
        remote:        Validating checksum
        remote:        Using default npm version: .+
        remote:        Downloading and installing yarn .+
        remote:        Using yarn .+
      REGEX
      expect(successful_body(app).strip).to eq("Hello from corepack-yarn")
    end
  end
end
