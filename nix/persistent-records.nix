{ mkDerivation, base, data-default, fetchgit, lib, path-pieces
, persistent, persistent-sqlite, template-haskell, text, uuid
}:
mkDerivation {
  pname = "persistent-records";
  version = "0.1.0.0";
  src = fetchgit {
    url = "https://github.com/lambdajon/persistent-records.git";
    sha256 = "1irc5167imfmdlcj3hg99bgwynbiz2wpadc3r9421grjvqxkxwmh";
    rev = "36ae47763050f60d4066afa2ea3d1425df86ede2";
    fetchSubmodules = true;
  };
  libraryHaskellDepends = [
    base data-default persistent template-haskell
  ];
  testHaskellDepends = [
    base data-default path-pieces persistent persistent-sqlite text
    uuid
  ];
  homepage = "https://github.com/lambdajon/persistent-records";
  description = "Generate record types and mappers from Persistent entities";
  license = lib.licenses.bsd3;
}
