_final: prev:
let
  warning = "certipy-ad local deviation is active; remove overlays/certipy-ad once nixpkgs fixes requests metadata.";

  pnameOf = dependency: dependency.pname or null;

  inputsOf =
    package:
    (package.dependencies or [ ])
    ++ (package.propagatedBuildInputs or [ ]);

  findByPname =
    pname: dependencies:
    let
      matches = builtins.filter (dependency: pnameOf dependency == pname) dependencies;
    in
    if matches == [ ] then null else builtins.head matches;

  getByPname =
    pname: dependencies:
    let
      dependency = findByPname pname dependencies;
    in
    if dependency == null then
      builtins.throw "Expected dependency '${pname}'"
    else
      dependency;

  replaceByPname =
    pname: replacement: dependencies:
    builtins.map (
      dependency:
      if pnameOf dependency == pname then
        replacement
      else
        dependency
    ) dependencies;

  relaxDeps =
    oldAttrs:
    if (oldAttrs.pythonRelaxDeps or false) == true then
      true
    else
      (oldAttrs.pythonRelaxDeps or [ ]) ++ [ "requests" ];

  patchCertipyAd =
    { package, impacket }:
    builtins.trace "WARNING: ${warning}" (
      package.overridePythonAttrs (oldAttrs: {
        pythonRelaxDeps = relaxDeps oldAttrs;
        dontCheckRuntimeDeps = true;

        preBuild = ''
          echo
          echo "WARNING: ${warning}"
          echo
        ''
        + (oldAttrs.preBuild or "");

        dependencies = replaceByPname "impacket" impacket (oldAttrs.dependencies or [ ]);

        propagatedBuildInputs = replaceByPname "impacket" impacket (
          oldAttrs.propagatedBuildInputs or [ ]
        );
      })
    );

  patchNetexec =
    package:
    package.overridePythonAttrs (
      oldAttrs:
      let
        netexecInputs = inputsOf oldAttrs;
        certipyAd = getByPname "certipy-ad" netexecInputs;
        directImpacket = findByPname "impacket" netexecInputs;
        bloodhoundPy = findByPname "bloodhound-py" netexecInputs;

        bloodhoundImpacket =
          if bloodhoundPy == null then
            null
          else
            findByPname "impacket" (inputsOf bloodhoundPy);

        impacket =
          if directImpacket != null then
            directImpacket
          else if bloodhoundImpacket != null then
            bloodhoundImpacket
          else
            builtins.throw "Expected netexec impacket dependency";

        patchedCertipyAd = patchCertipyAd {
          package = certipyAd;
          inherit impacket;
        };
      in
      {
        dependencies = replaceByPname "certipy-ad" patchedCertipyAd (oldAttrs.dependencies or [ ]);

        propagatedBuildInputs = replaceByPname "certipy-ad" patchedCertipyAd (
          oldAttrs.propagatedBuildInputs or [ ]
        );
      }
    );

  patchPython312Packages =
    packageSet:
    packageSet.overrideScope (_pythonFinal: pythonPrev: {
      certipy-ad = builtins.trace "WARNING: ${warning}" (
        pythonPrev.certipy-ad.overridePythonAttrs (oldAttrs: {
          pythonRelaxDeps = relaxDeps oldAttrs;
          dontCheckRuntimeDeps = true;

          preBuild = ''
            echo
            echo "WARNING: ${warning}"
            echo
          ''
          + (oldAttrs.preBuild or "");
        })
      );
    });
in
{
  python312Packages = patchPython312Packages prev.python312Packages;
  netexec = patchNetexec prev.netexec;
}
