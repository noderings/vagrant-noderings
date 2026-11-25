# Contributing

Thanks for helping improve vagrant-noderings.

1. Open an issue describing the bug or change before large pull requests.
2. Fork the repository and create a topic branch.
3. Run `bundle exec rake`. RuboCop and the unit tests must pass. The unit tests run
   against the in-memory API in `spec/support/fake_noderings.rb`, so they need no token.
4. Add tests for new behaviour in `spec/unit`.
5. For changes that reach the API, try them with the real Vagrant: build the gem, run
   `vagrant plugin install ./vagrant-noderings-*.gem`, export `NODERINGS_TOKEN` and run
   `vagrant up --provider=noderings` and `vagrant destroy`. This orders a billed server.
6. Use [Conventional Commits](https://www.conventionalcommits.org/) and sign off each
   commit (`git commit -s`) to certify the
   [Developer Certificate of Origin](https://developercertificate.org/).

The files in `lib/vagrant-noderings/api/` are the NodeRings API client shared with the
NodeRings Chef, knife, Test Kitchen and Puppet projects. Changes to them are made in the
shared source and copied here, so please describe API client fixes in an issue rather than
editing those files directly.

Please report security problems privately as described in [SECURITY.md](SECURITY.md).
