module python;
import std.array;
import std.file;
import std.stdio;
import std.path;
import std.string;
import std.process;
import std.conv : to;
import util;



class Python {
    public string prefix;
    private string bindir;
    private string libdir;
    private string venv_tmpdir;
    public string[string] env;
    private string[string] env_orig;

    this(string prefix) {
        this.prefix = buildPath(absolutePath(prefix));
        this.env = getenv();
        this.env_orig = env.dup;

        this.initialize();
    }

    public void initialize() {
        if (!this.prefix.exists) {
            throw new Exception(format("'%s': prefix does not exist\n", this.prefix));
        }

        this.bindir = buildPath(prefix, "bin");
        this.libdir = buildPath(prefix, "lib");

        this.env["PATH"] = join([this.bindir,
                                 this.env.get("PATH", "")],
                                 pathSeparator);
        this.env["LD_LIBRARY_PATH"] = join([this.libdir,
                                            this.env.get("LD_LIBRARY_PATH", "")],
                                            pathSeparator);

        if (this.have_py2k()) {
            throw new Exception("Python 2.7 is not supported");
        }
    }

    public void bleeding_edge() {
        this.sh_block("pip install --upgrade pip setuptools");
    }

    public void venv_create(string name) {
        if (name.exists) {
            stderr.writefln("'%s': virtual environment exists", name);
            return;
        }
        auto result = this.sh_block("python -m venv " ~ name);
        if (result.status) {
            stderr.writef(result.output);
            throw new Exception(format("%s: virtual environment creation failed\n", name));
        }
    }

    public void venv_activate(string name) {
        this.env_orig = this.env.dup;
        string[string] env_new = getenv(this.env,
                                        format("source %s",
                                               buildPath(name, "bin", "activate")));
        this.env = env_new.dup;
    }

    public void venv_deactivate() {
        this.env = this.env_orig.dup;
    }

    public ulong get_version() {
        auto output = this.run_block("import sys; print(sys.hexversion)").output.strip();
        ulong ver = output.to!ulong;
        return ver;
    }

    public bool have_py2k() {
        return this.get_version() < 0x03_00_00_0f;
    }

    public int run(string command) {
        auto proc = this.sh(format("python -c '%s'", command));
        return proc;
    }

    public auto run_block(string command) {
        auto proc = this.sh_block(format("python -c '%s'", command));
        return proc;
    }

    public int sh(string command) {
        auto proc = spawnShell(command, env=this.env);
        scope(exit) wait(proc);
        return wait(proc);
    }

    public auto sh_block(string command) {
        auto proc = executeShell(command, env=this.env);
        return proc;
    }
}
