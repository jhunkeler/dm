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
    string mergefile;
    string base_spec;

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
            "base-spec", "conda explicit or yaml environment dump", &base_spec
        );

        if (optargs.helpWanted) {
            defaultGetoptPrinter("Delivery merge [fill in the blanks]",
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

    writeln("Done!");
    return 0;
}
