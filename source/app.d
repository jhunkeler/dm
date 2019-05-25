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

    if (!test_requires.empty) {
        test_requires = buildPath(test_requires).absolutePath;
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

    conda.dump_env_yaml(buildPath(output_dir, env_name ~ ".yml"));
    conda.dump_env_explicit(buildPath(output_dir, env_name ~ ".txt"));

    if (run_tests) {
        string testdir = buildPath(output_dir, "testdir");
        test_runner_t runner = test_runner_t(test_program, test_args, test_requires);
        testable_t[] testable = testable_packages(conda, mergefile);
        foreach (t; testable) {
            integration_test(conda, testdir, runner, t);
        }
    }

    writeln("Done!");
    return 0;
}
