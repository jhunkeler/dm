import std.stdio;
import std.array;
import std.format;
import std.file;
import std.typecons;
import std.path : buildPath, chainPath, absolutePath;
import conda;
import merge;

int main(string[] args) {
    import std.getopt;
    string env_name;
    string output_dir = "delivery";
    string installer_prefix = "miniconda";
    string installer_variant = "3";
    string installer_version = "4.5.12";
    bool run_tests = false;
    string test_program = "pytest";
    string test_args = "-v";       // arguments to pass to test runner
    string test_requires;   // pip requirements file
    string mergefile;
    string base_spec;
    string dumpfile_yaml;
    string dumpfile_explicit;
    string dumpfile_freeze;

    // disable buffering
    stdout.setvbuf(0, _IONBF);
    stderr.setvbuf(0, _IONBF);

    try {
        auto optargs = getopt(
            args,
            config.passThrough,
            config.required, "env-name|n", "name of delivery", &env_name,
            config.required, "dmfile|d", "delivery merge specification file", &mergefile,
            "output-dir|o", "store delivery-related results in dir", &output_dir,
            "install-prefix|p", "path to install miniconda", &installer_prefix,
            "install-variant", "miniconda Python variant", &installer_variant,
            "install-version|i", "version of miniconda installer", &installer_version,
            "run-tests|R", "scan merged packages and execute their tests", &run_tests,
            "test-program", "program that will execute tests", &test_program,
            "test-args", "arguments passed to test executor", &test_args,
            "test-requires", "path to pip requirements file", &test_requires,
            "base-spec", "conda explicit or yaml environment dump file", &base_spec
        );

        if (optargs.helpWanted) {
            defaultGetoptPrinter("Create reproducible pipeline deliveries",
                                 optargs.options);
            return 0;
        }
    } catch (GetOptException e) {
        writeln(e.msg);
        return 1;
    }

    installer_prefix = buildPath(installer_prefix).absolutePath;
    output_dir = buildPath(output_dir, env_name).absolutePath;
    mergefile = buildPath(mergefile).absolutePath;

    dumpfile_yaml = buildPath(output_dir, env_name ~ ".yml");
    dumpfile_explicit = buildPath(output_dir, env_name ~ ".txt");
    dumpfile_freeze = buildPath(output_dir, env_name ~ ".pip");

    if (!test_requires.empty) {
        test_requires = buildPath(test_requires).absolutePath;
    }

    if (!test_requires.exists) {
        writeln("--test-requires, file not found: '" ~ test_requires ~ "'");
        return 1;
    }

    if (installer_variant != "3") {
        writeln("Python 2.7 has reached end-of-life.");
        writeln("3.x variant will be used instead.");
        installer_variant = "3";
    }

    // Ingest the dump file via --base-spec or with a positional argument.
    if (base_spec.empty && args.length > 1) {
        base_spec = args[1];
        args.popBack();
    }

    // Make sure base_spec contains at least something
    if (base_spec.empty) {
        writeln("Missing base environment dump file (--base-spec)");
        return 1;
    }

    Conda conda = new Conda();
    conda.channels = [
        "http://ssb.stsci.edu/astroconda",
        "defaults",
        "http://ssb.stsci.edu/astroconda-dev"
    ];
    conda.install_prefix = installer_prefix;
    conda.installer_version = installer_version;
    conda.installer_variant = installer_variant;

    if (!conda.installer()) {
        writeln("Installation failed.");
        return 1;
    }

    conda.initialize();

    if (conda.env_exists(env_name)) {
        writefln("Environment '%s' already exists. Removing.", env_name);
        conda.run("env remove -n " ~ env_name);
    }

    if (!env_combine(conda, env_name, base_spec, mergefile)) {
        writeln("Delivery merge failed!");
        return 1;
    }

    if (!output_dir.exists) {
        writeln("Creating output directory: " ~ output_dir);
        output_dir.mkdirRecurse;
    }

    writeln("Creating YAML dump: " ~ dumpfile_yaml);
    conda.dump_env_yaml(dumpfile_yaml);
    writeln("Creating explicit dump: " ~ dumpfile_explicit);
    conda.dump_env_explicit(dumpfile_explicit);
    writeln("Creating pip-freeze dump: " ~ dumpfile_freeze);
    conda.dump_env_freeze(dumpfile_freeze);

    if (run_tests) {
        int failures = 0;
        string testdir = buildPath(output_dir, "testdir");
        test_runner_t runner = test_runner_t(test_program, test_args, test_requires);
        testable_t[] pkgs = testable_packages(conda, mergefile);

        foreach (pkg; pkgs) {
            failures += integration_test(conda, testdir, runner, pkg);
        }

        if (failures) {
            writefln("%d of %d integration tests failed!", failures, pkgs.length);
        } else {
            writefln("All integration tests passed!");
        }
    }

    writefln("Done!");
    return 0;
}
