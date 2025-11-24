# {{project_name}}

A C++ project built with the [Lana build system](https://github.com/lana-build/lana/blob/main/docs/guide.md).

{{quickstart}}

{{project_structure}}

## Build Directives
Lana reads build instructions directly from your source files. Add `// build-directive:` comments near the top of a translation unit to specify unit names, dependencies, and custom flags. See `docs/guide.md#build-directives` for the full catalog.

## Configuration
Global build settings live in `config.ini`. Command-line flags override config values, which override built-in defaults. Consult `docs/guide.md#configuration` for details and advanced examples.
