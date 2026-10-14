open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Bridge
      | External
      | Spot_clearing
      | Perp_pnl
      | Trading_fees
      | Funding
      | Builder_fees
      | Referral_rewards
      | Vault_commission
      | Vaults
      | Staking_rewards
      | Opening_balance
      | Other
      | Custom of
          { name : string
          ; kind : Ledger.Account_kind.Stable.V1.t
          }
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

module T = struct
  type t = Stable.V1.t =
    | Bridge
    | External
    | Spot_clearing
    | Perp_pnl
    | Trading_fees
    | Funding
    | Builder_fees
    | Referral_rewards
    | Vault_commission
    | Vaults
    | Staking_rewards
    | Opening_balance
    | Other
    | Custom of
        { name : string
        ; kind : Ledger.Account_kind.t
        }
  [@@deriving sexp, compare, equal, hash]
end

include T

let all_builtin =
  [ Bridge
  ; External
  ; Spot_clearing
  ; Perp_pnl
  ; Trading_fees
  ; Funding
  ; Builder_fees
  ; Referral_rewards
  ; Vault_commission
  ; Vaults
  ; Staking_rewards
  ; Opening_balance
  ; Other
  ]
;;

let to_string = function
  | Bridge -> "bridge"
  | External -> "external"
  | Spot_clearing -> "spot_clearing"
  | Perp_pnl -> "perp_pnl"
  | Trading_fees -> "trading_fees"
  | Funding -> "funding"
  | Builder_fees -> "builder_fees"
  | Referral_rewards -> "referral_rewards"
  | Vault_commission -> "vault_commission"
  | Vaults -> "vaults"
  | Staking_rewards -> "staking_rewards"
  | Opening_balance -> "opening_balance"
  | Other -> "other"
  | Custom { name; kind = _ } -> name
;;

let custom ~name ~kind =
  let ok_char c = Char.is_lowercase c || Char.is_digit c || Char.equal c '_' in
  let builtin_clash =
    List.exists all_builtin ~f:(fun c -> String.equal (to_string c) name)
  in
  if String.length name < 1
     || String.length name > 24
     || not (String.for_all name ~f:ok_char)
  then Or_error.error_s [%message "invalid custom category name" name]
  else if builtin_clash
  then Or_error.error_s [%message "custom category clashes with a built-in one" name]
  else Ok (Custom { name; kind })
;;

let account_kind : t -> Ledger.Account_kind.t = function
  | Bridge | External | Opening_balance -> Equity
  | Spot_clearing | Vaults | Other -> Asset
  | Trading_fees -> Expense
  | Perp_pnl
  | Funding
  | Builder_fees
  | Referral_rewards
  | Vault_commission
  | Staking_rewards -> Income
  | Custom { kind; name = _ } -> kind
;;

let purpose : t -> Ledger.Account.Purpose.t = function
  | Spot_clearing -> Clearing
  | Builder_fees -> Fee_income
  | Bridge
  | External
  | Perp_pnl
  | Trading_fees
  | Funding
  | Referral_rewards
  | Vault_commission
  | Vaults
  | Staking_rewards
  | Opening_balance
  | Other
  | Custom _ -> General
;;

let quickcheck_generator =
  Quickcheck.Generator.of_list
    (Custom { name = "hedge_pnl"; kind = Income } :: all_builtin)
;;

include Comparable.Make (T)
