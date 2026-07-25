{
  description = "Dev-only inputs for bubblebox agent harnesses (hermes, pi).";

  inputs = {
    hermes-agent.url = "github:NousResearch/hermes-agent";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = _: { };
}
