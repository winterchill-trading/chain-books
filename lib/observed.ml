open! Core
module Time = Time_ns.Stable.Alternate_sexp.V1

module Balance = struct
  module Stable = struct
    module V1 = struct
      type t =
        { location : Location.Stable.V1.t
        ; amount : Money.Amount.Stable.V1.t
        ; observed_at : Time.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { location : Location.t
    ; amount : Money.Amount.t
    ; observed_at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]
end

module Position = struct
  module Stable = struct
    module V1 = struct
      type t =
        { address : Address.Stable.V1.t
        ; instrument : Instrument.Stable.V1.t
        ; size : Exact.Stable.V1.t
        ; entry_price : Exact.Stable.V1.t option
        ; observed_at : Time.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  type t = Stable.V1.t =
    { address : Address.t
    ; instrument : Instrument.t
    ; size : Exact.t
    ; entry_price : Exact.t option
    ; observed_at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]
end

module Stable = struct
  module V1 = struct
    type t =
      { balances : Balance.Stable.V1.t list
      ; positions : Position.Stable.V1.t list
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

type t = Stable.V1.t =
  { balances : Balance.t list
  ; positions : Position.t list
  }
[@@deriving sexp, compare, equal]

let empty = { balances = []; positions = [] }

let merge ts =
  { balances = List.concat_map ts ~f:(fun t -> t.balances)
  ; positions = List.concat_map ts ~f:(fun t -> t.positions)
  }
;;
