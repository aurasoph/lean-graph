import TestTarget

/-- A second module depending on `TestTarget`, to exercise cross-module ordering
and notation (`⊕`) coming from a different file than the target. -/
def Point.double (p : Point) : Point := p ⊕ p

theorem Point.double_x (p : Point) : (Point.double p).x = p.x + p.x := by
  simp [Point.double, Point.add]
