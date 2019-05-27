module ini;

import std.stdio;
import std.file;
import std.array;


struct Section_t {
    string name;
    string[string][] pairs;
}

class ConfigParser {
    File file;
    string[string][] pairs;
    int[] section_pos;

    this(File file) {
        this.file = file;
    }

    auto _parse() {
        foreach (line; this.file.byLine) {
            writeln("-> " ~ line);
        }
    }
}
