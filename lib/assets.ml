open! Core

let register_token ~code ~decimals =
  Money.Currency.register ~code ~exponent:decimals ~kind:Crypto ()
;;

let hype = Or_error.ok_exn (register_token ~code:"HYPE" ~decimals:8)
