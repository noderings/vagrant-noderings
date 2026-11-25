# Security policy

## Reporting a vulnerability

Please do not open a public issue for security problems. Email **partners@noderings.com** with:

- a description of the issue and its impact
- steps to reproduce, or a proof of concept
- the plugin version (`vagrant plugin list`) and Vagrant version (`vagrant --version`)

We acknowledge reports within three working days and keep you updated until the issue is fixed. Credit is given in the release notes unless you ask us not to.

## Supported versions

Security fixes are made for the latest minor release.

## Handling credentials

The provider reads the NodeRings service account token from `provider.token` or the `NODERINGS_TOKEN` environment variable. Prefer the environment variable, so the token never lands in a `Vagrantfile` that gets committed, and give the service account the narrowest NodeRings role that covers what you create. The private key the provider generates for each machine is kept in `.vagrant/machines/<name>/noderings/state/` with mode 0600 and deleted on `vagrant destroy`; keep `.vagrant/` out of version control.
