{ mkDerivation, aeson, base, bytestring, conduit
, conduit-combinators, containers, directory, esqueleto, filepath
, forgejo, generic-lens, hspec, hspec-wai, http-api-data
, http-client-tls, http-media, http-types, lens, lib, monad-logger
, mtl, named, optparse-generic, path-pieces, persistent
, persistent-postgresql, persistent-records, random, resource-pool
, safe-exceptions, servant-client, servant-client-core
, servant-server, shower, stm, text, time, toml-parser
, transformers, typed-process, uuid, vector, wai, wai-extra, warp
}:
mkDerivation {
  pname = "kotiba";
  version = "0.1.0.0";
  src = ./..;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    aeson base bytestring conduit conduit-combinators containers
    directory esqueleto filepath forgejo generic-lens http-api-data
    http-client-tls http-media http-types lens monad-logger mtl named
    optparse-generic path-pieces persistent persistent-postgresql
    persistent-records random resource-pool safe-exceptions
    servant-client servant-client-core servant-server shower stm text
    time toml-parser transformers typed-process uuid vector wai
    wai-extra warp
  ];
  executableHaskellDepends = [ base ];
  testHaskellDepends = [ base hspec hspec-wai ];
  homepage = "https://kotiba.app.xinux.uz";
  license = lib.licenses.agpl3Plus;
  mainProgram = "kotiba";
}
