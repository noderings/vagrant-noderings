# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.2.1](https://github.com/noderings/vagrant-noderings/compare/v0.2.0...v0.2.1) (2026-11-27)


### Documentation

* link the official Go SDK in the README ([#7](https://github.com/noderings/vagrant-noderings/issues/7)) ([9965803](https://github.com/noderings/vagrant-noderings/commit/9965803dbb934c26958881a2d8c90471a871f83b))

## [0.2.0](https://github.com/noderings/vagrant-noderings/compare/v0.1.0...v0.2.0) (2026-11-26)


### Features

* choose the provider of Vagrant servers ([#4](https://github.com/noderings/vagrant-noderings/issues/4)) ([3a583f4](https://github.com/noderings/vagrant-noderings/commit/3a583f4746afa5ec60e2c20940b8813d1fa444dd))

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
