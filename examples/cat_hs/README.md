# cat_hs - A rules_haskell Example Project

This project re-implements a subset of the `cat` command-line tool in
Haskell. It serves as an example of a project built using
the [Bazel][bazel] build system, using [rules_haskell][rules_haskell]
to define the Haskell build, including rules that wrap Cabal to build
third-party dependencies downloadable from Hackage, and
using [rules_nixpkgs][rules_nixpkgs] and [Nix][nix] to manage system
dependencies.

[bazel]: https://bazel.build/
[rules_haskell]: https://haskell.build/
[rules_nixpkgs]: https://github.com/tweag/rules_nixpkgs
[nix]: https://nixos.org/nix/

## Prerequisites

You need to install the [Nix package manager][nix]. All further dependencies
will be managed using Nix.

## Instructions

To build the package execute the following command *in the `examples/`
directory*:

```
$ nix-shell --pure --run "bazel build //cat_hs/..."
```

To run the tests execute the following command.

```
$ nix-shell --pure --run "bazel test //cat_hs/..."
```

To run the executable enter the following commands.

```
$ nix-shell --pure --run "bazel run //cat_hs/exec/cat_hs -- -h"
$ nix-shell --pure --run "bazel run //cat_hs/exec/cat_hs -- $PWD/README.md"
```
