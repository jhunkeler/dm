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
    string installer_version = "4.5.12";
    bool run_tests = false;
    string mergefile;
    string base_spec;

    auto helpInformation = getopt(
        args,
        config.passThrough,
        config.required, "env-name|n", "name of delivery", &env_name,
        config.required, "dmfile|d", "delivery merge specification file", &mergefile,
        "output-dir|o", "store delivery-related results in dir", &output_dir,
        "install-prefix|p", "path to install miniconda", &installer_prefix,
        "install-version|i", "version of miniconda installer", &installer_version,
        "run-tests|R", "scan merged packages and execute their tests", &run_tests,
        "base-spec", "conda explicit or yaml environment dump", &base_spec
    );

    if (helpInformation.helpWanted) {
        defaultGetoptPrinter("Delivery merge [fill in the blanks]",
                             helpInformation.options);
        return 0;
    }

    installer_prefix = buildPath(installer_prefix).absolutePath;
    output_dir = buildPath(output_dir, env_name).absolutePath;
    mergefile = buildPath(mergefile).absolutePath;

    // Ingest the dump file via --base-spec or with a positional argument.
    if (base_spec.empty && args.length > 1) {
        base_spec = args[1];
        args.popBack();
    }

    /*
    string optfmt = "env_name: %s\n"
        ~ "output_dir: %s\n"
        ~ "installer_prefix: %s\n"
        ~ "installer_version: %s\n"
        ~ "run_tests: %d\n"
        ~ "mergefile: %s\n"
        ~ "base_spec: %s\n"
        ~ "ARGS: %s\n";
    writefln(optfmt, env_name, output_dir, installer_prefix, installer_version,
             run_tests, mergefile, base_spec, args);
    */

    Conda conda = new Conda();
    conda.channels = [
        "http://ssb.stsci.edu/astroconda",
        "defaults",
        "http://ssb.stsci.edu/astroconda-dev"
    ];
    conda.install_prefix = installer_prefix;
    conda.installer_version = installer_version;
    conda.installer_variant = "3";
    if (!conda.installer()) {
        writeln("Installation failed.");
        return 1;
    }
    conda.initialize();
    if (!env_combine(conda, env_name, base_spec, mergefile)) {
        writeln("Delivery merge failed. Adjust '*.dm' file to match constraints reported by the 'solver'.");
        return 1;
    }

    if (!output_dir.exists) {
        output_dir.mkdirRecurse;
    }
    writeln(conda.dump_env_yaml(buildPath(output_dir, env_name ~ ".yml")));
    writeln(conda.dump_env_explicit(buildPath(output_dir, env_name ~ ".txt")));

    auto info = testable_packages(conda, "test.dm");
    writeln(info);

    /*
    conda.activate("base");
    conda.run("info");
    conda.sh("python --version");
    conda.sh("python -c 'import sys; print(sys.path)'");
    */


    /*
    conda.sh("git clone https://github.com/spacetelescope/tweakwcs");
    auto project = "tweakwcs";
    chdir(project);
    conda.sh("pip install stsci.distutils numpy");
    conda.sh("pip install -e '.[test]'");
    conda.sh("pytest -v");
    chdir("..");
    */

    return 0;
}
