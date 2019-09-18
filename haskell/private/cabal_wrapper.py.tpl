#!/usr/bin/env python3

# cabal_wrapper.py <PKG_NAME> <SETUP_PATH> <PKG_DIR> <PACKAGE_DB_PATH> [EXTRA_ARGS...] -- [PATH_ARGS...]
#
# This wrapper calls Cabal's configure/build/install steps one big
# action so that we don't have to track all inputs explicitly between
# steps.
#
# PKG_NAME: Package ID of the resulting package.
# SETUP_PATH: Path to Setup.hs
# PKG_DIR: Directory containing the Cabal file
# PACKAGE_DB_PATH: Output package DB path.
# EXTRA_ARGS: Additional args to Setup.hs configure.
# PATH_ARGS: Additional args to Setup.hs configure where paths need to be prefixed with execroot.

from glob import glob
import os
import os.path
import re
import shlex
import subprocess
import sys
import tempfile

debug = False

def run(cmd, *args, **kwargs):
    if debug:
        print("+ " + " ".join([shlex.quote(arg) for arg in cmd]), file=sys.stderr)
        sys.stderr.flush()
    subprocess.run(cmd, *args, **kwargs)

def canonicalize_path(path):
    return ":".join([
        os.path.abspath(entry)
        for entry in path.split(":")
        if entry != ""
    ])

# Remove any relative entries, because we'll be changing CWD shortly.
os.environ["LD_LIBRARY_PATH"] = canonicalize_path(os.getenv("LD_LIBRARY_PATH", ""))
os.environ["LIBRARY_PATH"] = canonicalize_path(os.getenv("LIBRARY_PATH", ""))
os.environ["PATH"] = canonicalize_path(os.getenv("PATH", ""))

name = sys.argv.pop(1)
execroot = os.getcwd()
setup = os.path.join(execroot, sys.argv.pop(1))
srcdir = os.path.join(execroot, sys.argv.pop(1))
# By definition (see ghc-pkg source code).
pkgroot = os.path.realpath(os.path.join(execroot, os.path.dirname(sys.argv.pop(1))))
libdir = os.path.join(pkgroot, "iface")
dynlibdir = os.path.join(pkgroot, "lib")
bindir = os.path.join(pkgroot, "bin")
datadir = os.path.join(pkgroot, "data")
package_database = os.path.join(pkgroot, "package.conf.d")

runghc = os.path.join(execroot, r"%{runghc}")
ghc = os.path.join(execroot, r"%{ghc}")
ghc_pkg = os.path.join(execroot, r"%{ghc_pkg}")

extra_args = []
current_arg = sys.argv.pop(1)
while current_arg != "--":
    extra_args.append(current_arg)
    current_arg = sys.argv.pop(1)
del current_arg

path_args = sys.argv[1:]

ar = os.path.realpath("%{ar}")
strip = os.path.realpath("%{strip}")

def recache_db():
    run([ghc_pkg, "recache", "--package-db=" + package_database])

recache_db()

with tempfile.TemporaryDirectory() as distdir:
    enable_relocatable_flags = ["--enable-relocatable"] \
            if "%{is_windows}" != "True" else []

    old_cwd = os.getcwd()
    os.chdir(srcdir)
    os.putenv("HOME", "/var/empty")
    run([runghc, setup, "configure", \
        "--verbose=0", \
        "--user", \
        "--with-compiler=" + ghc,
        "--with-hc-pkg=" + ghc_pkg,
        "--with-ar=" + ar,
        "--with-strip=" + strip,
        "--enable-deterministic", \
        ] +
        enable_relocatable_flags + \
        [ \
        "--builddir=" + distdir, \
        "--prefix=" + pkgroot, \
        "--libdir=" + libdir, \
        "--dynlibdir=" + dynlibdir, \
        "--libsubdir=", \
        "--bindir=" + bindir, \
        "--datadir=" + datadir, \
        "--package-db=clear", \
        "--package-db=global", \
        ] + \
        extra_args + \
        [ arg.replace("=", "=" + execroot + "/") for arg in path_args ] + \
        [ "--package-db=" + package_database ], # This arg must come last.
        )
    run([runghc, setup, "build", "--verbose=0", "--builddir=" + distdir])
    run([runghc, setup, "install", "--verbose=0", "--builddir=" + distdir])
    os.chdir(old_cwd)

# XXX Cabal has a bizarre layout that we can't control directly. It
# confounds the library-dir and the import-dir (but not the
# dynamic-library-dir). That's pretty annoying, because Bazel won't
# allow overlap in the path to the interface files directory and the
# path to the static library. So we move the static library elsewhere
# and patch the .conf file accordingly.
#
# There were plans for controlling this, but they died. See:
# https://github.com/haskell/cabal/pull/3982#issuecomment-254038734
libraries=glob(os.path.join(libdir, "libHS*.a"))
package_conf_file = os.path.join(package_database, name + ".conf")

def make_relocatable_paths(line):
    line = re.sub("library-dirs:.*", "library-dirs: ${pkgroot}/lib", line)

    def make_relative_to_pkgroot(matchobj):
        abspath=matchobj.group(0)
        return os.path.join("${pkgroot}", os.path.relpath(abspath, start=pkgroot))

    # The $execroot is an absolute path and should not leak into the output.
    # Replace each ocurrence of execroot by a path relative to ${pkgroot}.
    line = re.sub(execroot + '\S*', make_relative_to_pkgroot, line)
    return line

if libraries != [] and os.path.isfile(package_conf_file):
    for lib in libraries:
        os.rename(lib, os.path.join(dynlibdir, os.path.basename(lib)))

    tmp_package_conf_file = package_conf_file + ".tmp"
    with open(package_conf_file, 'r') as package_conf:
        with open(tmp_package_conf_file, 'w') as tmp_package_conf:
            for line in package_conf.readlines():
                print(make_relocatable_paths(line), file=tmp_package_conf)
    os.remove(package_conf_file)
    os.rename(tmp_package_conf_file, package_conf_file)
    recache_db()
