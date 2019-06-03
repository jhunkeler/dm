import std.getopt;
import std.stdio;
import std.array;
import std.format;
import std.file;
import std.typecons;
import std.path : buildPath, chainPath, absolutePath;
import std.range : enumerate;
import conda;
import merge;
import session;
import util;


int main(string[] args) {
    string output_dir = "delivery";
    string test_dir = "testdir";
    string installer_prefix = "miniconda";
    string installer_variant = "3";
    string installer_version = "4.5.12";
    string dumpfile_yaml;
    string dumpfile_explicit;
    string dumpfile_freeze;
    string configfile;

    // disable buffering
    stdout.setvbuf(0, _IONBF);
    stderr.setvbuf(0, _IONBF);

    try {
        arraySep = ",";     // set getopt.arraySep. allows passing multiple
                            // args as comma delimited strings.
        auto optargs = getopt(
            args,
            config.passThrough,
            config.required, "config", "dm yaml configuration", &configfile,
            "output-dir|o", "store delivery-related results in dir", &output_dir,
            "test-dir|t", "store test-related results in dir", &test_dir,
            "install-prefix|p", "path to install miniconda", &installer_prefix,
            "install-variant", "miniconda Python variant", &installer_variant,
            "install-version|i", "version of miniconda installer", &installer_version,
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

    Session_t session = getconf(configfile);
    installer_prefix = buildPath(installer_prefix).absolutePath;
    output_dir = buildPath(output_dir, session.delivery).absolutePath;
    test_dir = buildPath(test_dir).absolutePath;

    dumpfile_yaml = buildPath(output_dir, session.delivery ~ ".yml");
    dumpfile_explicit = buildPath(output_dir, session.delivery ~ ".txt");
    dumpfile_freeze = buildPath(output_dir, session.delivery ~ ".pip");

    if (installer_variant != "3") {
        writeln("Python 2.7 has reached end-of-life.");
        writeln("3.x variant will be used instead.");
        installer_variant = "3";
    }

    if (session.conda_channels.empty) {
        session.conda_channels = [
            "http://ssb.stsci.edu/astroconda",
            "defaults",
            "http://ssb.stsci.edu/astroconda-dev"
        ];
    }

    Conda conda = new Conda();
    conda.channels = session.conda_channels;
    conda.install_prefix = installer_prefix;
    conda.installer_version = installer_version;
    conda.installer_variant = installer_variant;

    if (!conda.installer()) {
        writeln("Installation failed.");
        return 1;
    }

    // Assimilate environment variables from the configuration file
    foreach (pair; session.runtime.byPair) {
        conda.env[pair.key] = session.runtime[pair.key];
    }

    // Place miniconda at the head of PATH.
    conda.initialize();

    // When reusing an environment it's best to destroy it before continuing.
    if (conda.env_exists(session.delivery)) {
        writefln("Environment '%s' already exists. Removing.", session.delivery);
        conda.run("env remove -n " ~ session.delivery);
    }

    if (!env_combine(session, conda)) {
        writeln("Delivery merge failed!");
        return 1;
    }

    if (!output_dir.exists) {
        writeln("Creating output directory: " ~ output_dir);
        output_dir.mkdirRecurse;
    }

    // Generate deliverables
    conda.activate(session.delivery);
    writeln("Creating YAML dump: " ~ dumpfile_yaml);
    conda.dump_env_yaml(dumpfile_yaml);
    writeln("Creating explicit dump: " ~ dumpfile_explicit);
    conda.dump_env_explicit(dumpfile_explicit);
    writeln("Creating pip-freeze dump: " ~ dumpfile_freeze);
    conda.dump_env_freeze(dumpfile_freeze);
    conda.deactivate();

    if (session.run_tests) {
        if (!test_dir.exists) {
            writeln("Creating test output directory: " ~ test_dir);
            test_dir.mkdirRecurse;
        }

        int failures = 0;

        // Discover git repository data for just-installed packages
        testable_t[] pkgs = testable_packages(conda, session.conda_requirements, session.test_filter_git_orgs);

        // Allow use of environment variables in test program argument list
        session.test_args = interpolate(conda.env, session.test_args);

        // Process each package, executing its tests
        foreach (i, pkg; pkgs.enumerate(0)) {
            string cloned = format("%04d_%s", i, session.delivery);
            if(conda.run("create -n " ~ cloned ~ " --clone " ~ session.delivery)) {
                return 1;
            }

            // activate conda on the cloned environment
            conda.activate(cloned);

            // count up the number of failures
            failures += integration_test(session, conda, test_dir, pkg);

            // deactivate conda environment
            conda.deactivate();

            // remove conda environement
            if(conda.run("env remove -n " ~ cloned)) {
                return 1;
            }
        }

        if (failures) {
            writefln("\n%d of %d integration tests failed!", failures, pkgs.length);
        }
    }

    writefln("done!");
    return 0;
}
