{
  baseContainer ? null,
}:
{
  b-router-access-hostile =
    (if builtins.isAttrs baseContainer then baseContainer else { })
    // {
      bindMounts =
        (if builtins.isAttrs baseContainer && builtins.isAttrs (baseContainer.bindMounts or null) then
          baseContainer.bindMounts
        else
          { })
        // {
          "/run/secrets/subnet-ipv6" = {
            hostPath = "/run/secrets/subnet-ipv6";
            isReadOnly = true;
          };
        };
    };
}
