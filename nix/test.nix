flake:
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "kotiba";

  nodes.machine = { ... }: {
    imports = [ flake.nixosModules.default ];

    services.kotiba = {
      enable = true;
      bots = [{
        login = "support";
        frId = 8;
      }];

      createDatabaseLocally = true;
      forgejoToken = "${pkgs.writeText "token" ''
        fake-token-for-testing
      ''}";

      forgejoUrl = "git.oss.uzinfocom.uz";
      identityName = "John Doe";
      identityEmail = "johndoe@mail.com";
    };
    system.stateVersion = "25.05";
  };

  # disable only when working on testScript
  skipTypeCheck = true;

  testScript = builtins.readFile ./test.py;
}
