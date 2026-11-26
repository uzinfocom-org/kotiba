flake:
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "kotiba";

  nodes.machine = { ... }: {
    imports = [ flake.nixosModules.default ];

    services.kotiba = {
      enable = true;
      createDatabaseLocally = true;
      forgejoUrl = "git.oss.uzinfocom.uz";

      orgs.testorg = {
        webhookSecretFile =
          "${pkgs.writeText "webhook-secret" "fake-webhook-secret"}";
        bot = {
          login = "support";
          frId = 8;
          tokenFile = "${pkgs.writeText "token" "fake-token-for-testing"}";
          name = "John Doe";
          email = "johndoe@mail.com";
        };
      };
    };
    system.stateVersion = "25.05";
  };

  # disable only when working on testScript
  skipTypeCheck = true;

  testScript = builtins.readFile ./test.py;
}
