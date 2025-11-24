// build-directive: unit-name(lib/cli)
// build-directive: depends-units()
// build-directive: link()
// build-directive: out(lib/cli)
// build-directive: shared(true)
// build-directive: cflags(-fPIC)

#include <iostream>
#include "cli.h"

namespace lana {
    void print_help() {
        std::cout << "Lana CLI help" << std::endl;
    }
}
