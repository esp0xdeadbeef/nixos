{ lib }:

{
  mkRouteSection =
    r:
    let
      via =
        if r ? via4 && r.via4 != null then
          r.via4
        else if r ? via6 && r.via6 != null then
          r.via6
        else
          null;
    in
    lib.filterAttrs (_: v: v != null) {
      Destination = r.dst;
      Gateway = via;
    };
}
