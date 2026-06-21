{
  description = "Dev-only inputs for bubblebox agent harnesses (hermes, pi).";

  inputs = {
    hermes-agent.url = "github:NousResearch/hermes-agent";
    pi-mono = {
      url = "github:badlogic/pi-mono";
      flake = false;
    };
  };

  outputs = _: { };
}
