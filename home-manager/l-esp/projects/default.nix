{ outputs, ... }:
{
  imports = outputs.lib.enabledImportsRecursive ./.;
}
