import TestTarget

/- Exercises namespace + section-variable context: decls here are written with
short names inside `namespace Geo`, so a faithful export must keep the namespace
(so `Vec.zero_dx` really is `Geo.Vec.zero_dx`), while dropping the unneeded
`variable` and `scaleBy`. -/
namespace Geo

variable (scale : Nat)

structure Vec where
  dx : Nat
  dy : Nat

def Vec.zero : Vec := { dx := 0, dy := 0 }

def Vec.scaleBy (v : Vec) : Vec := { dx := v.dx * scale, dy := v.dy * scale }

theorem Vec.zero_dx : Vec.zero.dx = 0 := rfl

end Geo
