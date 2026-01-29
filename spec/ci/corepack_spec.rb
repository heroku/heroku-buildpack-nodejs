require_relative '../spec_helper'

describe "corepack support" do
  it "should be able to run an app that installs pnpm using corepack's packageManager field" do
    app = Hatchet::Runner.new("spec/fixtures/repos/corepack-pnpm")
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from corepack-pnpm")
    end
    app.run("pnpm --version").to match("???")
    app.run("echo $PATH").to eq(<<~OUTPUT)
      PATH=???
    OUTPUT
  end

  it "should be able to run an app that installs yarn using corepack's packageManager field" do
    app = Hatchet::Runner.new("spec/fixtures/repos/corepack-yarn")
    app.deploy do |app|
      expect(successful_body(app).strip).to eq("Hello from corepack-yarn")
    end
    app.run("yarn --version").to match("???")
  end
end

