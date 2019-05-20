module merge;
import std.stdio;
import std.string;
import std.array;
import std.format;
import std.typecons;
import std.file;
import std.regex;
import conda;


auto RE_COMMENT = regex(r"[;#]");
auto RE_DMFILE = regex(r"^(?P<name>[A-z\-_l]+)(?:[=<>]+)?(?P<version>[A-z0-9. ]+)?");
auto RE_DMFILE_INVALID_VERSION = regex(r"[ !@#$%^&\*\(\)\-_]+");
auto RE_DELIVERY_NAME = regex(r"(?P<name>.*)[-_](?P<version>.*)[-_]py(?P<python_version>\d+)[-_.](?P<iteration>\d+)[-_.](?P<ext>.*)");


string safe_spec(string s) {
    return "'" ~ s ~ "'";
}

string safe_install(string[] specs) {
    string[] result;
    foreach (record; specs) {
        result ~= safe_spec(record);
    }
    return result.join(" ");
}

string[string][] dmfile(string filename) {
    string[string][] results;
    foreach (line; File(filename).byLine()) {
        string[string] pkg;
        line = strip(line);
        auto has_comment = matchFirst(line, RE_COMMENT);
        if (!has_comment.empty) { line = strip(has_comment.pre()); }
        if (line.empty) { continue; }

        auto record = matchFirst(line, RE_DMFILE);
        writefln("-> package: %-10s :: version: %-10s", record["name"],
                !record["version"].empty ? record["version"] : "none");

        pkg["name"] = record["name"].dup;
        pkg["version"] = record["version"].dup;
        pkg["fullspec"] = record.hit.dup;
        results ~= pkg;
    }
    return results;
}

bool env_combine(ref Conda conda, string name, string specfile, string mergefile) {
    if (indexOf(specfile, "://", 0) < 0 && !specfile.exists) {
        throw new Exception(specfile ~ " does not exist");
    } else if (!mergefile.exists) {
        throw new Exception(mergefile ~ " does not exist");
    }

    int retval = 0;
    string[] specs;
    auto merge_data = dmfile(mergefile);
    foreach (record; merge_data) {
        specs ~= record["fullspec"];
    }

    retval = conda.run("create -n "
                          ~ name
                          ~ " --file "
                          ~ specfile);
    if (retval) {
        return false;
    }

    conda.activate(name);

    retval = conda.run("install "
                       ~ conda.multiarg("-c", conda.channels)
                       ~ " "
                       ~ safe_install(specs));
    if (retval) {
        return false;
    }
    return true;
}
