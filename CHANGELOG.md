# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-25

### Added

- The `noderings` provider: `vagrant up` orders the cheapest matching NodeRings
  marketplace offer (or the best rated, or an exact plan and region), waits for SSH, and
  runs provisioners. No box is needed; the operating system comes from `distro`.
- `vagrant halt`, `reload`, `ssh`, `provision`, `status` and `destroy`. Destroy also
  deletes the temporary SSH key.
- A per-machine SSH key, generated in `.vagrant/` and uploaded as a temporary NodeRings
  key, or existing NodeRings keys via `ssh_keys`.
- Synced folders over rsync.
- Optional firewall ruleset, tags, billing type and provider selection.
