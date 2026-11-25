# vagrant-noderings

[![CI](https://github.com/noderings/vagrant-noderings/actions/workflows/ci.yml/badge.svg)](https://github.com/noderings/vagrant-noderings/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/vagrant-noderings.svg)](https://rubygems.org/gems/vagrant-noderings)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

A [Vagrant](https://www.vagrantup.com) provider for [NodeRings](https://noderings.com). Run
your development and test machines on NodeRings virtual machines with the usual
`vagrant up`, `vagrant ssh` and `vagrant destroy`.

```ruby
Vagrant.configure("2") do |config|
  config.vm.provider :noderings do |provider|
    provider.plan    = "SC-GC-1C-1G-20"
    provider.country = "United States"
    provider.city    = "Ashburn"
    provider.distro  = "ubuntu_24_04"
  end

  config.vm.provision "shell", inline: "apt-get update && apt-get install -y nginx"
end
```

```shell
export NODERINGS_TOKEN=...      # a NodeRings service account token
vagrant up --provider=noderings
vagrant ssh
vagrant destroy
```

`vagrant up` orders the cheapest NodeRings offer for the plan in that city, waits until
SSH answers, syncs the project folder to `/vagrant` and runs the provisioners. No box is
needed: the operating system comes from `distro`.

## Requirements

* Vagrant 2.2 or later
* `rsync` on your workstation, for synced folders
* A NodeRings service account token. Create one in the NodeRings console under
  **Organization → Access Control → Service accounts**.
* A payment method or credit on the organization. Ordering a server is billed; hourly
  (usage) plans stop billing when `vagrant destroy` deletes the server.

## Installation

```shell
vagrant plugin install vagrant-noderings
```

## Commands

| Command | What happens on NodeRings |
| --- | --- |
| `vagrant up` | Orders the server, or starts it if it is stopped, then provisions it |
| `vagrant ssh` | Logs in as `root` with the machine's key |
| `vagrant provision` | Runs the provisioners again |
| `vagrant halt` | Stops the server; its disk and IP addresses are kept |
| `vagrant reload` | Stops and starts the server, then provisions if asked to |
| `vagrant status` | Shows `running`, `stopped` or `not created` |
| `vagrant destroy` | Deletes the server and its temporary SSH key |

## Configuration

Set these on the provider in your `Vagrantfile`:

| Option | Default | Description |
| --- | --- | --- |
| `token` | `NODERINGS_TOKEN` environment variable | API token. Prefer the environment variable to keep it out of the `Vagrantfile`. |
| `api_url` | `https://api.noderings.com` | API endpoint (`NODERINGS_API_URL`). |
| `organization_id` | none | Organization to act in, for tokens that can reach more than one (`NODERINGS_ORGANIZATION_ID`). |
| `plan` | none | Plan code to order, such as `SC-GC-1C-1G-20`. Required with `country` and `city`. |
| `country` | none | Country of the offer, such as `United States`. |
| `city` | none | City of the offer, such as `Ashburn`. |
| `billing_type` | `usage` | `usage` (hourly), `subscription` (monthly) or `free`. |
| `sort` | `price` | Order the cheapest matching offer, or the best rated with `rating`. |
| `provider_id` | none | Only consider offers from this provider. |
| `plan_id`, `region_id` | none | An exact plan and region, instead of `plan`, `country` and `city`. |
| `distro` | `ubuntu_24_04` | Operating system: `ubuntu_22_04`, `ubuntu_24_04`, `ubuntu_26_04`, `debian_12`, `debian_13`, `fedora_43`, `fedora_44`, `centos_9`, `centos_10`, `almalinux_9`, `almalinux_10`, `rocky_9` or `rocky_10`. |
| `hostname` | `vagrant-<machine>-<random>` | Hostname of the server (one DNS label). |
| `ssh_keys` | `[]` | Names or IDs of NodeRings SSH keys to install instead of a generated key. |
| `firewall_ruleset` | none | Name or ID of a firewall ruleset to attach. It must allow SSH from your workstation. |
| `tags` | `["vagrant"]` | Tags on the server. |
| `wait_timeout` | `900` | Seconds to wait for each operation. |

To see which plans are sold where, use the NodeRings console marketplace, or
`knife noderings plan list --country "United States" --city Ashburn` from
[knife-noderings](https://github.com/noderings/knife-noderings).

### SSH keys

By default the provider generates an RSA key for each machine in
`.vagrant/machines/<name>/noderings/`, uploads its public half to NodeRings as a
temporary key, logs in with it, and deletes both on `vagrant destroy`.

To use keys already stored in NodeRings, list them in `ssh_keys` and point Vagrant at
the matching private key:

```ruby
config.vm.provider :noderings do |provider, override|
  provider.ssh_keys = ["laptop"]
  override.ssh.private_key_path = "~/.ssh/id_ed25519"
end
```

### Synced folders

The project folder is synced to `/vagrant` with rsync when the machine comes up and on
`vagrant reload`. Run `vagrant rsync` to sync again, or `vagrant rsync-auto` to sync on
every change. NFS and SMB folders are not available on a remote server.

### Several machines

```ruby
Vagrant.configure("2") do |config|
  config.vm.provider :noderings do |provider|
    provider.plan    = "SC-GC-1C-1G-20"
    provider.country = "United States"
    provider.city    = "Ashburn"
  end

  config.vm.define "web" do |web|
    web.vm.provider(:noderings) { |p| p.distro = "ubuntu_24_04" }
  end

  config.vm.define "db" do |db|
    db.vm.provider(:noderings) { |p| p.distro = "debian_13" }
  end
end
```

`vagrant up --provider=noderings` orders both servers in parallel.

## Development

```shell
bundle install
bundle exec rake          # RuboCop and the unit tests
```

The unit tests run against an in-memory NodeRings API, so they need no token. To try a
change with the real Vagrant and the real API (this orders a billed server):

```shell
gem build vagrant-noderings.gemspec
vagrant plugin install ./vagrant-noderings-0.1.0.gem
NODERINGS_TOKEN=... vagrant up --provider=noderings
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright NodeRings. Licensed under the [Apache License, Version 2.0](LICENSE).
