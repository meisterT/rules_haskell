load("//hazel_base_repository:hazel_base_repository.bzl",
     "hazel_base_repository",
     "symlink_and_invoke_hazel")

def _hazel_paths_module_impl(ctx):
  ctx.actions.expand_template(
      template=ctx.file._template,
      output=ctx.outputs.module,
      substitutions={
          "{MODULE_NAME}": ctx.label.name,
          "{VERSION_NUMBER_LIST}": str(ctx.attr.version_number),
          "{DATADIR_IMPL}": "return \"\"",
      })

hazel_paths_module = rule(
    implementation = _hazel_paths_module_impl,
    attrs={
        "version_number": attr.int_list(mandatory=True),
        "_template": attr.label(
            default=Label("//:paths-template.hs"),
            allow_files=True,
            single_file=True),
    },
    outputs={"module": "hazel.paths/%{name}.hs"})

def _hazel_writefile_impl(ctx):
  ctx.actions.write(ctx.outputs.out, ctx.attr.contents, is_executable=False)

hazel_writefile = rule(
    implementation = _hazel_writefile_impl,
    attrs = {
        "contents": attr.string(mandatory=True),
        "output": attr.string(mandatory=True),
    },
    outputs={"out": "%{output}"})

def _hazel_symlink_impl(ctx):
  ctx.actions.run(
      outputs=[ctx.outputs.out],
      inputs=[ctx.file.src],
      executable="ln",
      arguments=["-s",
                  "/".join([".."] * len(ctx.outputs.out.dirname.split("/")))
                    + "/" + ctx.file.src.path,
                  ctx.outputs.out.path])

hazel_symlink = rule(
    implementation = _hazel_symlink_impl,
    attrs = {
        "src": attr.label(mandatory=True, allow_files=True, single_file=True),
        "out": attr.string(mandatory=True),
    },
    outputs={"out": "%{out}"})

def _cabal_haskell_package_impl(ctx):
  pkg = "{}-{}".format(ctx.attr.package_name, ctx.attr.package_version)
  url = "https://hackage.haskell.org/package/{}.tar.gz".format(pkg)
  # If the SHA is wrong, the error message is very unhelpful:
  # https://github.com/bazelbuild/bazel/issues/3709
  # As a workaround, we compute it manually if it's not set (and then fail
  # this rule).
  if not ctx.attr.sha256:
    ctx.download(url=url, output="tar")
    res = ctx.execute(["openssl", "sha", "-sha256", "tar"])
    fail("Missing expected attribute \"sha256\" for {}; computed {}".format(pkg, res.stdout + res.stderr))

  ctx.download_and_extract(
      url=url,
      stripPrefix=ctx.attr.package_name + "-" + ctx.attr.package_version,
      sha256=ctx.attr.sha256,
      output="")

  symlink_and_invoke_hazel(ctx, ctx.attr.hazel_base_repo_name, ctx.attr.package_name + ".cabal", "BUILD")


_cabal_haskell_package = repository_rule(
    implementation=_cabal_haskell_package_impl,
    attrs={
        "package_name": attr.string(mandatory=True),
        "package_version": attr.string(mandatory=True),
        "hazel_base_repo_name": attr.string(mandatory=True),
        "sha256": attr.string(mandatory=True),
    })

def _all_hazel_packages_impl(ctx):
  ctx.file("BUILD", """
filegroup(
    name = "all-package-files",
    srcs = [{}],
)
           """.format(",".join(["\"{}\"".format(f) for f in ctx.attr.files])),
          executable=False)

_all_hazel_packages = repository_rule(
    implementation=_all_hazel_packages_impl,
    attrs={
        "files": attr.label_list(mandatory=True),
    })


def hazel_repositories(prebuilt_dependencies, packages):
  """Generates external dependencies for a set of Haskell packages.

  This macro should be invoked in the WORKSPACE.  It generates a set of
  external dependencies corresponding to the given packages:
  - @hazel_base_repository: The compiled "hazel" Haskell binary, along with
    support files.
  - @haskell_{package}: A build of the given Cabal package, one per entry
    of the "packages" argument.  (Note that Bazel only builds these
    on-demand when needed by other rules.)  This repository automatically
    downloads the package's Cabal distribution from Hackage and parses the
    .cabal file to generate BUILD rules.
  - @all_hazel_packages: A repository depending on each package.  Useful for
    measuring our coverage of the full package set.

  Args:
    prebuilt_dependencies: A dict mapping Haskell package names to version
      numbers.  These packages are assumed to be provided by GHC, and we do
      not generate repositories for them.
    packages: A dict mapping strings to structs, where each struct has two fields:
      - version: A version string
      - sha256: A hex-encoded SHA of the Cabal distribution (*.tar.gz).
  """
  hazel_base_repo_name = "hazel_base_repository"
  hazel_base_repository(
      name = hazel_base_repo_name,
      # TODO: don't hard-code this in
      ghc="@ghc//:bin/ghc",
      versions = [n + "-" + packages[n].version for n in packages],
      prebuilt_dependencies = [n + "-" + prebuilt_dependencies[n]
                               for n in prebuilt_dependencies],
  )
  for p in packages:
    _cabal_haskell_package(
        name = "haskell_" + p,
        package_name = p,
        package_version = packages[p].version,
        sha256 = packages[p].sha256 if hasattr(packages[p], "sha256") else None,
        hazel_base_repo_name = hazel_base_repo_name,
    )

  _all_hazel_packages(
      name = "all_hazel_packages",
      files = ["@haskell_{}//:files".format(p) for p in packages])

def hazel_library(name):
  """Returns the label of the haskell_library rule for the given package."""
  return "@haskell_{}//:lib-{}".format(name,name)