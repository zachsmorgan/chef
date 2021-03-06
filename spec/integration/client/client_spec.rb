require "support/shared/integration/integration_helper"
require "chef/mixin/shell_out"
require "tiny_server"
require "tmpdir"

describe "chef-client" do

  def recipes_filename
    File.join(CHEF_SPEC_DATA, "recipes.tgz")
  end

  def start_tiny_server(server_opts = {})
    @server = TinyServer::Manager.new(server_opts)
    @server.start
    @api = TinyServer::API.instance
    @api.clear
    #
    # trivial endpoints
    #
    # just a normal file
    # (expected_content should be uncompressed)
    @api.get("/recipes.tgz", 200) {
      File.open(recipes_filename, "rb") do |f|
        f.read
      end
    }
  end

  def stop_tiny_server
    @server.stop
    @server = @api = nil
  end

  include IntegrationSupport
  include Chef::Mixin::ShellOut

  let(:chef_dir) { File.join(File.dirname(__FILE__), "..", "..", "..", "bin") }

  # Invoke `chef-client` as `ruby PATH/TO/chef-client`. This ensures the
  # following constraints are satisfied:
  # * Windows: windows can only run batch scripts as bare executables. Rubygems
  # creates batch wrappers for installed gems, but we don't have batch wrappers
  # in the source tree.
  # * Other `chef-client` in PATH: A common case is running the tests on a
  # machine that has omnibus chef installed. In that case we need to ensure
  # we're running `chef-client` from the source tree and not the external one.
  # cf. CHEF-4914
  let(:chef_client) { "ruby '#{chef_dir}/chef-client' --minimal-ohai" }

  let(:critical_env_vars) { %w{_ORIGINAL_GEM_PATH GEM_PATH GEM_HOME GEM_ROOT BUNDLE_BIN_PATH BUNDLE_GEMFILE RUBYLIB RUBYOPT RUBY_ENGINE RUBY_ROOT RUBY_VERSION PATH}.map { |o| "#{o}=#{ENV[o]}" } .join(" ") }

  when_the_repository "has a cookbook with a no-op recipe" do
    before { file "cookbooks/x/recipes/default.rb", "" }

    it "should complete with success" do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
EOM

      shell_out!("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default'", :cwd => chef_dir)
    end

    it "should complete successfully with no other environment variables", :skip => (Chef::Platform.windows?) do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
EOM

      begin
        result = shell_out("env -i #{critical_env_vars} #{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default'", :cwd => chef_dir)
        result.error!
      rescue
        Chef::Log.info "Bare invocation will have the following load-path."
        Chef::Log.info shell_out!("env -i #{critical_env_vars} ruby -e 'puts $:'").stdout
        raise
      end
    end

    it "should complete successfully with --no-listen" do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
EOM

      result = shell_out("#{chef_client} --no-listen -c \"#{path_to('config/client.rb')}\" -o 'x::default'", :cwd => chef_dir)
      result.error!
    end

    it "should be able to node.save with bad utf8 characters in the node data" do
      file "cookbooks/x/attributes/default.rb", 'default["badutf8"] = "Elan Ruusam\xE4e"'
      result = shell_out("#{chef_client} -z -r 'x::default' --disable-config", :cwd => path_to(""))
      result.error!
    end

    context "and no config file" do
      it "should complete with success when cwd is just above cookbooks and paths are not specified" do
        result = shell_out("#{chef_client} -z -o 'x::default' --disable-config", :cwd => path_to(""))
        result.error!
      end

      it "should complete with success when cwd is below cookbooks and paths are not specified" do
        result = shell_out("#{chef_client} -z -o 'x::default' --disable-config", :cwd => path_to("cookbooks/x"))
        result.error!
      end

      it "should fail when cwd is below high above and paths are not specified" do
        result = shell_out("#{chef_client} -z -o 'x::default' --disable-config", :cwd => File.expand_path("..", path_to("")))
        expect(result.exitstatus).to eq(1)
      end
    end

    context "and a config file under .chef/knife.rb" do
      before { file ".chef/knife.rb", "xxx.xxx" }

      it "should load .chef/knife.rb when -z is specified" do
        result = shell_out("#{chef_client} -z -o 'x::default'", :cwd => path_to(""))
        # FATAL: Configuration error NoMethodError: undefined method `xxx' for nil:NilClass
        expect(result.stdout).to include("xxx")
      end

    end

    it "should complete with success" do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
EOM

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default'", :cwd => chef_dir)
      result.error!
    end

    context "and a private key" do
      before do
        file "mykey.pem", <<EOM
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEApubutqtYYQ5UiA9QhWP7UvSmsfHsAoPKEVVPdVW/e8Svwpyf
0Xef6OFWVmBE+W442ZjLOe2y6p2nSnaq4y7dg99NFz6X+16mcKiCbj0RCiGqCvCk
NftHhTgO9/RFvCbmKZ1RKNob1YzLrFpxBHaSh9po+DGWhApcd+I+op+ZzvDgXhNn
0nauZu3rZmApI/r7EEAOjFedAXs7VPNXhhtZAiLSAVIrwU3ZajtSzgXOxbNzgj5O
AAAMmThK+71qPdffAdO4J198H6/MY04qgtFo7vumzCq0UCaGZfmeI1UNE4+xQWwP
HJ3pDAP61C6Ebx2snI2kAd9QMx9Y78nIedRHPwIDAQABAoIBAHssRtPM1GacWsom
8zfeN6ZbI4KDlbetZz0vhnqDk9NVrpijWlcOP5dwZXVNitnB/HaqCqFvyPDY9JNB
zI/pEFW4QH59FVDP42mVEt0keCTP/1wfiDDGh1vLqVBYl/ZphscDcNgDTzNkuxMx
k+LFVxKnn3w7rGc59lALSkpeGvbbIDjp3LUMlUeCF8CIFyYZh9ZvXe4OCxYdyjxb
i8tnMLKvJ4Psbh5jMapsu3rHQkfPdqzztQUz8vs0NYwP5vWge46FUyk+WNm/IhbJ
G3YM22nwUS8Eu2bmTtADSJolATbCSkOwQ1D+Fybz/4obfYeGaCdOqB05ttubhenV
ShsAb7ECgYEA20ecRVxw2S7qA7sqJ4NuYOg9TpfGooptYNA1IP971eB6SaGAelEL
awYkGNuu2URmm5ElZpwJFFTDLGA7t2zB2xI1FeySPPIVPvJGSiZoFQOVlIg9WQzK
7jTtFQ/tOMrF+bigEUJh5bP1/7HzqSpuOsPjEUb2aoCTp+tpiRGL7TUCgYEAwtns
g3ysrSEcTzpSv7fQRJRk1lkBhatgNd0oc+ikzf74DaVLhBg1jvSThDhiDCdB59mr
Jh41cnR1XqE8jmdQbCDRiFrI1Pq6TPaDZFcovDVE1gue9x86v3FOH2ukPG4d2/Xy
HevXjThtpMMsWFi0JYXuzXuV5HOvLZiP8sN3lSMCgYANpdxdGM7RRbE9ADY0dWK2
V14ReTLcxP7fyrWz0xLzEeCqmomzkz3BsIUoouu0DCTSw+rvAwExqcDoDylIVlWO
fAifz7SeZHbcDxo+3TsXK7zwnLYsx7YNs2+aIv6hzUUbMNmNmXMcZ+IEwx+mRMTN
lYmZdrA5mr0V83oDFPt/jQKBgC74RVE03pMlZiObFZNtheDiPKSG9Bz6wMh7NWMr
c37MtZLkg52mEFMTlfPLe6ceV37CM8WOhqe+dwSGrYhOU06dYqUR7VOZ1Qr0aZvo
fsNPu/Y0+u7rMkgv0fs1AXQnvz7kvKaF0YITVirfeXMafuKEtJoH7owRbur42cpV
YCAtAoGAP1rHOc+w0RUcBK3sY7aErrih0OPh9U5bvJsrw1C0FIZhCEoDVA+fNIQL
syHLXYFNy0OxMtH/bBAXBGNHd9gf5uOnqh0pYcbe/uRAxumC7Rl0cL509eURiA2T
+vFmf54y9YdnLXaqv+FhJT6B6V7WX7IpU9BMqJY1cJYXHuHG2KA=
-----END RSA PRIVATE KEY-----
EOM
      end

      it "should complete with success even with a client key" do
        file "config/client.rb", <<EOM
local_mode true
client_key #{path_to('mykey.pem').inspect}
cookbook_path #{path_to('cookbooks').inspect}
EOM

        result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default'", :cwd => chef_dir)
        result.error!
      end

      it "should run recipes specified directly on the command line" do
        file "config/client.rb", <<EOM
local_mode true
client_key #{path_to('mykey.pem').inspect}
cookbook_path #{path_to('cookbooks').inspect}
EOM

        file "arbitrary.rb", <<EOM
file #{path_to('tempfile.txt').inspect} do
  content '1'
end
EOM

        file "arbitrary2.rb", <<EOM
file #{path_to('tempfile2.txt').inspect} do
  content '2'
end
EOM

        result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" #{path_to('arbitrary.rb')} #{path_to('arbitrary2.rb')}", :cwd => chef_dir)
        result.error!

        expect(IO.read(path_to("tempfile.txt"))).to eq("1")
        expect(IO.read(path_to("tempfile2.txt"))).to eq("2")
      end

      it "should run recipes specified as relative paths directly on the command line" do
        file "config/client.rb", <<EOM
local_mode true
client_key #{path_to('mykey.pem').inspect}
cookbook_path #{path_to('cookbooks').inspect}
EOM

        file "arbitrary.rb", <<EOM
file #{path_to('tempfile.txt').inspect} do
  content '1'
end
EOM

        result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" arbitrary.rb", :cwd => path_to(""))
        result.error!

        expect(IO.read(path_to("tempfile.txt"))).to eq("1")
      end

      it "should run recipes specified directly on the command line AFTER recipes in the run list" do
        file "config/client.rb", <<EOM
local_mode true
client_key #{path_to('mykey.pem').inspect}
cookbook_path #{path_to('cookbooks').inspect}
EOM

        file "cookbooks/x/recipes/constant_definition.rb", <<EOM
class ::Blah
  THECONSTANT = '1'
end
EOM
        file "arbitrary.rb", <<EOM
file #{path_to('tempfile.txt').inspect} do
  content ::Blah::THECONSTANT
end
EOM

        result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o x::constant_definition arbitrary.rb", :cwd => path_to(""))
        result.error!

        expect(IO.read(path_to("tempfile.txt"))).to eq("1")
      end

    end

    it "should complete with success when passed the -z flag" do
      file "config/client.rb", <<EOM
chef_server_url 'http://omg.com/blah'
cookbook_path "#{path_to('cookbooks')}"
EOM

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' -z", :cwd => chef_dir)
      result.error!
    end

    it "should complete with success when passed the --local-mode flag" do
      file "config/client.rb", <<EOM
chef_server_url 'http://omg.com/blah'
cookbook_path "#{path_to('cookbooks')}"
EOM

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' --local-mode", :cwd => chef_dir)
      result.error!
    end

    it "should not print SSL warnings when running in local-mode" do
      file "config/client.rb", <<EOM
chef_server_url 'http://omg.com/blah'
cookbook_path "#{path_to('cookbooks')}"
EOM

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' --local-mode", :cwd => chef_dir)
      expect(result.stdout).not_to include("SSL validation of HTTPS requests is disabled.")
      result.error!
    end

    it "should complete with success when passed -z and --chef-zero-port" do
      file "config/client.rb", <<EOM
chef_server_url 'http://omg.com/blah'
cookbook_path "#{path_to('cookbooks')}"
EOM

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' -z", :cwd => chef_dir)
      result.error!
    end

    it "should complete with success when setting the run list with -r" do
      file "config/client.rb", <<EOM
chef_server_url 'http://omg.com/blah'
cookbook_path "#{path_to('cookbooks')}"
EOM

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -r 'x::default' -z", :cwd => chef_dir)
      expect(result.stdout).not_to include("Overridden Run List")
      expect(result.stdout).to include("Run List is [recipe[x::default]]")
      #puts result.stdout
      result.error!
    end

    it "should complete with success when using --profile-ruby and output a profile file" do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
EOM
      result = shell_out!("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' -z --profile-ruby", :cwd => chef_dir)
      expect(File.exist?(path_to("config/local-mode-cache/cache/graph_profile.out"))).to be true
    end

    it "doesn't produce a profile when --profile-ruby is not present" do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
EOM
      result = shell_out!("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' -z", :cwd => chef_dir)
      expect(File.exist?(path_to("config/local-mode-cache/cache/graph_profile.out"))).to be false
    end
  end

  when_the_repository "has a cookbook that should fail chef_version checks" do
    before do
      file "cookbooks/x/recipes/default.rb", ""
      file "cookbooks/x/metadata.rb", <<EOM
name 'x'
version '0.0.1'
chef_version '~> 999.99'
EOM
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
EOM
    end
    it "should fail the chef client run" do
      command = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' --no-fork", :cwd => chef_dir)
      expect(command.exitstatus).to eql(1)
      expect(command.stdout).to match(/Chef::Exceptions::CookbookChefVersionMismatch/)
    end
  end

  when_the_repository "has a cookbook that uses cheffish resources" do
    before do
      file "cookbooks/x/recipes/default.rb", <<-EOM
        raise "Cheffish was loaded before we used any cheffish things!" if defined?(Cheffish::VERSION)
        ran_block = false
        got_server = with_chef_server 'https://blah.com' do
          ran_block = true
          run_context.cheffish.current_chef_server
        end
        raise "with_chef_server block was not run!" if !ran_block
        raise "Cheffish was not loaded when we did cheffish things!" if !defined?(Cheffish::VERSION)
        raise "current_chef_server did not return its value!" if got_server[:chef_server_url] != 'https://blah.com'
      EOM
      file "config/client.rb", <<-EOM
        local_mode true
        cookbook_path "#{path_to('cookbooks')}"
      EOM
    end

    it "the cheffish DSL is loaded lazily" do
      command = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' --no-fork", :cwd => chef_dir)
      expect(command.exitstatus).to eql(0)
    end
  end

  when_the_repository "has a cookbook that uses chef-provisioning resources" do
    before do
      file "cookbooks/x/recipes/default.rb", <<-EOM
        with_driver 'blah'
      EOM
      file "config/client.rb", <<-EOM
        local_mode true
        cookbook_path "#{path_to('cookbooks')}"
      EOM
    end

    it "the cheffish DSL tries to load but fails (because chef-provisioning is not there)" do
      command = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default' --no-fork", :cwd => chef_dir)
      expect(command.exitstatus).to eql(1)
      expect(command.stdout).to match(/cannot load such file -- chef\/provisioning/)
    end
  end

  when_the_repository "has a cookbook that generates deprecation warnings" do
    before do
      file "cookbooks/x/recipes/default.rb", <<-EOM
        class ::MyResource < Chef::Resource
          use_automatic_resource_name
          property :x, default: []
          property :y, default: {}
        end

        my_resource 'blah' do
          1.upto(10) do
            x nil
          end
          x nil
        end
      EOM
    end

    def match_indices(regex, str)
      result = []
      pos = 0
      while match = regex.match(str, pos)
        result << match.begin(0)
        pos = match.end(0) + 1
      end
      result
    end

    it "should output each deprecation warning only once, at the end of the run" do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
# Mimick what happens when you are on the console
formatters << :doc
log_level :warn
EOM

      ENV.delete("CHEF_TREAT_DEPRECATION_WARNINGS_AS_ERRORS")

      result = shell_out!("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'x::default'", :cwd => chef_dir)
      expect(result.error?).to be_falsey

      # Search to the end of the client run in the output
      run_complete = result.stdout.index("Running handlers complete")
      expect(run_complete).to be >= 0

      # Make sure there is exactly one result for each, and that it occurs *after* the complete message.
      expect(match_indices(/An attempt was made to change x from \[\] to nil by calling x\(nil\). In Chef 12, this does a get rather than a set. In Chef 13, this will change to set the value to nil./, result.stdout)).to match([ be > run_complete ])
    end
  end

  when_the_repository "has a cookbook with only an audit recipe" do

    before do
      file "config/client.rb", <<EOM
local_mode true
cookbook_path "#{path_to('cookbooks')}"
audit_mode :enabled
EOM
    end

    it "should exit with a zero code when there is not an audit failure" do
      file "cookbooks/audit_test/recipes/succeed.rb", <<-RECIPE
control_group "control group without top level control" do
  it "should succeed" do
    expect(2 - 2).to eq(0)
  end
end
      RECIPE

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'audit_test::succeed'", :cwd => chef_dir)
      expect(result.error?).to be_falsey
      expect(result.stdout).to include("Successfully executed all `control_group` blocks and contained examples")
    end

    it "should exit with a non-zero code when there is an audit failure" do
      file "cookbooks/audit_test/recipes/fail.rb", <<-RECIPE
control_group "control group without top level control" do
  it "should fail" do
    expect(2 - 2).to eq(1)
  end
end
      RECIPE

      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" -o 'audit_test::fail'", :cwd => chef_dir)
      expect(result.error?).to be_truthy
      expect(result.stdout).to include("Failure/Error: expect(2 - 2).to eq(1)")
    end
  end

  # Fails on appveyor, but works locally on windows and on windows hosts in Ci.
  context "when using recipe-url", :skip_appveyor do
    before(:all) do
      start_tiny_server
    end

    after(:all) do
      stop_tiny_server
    end

    let(:tmp_dir) { Dir.mktmpdir("recipe-url") }

    it "should complete with success when passed -z and --recipe-url" do
      file "config/client.rb", <<EOM
chef_repo_path "#{tmp_dir}"
EOM
      result = shell_out("#{chef_client} -c \"#{path_to('config/client.rb')}\" --recipe-url=http://localhost:9000/recipes.tgz -o 'x::default' -z", :cwd => tmp_dir)
      result.error!
    end

    it "should fail when passed --recipe-url and not passed -z" do
      result = shell_out("#{chef_client} --recipe-url=http://localhost:9000/recipes.tgz", :cwd => tmp_dir)
      expect(result.exitstatus).not_to eq(0)
    end
  end
end
