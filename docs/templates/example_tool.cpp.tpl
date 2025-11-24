#include <iostream>
#include "cli.h"

// build-directive: unit-name(tools/example_tool)
// build-directive: depends-units(lib/cli)
// build-directive: link(cli.so)
// build-directive: out(tools/example_tool)

int main() {
    std::cout << "Tool example" << std::endl;
    lana::print_help();
    return 0;
}
