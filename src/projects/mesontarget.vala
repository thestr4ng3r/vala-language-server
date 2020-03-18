using Gee;

/**
 * Represents a Meson build target.
 */
class Vls.MesonTarget : BuildTarget {
    public MesonTarget (Meson.TargetInfo meson_target_info, string meson_build_dir) 
                        throws ConvertError, FileError, CompilationError {
        base (meson_target_info.defined_in, meson_target_info.id, "MesonTarget");

        if (meson_target_info.target_sources.size != 1) {
            warning ("expected 1 Vala target source in meson target, got %d", meson_target_info.target_sources.size);
        }

        assert (meson_target_info.target_sources.size > 0);

        var target_source = meson_target_info.target_sources[0];
        bool experimental = false;
        bool experimental_non_null = false;
        Vala.Profile profile = Vala.Profile.GOBJECT;
        bool abi_stability = false;
        var args = new HashMap<string, ArrayList<string>> ();
        var files_from_args = new HashSet<string> ();
        string? build_dir = null;
        string? vapi_file = null;
        string? gir_file = null;
        string? internal_vapi_file = null;
        var meson_build_dir_file = File.new_for_path (meson_build_dir);

        // get all flags
        string? flag_name, arg_value;       // --<flag_name>[=<arg_value>]
        for (int arg_i = -1;
             (arg_i = iterate_valac_args (target_source.parameters, out flag_name, out arg_value, arg_i)) < target_source.parameters.length;) {
            if (flag_name == "pkg" || flag_name == "vapidir" ||
                flag_name == "girdir" || flag_name == "metadatadir" ||
                flag_name == "gresourcesdir" || flag_name == "define") {
                if (!args.has_key (flag_name))
                    args[flag_name] = new ArrayList<string> ();
                args[flag_name].add (arg_value);
            } else if (flag_name == "experimental") {
                experimental = true;
            } else if (flag_name == "experimental-non-null") {
                experimental_non_null = true;
            } else if (flag_name == "profile") {
                if (arg_value == "posix")
                    profile = Vala.Profile.POSIX;
            } else if (flag_name == "abi-stability") {
                abi_stability = true;
            } else if (flag_name == "directory") {
                build_dir = File.new_build_filename (meson_build_dir, (!) arg_value).get_path ();
            } else if (flag_name == "vapi" || flag_name == "gir" || flag_name == "internal-vapi") {
                if (arg_value == null) {
                    warning (@"MesonTarget($(meson_target_info.id)) --$flag_name is null");
                    continue;
                }

                string path;
                if (Path.is_absolute (arg_value)) {
                    path = (!) arg_value;
                } else {
                    if (build_dir == null) {
                        warning (@"MesonTarget($(meson_target_info.id)) no build dir (--directory) known before --vapi, assuming Meson build dir ($meson_build_dir)");
                        var guessed_file = File.new_build_filename (meson_build_dir, arg_value);
                        if (meson_build_dir_file.get_relative_path (guessed_file) == null) {
                            warning (@"$(guessed_file.get_path ()) is not within $meson_build_dir, so it will be ignored");
                            continue;
                        }
                        path = guessed_file.get_path ();
                    } else {
                        path = File.new_build_filename (build_dir, arg_value).get_path ();
                    }
                }
                debug ("MesonTarget(%s) setting %s to (path) %s", meson_target_info.id, flag_name, path);
                if (flag_name == "vapi")
                    vapi_file = path;
                else if (flag_name == "gir")
                    gir_file = path;
                else
                    internal_vapi_file = path;
            } else if (flag_name == null) {
                if (arg_value == null) {
                    warning ("failed to parse argument #%d (%s) of target MesonTarget(%s)", 
                             arg_i, target_source.parameters[arg_i], meson_target_info.id);
                } else if (arg_value.has_suffix (".vapi") || arg_value.has_suffix (".gir")) {
                    files_from_args.add (arg_value);
                }
            } else {
                warning ("ignoring argument #%d (%s) of target MesonTarget(%s)", 
                         arg_i, target_source.parameters[arg_i], meson_target_info.id);
            }
        }

        compilation = new Compilation (this, experimental,
                experimental_non_null,
                profile, abi_stability,
                args["pkg"],
                args["vapidir"],
                args["girdir"],
                args["metadatadir"],
                args["gresourcesdir"],
                args["define"],
                vapi_file,
                gir_file,
                internal_vapi_file);

        // add source files to compilation
        foreach (string source in files_from_args) {
            debug (@"$this: adding source file $source from args");
            compilation.add_source_file (source);
        }

        foreach (string source in target_source.sources) {
            File source_file;
            if (!Path.is_absolute (source))
                source_file = File.new_build_filename (build_dir, source);
            else
                source_file = File.new_for_path (source);
            if (source_file.query_exists ()) {
                debug (@"$this: adding source file $source");
                compilation.add_source_file (source);
            }
        }
    }
}