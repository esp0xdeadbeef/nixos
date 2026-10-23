_final: prev:
{
  # git 2.54.0's t0213-trace2-ancestry.sh fails in the Nix build sandbox.
  #
  #   t0213-trace2-ancestry.sh    Tests: 5 Failed: 4 (tests 2-5)
  #   Files=1028, Tests=29512     -- i.e. 29508 pass
  #
  # The test walks the real process tree via procinfo and asserts the exact
  # ancestor list, truncating it at the outermost `test-tool`:
  #
  #   s/\(.*test-tool\) .*/\1/
  #
  # It expects a bare `test-tool` in the chain.  Under `installCheck`, nixpkgs
  # runs the suite against the installed tree (GIT_TEST_INSTALLED=$out/bin), so
  # ancestors come from that environment rather than the bin-wrappers the test
  # was written against, the truncation matches nothing, and the comparison
  # fails.  Test 1 ("detect cmd_ancestry support") still passes, so procinfo
  # itself works -- only the environment-dependent ancestry string differs.
  # The test's own header acknowledges this coupling ("processes will also
  # report ancestors above test-tool that depend on the test runner
  # environment").
  #
  # This is the same class of failure nixpkgs already handles for 11 other git
  # tests in preInstallCheck's "Flaky tests" block (t0027, t1451, t5319, ...),
  # so use the same `disable_test` helper it defines rather than disabling
  # checks wholesale.  1027 of 1028 test files keep running.
  #
  # Nothing here depends on trace2 ancestry reporting.  Remove this once the
  # nixpkgs pin ships a git whose t0213 passes under installCheck.
  git = prev.git.overrideAttrs (old: {
    preInstallCheck = (old.preInstallCheck or "") + ''
      # nixpkgs' `disable_test` helper is declared in the original
      # preInstallCheck; re-added here so this snippet stands alone.
      function disable_test {
        local test=$1 pattern=$2
        if [ $# -eq 1 ]; then
          mv t/{,skip-}$test.sh || true
        else
          sed -i t/$test.sh \
            -e "/^\s*test_expect_.*$pattern/,/^\s*' *\$/{s/^/: #/}"
        fi
      }

      # t0213-trace2-ancestry.sh asserts an exact process-ancestry chain that
      # does not hold under GIT_TEST_INSTALLED=$out/bin in the sandbox.
      disable_test t0213-trace2-ancestry
    '';
  });
}
