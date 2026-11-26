# frozen_string_literal: true

require "open3"

describe "vagrant-noderings actions" do
  let(:action) { VagrantPlugins::Noderings::Action }
  let(:machine) { FakeMachine.new(provider_config, @data_dir) }
  let(:env) { { machine: machine, ui: ui } }

  def vm
    @fake.vms.values.first
  end

  def up
    run_action(action::CreateServer, env)
  end

  describe "the plugin" do
    it "registers a provider that needs no box" do
      opts = VagrantPlugins::Noderings::Plugin.components.providers[:noderings].last
      expect(opts).to include(box_optional: true, parallel: true)
    end
  end

  describe "CreateServer" do
    it "orders the cheapest offer with a generated key and remembers the server" do
      up
      body = @fake.created_vm_bodies.last
      key = @fake.ssh_keys.values.first
      expect(body).to include("planId" => FakeNoderings::PLAN_ID, "distro" => "DISTRO_UBUNTU_24_04",
                              "tags" => ["vagrant"], "sshKeyIds" => [key["id"]])
      expect(body["hostname"]).to match(/\Avagrant-default-[a-z0-9]{6}\z/)
      expect(key["publicKey"]).to start_with("ssh-rsa ")
      expect(machine.id).to eq vm["id"]
      expect(File.stat(machine.data_dir.join("state/id_rsa")).mode & 0o777).to eq 0o600
      expect(@fake.calls.last[4]["User-Agent"]).to start_with("vagrant-noderings/")
    end

    it "uses named NodeRings keys and attaches a firewall" do
      @fake.ssh_keys["k1"] = { "id" => "k1", "name" => "laptop", "publicKey" => "ssh-ed25519 AAAA" }
      @fake.call("POST", "https://api.noderings.com/v1/firewall/rulesets", {}, '{"ruleset":{"name":"ssh"}}', 1)
      env[:machine] = FakeMachine.new(provider_config(ssh_keys: ["laptop"], firewall_ruleset: "ssh", hostname: "dev-1"), @data_dir)
      run_action(action::CreateServer, env)
      expect(@fake.created_vm_bodies.last).to include("hostname" => "dev-1", "sshKeyIds" => ["k1"])
      expect(vm["firewallRulesetId"]).to eq @fake.rulesets.keys.first
      expect(@fake.ssh_keys.length).to eq 1
    end

    context "with hosting_provider" do
      def up_from(provider)
        env[:machine] = FakeMachine.new(provider_config(hosting_provider: provider), @data_dir)
        run_action(action::CreateServer, env)
      end

      [FakeNoderings::ACME_ID, "acme-hosting", "Acme Hosting", "  acme HOSTING "].each do |provider|
        it "orders from the provider given as #{provider.inspect}" do
          up_from(provider)
          expect(@fake.created_vm_bodies.last).to include("planId" => FakeNoderings::ACME_PLAN_ID,
                                                          "regionId" => FakeNoderings::ACME_REGION_ID)
        end
      end

      it "orders the cheapest offer without one" do
        up
        expect(@fake.created_vm_bodies.last["planId"]).to eq FakeNoderings::PLAN_ID
      end

      it "fails for an unknown provider" do
        expect { up_from("Nobody Hosting") }
          .to raise_error(VagrantPlugins::Noderings::Errors::APIError, /from provider Nobody Hosting/)
        expect(@fake.created_vm_bodies).to be_empty
      end

      it "refuses a provider name two providers share" do
        @fake.extra_providers << FakeNoderings::ACME_OFFER.merge("organizationId" => "66666666-6666-6666-6666-666666666666")
        expect { up_from("acme hosting") }
          .to raise_error(VagrantPlugins::Noderings::Errors::APIError, /more than one provider is named acme hosting/)
        expect(@fake.created_vm_bodies).to be_empty
      end
    end

    it "explains an offer that does not exist" do
      env[:machine] = FakeMachine.new(provider_config(city: "Nowhere"), @data_dir)
      expect { run_action(action::CreateServer, env) }
        .to raise_error(VagrantPlugins::Noderings::Errors::APIError, /No offer for plan code SC-GC-1C-1G-20 in Nowhere/)
    end
  end

  describe "ReadState and ReadSSHInfo" do
    it "maps the power state and reports how to log in" do
      expect(run_action(action::ReadState, env)[:machine_state_id]).to eq :not_created
      up
      expect(run_action(action::ReadState, env)[:machine_state_id]).to eq :running
      vm["operationStatus"] = "OPERATION_STATUS_CREATED"
      expect(run_action(action::ReadState, env)[:machine_state_id]).to eq :running
      vm["operationStatus"] = "OPERATION_STATUS_STOPPED"
      expect(run_action(action::ReadState, env)[:machine_state_id]).to eq :stopped
      info = run_action(action::ReadSSHInfo, env)[:machine_ssh_info]
      expect(info).to eq(host: "192.0.2.50", port: 22, username: "root",
                         private_key_path: [machine.data_dir.join("state/id_rsa").to_s])
    end

    it "forgets a server deleted outside Vagrant" do
      up
      @fake.vms.clear
      expect(run_action(action::ReadState, env)[:machine_state_id]).to eq :not_created
      expect(machine.id).to be_nil
    end
  end

  describe "StopServer, StartServer and DestroyServer" do
    it "stops, starts and deletes the server with its key" do
      up
      run_action(action::StopServer, env)
      expect(vm["operationStatus"]).to eq "OPERATION_STATUS_STOPPED"
      machine.state_id = :stopped
      run_action(action::StartServer, env)
      expect(vm["operationStatus"]).to eq "OPERATION_STATUS_STARTED"
      run_action(action::DestroyServer, env)
      expect(@fake.vms).to be_empty
      expect(@fake.ssh_keys).to be_empty
      expect(machine.id).to be_nil
      expect(machine.data_dir.join("state")).not_to exist
    end

    it "keeps the hostname and key across runs" do
      up
      session = VagrantPlugins::Noderings::Session.new(machine)
      name = session.hostname
      expect(VagrantPlugins::Noderings::Session.new(machine).hostname).to eq name
      expect(session.ssh_key_ids).to eq [@fake.ssh_keys.keys.first]
      expect(@fake.ssh_keys.length).to eq 1
    end
  end

  describe "the public key" do
    it "is a valid OpenSSH key for the generated private key" do
      session = VagrantPlugins::Noderings::Session.new(machine)
      session.ssh_key_ids
      pub = File.join(@data_dir, "key.pub")
      File.write(pub, session.public_key)
      fingerprint, status = Open3.capture2e("ssh-keygen", "-l", "-f", pub)
      expect(status.success?).to be true
      derived = `ssh-keygen -y -f #{machine.data_dir.join("state/id_rsa")} 2>&1`.split[0, 2]
      expect(session.public_key.split[0, 2]).to eq derived
      expect(fingerprint).to include("RSA")
    end
  end

  describe "the action stacks" do
    it "builds every command Vagrant asks for" do
      %w[up halt destroy reload provision ssh ssh_run read_ssh_info read_state].each do |name|
        expect(action.public_send("action_#{name}")).to be_a(Vagrant::Action::Builder)
      end
    end
  end
end
