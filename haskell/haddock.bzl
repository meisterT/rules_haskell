"""Haddock support"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "@rules_haskell//haskell:providers.bzl",
    "HaddockInfo",
    "HaskellInfo",
    "HaskellLibraryInfo",
    "get_ghci_extra_libs",
)
load(":private/context.bzl", "haskell_context", "render_env")
load(":private/set.bzl", "set")

def _get_haddock_path(package_id):
    """Get path to Haddock file of a package given its id.

    Args:
      package_id: string, package id.

    Returns:
      string: relative path to haddock file.
    """
    return package_id + ".haddock"

def _haskell_doc_aspect_impl(target, ctx):
    if not (HaskellLibraryInfo in target and target[HaskellInfo].source_files.to_list()):
        return []

    # Packages imported via `//haskell:import.bzl%haskell_import` already
    # contain an `HaddockInfo` provider, so we just forward it
    if HaddockInfo in target:
        return []

    hs = haskell_context(ctx, ctx.rule.attr)

    package_id = target[HaskellLibraryInfo].package_id
    html_dir_raw = "doc-{0}".format(package_id)
    html_dir = ctx.actions.declare_directory(html_dir_raw)
    haddock_file = ctx.actions.declare_file(_get_haddock_path(package_id))

    # XXX Haddock really wants a version number, so invent one from
    # thin air. See https://github.com/haskell/haddock/issues/898.
    if target[HaskellLibraryInfo].version:
        version = target[HaskellLibraryInfo].version
    else:
        version = "0"

    args = ctx.actions.args()
    args.add("--package-name={0}".format(package_id))
    args.add("--package-version={0}".format(version))
    args.add_all([
        "-D",
        haddock_file.path,
        "-o",
        html_dir.path,
        "--html",
        "--hoogle",
        "--title={0}".format(package_id),
        "--hyperlinked-source",
    ])

    transitive_haddocks = {}
    transitive_html = {}

    for dep in ctx.rule.attr.deps:
        if HaddockInfo in dep:
            transitive_haddocks.update(dep[HaddockInfo].transitive_haddocks)
            transitive_html.update(dep[HaddockInfo].transitive_html)

    for pid in transitive_haddocks:
        for interface in transitive_haddocks[pid]:
            args.add("--read-interface=../{0},{1}".format(
                pid,
                interface.path,
            ))

    compile_flags = ctx.actions.args()
    for x in target[HaskellInfo].compile_flags:
        compile_flags.add_all(["--optghc", x])
    compile_flags.add_all(target[HaskellInfo].source_files)
    compile_flags.add("-v0")

    # haddock flags should take precedence over ghc args, hence are in
    # last position
    compile_flags.add_all(hs.toolchain.haddock_flags)

    locale_archive_depset = (
        depset([hs.toolchain.locale_archive]) if hs.toolchain.locale_archive != None else depset()
    )

    # C library dependencies for runtime.
    (ghci_extra_libs, ghc_env) = get_ghci_extra_libs(
        hs,
        target[CcInfo],
        # haddock changes directory during its execution. We prefix
        # LD_LIBRARY_PATH with the current working directory on wrapper script
        # startup.
        path_prefix = "$PWD",
    )

    # TODO(mboes): we should be able to instantiate this template only
    # once per toolchain instance, rather than here.
    haddock_wrapper = ctx.actions.declare_file("haddock_wrapper-{}".format(hs.name))
    ctx.actions.expand_template(
        template = ctx.file._haddock_wrapper_tpl,
        output = haddock_wrapper,
        substitutions = {
            "%{ghc-pkg}": hs.tools.ghc_pkg.path,
            "%{haddock}": hs.tools.haddock.path,
            # XXX Workaround
            # https://github.com/bazelbuild/bazel/issues/5980.
            "%{env}": render_env(dicts.add(hs.env, ghc_env)),
        },
        is_executable = True,
    )

    ctx.actions.run(
        inputs = depset(transitive = [
            target[HaskellInfo].package_databases,
            target[HaskellInfo].interface_dirs,
            target[HaskellInfo].source_files,
            target[HaskellInfo].extra_source_files,
            target[HaskellInfo].dynamic_libraries,
            ghci_extra_libs,
            depset(transitive = [depset(i) for i in transitive_haddocks.values()]),
            target[CcInfo].compilation_context.headers,
            depset([
                hs.tools.ghc_pkg,
                hs.tools.haddock,
            ]),
            locale_archive_depset,
        ]),
        outputs = [haddock_file, html_dir],
        mnemonic = "HaskellHaddock",
        progress_message = "HaskellHaddock {}".format(ctx.label),
        executable = haddock_wrapper,
        arguments = [
            args,
            compile_flags,
        ],
        use_default_shell_env = True,
    )

    transitive_html.update({package_id: html_dir})
    transitive_haddocks.update({package_id: [haddock_file]})

    haddock_info = HaddockInfo(
        package_id = package_id,
        transitive_html = transitive_html,
        transitive_haddocks = transitive_haddocks,
    )
    output_files = OutputGroupInfo(default = transitive_html.values())

    return [haddock_info, output_files]

haskell_doc_aspect = aspect(
    _haskell_doc_aspect_impl,
    attrs = {
        "_haddock_wrapper_tpl": attr.label(
            allow_single_file = True,
            default = Label("@rules_haskell//haskell:private/haddock_wrapper.sh.tpl"),
        ),
    },
    attr_aspects = ["deps"],
    toolchains = ["@rules_haskell//haskell:toolchain"],
)

def _dirname(file):
    return file.dirname

def _haskell_doc_rule_impl(ctx):
    hs = haskell_context(ctx)

    # Reject cases when number of dependencies is 0.

    if not ctx.attr.deps:
        fail("haskell_doc needs at least one haskell_library component in deps")

    doc_root_raw = ctx.attr.name
    haddock_dict = {}
    html_dict_original = {}
    all_caches = depset(transitive = [
        dep[HaskellInfo].package_databases
        for dep in ctx.attr.deps
        if HaskellInfo in dep
    ])

    for dep in ctx.attr.deps:
        if HaddockInfo in dep:
            html_dict_original.update(dep[HaddockInfo].transitive_html)
            haddock_dict.update(dep[HaddockInfo].transitive_haddocks)

    # Copy docs of Bazel deps into predefined locations under the root doc
    # directory.

    html_dict_copied = {}
    doc_root_path = ""

    for package_id in html_dict_original:
        html_dir = html_dict_original[package_id]
        output_dir = ctx.actions.declare_directory(
            paths.join(
                doc_root_raw,
                package_id,
            ),
        )
        doc_root_path = paths.dirname(output_dir.path)

        html_dict_copied[package_id] = output_dir

        ctx.actions.run_shell(
            inputs = [html_dir],
            outputs = [output_dir],
            command = """
      mkdir -p "{doc_dir}"
      # Copy Haddocks of a dependency.
      cp -R -L "{html_dir}/." "{target_dir}"
      """.format(
                doc_dir = doc_root_path,
                html_dir = html_dir.path,
                target_dir = output_dir.path,
            ),
        )

    # Do one more Haddock call to generate the unified index

    index_root_raw = paths.join(doc_root_raw, "index")
    index_root = ctx.actions.declare_directory(index_root_raw)

    args = ctx.actions.args()
    args.add_all([
        "-o",
        index_root.path,
        "--title={0}".format(ctx.attr.name),
        "--gen-index",
        "--gen-contents",
    ])

    if ctx.attr.index_transitive_deps:
        # Include all packages in the unified index.
        for package_id in html_dict_copied:
            for interface in haddock_dict[package_id]:
                args.add("--read-interface=../{0},{1}".format(
                    package_id,
                    interface.path,
                ))
    else:
        # Include only direct dependencies.
        for dep in ctx.attr.deps:
            if HaddockInfo in dep:
                package_id = dep[HaddockInfo].package_id
                for interface in haddock_dict[package_id]:
                    args.add("--read-interface=../{0},{1}".format(
                        package_id,
                        interface.path,
                    ))

    args.add_all(all_caches, map_each = _dirname, format_each = "--optghc=-package-db=%s")
    locale_archive_depset = (
        depset([hs.toolchain.locale_archive]) if hs.toolchain.locale_archive != None else depset()
    )

    ctx.actions.run(
        inputs = depset(transitive = [
            all_caches,
            depset(html_dict_copied.values()),
            depset(transitive = [depset(i) for i in haddock_dict.values()]),
            locale_archive_depset,
        ]),
        outputs = [index_root],
        mnemonic = "HaskellHaddockIndex",
        executable = hs.tools.haddock,
        arguments = [args],
    )

    return [DefaultInfo(
        files = depset(html_dict_copied.values() + [index_root]),
    )]

haskell_doc = rule(
    _haskell_doc_rule_impl,
    attrs = {
        "deps": attr.label_list(
            aspects = [haskell_doc_aspect],
            doc = "List of Haskell libraries to generate documentation for.",
        ),
        "index_transitive_deps": attr.bool(
            default = False,
            doc = "Whether to include documentation of transitive dependencies in index.",
        ),
    },
    toolchains = ["@rules_haskell//haskell:toolchain"],
)
"""Create API documentation.

Builds API documentation (using [Haddock][haddock]) for the given
Haskell libraries. It will automatically build documentation for any
transitive dependencies to allow for cross-package documentation
linking.

Example:
  ```bzl
  haskell_library(
    name = "my-lib",
    ...
  )

  haskell_doc(
    name = "my-lib-doc",
    deps = [":my-lib"],
  )
  ```

[haddock]: http://haskell-haddock.readthedocs.io/en/latest/
"""
