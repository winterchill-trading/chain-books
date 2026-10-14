open! Core
module Time = Time_ns.Stable.Alternate_sexp.V1

module Kind = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Deposit
        | Withdrawal
        | Transfer_in
        | Transfer_out
        | Internal
        | Trade
        | Trade_fee
        | Funding
        | Builder_fee
        | Referral_reward
        | Vault_commission
        | Vault_deposit
        | Vault_withdrawal
        | Staking_reward
        | Staking
        | Other
      [@@deriving bin_io, sexp, compare, equal, hash, enumerate]
    end
  end

  include Stable.V1

  let to_string = function
    | Deposit -> "deposit"
    | Withdrawal -> "withdrawal"
    | Transfer_in -> "transfer_in"
    | Transfer_out -> "transfer_out"
    | Internal -> "internal"
    | Trade -> "trade"
    | Trade_fee -> "trade_fee"
    | Funding -> "funding"
    | Builder_fee -> "builder_fee"
    | Referral_reward -> "referral_reward"
    | Vault_commission -> "vault_commission"
    | Vault_deposit -> "vault_deposit"
    | Vault_withdrawal -> "vault_withdrawal"
    | Staking_reward -> "staking_reward"
    | Staking -> "staking"
    | Other -> "other"
  ;;

  let of_string_or_error s =
    match List.find all ~f:(fun k -> String.equal (to_string k) s) with
    | Some k -> Ok k
    | None -> Or_error.error_s [%message "unknown activity kind" s]
  ;;

  let quickcheck_generator = Quickcheck.Generator.of_list all
end

module Counter = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Location of Location.Stable.V1.t
        | Counterparty of Category.Stable.V1.t
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Fields = struct
  type t =
    { event_id : Event_id.Stable.V1.t
    ; kind : Kind.Stable.V1.t
    ; location : Location.Stable.V1.t
    ; amount : Money.Amount.Stable.V1.t
    ; occurred_at : Time.t
    ; counter : Counter.Stable.V1.t
    ; market : string option
    ; reference : string option
    ; client_key : string option
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Fields.t =
  { event_id : Event_id.t
  ; kind : Kind.t
  ; location : Location.t
  ; amount : Money.Amount.t
  ; occurred_at : Time_ns.Alternate_sexp.t
  ; counter : Counter.t
  ; market : string option
  ; reference : string option
  ; client_key : string option
  }
[@@deriving compare, equal]

let default_counterparty (kind : Kind.t) ~venue : Category.t option =
  match kind with
  | Deposit | Withdrawal -> Some Bridge
  | Transfer_in | Transfer_out -> Some External
  | Trade -> Some (if Venue.is_perp venue then Perp_pnl else Spot_clearing)
  | Trade_fee -> Some Trading_fees
  | Funding -> Some Funding
  | Builder_fee -> Some Builder_fees
  | Referral_reward -> Some Referral_rewards
  | Vault_commission -> Some Vault_commission
  | Vault_deposit | Vault_withdrawal -> Some Vaults
  | Staking_reward -> Some Staking_rewards
  | Other -> Some Other
  | Internal | Staking -> None
;;

let validate (t : t) =
  match t.counter with
  | Location l when Location.equal l t.location ->
    Or_error.error_s
      [%message
        "activity moves an asset from a location to itself"
          ~event_id:(t.event_id : Event_id.t)]
  | Location _ | Counterparty _ -> Ok t
;;

let create
  ~event_id
  ~kind
  ~location
  ~amount
  ~occurred_at
  ?counter
  ?market
  ?reference
  ?client_key
  ()
  =
  let%bind.Or_error counter =
    match counter with
    | Some c -> Ok c
    | None ->
      (match default_counterparty kind ~venue:location.Location.venue with
       | Some category -> Ok (Counter.Counterparty category)
       | None ->
         Or_error.error_s
           [%message
             "activity kind needs an explicit counter location"
               ~kind:(Kind.to_string kind)
               ~event_id:(event_id : Event_id.t)])
  in
  validate
    { event_id
    ; kind
    ; location
    ; amount
    ; occurred_at
    ; counter
    ; market
    ; reference
    ; client_key
    }
;;

let asset t = Money.Amount.currency t.amount
let sexp_of_t = Fields.sexp_of_t
let t_of_sexp sexp = Or_error.ok_exn (validate (Fields.t_of_sexp sexp))

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving compare, equal]

    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Fields)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable fields = Or_error.ok_exn (validate fields)
        end)
  end
end
