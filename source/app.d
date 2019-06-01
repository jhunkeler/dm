import std.getopt;
import std.stdio;
import std.array;
import std.format;
import std.file;
import std.typecons;
import std.path : buildPath, chainPath, absolutePath;
import conda;
import merge;
import session;


int main(string[] args) {
    string output_dir = "delivery";
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

    conda.initialize();

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

    writeln("Creating YAML dump: " ~ dumpfile_yaml);
    conda.dump_env_yaml(dumpfile_yaml);
    writeln("Creating explicit dump: " ~ dumpfile_explicit);
    conda.dump_env_explicit(dumpfile_explicit);
    writeln("Creating pip-freeze dump: " ~ dumpfile_freeze);
    conda.dump_env_freeze(dumpfile_freeze);

    if (session.run_tests) {
        int failures = 0;
        string testdir = buildPath(output_dir, "testdir");
        testable_t[] pkgs = testable_packages(conda, session.conda_requirements);

        foreach (pkg; pkgs) {
            failures += integration_test(session, conda, testdir, pkg);
        }

        if (failures) {
            writefln("\n%d of %d integration tests failed!", failures, pkgs.length);
        }
    }

    writefln("done!");
    return 0;
}
