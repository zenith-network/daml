# Copyright (c) 2025 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

load("@os_info//:os_info.bzl", "is_windows")
load("@build_environment//:configuration.bzl", "sdk_version")
load("@build_bazel_rules_nodejs//:index.bzl", "nodejs_binary")

def ts_docs(pkg_name, srcs, deps):
    "Macro for Typescript documentation generation with typedoc"

    nodejs_binary(
        name = "_typedoc_cli",
        data = deps + [
            "@language_support_js_deps//typedoc:typedoc",
        ],
        entry_point = {
            "@language_support_js_deps//:node_modules/typedoc": "dist/lib/cli.js",
        },
        visibility = ["//visibility:private"],
    ) if not is_windows else None

    native.genrule(
        name = "docs",
        outs = [pkg_name + "-docs.tar.gz"],
        srcs = [":README.md", ":tsconfig.json"] + srcs,
        tools = [
            ":_typedoc_cli",
            "//bazel_tools/sh:mktgz",
        ],
        cmd = """
          set -eou pipefail
          WORKDIR=$$(mktemp -d)
          trap "rm -rf $$WORKDIR" EXIT
          # Ensure the launcher can find basic shell tools on NixOS/Linux sandboxes.
          export PATH="/run/current-system/sw/bin:$$PATH"

          mkdir -p $$WORKDIR/docs
          $(execpath :_typedoc_cli) \
            --tsconfig $(location :tsconfig.json) \
            $(location :index.ts) \
            --out $$WORKDIR/docs

          # Replace version number in all files
          sed -i -e 's/0.0.0-SDKVERSION/{sdk_version}/' $$WORKDIR/**/*.html

          # We want the NPM version of the docs (i.e. the README.md) to point
          # back to our own documentation, but here we're creating our local
          # copy and that one shouldn't link to itself.
          sed -i -e '/START_BACKLINK/,/END_BACKLINK/d' $$WORKDIR/docs/index.html

          OUT=$$PWD/$@
          MKTGZ=$$PWD/$(execpath //bazel_tools/sh:mktgz)
          cd $$WORKDIR
          $$MKTGZ $$OUT -h docs
        """.format(sdk_version = sdk_version),
        visibility = ["//visibility:public"],
    ) if not is_windows else None
