/-
Small Core-Lean-only target for exercising the minimal-library exporter.
Deliberately exercises the tricky cases: an inductive (⇒ recursor, `casesOn`,
constructors), a structure (⇒ projections, `mk`), a `def` with pattern matching
(⇒ equation lemmas / `match_1`), and theorems with proofs. None of this imports
Mathlib; everything below bottoms out at core (`Nat`, `Bool`, `Eq`, `rfl`).
-/

inductive Color where
  | red
  | green
  | blue

def Color.isRed : Color → Bool
  | .red => true
  | _    => false

structure Point where
  x : Nat
  y : Nat

def Point.origin : Point := { x := 0, y := 0 }

def Point.shift (p : Point) (d : Nat) : Point := { x := p.x + d, y := p.y + d }

theorem Point.origin_x : Point.origin.x = 0 := rfl

theorem Color.isRed_red : Color.isRed Color.red = true := rfl

theorem Point.shift_origin_x (d : Nat) : (Point.origin.shift d).x = d := by
  simp [Point.shift, Point.origin]

def Point.add (p q : Point) : Point := { x := p.x + q.x, y := p.y + q.y }

infixl:65 " ⊕ " => Point.add

theorem Point.add_comm_x (p q : Point) : (p ⊕ q).x = (q ⊕ p).x := by
  simp [Point.add, Nat.add_comm]
