# rules_haskell

[![CircleCI](https://circleci.com/gh/tweag/rules_haskell.svg?style=svg)](https://circleci.com/gh/tweag/rules_haskell)

Haskell rules for the [Bazel build tool][bazel].

[bazel]: https://bazel.build/

## Rules

* [haskell_binary](#haskell_binary)
* [haskell_library](#haskell_library)

## Setup

Add the following to your `WORKSPACE` file, and select a `$COMMIT` accordingly.

```bzl
http_archive(
    name = "io_tweag_rules_haskell",
    strip_prefix = "rules_haskell-$COMMIT",
    urls = ["https://github.com/tweag/rules_haskell/archive/$COMMIT.tar.gz"],
)
```

and this to your BUILD files.

```bzl
load("@io_tweag_rules_haskell//haskell:haskell.bzl", "haskell_binary", "haskell_library")
```

## Rules

### haskell_binary

Generates a Haskell binary.

```bzl
haskell_binary(name, srcs, deps)
```

#### Example

```bzl
haskell_binary(
    name = "main",
    srcs = ["Main.hs", "Other.hs"],
    deps = ["//lib:some_lib"]
)
```

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>name</code></td>
      <td>
        <p><code>Name, required</code></p>
        <p>A unique name for this target</p>
      </td>
    </tr>
    <tr>
      <td><code>srcs</code></td>
      <td>
        <p><code>List of labels, required</code></p>
        <p>List of Haskell <code>.hs</code> source files used to build the binary</p>
      </td>
    </tr>
    <tr>
      <td><code>deps</code></td>
      <td>
        <p><code>List of labels, required</code></p>
        <p>List of other Haskell libraries to be linked to this target</p>
      </td>
    </tr>
  </tbody>
</table>

### haskell_library

Generates a Haskell library.

```bzl
haskell_library(name, srcs, deps)
```

#### Example

```bzl
haskell_library(
    name = 'hello_lib',
    srcs = glob(['hello_lib/**/*.hs']),
    deps = ["//hello_sublib:lib"]
)
```

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>name</code></td>
      <td>
        <p><code>Name, required</code></p>
        <p>A unique name for this target</p>
      </td>
    </tr>
    <tr>
      <td><code>srcs</code></td>
      <td>
        <p><code>List of labels, required</code></p>
        <p>List of Haskell <code>.hs</code> source files used to build the library</p>
      </td>
    </tr>
    <tr>
      <td><code>deps</code></td>
      <td>
        <p><code>List of labels, required</code></p>
        <p>List of other Haskell libraries to be linked to this target</p>
      </td>
    </tr>
  </tbody>
</table>
