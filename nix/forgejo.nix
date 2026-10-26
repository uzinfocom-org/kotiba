{ mkDerivation, aeson, base, bytestring, conduit
, conduit-combinators, containers, fetchgit, filepath, generic-lens
, hspec, hspec-wai, http-api-data, http-client-tls, http-media
, http-types, lens, lib, monad-logger, mtl, named, optparse-generic
, path-pieces, safe-exceptions, servant, servant-client
, servant-client-core, servant-server, sop-core, stm, text, time
, transformers, uuid, vector, wai, wai-extra, warp
}:
mkDerivation {
  pname = "forgejo";
  version = "0.1.0.0";
  src = fetchgit {
    url = "https://github.com/uzinfocom-org/forgejo.git";
    sha256 = "0ndzp99byfdakcphy96wwfaly03cc9yghqd1rnmajgzyvbpvi297";
    rev = "4aa53ba869db02ee9a50c358e832407eec1897db";
    fetchSubmodules = true;
  };
  libraryHaskellDepends = [
    aeson base bytestring conduit conduit-combinators containers
    filepath generic-lens http-api-data http-client-tls http-media
    http-types lens monad-logger mtl named optparse-generic path-pieces
    safe-exceptions servant servant-client servant-client-core
    servant-server sop-core stm text time transformers uuid vector wai
    wai-extra warp
  ];
  testHaskellDepends = [ base hspec hspec-wai ];
  homepage = "https://github.com/uzinfocom-org/forgejo";
  license = lib.licenses.bsd3;
}
