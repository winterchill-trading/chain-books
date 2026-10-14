(** One item of the [userNonFundingLedgerUpdates] info request: every balance change of
    an account that is not a fill or a funding payment.

    {v
    {"time": 1739891428531, "hash": "0x489d...", "delta": {"type": "withdraw", "usdc": "99.0", "nonce": 1739891096964000, "fee": "1.0"}}
    v}

    The delta types below were checked against mainnet answers in October 2026; any
    other type (liquidations, which move money through fills, lending, priority gas
    auctions of other tokens, ...) is kept as [Other] with its JSON. Amounts are exact
    decimals; [rewardsClaim] is decoded from its documented [amount] field (no mainnet
    sample was available). *)

open! Core

module Delta : sig
  type t =
    | Deposit of { usdc : Q.t }
    | Withdraw of
        { usdc : Q.t
        ; fee : Q.t
        }
    | Internal_transfer of
        { usdc : Q.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        ; fee : Q.t
        }
    | Sub_account_transfer of
        { usdc : Q.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        }
    | Account_class_transfer of
        { usdc : Q.t
        ; to_perp : bool
        }
    | Spot_transfer of
        { token : string
        ; amount : Q.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        ; fee : Q.t (** in USDC *)
        }
    | Send of
        { token : string
        ; amount : Q.t
        ; user : Hl_protocol.Address.t
        ; destination : Hl_protocol.Address.t
        ; source_dex : string (** [""] for the default perpetuals dex, [spot], or a dex *)
        ; destination_dex : string
        ; fee : Q.t
        ; fee_token : string (** [""] means USDC *)
        }
    | Vault_create of
        { vault : Hl_protocol.Address.t
        ; usdc : Q.t
        ; fee : Q.t
        }
    | Vault_deposit of
        { vault : Hl_protocol.Address.t
        ; usdc : Q.t
        }
    | Vault_withdraw of
        { vault : Hl_protocol.Address.t
        ; user : Hl_protocol.Address.t
        ; net_withdrawn_usd : Q.t
        }
    | Vault_distribution of
        { vault : Hl_protocol.Address.t
        ; usdc : Q.t
        }
    | Rewards_claim of { amount : Q.t }
    | C_staking_transfer of
        { token : string
        ; amount : Q.t
        ; is_deposit : bool
        }
    | Spot_genesis of
        { token : string
        ; amount : Q.t
        }
    | Gas_auction of
        { token : string
        ; amount : Q.t
        } (** [gossipPriorityGasAuction]: a fee paid *)
    | Other of
        { type_ : string
        ; json : Yojson.Safe.t
        }
  [@@deriving sexp_of]

  (** The wire [type], e.g. [accountClassTransfer]. *)
  val type_name : t -> string
end

type t =
  { time : int (** milliseconds since the epoch *)
  ; hash : string
  ; delta : Delta.t
  }
[@@deriving sexp_of]

val of_yojson : Yojson.Safe.t -> t Or_error.t

(** A JSON array of updates, as the info request answers. *)
val list_of_yojson : Yojson.Safe.t -> t list Or_error.t
