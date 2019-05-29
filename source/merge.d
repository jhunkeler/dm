module merge;
import std.algorithm;
import std.array;
import std.conv : to;
import std.file;
import std.format;
import std.typecons;
import std.path;
import std.range;
import std.regex;
import std.stdio;
import std.string;
import conda;
import util;
import dyaml : dumper, Loader, Node;


auto RE_COMMENT = regex(r"[;#]");
auto RE_DMFILE = regex(r"^(?P<name>[A-z\-_.]+)(?:[=<>]+)?(?P<version>[A-z0-9. ]+)?");
auto RE_DMFILE_INVALID_VERSION = regex(r"[ !@#$%^&\*\(\)\-_]+");
auto RE_DELIVERY_NAME = regex(r"(?P<name>.*)[-_](?P<version>.*)[-_]py(?P<python_version>\d+)[-_.](?P<iteration>\d+)[-_.](?P<ext>.*)");


struct test_runner_t {
    string program;
    string args;
    string requires;
}

struct testable_t {
    string repo;
    string head;
}


string[string][] dmfile(string filename) {
    string[string][] results;
    foreach (line; File(filename).byLine()) {
        string[string] pkg;
        line = strip(line);
        auto has_comment = matchFirst(line, RE_COMMENT);
        if (!has_comment.empty) { line = strip(has_comment.pre()); }
        if (line.empty) { continue; }

        auto record = matchFirst(line, RE_DMFILE);
        pkg["name"] = record["name"].dup;
        pkg["version"] = record["version"].dup;
        pkg["fullspec"] = record.hit.dup;
        results ~= pkg;
    }
    return results;
}


bool env_combine(ref Conda conda, string name, string specfile, string mergefile) {
    if (indexOf(specfile, "://", 0) < 0 && !specfile.exists) {
        throw new Exception(specfile ~ " does not exist");
    } else if (!mergefile.exists) {
        throw new Exception(mergefile ~ " does not exist");
    }

    int retval = 0;
    string[] specs;
    string opmode = specfile.endsWith(".yml") ? "env " : "";

    if(conda.run(opmode ~ "create -n " ~ name ~ " --file " ~ specfile)) {
        return false;
    }

    conda.activate(name);

    writeln("Delivery merge specification:");
    foreach (record; dmfile(mergefile)) {
        writefln("-> package: %-15s :: version: %s",
                 record["name"],
                 !record["version"].empty ? record["version"] : "any");

        specs ~= record["fullspec"];
    }

    if (conda.run("install " ~ conda.multiarg("-c", conda.channels)
                  ~ " " ~ safe_install(specs))) {
        return false;
    }
    return true;
}


testable_t[] testable_packages(ref Conda conda, string mergefile) {
    testable_t[] results;
    foreach (record; dmfile(mergefile)) {
        Node meta;
        string pkg_d;
        string pkg;
        string repository;
        string head;
        string[] logdata;
        string[] found_packages = conda.scan_packages(record["name"]
                                                ~ "-"
                                                ~ record["version"]
                                                ~ "*");

        if (found_packages.empty) {
            writefln("Unable to locate package: %s", record["fullspec"]);
            continue;
        } else if (found_packages.length > 1) {
            pkg = found_packages[$-1];
        } else {
            pkg = found_packages[0];
        }
        pkg_d = chainPath(conda.install_prefix,
                          "pkgs",
                          pkg).array;

        string info_d = chainPath(pkg_d, "info").array;
        string recipe_d = chainPath(info_d, "recipe").array;
        string git_log = chainPath(info_d, "git").array;
        string recipe = chainPath(recipe_d, "meta.yaml").array;

        if (!git_log.exists) {
            continue;
        }

        foreach (line; File(git_log).byLine) {
            logdata ~= line.dup;
        }

        if (logdata.empty) {
            continue;
        }

        head = logdata[1].split()[1];
        meta = Loader.fromFile(recipe).load();
        try {
            repository = meta["source"]["git_url"].as!string;
        } catch (Exception e) {
            writeln(e.msg);
            repository = "";
        }

        results ~= testable_t(repository, head);
    }
    return results;
}

auto integration_test(ref Conda conda, string outdir, test_runner_t runner, testable_t pkg) {
    import core.stdc.stdlib : exit;
    import std.ascii : letters;
    import std.conv : to;
    import std.random : randomSample;
    import std.utf : byCodeUnit;

    auto id = letters.byCodeUnit.randomSample(6).to!string;
    string basetemp = tempDir.buildPath("dm_testable_" ~ id);
    basetemp.mkdir;
    scope(exit) basetemp.rmdirRecurse;

    string cwd = getcwd().absolutePath;
    scope (exit) cwd.chdir;
    string repo_root = buildPath(outdir, pkg.repo.baseName)
                                 .replace(".git", "");
    outdir.mkdirRecurse;

    if (!repo_root.exists) {
        if (conda.sh("git clone --recursive " ~ pkg.repo ~ " " ~ repo_root)) {
            return 1;
        }
    }

    repo_root.chdir;

    if (conda.sh("git checkout " ~ pkg.head)) {
        return 1;
    }

    foreach (string found; conda.scan_packages(repo_root.baseName ~ "*").sort.uniq) {
        string[] tmp = found.split("-");
        found = tmp[0];
        // Does not need to succeed for all matches
        conda.run("remove " ~ found);
    }

    if (runner.requires) {
        if (conda.sh("python -m pip install -r " ~ runner.requires)) {
            return 1;
        }
    }

    if (conda.sh("python -m pip install -e .[test]")) {
        return 1;
    }

    if (conda.sh("python setup.py egg_info")) {
        return 1;
    }

    if (runner.program == "pytest" || runner.program == "py.test") {
        string testconf = "pytest.ini";
        if (!testconf.exists) {
            testconf = "setup.cfg";
        }
        pytest_xunit2(testconf);
    }

    if (conda.sh(runner.program ~ " " ~ runner.args ~ " --basetemp=" ~ basetemp)) {
        return 1;
    }
    return 0;
}
