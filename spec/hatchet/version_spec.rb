require_relative '../spec_helper'

#Test that builds fail when a bad version is specified
describe "bad node version" do
  it "gives a helpful error" do
    Hatchet::Runner.new("default-node", allow_failure: true).tap do |app|
      app.before_deploy do
        File.open("package.json", "w+") do |f|
          f.write '{"engines": {
            "node": "14.x.badversion"
          }}'
        end
      end
      app.deploy do
        expect(app.output).to include("Invalid semantic version \"14.x.badversion\"")
      end
    end
  end
end
