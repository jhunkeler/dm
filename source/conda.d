import core.cpuid : isX86_64;
import std.file;
import std.stdio;
import std.string;
import std.system;
import std.path;
import std.process;
import std.typecons;


static auto getenv(string[string] base=null, string preface=null) {
    const char delim = '=';
    string[string] env;
    string cmd = "env";

    if (preface !is null) {
        cmd = preface ~ " && " ~ cmd;
        writeln("preface: " ~ cmd);
    }

    auto env_sh = executeShell(cmd, env=base);

    if (env_sh.status) {
        writeln(env_sh.status, env_sh.output);
        throw new Exception("Unable to read shell environment");
    }

    foreach (string line; splitLines(env_sh.output)) {
        if (line.empty) {
            continue;
        }
        auto data = split(line, delim);

        // Recombine extra '=' chars
        if (data.length > 2) {
           data[1] = join(data[1 .. $], delim);
        }
        env[data[0]] = data[1];
    }
    return env;
}


class Conda {
    import std.net.curl : download;

    public bool initialized = false;
    public bool override_channels = true;
    public string[] channels;
    public string install_prefix;
    public string installer_version = "4.5.12";
    public string installer_variant = "3";
    private string[string] env;
    private string[string] env_orig;
    private const string url_base = "https://repo.continuum.io";
    private const string url_miniconda = join([this.url_base, "miniconda"], "/");
    private string url_installer;

    this() {
        env = getenv();
        env_orig = env.dup;
        this.url_installer = join([this.url_miniconda, this.installer_file()], dirSeparator);
    }

    void dump_env_shell() {
        foreach (pair; this.env.byKeyValue()) {
            writeln(pair.key ~ " = " ~ pair.value);
        }
    }

    private string arch() {
        if (isX86_64()) {
            return "x86_64";
        }
        else if (!isX86_64()) {
            return "x86";
        }
        throw new Exception("Unsupported CPU");
    }

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

    bool installed() {
        if (!this.install_prefix.empty && this.install_prefix.exists) {
            return true;
        }
        return false;
    }

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

    private bool have_installer() {
        if (!this.installer_file().exists) {
            return false;
        }
        return true;
    }

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

    bool installer() {
        if (this.in_env() || this.install_prefix.exists) {
            writefln("Conda is already installed: %s", this.install_prefix);
            return true;
        } else if (this.install_prefix.empty) {
            this.install_prefix = absolutePath("./miniconda");
        } else {
            this.install_prefix = absolutePath(this.install_prefix);
        }

        if (this.have_installer()) {
            writeln("Installer already exists");
        } else {
            download(this.url_installer, this.installer_file());
        }

        auto installer = executeShell(
                "bash "
                ~ this.installer_file()
                ~ " -b"
                ~ " -p "
                ~ this.install_prefix,
                env=this.env);

        writeln(installer.output);

        if (installer.status != 0) {
            return false;
        }

        return true;
    }

    void configure_headless() {
        // YAML is cheap.
        // Generate a .condarc inside the new prefix root
        auto fp = File(this.install_prefix ~ dirSeparator ~ ".condarc", "w+");
        fp.write("changeps1: False\n");
        fp.write("always_yes: True\n");
        fp.write("quiet: True\n");
        fp.write("auto_update_conda: False\n");
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

    void initialize() {
        if (this.initialized) {
            writeln("Conda installation has already been initialized");
            return;
        }

        this.env["PATH"] = join(
                [this.install_prefix ~ dirSeparator ~ "bin",
                this.env["PATH"]],
                pathSeparator);
        this.configure_headless();
        this.initialized = true;
    }

    void activate(string name) {
        this.env_orig = this.env.dup;
        string[string] env_new = getenv(this.env, "source activate " ~ name);
        this.env = env_new.dup;
    }

    void deactivate() {
        this.env = this.env_orig.dup;
    }

    int run(string command) {
        string cmd = "conda " ~ command;
        auto proc = this.sh(cmd);
        return proc;
    }

    auto sh_block(string command) {
        auto proc = executeShell(command, env=this.env);
        return proc;
    }

    int sh(string command) {
        writeln("Running: " ~ command);
        auto proc = spawnShell(command, env=this.env);
        return wait(proc);
    }

    string multiarg(string flag, string[] arr) {
        return flag ~ " " ~ arr.join(" " ~ flag ~ " ");
    }
}
