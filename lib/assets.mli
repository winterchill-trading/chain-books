(** Currencies for on-chain assets that [Money.Currency] lacks, registered when the
    library is linked so they parse before [Money.Currency.freeze]. USDC held at an
    exchange is [Money.Currency.usdc] (6 digits, no network tag). *)

open! Core

(** [HYPE], 8 digits: the token's smallest on-chain unit ([weiDecimals]). *)
val hype : Money.Currency.t

(** [register_token ~code ~decimals] registers (or returns, when already registered
    identically) a crypto currency with no network tag, e.g. a spot token the books
    follow. Fails like [Money.Currency.register]. *)
val register_token : code:string -> decimals:int -> Money.Currency.t Or_error.t
