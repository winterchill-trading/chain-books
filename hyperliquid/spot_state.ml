open! Core

module Balance = struct
  type t =
    { coin : string
    ; total : Chain_books.Exact.t
    }
  [@@deriving sexp_of]
end

type t = { balances : Balance.t list } [@@deriving sexp_of]

let of_json json =
  match Wire.field json "balances" with
  | `List items ->
    { balances =
        List.map items ~f:(fun b ->
          { Balance.coin = Wire.string b "coin"; total = Wire.decimal b "total" })
    }
  | _ -> failwith "field balances: not an array"
;;

let of_yojson = Wire.decode ~what:"spot state" of_json
