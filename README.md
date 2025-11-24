# Lana - V C++ Build System

A simple, fast C++ build tool designed for modern C++ projects. Lana compiles itself with V and targets portable C++ workflows without relying on heavyweight generators.

## Documentation

- 📚 **Canonical guide:** [`docs/guide.md`](docs/guide.md) now hosts the full documentation (installation, configuration, directives, troubleshooting).
- 🧩 **Reusable snippets:** Shared markdown/JSON data lives under [`docs/snippets`](docs/snippets) and [`docs/commands.json`](docs/commands.json). The CLI help output and initializer templates consume these files directly.

## Quick Start

See [`docs/snippets/quickstart.md`](docs/snippets/quickstart.md) for the exact commands surfaced by `lana init`, the README template, and `lana --help`.

## Project Structure

[`docs/snippets/project_structure.md`](docs/snippets/project_structure.md) is the single source for structure diagrams used across the README, guide, and generated projects.

## Commands & Options

The CLI help text is generated from [`docs/commands.json`](docs/commands.json). Update that file to add or modify commands/options once, and every consumer (help output, initializer docs, website) stays in sync.

## Contributing

- Fork the repository, create a feature branch, hack away, and open a PR.
- Please keep user-facing documentation changes inside `docs/` whenever possible—other surfaces will pull from there automatically.

## License

MIT License - see [LICENSE](LICENSE) for details.
