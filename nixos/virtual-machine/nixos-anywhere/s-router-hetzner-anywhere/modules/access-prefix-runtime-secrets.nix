{ nebulaRenderer
, containers
, runtimeSecretsDir
, secretNames
,
}:
nebulaRenderer.buildRuntimeSecretMounts {
  inherit containers runtimeSecretsDir secretNames;
}
