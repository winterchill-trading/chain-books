(** Identifies one binding: an on-chain address (and its sub-accounts) that an
    organisation's books follow. It prefixes every account id and idempotency key the
    library builds, so it is short: 1 to 16 characters from [A-Z a-z 0-9 _ - .] (no [':'],
    which separates the parts of those ids). *)

open! Core
include Short_id.S
