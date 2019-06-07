module session;

import core.stdc.stdlib : exit, EXIT_FAILURE;
import std.array;
import std.file;
import std.stdio;
import std.string;
import util;
import dyaml;

/**
  Extended test configuration structure
  */
struct TestExtended_t {
    /// Package name
    string name;
    /// Runtime environment for package
    string[string] runtime;
    /// Arguments to pass to `Session_t.test_program`
    string test_args;
    /// Arbitrary commands to execute for package
    string[] commands;
}

/**
  Global delivery configuration structure
  */
struct Session_t {
    /// Name of delivery
    string delivery_name;
    /// Version of delivery
    string delivery_version;
    /// Revision of delivery (disabled if `final` is `true`)
    ubyte delivery_rev;
    /// Platform of delivery (automatically generated)
    string delivery_platform;
    /// Python version to use for delivery
    string delivery_python;
    /// Fully qualified name (automatically generated)
    string delivery;
    /// A conda environment specification to inherit from
    string base_spec;
    /// `exit` or `continue` on error. (NOT IMPLEMENTED)
    string on_error;
    /// NOT IMPLEMENTED
    string script_pre;
    /// NOT IMPLEMENTED
    string script_post;
    /// runtime environment variables
    string[string] runtime;
    /// conda channels (order preserved)
    string[] conda_channels;
    /// conda packages to install
    string[] conda_requirements;
    /// pypi index(s) to use
    string[] pip_index;
    /// pypi packages to install (accepts arbitrary pip arguments)
    string[] pip_requirements;
    /// Determine if integration tests will be executed
    bool run_tests = false;
    /// Test framework to execute
    string test_program = "pytest";
    /// default arguments to pass to `test_program`
    string test_args = "-v";
    /// define an array of extended test configurations
    TestExtended_t[] test_extended;
    /// conda packages to install globally for integration testing
    string[] test_conda_requirements;
    /// pypi packages to install globally for integration testing
    string[] test_pip_requirements;
    /// test packages originating from specific users (i.e. spacetelescope)
    string[] test_filter_git_orgs;
    /// NOT IMPLEMENTED
    string[] test_filter_git_projects;
}


/**
  Read delivery configuration file

Params:
    filename = path to YAML configuration file

Returns:
    populated `Session_t` struct
 */
Session_t getconf(string filename) {
    Node root = Loader.fromFile(filename).load();
    Node data;
    Session_t session;

    // Required configuration items
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

    if (root.containsKey("test_extended")) {
        data = root["test_extended"];

        foreach (Node parent_1, Node child_1; data) {
            TestExtended_t te;
            te.name = parent_1.as!string;
            if (child_1.containsKey("runtime")) {
                foreach (Node parent_2, Node child_2; child_1["runtime"]) {
                    te.runtime[parent_2.as!string] = child_2.as!string;
                }
            }
            if (child_1.containsKey("commands")) {
                foreach (Node v; child_1["commands"]) {
                    te.commands ~= v.as!string.strip;
                }
            }
            if (child_1.containsKey("test_args")) {
                te.test_args = child_1["test_args"].as!string;
            }
            session.test_extended ~= te;
        }
    }
    return session;
}
