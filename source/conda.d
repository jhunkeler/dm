import core.cpuid : isX86_64;
import std.array;
import std.conv;
import std.file;
import std.stdio;
import std.string;
import std.system;
import std.path;
import std.process;
import std.typecons;
import util;


/**
  Interact with a `conda` installation. If `install_prefix` does
  not exist, miniconda will be downloaded and installed in the current
  directory.
  */
class Conda {
    import std.net.curl : download;

    /// Gate to prevent PATH clobbering or reconfiguration
    public bool initialized = false;
    /// channel URIs (order preserved)
    public string[] channels;
    /// path to install miniconda (or existing miniconda installation)
    public string install_prefix;
    /// which version of miniconda to install
    public string installer_version = "4.5.12";
    /// which variant (python "2", or "3")
    public string installer_variant = "3";
    /// the runtime environment used for all shell executions
    public string[string] env;

    private string[string] env_orig;
    private const string url_base = "https://repo.continuum.io";
    private const string url_miniconda = join([this.url_base, "miniconda"], "/");
    private string url_installer;

    this() {
        env = getenv();
        env_orig = env.dup;
        this.url_installer = join([this.url_miniconda, this.installer_file()], "/");
    }

    void dump_env_shell() {
        foreach (pair; this.env.byKeyValue()) {
            writeln(pair.key ~ "=" ~ pair.value);
        }
    }

    /// there isn't a good way to determine the CPU type in `phobos`
    private string arch() {
        if (isX86_64()) {
            return "x86_64";
        }
        else if (!isX86_64()) {
            return "x86";
        }
        throw new Exception("Unsupported CPU");
    }

    /// generate conda platform string
    private string platform() {
        import std.system : OS, os;
        string report;
        switch (os) {
            default:
                throw new Exception("Unsupported OS");

            case OS.linux:
                report = "Linux";
                break;

            case OS.osx:
                report = "MacOSX";
                break;

            case OS.win32:
            case OS.win64:
                report = "Windows";
                break;

        }
        return report;
    }

    /// determine if the installation prefix
    bool installed() {
        if (!this.install_prefix.empty && this.install_prefix.exists) {
            return true;
        }
        return false;
    }

    /// determine if "our" conda is "the conda" in the environment
    bool in_env() {
        string path = this.env.get("PATH", "");

        if (path.empty || this.install_prefix.empty) {
            return false;
        }

        foreach (string record; split(path, pathSeparator)) {
            if (record == this.install_prefix ~ pathSeparator ~ "bin") {
                return true;
            }
        }
        return false;
    }

    /// determine if the installer exists
    private bool have_installer() {
        if (!this.installer_file().exists) {
            return false;
        }
        return true;
    }

    /// generate an installer filename name based on gathered specs
    private string installer_file() {
        string ext = ".sh";
        version (Windows) { ext = ".exe"; }
        string filename = join([
            "Miniconda" ~ this.installer_variant,
            this.installer_version,
            this.platform(),
            this.arch()
        ], "-") ~ ext;
        return filename;
    }

    /// install miniconda into `install_prefix`
    bool installer() {
        if (this.in_env() || this.install_prefix.exists) {
            writefln("Miniconda is already installed: %s", this.install_prefix);
            return true;
        } else if (this.install_prefix.empty) {
            this.install_prefix = absolutePath("./miniconda");
        } else {
            this.install_prefix = absolutePath(this.install_prefix);
        }

        if (this.have_installer()) {
            writeln("Miniconda installation script already exists");
        } else {
            writeln("Downloading " ~ this.installer_file());
            download(this.url_installer, this.installer_file());
        }

        // execute installation (batch mode)
        auto installer = this.sh(
                "bash "
                ~ this.installer_file()
                ~ " -b"
                ~ " -p "
                ~ this.install_prefix);

        if (installer != 0) {
            return false;
        }

        return true;
    }

    /// Generate a .condarc inside the root of the `install_prefix`
    void configure_headless() {
        auto fp = File(chainPath(this.install_prefix, ".condarc").array, "w+");
        fp.write("changeps1: False\n");
        fp.write("always_yes: True\n");
        fp.write("quiet: True\n");
        fp.write("auto_update_conda: False\n");
        fp.write("notify_outdated_conda: False\n");
        fp.write("rollback_enabled: False\n");
        fp.write("channels:\n");
        if (this.channels.empty) {
            fp.write("  - defaults\n");
        } else {
            foreach (channel; this.channels) {
                fp.write("  - " ~ channel ~ "\n");
            }
        }
    }

    /// Add conda to the runtime environment and configure it for general use
    void initialize() {
        if (this.initialized) {
            writeln("Conda installation has already been initialized");
            return;
        }

        this.env["PATH"] = join(
                [cast(string)chainPath(this.install_prefix, "bin").array,
                this.env["PATH"]],
                pathSeparator);
        this.configure_headless();
        this.fix_setuptools();
        this.initialized = true;
    }

    /// Activates a conda environment by name
    void activate(string name) {
        this.env_orig = this.env.dup;
        string[string] env_new = getenv(this.env, "source activate " ~ name);
        this.env = env_new.dup;
        this.fix_setuptools();
    }

    /// Restores the last recorded environment
    /// TODO: `env` should be able to handle nested environments
    void deactivate() {
        this.env = this.env_orig.dup;
    }


    /// Execute a conda command
    int run(string command) {
        auto proc = this.sh("conda " ~ command);
        return proc;
    }

    /// ditto
    /// returns process object
    auto run_block(string command) {
        auto proc = this.sh_block("conda " ~ command);
        return proc;
    }

    /// Execute shell command
    int sh(string command) {
        banner('#', command);
        auto proc = spawnShell(command, env=this.env);
        scope(exit) wait(proc);
        return wait(proc);
    }

    /// ditto
    /// returns process object
    auto sh_block(string command) {
        auto proc = executeShell(command, env=this.env);
        return proc;
    }

    /// Generate additive command line arguments
    string multiarg(string flag, string[] arr) {
        if (arr.empty)
            return "";
        return flag ~ " " ~ arr.join(" " ~ flag ~ " ");
    }

    /// Wildcard search prefix for extracted packages
    string[] scan_packages(string pattern="*") {
        string[] result;
        string pkgdir = chainPath(this.install_prefix, "pkgs").array;
        if (!pkgdir.exists) {
            throw new Exception(pkgdir ~ " does not exist");
        }

        foreach (DirEntry e; dirEntries(pkgdir, pattern, SpanMode.shallow)) {
            if (e.isFile || e.name.endsWith(dirSeparator ~ "cache")) {
                continue;
            }
            result ~= baseName(e.name);
        }
        return result;
    }

    /// determine if a conda environment is present
    bool env_exists(string name) {
        return buildPath(this.install_prefix, "envs", name).exists;
    }

    /// return system path to `name`ed environment
    string env_where(string name) {
        if (this.env_exists(name)) {
            return buildPath(this.install_prefix, "envs", name);
        }
        return null;
    }

    /// return current conda environment
    string env_current() {
        return this.env.get("CONDA_PREFIX", null);
    }

    /// returns site-packages directory for the active Python interpreter
    string site() {
        return this.sh_block("python -c 'import site; print(site.getsitepackages()[0])'").output.strip;
    }

    /// conda does not like setuptools.
    /// this allows `pip` to [un]install packages
    void fix_setuptools() {
        string pthfile = buildPath(this.site(), "easy-install.pth");
        if (!pthfile.exists) {
            // inject easy-install.pth
            File(pthfile, "w+").write("");
        }
    }

    string dump_env_yaml(string filename=null) {
        string args;
        if (filename !is null) {
            args = "--file " ~ filename;
        }
        auto proc = this.run_block("env export " ~ args);
        return proc.output;
    }

    string dump_env_explicit(string filename=null) {
        auto proc = this.run_block("list --explicit");
        if (filename !is null) {
            auto file = File(filename, "w+");
            file.write(proc.output);
        }
        return proc.output;
    }

    // Note: This is to see what pip sees. It will not be useful to an end
    // user.
    string dump_env_freeze(string filename=null) {
        auto proc = this.sh_block("pip freeze");
        if (filename !is null) {
            auto file = File(filename, "w+");
            file.write(proc.output);
        }
        return proc.output;
    }
}
