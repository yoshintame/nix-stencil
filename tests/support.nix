{ lib }:
eval: rec {
  failedMessages = config: map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
  rejects = fragment: modules: lib.any (lib.hasInfix fragment) (failedMessages (eval modules));
  warns = fragment: modules: lib.any (lib.hasInfix fragment) (eval modules).warnings;
}
