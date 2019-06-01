module session;

import core.stdc.stdlib : exit, EXIT_FAILURE;
import std.array;
import std.file;
import std.stdio;
import std.string;
import util;
import dyaml;


struct Session_t {
    string delivery_name;
    string delivery_version;
    ubyte delivery_rev;
    string delivery_platform;
    string delivery_python;
    string delivery;
    string base_spec;
    string on_error;
    string script_pre;
    string script_post;
    string[string] runtime;
    string[] conda_channels;
    string[] conda_requirements;
    string[] pip_index;
    string[] pip_requirements;
    bool run_tests = false;
    string test_program = "pytest";
    string test_args = "-v";
    string[] test_conda_requirements;
    string[] test_pip_requirements;
    string[] test_filter_git_orgs;
    string[] test_filter_git_projects;
}


Session_t getconf(string filename) {
    Node root = Loader.fromFile(filename).load();
    Node data;
    Session_t session;

    /// Required configuration items
    try {
        session.delivery_name = root["delivery_name"].as!string;
        session.delivery_version = root["delivery_version"].as!string;
        session.delivery_rev = root["delivery_rev"].as!ubyte;
        session.delivery_python = root["delivery_python"].as!string;

        if (!session.delivery_python.empty) {
            session.conda_requirements ~= "python=" ~ session.delivery_python;
        }

        version (OSX) session.delivery_platform = "osx";
        version (linux) session.delivery_platform = "linux";
        version (Windows) session.delivery_platform = "windows";

        session.delivery = format("%s-%s-%s-py%s.%02d",
                session.delivery_name,
                session.delivery_version,
                session.delivery_platform,
                short_version(session.delivery_python),
                session.delivery_rev);
    } catch (YAMLException e) {
        stderr.writefln("\n%s: configuration error!\n%s\n", filename, e.msg);
        exit(EXIT_FAILURE);
    }

    /// Optional configuration items
    if (root.containsKey("base_spec"))
        session.base_spec = root["base_spec"].as!string;

    if (root.containsKey("on_error"))
        session.on_error = root["on_error"].as!string;

    if (root.containsKey("script_pre"))
        session.script_pre = root["script_pre"].as!string;

    if (root.containsKey("script_post"))
        session.script_post = root["script_post"].as!string;

    if (root.containsKey("runtime")) {
        data = root["runtime"];
        foreach (Node k, Node v; data)
            session.runtime[k.as!string] = v.as!string;
    }

    if (root.containsKey("conda_channels")) {
        data = root["conda_channels"];
        foreach (Node v; data)
            session.conda_channels ~= v.as!string;
    }

    if (root.containsKey("conda_requirements")) {
        data = root["conda_requirements"];
        foreach (Node v; data)
            session.conda_requirements ~= v.as!string;
    }

    if (root.containsKey("pip_index")) {
        data = root["pip_index"];
        foreach (Node v; data)
            session.pip_index ~= v.as!string;
    }

    if (root.containsKey("pip_requirements")) {
        data = root["pip_requirements"];
        foreach (Node v; data)
            session.pip_requirements ~= v.as!string;
    }

    if (root.containsKey("run_tests")) {
        session.run_tests = root["run_tests"].as!bool;
    }

    if (root.containsKey("test_program")) {
        session.test_program = root["test_program"].as!string;
    }

    if (root.containsKey("test_args")) {
        session.test_args = root["test_args"].as!string;
    }

    if (root.containsKey("test_conda_requirements")) {
        data = root["test_conda_requirements"];
        foreach (Node v; data)
            session.test_conda_requirements ~= v.as!string;
    }

    if (root.containsKey("test_pip_requirements")) {
        data = root["test_pip_requirements"];
        foreach (Node v; data)
            session.test_pip_requirements ~= v.as!string;
    }

    if (root.containsKey("test_filter_git_orgs")) {
        data = root["test_filter_git_orgs"];
        foreach (Node v; data)
            session.test_filter_git_orgs ~= v.as!string;
    }

    if (root.containsKey("test_filter_git_projects")) {
        data = root["test_filter_git_projects"];
        foreach (Node v; data)
            session.test_filter_git_projects ~= v.as!string;
    }
    return session;
}
