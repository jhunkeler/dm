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
import session;
import dyaml : dumper, Loader, Node;


auto RE_COMMENT = regex(r"[;#]");
auto RE_DMFILE = regex(r"^(?P<name>[A-z0-9\-_.]+)(?:[=<>]+)?(?P<version>[A-z0-9. ]+)?");
auto RE_DMFILE_INVALID_VERSION = regex(r"[ !@#$%^&\*\(\)\-_]+");
auto RE_DELIVERY_NAME = regex(r"(?P<name>.*)[-_](?P<version>.*)[-_]py(?P<python_version>\d+)[-_.](?P<iteration>\d+)[-_.](?P<ext>.*)");


struct test_runner_t {
    string program;
    string args;
    string[] requires;
}

struct testable_t {
    string repo;
    string head;
}


string[string][] dmfile(string[] packages) {
    string[string][] results;
    foreach (line; packages) {
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


bool env_combine(ref Session_t session, ref Conda conda) {
    if (indexOf(session.base_spec, "://", 0) < 0 && !session.base_spec.exists) {
        throw new Exception(session.base_spec ~ " does not exist");
    }

    int retval = 0;
    string[] specs;
    string opmode = session.base_spec.endsWith(".yml") ? "env " : "";

    if(conda.run(opmode ~ "create -n " ~ session.delivery
                 ~ " --file " ~ session.base_spec)) {
        return false;
    }

    //conda.activate(session.delivery);

    writeln("Delivery merge specification:");
    foreach (record; dmfile(session.conda_requirements)) {
        writefln("-> package: %-15s :: version: %s",
                 record["name"],
                 !record["version"].empty ? record["version"] : "any");

        specs ~= record["fullspec"];
    }

    if (conda.run("install -n " ~ session.delivery ~ " " ~ conda.multiarg("-c", conda.channels)
                  ~ " " ~ safe_install(specs))) {
        return false;
    }
    return true;
}


testable_t[] testable_packages(ref Conda conda, string[] inputs, string[] orgs=[]) {
    testable_t[] results;
    foreach (record; dmfile(inputs)) {
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

        bool[] skips;
        foreach (git_org; orgs) {
            if (!canFind(repository, git_org)) {
                skips ~= true;
            }
        }

        if (any(skips)) {
            writefln("Will not test package: %s", repository);
            continue;
        }
        results ~= testable_t(repository, head);
    }
    return results;
}


int integration_test(ref Session_t session,
                      ref Conda conda,
                      string outdir,
                      testable_t pkg) {
    import core.stdc.stdlib : exit;
    import std.ascii : letters;
    import std.conv : to;
    import std.random : randomSample;
    import std.utf : byCodeUnit;

    TestExtended_t te;
    auto id = letters.byCodeUnit.randomSample(6).to!string;
    string basetemp = tempDir.buildPath("dm_testable_" ~ id);
    basetemp.mkdir;
    scope(exit) basetemp.rmdirRecurse;

    string cwd = getcwd().absolutePath;
    scope (exit) cwd.chdir;
    string repo_root = buildPath(outdir, pkg.repo.baseName)
                                 .replace(".git", "");
    outdir.mkdirRecurse;

    if (repo_root.exists) {
        repo_root.rmdirRecurse;
    }

    if (conda.sh("git clone --recursive " ~ pkg.repo ~ " " ~ repo_root)) {
        return 1;
    }

    repo_root.chdir;

    if (conda.sh("git checkout " ~ pkg.head)) {
        return 1;
    }

    foreach (string found; conda.scan_packages(repo_root.baseName ~ "*").sort.uniq) {
        string[] tmp = found.split("-");
        found = tmp[0];
        // Does not need to succeed for all matches
        if (conda.run("remove --force " ~ found)) {
            conda.sh("python -m pip uninstall -y " ~ repo_root.baseName.replace("-", "_"));
        }
    }

    if (!session.test_conda_requirements.empty) {
        if (conda.sh("conda install "
                     ~ safe_install(session.test_conda_requirements))) {
            return 1;
        }
    }

    // Retrieve extended test data for this package
    foreach (TestExtended_t t; session.test_extended) {
        if (repo_root.baseName == t.name) {
            te = t;
            break;
        }
    }

    // Inject extended runtime environment early.
    // a pip-installed package might need something.
    foreach (string k, string v; te.runtime) {
        te.runtime[k] = interpolate(conda.env, v).dup;
        conda.env[k] = te.runtime[k];
    }

    if (!session.test_pip_requirements.empty) {
        if (conda.sh("python -m pip install "
                     ~ conda.multiarg("-i", session.pip_index) ~ " "
                     ~ safe_install(session.test_pip_requirements))) {
            return 1;
        }
    }

    if (conda.sh("python -m pip install "
                 ~ conda.multiarg("-i", session.pip_index) ~ " -e .[test]")) {
        return 1;
    }

    if (conda.sh("python setup.py egg_info")) {
        return 1;
    }

    if (session.test_program == "pytest" || session.test_program == "py.test") {
        string data;
        string pytest_cfg= "pytest.ini";
        if (!pytest_cfg.exists) {
            pytest_cfg = "setup.cfg";
        }
        data = pytest_xunit2(pytest_cfg);
        File(pytest_cfg, "w+").write(data);
    }

    // Execute extended commands
    foreach (string cmd; te.commands) {
        conda.sh(interpolate(conda.env, cmd));
    }

    // Run tests
    if (conda.sh(session.test_program ~ " "
                 ~ session.test_args ~ " "
                 ~ te.test_args ~ " "
                 ~ " --basetemp=" ~ basetemp)) {
        return 1;
    }
    return 0;
}
