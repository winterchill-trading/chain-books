open! Core
module Q_sexp = struct
  type t = Q.t

  let sexp_of_t q = Sexp.Atom (Chain_books.Exact.to_string q)
end

module Json_sexp = struct
  type t = Yojson.Safe.t

  let sexp_of_t j = Sexp.Atom (Yojson.Safe.to_string j)
end

module Delta = struct
  type t =
    | Deposit of { usdc : Q_sexp.t }
    | Withdraw of
        { usdc : Q_sexp.t
        ; fee : Q_sexp.t
        }
    | Internal_transfer of
        { usdc : Q_sexp.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        ; fee : Q_sexp.t
        }
    | Sub_account_transfer of
        { usdc : Q_sexp.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        }
    | Account_class_transfer of
        { usdc : Q_sexp.t
        ; to_perp : bool
        }
    | Spot_transfer of
        { token : string
        ; amount : Q_sexp.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        ; fee : Q_sexp.t
        }
    | Send of
        { token : string
        ; amount : Q_sexp.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        ; source_dex : string
        ; destination_dex : string
        ; fee : Q_sexp.t
        ; fee_token : string
        }
    | Vault_create of
        { vault : Hl_protocol.Address.t
        ; usdc : Q_sexp.t
        ; fee : Q_sexp.t
        }
    | Vault_deposit of
        { vault : Hl_protocol.Address.t
        ; usdc : Q_sexp.t
        }
    | Vault_withdraw of
        { vault : Hl_protocol.Address.t
        ; user : Hl_protocol.Address.t
        ; net_withdrawn_usd : Q_sexp.t
        }
    | Vault_distribution of
        { vault : Hl_protocol.Address.t
        ; usdc : Q_sexp.t
        }
    | Rewards_claim of { amount : Q_sexp.t }
    | C_staking_transfer of
        { token : string
        ; amount : Q_sexp.t
        ; is_deposit : bool
        }
    | Spot_genesis of
        { token : string
        ; amount : Q_sexp.t
        }
    | Gas_auction of
        { token : string
        ; amount : Q_sexp.t
        }
    | Other of
        { type_ : string
        ; json : Json_sexp.t
        }
  [@@deriving sexp_of]

  let type_name = function
    | Deposit _ -> "deposit"
    | Withdraw _ -> "withdraw"
    | Internal_transfer _ -> "internalTransfer"
    | Sub_account_transfer _ -> "subAccountTransfer"
    | Account_class_transfer _ -> "accountClassTransfer"
    | Spot_transfer _ -> "spotTransfer"
    | Send _ -> "send"
    | Vault_create _ -> "vaultCreate"
    | Vault_deposit _ -> "vaultDeposit"
    | Vault_withdraw _ -> "vaultWithdraw"
    | Vault_distribution _ -> "vaultDistribution"
    | Rewards_claim _ -> "rewardsClaim"
    | C_staking_transfer _ -> "cStakingTransfer"
    | Spot_genesis _ -> "spotGenesis"
    | Gas_auction _ -> "gossipPriorityGasAuction"
    | Other { type_; _ } -> type_
  ;;

  let of_json json =
    let open Wire in
    match string json "type" with
    | "deposit" -> Deposit { usdc = decimal json "usdc" }
    | "withdraw" -> Withdraw { usdc = decimal json "usdc"; fee = decimal_or_zero json "fee" }
    | "internalTransfer" ->
      Internal_transfer
        { usdc = decimal json "usdc"
        ; user = address json "user"
        ; destination = address json "destination"
        ; fee = decimal_or_zero json "fee"
        }
    | "subAccountTransfer" ->
      Sub_account_transfer
        { usdc = decimal json "usdc"
        ; user = address json "user"
        ; destination = address json "destination"
        }
    | "accountClassTransfer" ->
      Account_class_transfer { usdc = decimal json "usdc"; to_perp = bool json "toPerp" }
    | "spotTransfer" ->
      Spot_transfer
        { token = string json "token"
        ; amount = decimal json "amount"
        ; user = address json "user"
        ; destination = address json "destination"
        ; fee = decimal_or_zero json "fee"
        }
    | "send" ->
      Send
        { token = string json "token"
        ; amount = decimal json "amount"
        ; user = address json "user"
        ; destination = address json "destination"
        ; source_dex = string json "sourceDex"
        ; destination_dex = string json "destinationDex"
        ; fee = decimal_or_zero json "fee"
        ; fee_token = Option.value_map (field_opt json "feeToken") ~default:"" ~f:(fun _ -> string json "feeToken")
        }
    | "vaultCreate" ->
      Vault_create
        { vault = address json "vault"
        ; usdc = decimal json "usdc"
        ; fee = decimal_or_zero json "fee"
        }
    | "vaultDeposit" -> Vault_deposit { vault = address json "vault"; usdc = decimal json "usdc" }
    | "vaultWithdraw" ->
      Vault_withdraw
        { vault = address json "vault"
        ; user = address json "user"
        ; net_withdrawn_usd = decimal json "netWithdrawnUsd"
        }
    | "vaultDistribution" ->
      Vault_distribution { vault = address json "vault"; usdc = decimal json "usdc" }
    | "rewardsClaim" -> Rewards_claim { amount = decimal json "amount" }
    | "cStakingTransfer" ->
      C_staking_transfer
        { token = string json "token"
        ; amount = decimal json "amount"
        ; is_deposit = bool json "isDeposit"
        }
    | "spotGenesis" ->
      Spot_genesis { token = string json "token"; amount = decimal json "amount" }
    | "gossipPriorityGasAuction" ->
      Gas_auction { token = string json "token"; amount = decimal json "amount" }
    | type_ -> Other { type_; json }
  ;;
end

type t =
  { time : int
  ; hash : string
  ; delta : Delta.t
  }
[@@deriving sexp_of]

let of_json json =
  { time = Wire.int json "time"
  ; hash = Wire.string json "hash"
  ; delta = Delta.of_json (Wire.field json "delta")
  }
;;

let of_yojson = Wire.decode ~what:"ledger update" of_json

let list_of_yojson = function
  | `List items -> List.map items ~f:of_yojson |> Or_error.combine_errors
  | json -> Wire.decode ~what:"ledger updates" (fun _ -> failwith "not a JSON array") json
;;
