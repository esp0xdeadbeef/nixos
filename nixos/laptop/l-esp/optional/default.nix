{ self, ... }:
{
  imports = self.lib.enabledImports ./.;
}
