module tests

import os
import rand

fn new_temp_dir(prefix string) string {
    id := rand.uuid_v4()
    path := os.join_path(os.temp_dir(), '${prefix}_${id}')
    os.mkdir_all(path) or { panic(err) }
    return path
}
