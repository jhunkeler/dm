module util;
import std.ascii;
import std.array;
import std.stdio;
import std.string;
import std.process;
import std.algorithm;
import std.file;
import std.path;
import std.conv : to;


/// MAXCOLS refers to terminal width
enum byte MAXCOLS = 80;

/**
  Print a wordwrapped string encapsulated by `ch`

Params:
    ch = ASCII character to create border
    s = string to print
 */
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


/**
  Dump the parent shell runtime environment and convert it into an associative
  array

Params:
    base = use an existing mapping as the base environment
    preface = command to execute prior to dumping the environment

Returns:
    an associative array containing the runtime environment

Example:
---
import std.stdio;
import util;

void main()
{
    string exfile = "example.sh";
    File(exfile, "w+").write("export EXAMPLE_FILE=parsed\n");
    scope(exit) exfile.remove;

    auto myenv = getenv();
    myenv["EXAMPLE"] = "works";

    auto myenv2 = getenv(myenv);
    writeln(myenv2["EXAMPLE"]);

    auto myenv3 = getenv(myenv2, "source example.sh");
    writeln(myenv3["EXAMPLE"]);
    writeln(myenv3["EXAMPLE_FILE"]);
}
---
 */
string[string] getenv(string[string] base=null, string preface=null) {
    const char delim = '=';
    char delim_line = '\n';
    string[string] env;
    string cmd = "env";

    /// Under GNU we have the option to use nul-terminated strings, which means
    /// we can safely parse awful pairs generated by `env-modules`
    version (linux) {
        cmd ~= " -0";
        delim_line = '\0';
    }

    /// Untested
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


/**
  Produce a single-quoted string

Params:
    s = string to quote

Returns:
    single-quoted string

Example:
---
import std.stdio;
import util;

void main()
{
    writeln(safe_spec("single-quoted"));
    // 'single-quoted'
}
---
 */
string safe_spec(string s) {
    return "'" ~ s ~ "'";
}


/**
  Produces conda/pip compatible installation arguments

Params:
    specs = array of string arguments

Returns:
    string of single-quoted arguments

Example:
---
import std.stdio;
import util;

void main()
{
    string[] arguments = ["a", "b", "c"];
    writeln(safe_install(arguments));
    // 'a' 'b' 'c'
}
---
 */
string safe_install(string[] specs) {
    string[] result;
    foreach (record; specs) {
        result ~= safe_spec(record);
    }
    return result.join(" ");
}


/**
  Produces `conda`/`pip` compatible installation arguments by splitting on white
  space

  Params:
      specs = a string containing arguments

  Returns:
      string of single quoted arguments

  Example:
  ---
  import std.stdio;
  import util;

  void main()
  {
      string arguments = "a b c";
      writeln(safe_install(arguments));
      // 'a' 'b' 'c'
  }
  ---
 */
string safe_install(string specs) {
    string[] result;
    foreach (record; specs.split(" ")) {
        result ~= safe_spec(record);
    }
    return result.join(" ");
}


/**
  pytest emits invalid junit, so this rewrites the local configuration
  file (i.e. `setup.cfg`, `pytest.ini`, etc) to include the proper
  `junit_family` settings.

Params:
    filename = path to configuration file

Returns:
    new configuration file contents as string
 */
string pytest_xunit2(string filename) {
    // Generate the requested file if need be
    if (!filename.exists) {
        auto dummy = File(filename, "w+");
        dummy.write("");
        dummy.flush();
        dummy.close();
    }

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

    // figure out when/where we should write our revisions to the config
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


/**
  Find all occurences of character in a string

Params:
    s = string to read
    ch = character to find

Returns:
    array of offsets
  */
ulong[] indexOfAll(string s, char ch) {
    ulong[] result;
    for (ulong i = 0; i < s.length; i++) {
        if (s[i] == ch) {
            result ~= i;
        }
    }
    return result;
}


/// Unused
string expander(string[string] aa, string name, char delim = '$') {
    string s = aa[name].dup;
    ulong[] needles = indexOfAll(s, delim);
    string[string] found;

    foreach (needle; needles) {
        string tmp = "";
        for (ulong i = needle; i < s.length; i++) {
            if (s[i] == delim) continue;
            else if (s[i] == '{' || s[i] == '}') continue;
            else if (!s[i].isAlphaNum && s[i] != '_' ) break;
            tmp ~= s[i];
        }
        writeln(tmp);
        found[tmp] = aa.get(tmp, "");
    }

    foreach (pair; found.byPair) {
        s = s.replace(delim ~ pair.key, pair.value)
             .replace(format("%c{%s}", delim, pair.key), pair.value);
    }

    return s;
}



/**
  Perform variable interpolation on a string given a named environment

Params:
    aa = assoc. array to use (i.e. runtime environment)
    str = string to scan for variables
    delim = character to trigger parsing variable

Returns:
    string with variables replaced

Note:
    When a variable cannot be mapped the variable text in the string is not
    modified.

Example:
---
import std.stdio;
import util;

void main()
{
    string[string] aa = ["my_var": "example"];
    string my_str = "This is the ${my_var}.";
    writeln(interpolate(aa, my_str));
}
---
  */
string interpolate(string[string]aa, string str, char delim = '$') {
    import std.ascii;
    string s = str.dup;
    ulong[] needles = indexOfAll(s, delim);
    string[] found;

    // scan any indicies we've found
    foreach (needle; needles) {
        string tmp = "";
        // trigger variable parsing on delimiter
        for (ulong i = needle; i < s.length; i++) {
            if (s[i] == delim) continue;
            else if (s[i] == '{' || s[i] == '}')    // ${} also supported
                continue;
            else if (!s[i].isAlphaNum && s[i] != '_') // unusable, die
                break;
            tmp ~= s[i];
        }
        found ~= tmp;
    }

    // rewrite string with substitutions
    foreach (match; found) {
        foreach (pair; aa.byPair) {
            if (pair.key != match)
                continue;
            s = s.replace(delim ~ pair.key, pair.value)
                 .replace(format("%c{%s}", delim, pair.key), pair.value);
        }
    }

    return s;
}


/**
  Produce a short/compact version

Params:
    vrs = version string

Returns:
    shortened version string

Example:
---
import std.stdio;
import util;

void main()
{
    writeln(short_version("3.6.8"));
    // 36
    writeln(short_version("2.7.66"));
    // 27
}
---
  */
string short_version(string vrs) {
    string tmp = vrs.dup;
    tmp = tmp.replace(".", "");
    if (tmp.length > 2) {
        tmp = tmp[0 .. 2];
    }
    return tmp;
}
