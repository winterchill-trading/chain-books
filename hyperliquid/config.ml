open! Core

module Rewards = struct
  type t =
    | On_claim
    | Accrued
  [@@deriving sexp, compare, equal]
end

type t =
  { address : Hl_protocol.Address.t
  ; binding : Hl_protocol.Address.t list
  ; tokens : Money.Currency.t String.Map.t
  ; spot_pairs : (string * string) String.Map.t
  ; dex_collateral : Money.Currency.t String.Map.t
  ; rewards : Rewards.t
  ; claim_venue : Chain_books.Venue.t
  }
[@@deriving sexp_of]

let create
  ?(binding = [])
  ?(tokens = [])
  ?(spot_pairs = [])
  ?(dex_collateral = [])
  ?(rewards = Rewards.On_claim)
  ?(claim_venue = Chain_books.Venue.Perp)
  address
  =
  let defaults = [ "USDC", Money.Currency.usdc; "HYPE", Chain_books.Assets.hype ] in
  { address
  ; binding =
      List.dedup_and_sort (address :: binding) ~compare:Hl_protocol.Address.compare
  ; tokens = String.Map.of_alist_reduce (defaults @ tokens) ~f:(fun _ later -> later)
  ; spot_pairs = String.Map.of_alist_reduce spot_pairs ~f:(fun _ later -> later)
  ; dex_collateral = String.Map.of_alist_reduce dex_collateral ~f:(fun _ later -> later)
  ; rewards
  ; claim_venue
  }
;;

let is_bound t a = List.mem t.binding a ~equal:Hl_protocol.Address.equal
let token t name = Map.find t.tokens name

let collateral t (venue : Chain_books.Venue.t) =
  match venue with
  | Perp_dex dex ->
    Option.value (Map.find t.dex_collateral dex) ~default:Money.Currency.usdc
  | Perp | Spot | Rewards | Vault | Staking -> Money.Currency.usdc
;;
