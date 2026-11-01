#!/usr/bin/env python3
"""Splice the 12 tree-sitter SPM packages into the Xcode project, mirroring how Sparkle is wired,
scoped to the direct macOS app target's Frameworks phase. Idempotent: refuses if already applied.

Replay tool for the fork port — see docs/fork/Fork-Port-Manifest.md. Run from the repo root:
    python3 scripts/fork/apply-treesitter-spm.py
then `plutil -lint "Neon Vision Editor.xcodeproj/project.pbxproj"` and build.

The TreeSitterHighlighter.swift `#if canImport` guard keeps the engine inert in targets that do not
link the grammars (App Clip / Share Extension), so no synchronized-group exceptions are required.
"""
import sys
import pathlib

PBX = pathlib.Path("Neon Vision Editor.xcodeproj/project.pbxproj")

# productName, build-file suffix, product-ref suffix, package-ref suffix, repoURL, requirement body.
# css/js/python pinned exact: 0.24+ manifests compute sources via a relative fileExists('src/scanner.c')
# that resolves wrong under SwiftPM, dropping scanner.c and breaking the external-scanner link.
PKGS = [
    ("SwiftTreeSitter",      "0011", "0001", "0003", "https://github.com/ChimeHQ/SwiftTreeSitter",        "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.9.0;"),
    ("TreeSitterHTML",       "0012", "0002", "0013", "https://github.com/tree-sitter/tree-sitter-html",       "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.23.2;"),
    ("TreeSitterCSS",        "B001", "C001", "D001", "https://github.com/tree-sitter/tree-sitter-css",        "kind = exactVersion;\n\t\t\t\tversion = 0.23.2;"),
    ("TreeSitterJSON",       "B002", "C002", "D002", "https://github.com/tree-sitter/tree-sitter-json",       "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.24.8;"),
    ("TreeSitterJavaScript", "B003", "C003", "D003", "https://github.com/tree-sitter/tree-sitter-javascript", "kind = exactVersion;\n\t\t\t\tversion = 0.23.1;"),
    ("TreeSitterPython",     "B004", "C004", "D004", "https://github.com/tree-sitter/tree-sitter-python",     "kind = exactVersion;\n\t\t\t\tversion = 0.23.6;"),
    ("TreeSitterC",          "B005", "C005", "D005", "https://github.com/tree-sitter/tree-sitter-c",          "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.24.2;"),
    ("TreeSitterBash",       "B006", "C006", "D006", "https://github.com/tree-sitter/tree-sitter-bash",       "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.25.1;"),
    ("TreeSitterGo",         "B007", "C007", "D007", "https://github.com/tree-sitter/tree-sitter-go",         "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.25.0;"),
    ("TreeSitterRuby",       "B008", "C008", "D008", "https://github.com/tree-sitter/tree-sitter-ruby",       "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.23.1;"),
    ("TreeSitterRust",       "B009", "C009", "D009", "https://github.com/tree-sitter/tree-sitter-rust",       "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.24.2;"),
    ("TreeSitterJava",       "B010", "C010", "D010", "https://github.com/tree-sitter/tree-sitter-java",       "kind = upToNextMinorVersion;\n\t\t\t\tminimumVersion = 0.23.5;"),
]

# Anchors in the Sparkle wiring to insert relative to (all unique in the pbxproj).
BUILDFILE_ANCHOR = "B4E89D5A4B8248FBB1F8E3C1 /* Sparkle in Frameworks */ = {isa = PBXBuildFile"
FRAMEWORKS_ANCHOR = "\t\t\t\tB4E89D5A4B8248FBB1F8E3C1 /* Sparkle in Frameworks */,"
PRODDEP_LIST_ANCHOR = "\t\t\t\tB4E89D5B4B8248FBB1F8E3C1 /* Sparkle */,"
PKGREF_LIST_ANCHOR = '\t\t\t\tB4E89D5C4B8248FBB1F8E3C1 /* XCRemoteSwiftPackageReference "Sparkle" */,'
PRODDEP_SECTION_END = "/* End XCSwiftPackageProductDependency section */"
PKGREF_SECTION_END = "/* End XCRemoteSwiftPackageReference section */"


def full(suffix: str) -> str:
    """24-char sentinel UUID: 'A1B2C3D4' + zero padding + 4-char suffix."""
    return "A1B2C3D4" + "0" * (24 - 8 - len(suffix)) + suffix


def insert_after(txt: str, anchor: str, block: str) -> str:
    i = txt.index(anchor)
    j = txt.index("\n", i) + 1
    return txt[:j] + block + "\n" + txt[j:]


def insert_before(txt: str, anchor: str, block: str) -> str:
    i = txt.index(anchor)
    return txt[:i] + block + "\n" + txt[i:]


def main() -> int:
    text = PBX.read_text()
    if "A1B2C3D4" in text:
        print("sentinel UUIDs already present - nothing to do (already applied)")
        return 0

    buildfiles, fw_refs, prod_refs, pkg_refs, prod_stanzas, pkg_stanzas = [], [], [], [], [], []
    for name, b, c, d, url, req in PKGS:
        bid, cid, did = full(b), full(c), full(d)
        repo = url.rsplit("/", 1)[1]
        buildfiles.append(f"\t\t{bid} /* {name} in Frameworks */ = {{isa = PBXBuildFile; productRef = {cid} /* {name} */; }};")
        fw_refs.append(f"\t\t\t\t{bid} /* {name} in Frameworks */,")
        prod_refs.append(f"\t\t\t\t{cid} /* {name} */,")
        pkg_refs.append(f'\t\t\t\t{did} /* XCRemoteSwiftPackageReference "{repo}" */,')
        prod_stanzas.append(
            f'\t\t{cid} /* {name} */ = {{\n'
            f'\t\t\tisa = XCSwiftPackageProductDependency;\n'
            f'\t\t\tpackage = {did} /* XCRemoteSwiftPackageReference "{repo}" */;\n'
            f'\t\t\tproductName = {name};\n\t\t}};'
        )
        pkg_stanzas.append(
            f'\t\t{did} /* XCRemoteSwiftPackageReference "{repo}" */ = {{\n'
            f'\t\t\tisa = XCRemoteSwiftPackageReference;\n'
            f'\t\t\trepositoryURL = "{url}";\n'
            f'\t\t\trequirement = {{\n\t\t\t\t{req}\n\t\t\t}};\n\t\t}};'
        )

    text = insert_after(text, BUILDFILE_ANCHOR, "\n".join(buildfiles))
    text = insert_after(text, FRAMEWORKS_ANCHOR, "\n".join(fw_refs))
    text = insert_after(text, PRODDEP_LIST_ANCHOR, "\n".join(prod_refs))
    text = insert_after(text, PKGREF_LIST_ANCHOR, "\n".join(pkg_refs))
    text = insert_before(text, PRODDEP_SECTION_END, "\n".join(prod_stanzas))
    text = insert_before(text, PKGREF_SECTION_END, "\n".join(pkg_stanzas))

    PBX.write_text(text)
    print(f"spliced {len(PKGS)} packages into {PBX}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
