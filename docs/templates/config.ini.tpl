# {{project_name}} lana build configuration

[global]
project_name = {{project_name}}
src_dir = src
build_dir = build
bin_dir = bin
compiler = g++
debug = true
optimize = false
verbose = false
parallel_compilation = true
include_dirs = include
lib_search_paths =
cflags = -Wall -Wextra
ldflags =

dependencies_dir = dependencies

[shared_libs]
# legacy/manual entries go here when you don't want build directives

[tools]
# legacy/manual entries go here when you don't want build directives
