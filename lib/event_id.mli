(** A deterministic id for one normalised activity, derived from chain data by the adapter
    ([fill:<trade id>:fee], [funding:<ms>:<coin>], ...), so that reading the same history
    twice gives the same ids and books each movement once. 1 to 90 characters from
    [A-Z a-z 0-9 _ - . : / @ +]: the ledger's id alphabet, short enough that
    [chain:<binding>:<event id>] fits a ledger idempotency key. *)

open! Core
include Short_id.S
