{ lib }:

{
  firstNonNull =
    xs:
    let
      filtered = lib.filter (x: x != null) xs;
    in
    if filtered == [ ] then null else lib.head filtered;
}
