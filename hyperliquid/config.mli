(** What the Hyperliquid adapter needs besides the records: the account being read, the
    other addresses of the binding (so transfers between them are internal), and how
    venue token names map to currencies. *)

open! Core

(** How referral and builder rewards are booked. *)
module Rewards : sig
  type t =
    | On_claim
    (** income when claimed: a claim books [referral_reward] income at the claim
        venue. Use this when builder fills are not booked. *)
    | Accrued
    (** builder fills are booked as income to the [rewards] venue as they happen, and a
        claim moves the claimed amount from [rewards] to the claim venue *)
  [@@deriving sexp, compare, equal]
end

type t =
  { address : Hl_protocol.Address.t (** the account whose records are normalised *)
  ; binding : Hl_protocol.Address.t list (** every address of the binding *)
  ; tokens : Money.Currency.t String.Map.t (** venue token name to currency *)
  ; spot_pairs : (string * string) String.Map.t
  (** spot coin ([@107], [PURR/USDC]) to its base and quote token names *)
  ; dex_collateral : Money.Currency.t String.Map.t
  (** a perpetuals dex's margin currency, when not USDC *)
  ; rewards : Rewards.t
  ; claim_venue : Chain_books.Venue.t (** where claimed rewards are credited *)
  }
[@@deriving sexp_of]

(** [binding] defaults to [[address]] (and always includes it); [tokens] to [USDC] and
    [HYPE] (more are added, not replaced); [rewards] to [On_claim]; [claim_venue] to
    [perp]. *)
val create
  :  ?binding:Hl_protocol.Address.t list
  -> ?tokens:(string * Money.Currency.t) list
  -> ?spot_pairs:(string * (string * string)) list
  -> ?dex_collateral:(string * Money.Currency.t) list
  -> ?rewards:Rewards.t
  -> ?claim_venue:Chain_books.Venue.t
  -> Hl_protocol.Address.t
  -> t

(** Whether an address belongs to the binding. *)
val is_bound : t -> Hl_protocol.Address.t -> bool

(** The currency of a token name, if the books follow it. *)
val token : t -> string -> Money.Currency.t option

(** The margin currency of a perpetuals venue. *)
val collateral : t -> Chain_books.Venue.t -> Money.Currency.t
