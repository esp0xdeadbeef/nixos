{ ... }:

{
  # The guest and its nested container share this state over 9p. A stable
  # identity avoids DynamicUser releasing nested model paths to nobody when
  # either Ollama instance stops.
  services.ollama = {
    user = "ollama";
    group = "ollama";
  };

  users = {
    users.ollama.uid = 992;
    groups.ollama.gid = 992;
  };
}
