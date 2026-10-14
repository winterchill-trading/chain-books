(** An on-chain account address: 1 to 44 letters and digits, which covers [0x]-prefixed
    EVM addresses (42 characters) and base58 addresses (up to 44). Kept as given: base58
    is case-sensitive, so normalising the case of EVM addresses is the adapter's job. *)

open! Core
include Short_id.S
