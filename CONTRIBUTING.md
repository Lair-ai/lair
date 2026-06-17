# Contributing

Thank you for your interest in contributing to Lair.

Contributions are what make the open-source community such an amazing place. **Any contribution you make is greatly appreciated.**

### Ways to Contribute

- **Report bugs** — open an [issue](https://github.com/Lair-ai/lair/issues) with the `bug` label
- **Request features** — open an [issue](https://github.com/Lair-ai/lair/issues) with the `enhancement` label
- **Improve documentation** — fix typos, clarify steps, translate content
- **Submit code** — fix bugs or implement new features

### Development Workflow

1. **Fork** the repository
2. **Create** a feature branch from `dev`
 ```bash
 git checkout -b feature/my-amazing-feature
 ```
3. **Set up** your development environment (Ubuntu 24.04 LTS or DGX OS required)
4. **Make** your changes and write or update tests where applicable
5. **Test** your changes on a clean Ubuntu 24.04 system — ensure nothing is broken
6. **Commit** your changes using conventional commits
 ```bash
 git commit -m "feat: add support for XYZ"
 ```
7. **Push** to your branch
 ```bash
 git push origin feature/my-amazing-feature
 ```
8. **Open** a Pull Request against the `dev` branch

### Commit Message Convention

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

| Prefix | Use for |
|--------|---------|
| `feat:` | A new feature |
| `fix:` | A bug fix |
| `docs:` | Documentation only changes |
| `chore:` | Maintenance tasks (CI, dependencies, etc.) |
| `refactor:` | Code refactoring without behaviour change |
| `test:` | Adding or fixing tests |

### Pull Request Guidelines

- Keep PRs focused — one feature or fix per PR
- Include a clear description of what changes you made and why
- Reference any related issues (e.g. `Closes #42`)
- Make sure all scripts are tested on a clean Ubuntu 24.04 environment
- Update the documentation if your change affects user-facing behaviour

For larger features or architectural changes, please **open an issue first** to discuss the approach before investing time in implementation.
