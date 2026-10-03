# Contributing to FlipSwitch

First off, thank you for considering contributing to FlipSwitch! 🎉

## How Can I Contribute?

### Reporting Bugs

- **Check existing issues** to avoid duplicates
- Use the GitHub issue template
- Include steps to reproduce, expected behavior, and actual behavior
- Include your Salesforce API version and org edition if relevant

### Suggesting Features

- Open a GitHub issue with the `enhancement` label
- Describe the use case and why it would benefit others

### Pull Requests

1. **Fork the repo** and create your branch from `main`
2. **Set up your environment:**

   ```bash
   # Install npm dependencies
   npm ci

   # Authenticate your DevHub (if creating scratch orgs)
   sf org login web --alias devhub --set-default-dev-hub

   # Create a scratch org
   npm run scratch:create

   # Deploy the source
   npm run scratch:deploy:core

   # Assign permission sets
   npm run permset:assign:all
   ```

3. **Make your changes** in the `flipswitch/core/` directory
4. **Run tests:**

   ```bash
   # LWC Jest tests
   npm run test:lwc

   # Apex tests (requires a scratch org)
   npm run test:apex

   # Lint + format check
   npm run lint
   npm run prettier:verify
   ```

5. **Submit your PR** against `main`

### Code Style

- **Apex**: Follow Salesforce best practices, use `@TestSetup` for test data
- **LWC**: Follow `@salesforce/eslint-config-lwc/recommended`
- **Formatting**: Run `npm run prettier` before committing

## Development Setup

FlipSwitch is structured as a multi-directory Salesforce project:

```text
flipswitch/
├── core/          ← The installable unlocked package (make changes here)
├── extra-tests/   ← Additional integration tests (not packaged)
└── dev/           ← Local development metadata (not packaged)
```

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
