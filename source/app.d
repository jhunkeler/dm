import std.stdio;
import std.array;
import std.format;
import std.file;
import std.typecons;
import conda;
import merge;

int main(string[] args) {
    Conda conda = new Conda();
    conda.channels = [
        "http://ssb.stsci.edu/astroconda",
        "defaults",
        "http://ssb.stsci.edu/astroconda-dev"
    ];
    conda.install_prefix = "/tmp/miniconda";
    conda.installer_version = "4.5.12";
    conda.installer_variant = "3";
    if (!conda.installer()) {
        writeln("Installation failed.");
        return 1;
    }
    conda.initialize();
    auto info = testable_packages(conda, "test.dm");
    writeln(info);

    /*
    env_combine(conda,
            "delivery",
            "https://raw.githubusercontent.com/astroconda/astroconda-releases/master/hstdp/2019.3/dev/hstdp-2019.3-linux-py36.02.txt",
            "test.dm");
    conda.run("info");
    conda.run("list");
    */

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
