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
    sha256 = "1xyd1803gjbhhnm68a7znpjpj12sz3ba8lc7hx8shwyagp6dc54n";
    rev = "ee2d36db63b230aa6c200914f7e547e06db43bf3";
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
  testHaskellDepends = [
    aeson base hspec hspec-wai http-api-data http-client-tls mtl
    servant servant-client servant-server text time
  ];
  homepage = "https://github.com/uzinfocom-org/forgejo";
  license = lib.licenses.bsd3;
}
