{
  cpm ? null,
  compilerOut ? null,
  forwardingOut ? null,
  controlPlaneOut ? null,
}:

let
  candidate =
    if controlPlaneOut != null then
      controlPlaneOut
    else if cpm != null then
      cpm
    else if forwardingOut != null then
      forwardingOut
    else
      compilerOut;
in
if candidate == null then
  abort "renderer: CPM/control-plane input is required"
else
  candidate
