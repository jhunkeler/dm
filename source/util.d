module util;
import std.stdio;
import std.string;
import std.process;
import std.algorithm;
import std.file;
import std.path;
import std.conv : to;


enum byte MAXCOLS = 80;


void banner(const char ch, string s) {
    string ruler;
    byte i = 0;
    while (i < MAXCOLS) {
        ruler ~= ch;
        i++;
    }

    string result;
    string[] tmpstr = splitLines(wrap(s, MAXCOLS - 2, ch ~ " ", ch ~ "    "));
    foreach (idx, line; tmpstr) {
        if (idx < tmpstr.length - 1) {
            line ~= " \\";
        }
        result ~= line ~ "\n";
    }

    writeln(ruler);
    write(result);
    writeln(ruler);
}


static auto getenv(string[string] base=null, string preface=null) {
    const char delim = '=';
    char delim_line = '\n';
    string[string] env;
    string cmd = "env";

    version (linux) {
        cmd ~= " -0";
        delim_line = '\0';
    }

    version (Windows) {
        cmd = "set";
        delim_line = "\r\n";
    }

    // Execute a command before dumping the environment
    if (preface !is null) {
        cmd = preface ~ " && " ~ cmd;
    }

    auto env_sh = executeShell(cmd, env=base);
    if (env_sh.status) {
        throw new Exception("Unable to read shell environment:" ~ env_sh.output);
    }

    foreach (string line; split(env_sh.output, delim_line)) {
        if (line.empty) {
            continue;
        }
        auto data = split(line, delim);

        // Recombine extra '=' chars
        if (data.length > 2) {
           data[1] = join(data[1 .. $], delim);
        }
        env[data[0]] = data[1];
    }
    return env;
}


string safe_spec(string s) {
    return "'" ~ s ~ "'";
}


string safe_install(string[] specs) {
    string[] result;
    foreach (record; specs) {
        result ~= safe_spec(record);
    }
    return result.join(" ");
}


string safe_install(string specs) {
    string[] result;
    foreach (record; specs.split(" ")) {
        result ~= safe_spec(record);
    }
    return result.join(" ");
}


string pytest_xunit2(string filename) {
    string _data = readText(filename);
    string data;
    string result;
    bool inject = false;
    bool inject_wait = false;
    bool has_section = false;
    bool has_junit_family = false;
    string section;
    immutable string key = "junit_family";
    immutable string cfgitem = key ~ " = xunit2";

    if (filename.baseName == "setup.cfg") {
        section = "[tool:pytest]";
    } else if (filename.baseName == "pytest.ini") {
        section = "[pytest]";
    }

    foreach (line; splitLines(_data)) {
        string tmp = line.to!string;
        if (canFind(tmp, section)) {
            has_section = true;
        }
        if (canFind(tmp, key)) {
            has_junit_family = true;
        }
        data ~= tmp ~ "\n";
    }

    if (!has_section) {
        return data ~ format("\n%s\n%s\n", section, cfgitem);
    }

    foreach (rec; splitLines(data)) {
        if (!has_section) {
            break;
        } else if (rec.strip == section && !has_junit_family) {
            inject = true;
        } else if (has_junit_family) {
            inject_wait = true;
        } else if (inject_wait) {
            if (canFind(rec, key)) {
                rec = cfgitem ~ "\n";
                inject_wait = false;
            }
        } else if (inject) {
            result ~= cfgitem ~ "\n";
            inject = false;
        }

        result ~= rec ~ "\n";
    }

    return result;
}
