_final: prev:
let
  nixComponents = prev.nixVersions.nixComponents_2_34;
in
{
  # Build nix's manual as manpages-only.
  #
  # nixpkgs' modular manual derivation
  # (pkgs/tools/package-management/nix/modular/doc/manual/package.nix) is a
  # thin wrapper that runs upstream nix's meson build, and it hardcodes
  # `mdbook` in nativeBuildInputs.  Upstream meson only needs mdbook for the
  # HTML manual:
  #
  #   # doc/manual/meson.build
  #   if get_option('html-manual')
  #     mdbook = find_program('mdbook', native : true)
  #   endif
  #
  # so passing -Dhtml-manual=false both skips the HTML target and makes the
  # mdbook input unnecessary.
  #
  # Why this matters: mdbook 0.5.2 in this pin fails its own renderer tests
  # (renderer::missing_renderer, renderer::missing_optional_not_fatal -- 5
  # failed / 104 passed) and the failing path is not substitutable from
  # cache.nixos.org.  Any host that must build `nix` locally therefore dies in
  # nix-manual -> nix -> nixos-rebuild-ng.  Nothing here consumes nix's HTML
  # manual: `documentation.man` is even disabled on l-esp and l-envil, and
  # nix-everything only symlinks $doc/$man for the store closure.
  #
  # Deliberately NOT done here:
  #  - no overlay on mdbook itself (that would paper over its testsuite while
  #    still building an HTML manual nobody reads);
  #  - no patch file.  Upstream already exposes `html-manual` as a meson
  #    option, so this is an invocation change, not a source change.
  #
  # Revisit once the nixpkgs pin exposes upstream's
  # `nix-manual-manpages-only` component (the nix repo has since grown a
  # `buildHtmlManual` flag the modular copy lacks).
  nixVersions = prev.nixVersions // {
    nixComponents_2_34 = nixComponents.overrideScope (
      _componentFinal: componentPrev: {
        nix-manual = componentPrev.nix-manual.overrideAttrs (old: {
          nativeBuildInputs = builtins.filter
            (
              x: (x.pname or "") != "mdbook"
            )
            (old.nativeBuildInputs or [ ]);
          mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dhtml-manual=false" ];
        });
      }
    );
  };
}
