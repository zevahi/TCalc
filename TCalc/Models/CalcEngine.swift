// CalcEngine.swift
//
// The "brain" of the calculator. It knows nothing about SwiftUI — the view
// just forwards button presses here and shows `display`. Keeping the math
// separate from the UI makes each easier to read, change, and test.
//
// ── How an immediate-execution calculator works ──────────────────────────
// This is the same model as the basic iPhone calculator: each operator is
// applied as soon as the next one is pressed, left to right, with NO order
// of operations. So `2 + 3 × 4 =` gives 20, not 14.
//
// It's a small *state machine*: four pieces of state decide what every
// button does next.
//
//   display      – the text on screen (the number being typed, or a result)
//   accumulator  – the left-hand number, saved when an operator is pressed
//   pending      – the operator waiting for its right-hand number
//   isTyping     – true while the user is entering digits; false right after
//                  an operator/equals, so the next digit starts a new number
//
// ── Worked trace: 2 + 3 × 4 = ────────────────────────────────────────────
//   key   display  accumulator  pending  isTyping   what happened
//   2     "2"      nil          nil      true       start typing a number
//   +     "2"      2            +        false      save 2, remember +
//   3     "3"      2            +        true       new number replaces "2"
//   ×     "5"      5            ×        false      2 + 3 = 5 runs NOW, then remember ×
//   4     "4"      5            ×        true       new number replaces "5"
//   =     "20"     nil          nil      false      5 × 4 = 20
// ─────────────────────────────────────────────────────────────────────────

import Foundation  // for String(format:)

/// The four arithmetic operations the keypad offers.
///
/// Swift concept — *enum with raw values*: each case is backed by a `String`,
/// so `CalcOperation.add.rawValue == "+"`. The view uses `rawValue` as the
/// button label. `CaseIterable` gives us `CalcOperation.allCases` so the view
/// can loop over every operator without listing them by hand.
///
/// (Named `CalcOperation` rather than `Operation` because Foundation already
/// has a class called `Operation`, and sharing the name would be confusing.)
enum CalcOperation: String, CaseIterable {
  case add = "+"
  case subtract = "-"
  case multiply = "*"
  case divide = "/"

  /// Performs the operation on two numbers.
  ///
  /// Returns an *optional* (`Double?`): either a number, or `nil` meaning
  /// "this has no valid answer" (dividing by zero, or a result too large to
  /// represent). The caller must handle the `nil` case, which is how Swift
  /// forces us to think about errors instead of ignoring them.
  func apply(_ lhs: Double, _ rhs: Double) -> Double? {
    let result: Double
    switch self {
    case .add: result = lhs + rhs
    case .subtract: result = lhs - rhs
    case .multiply: result = lhs * rhs
    case .divide:
      // `guard` = "this must be true to continue, otherwise exit early".
      guard rhs != 0 else { return nil }
      result = lhs / rhs
    }
    // Doubles don't crash on overflow — they quietly become `infinity`.
    // Treat that as an error too, rather than showing "inf" on screen.
    return result.isFinite ? result : nil
  }
}

/// Holds the calculator's state and the rules for how each key changes it.
///
/// Swift concept — *struct + `mutating`*: a struct is a value type, so its
/// methods can't change its own properties unless marked `mutating`. Because
/// the view stores this struct in `@State`, every mutation produces a "new"
/// value, which is exactly what tells SwiftUI to redraw the screen.
struct CalcEngine {

  // MARK: - State

  /// The text shown on screen. `private(set)` means the view can *read* it
  /// but only the engine can *change* it.
  private(set) var display: String = "0"

  /// The left-hand number of a pending calculation, e.g. the `2` in `2 + …`.
  /// Optional because there isn't always one (before any operator is pressed).
  private var accumulator: Double?

  /// The operator waiting for its right-hand number, e.g. the `+` in `2 + …`.
  private var pending: CalcOperation?

  /// Whether the next digit should be appended to `display` (true) or start a
  /// brand-new number (false). It flips to false after an operator or `=`, so
  /// that typing `3` after `2 +` shows "3" instead of "23".
  private var isTyping = false

  /// `display` converted to a number for doing math. If the screen shows
  /// something that isn't a number (like "Error"), fall back to 0.
  /// `??` is the *nil-coalescing* operator: "use the left side, or the right
  /// side if the left is nil".
  private var currentValue: Double {
    Double(display) ?? 0
  }

  // MARK: - Key handlers (one per kind of button)

  /// Called when a digit key (0–9) is pressed.
  mutating func inputDigit(_ digit: Int) {
    if !isTyping {
      // First digit of a new number: replace whatever was on screen
      // (the initial "0", a previous result, or "Error").
      display = String(digit)
      isTyping = true
    } else if display == "0" {
      // Avoid leading zeros: "0" then "5" should show "5", not "05".
      display = String(digit)
    } else {
      // Normal case: keep building the number, "1" then "2" → "12".
      display += String(digit)
    }
  }

  /// Called when the decimal point key is pressed.
  mutating func inputDecimal() {
    if !isTyping {
      // Starting a new number with "." — show "0." so it reads naturally.
      display = "0."
      isTyping = true
    } else if !display.contains(".") {
      // Only one decimal point allowed per number.
      display += "."
    }
    // Otherwise there's already a "." — ignore the extra press.
  }

  /// Called when an operator key (+ - * /) is pressed.
  mutating func setOperation(_ operation: CalcOperation) {
    if let pending, let accumulator, isTyping {
      // Chaining, e.g. the "×" in `2 + 3 ×`: there's already a pending
      // `2 +` and the user just typed `3`. This is the heart of immediate
      // execution — finish `2 + 3` NOW, show 5, and use 5 as the new left side.
      // (`if let pending` unwraps the optional: inside these braces `pending`
      // is a plain `CalcOperation`, not a `CalcOperation?`.)
      guard let result = pending.apply(accumulator, currentValue) else {
        showError()
        return
      }
      display = format(result)
    } else if pending != nil && !isTyping {
      // Two operators in a row, e.g. `3 + *`: the user changed their mind.
      // No new number was typed, so just swap the operator and stop.
      pending = operation
      return
    }

    // Save the number on screen as the left-hand side and remember the
    // operator. The next digit will start a fresh number (isTyping = false).
    accumulator = currentValue
    pending = operation
    isTyping = false
  }

  /// Called when `=` is pressed: finish the pending calculation, if any.
  mutating func equals() {
    // Nothing to calculate, e.g. pressing `=` right after typing `5`.
    // `guard let` unwraps both optionals or exits early.
    guard let pending, let accumulator else {
      isTyping = false
      return
    }

    // Note: if the user presses `3 + =` without typing a second number,
    // `currentValue` is still 3, so this gives 3 + 3 = 6 (same as iOS).
    guard let result = pending.apply(accumulator, currentValue) else {
      showError()
      return
    }

    display = format(result)
    // The calculation is complete: clear it so the next operator press
    // starts a new one using this result as its left side.
    self.accumulator = nil
    self.pending = nil
    isTyping = false
  }

  /// Called by the clear (✕) button: back to the starting state.
  /// Assigning a fresh `CalcEngine()` to `self` resets every property at
  /// once, so this can never forget one.
  mutating func clear() {
    self = CalcEngine()
  }

  // MARK: - Helpers

  /// Puts the calculator into an error state (e.g. after dividing by zero).
  /// Everything resets, so the next digit starts over cleanly.
  private mutating func showError() {
    self = CalcEngine()
    display = "Error"
  }

  /// Turns a result into display text.
  ///
  /// `%.10g` means "at most 10 significant digits, no trailing zeros":
  ///   - 4.0 shows as "4", not "4.0"
  ///   - 0.1 + 0.2 shows as "0.3" instead of "0.30000000000000004".
  ///     Computers store decimals in binary, and 0.1 can't be represented
  ///     exactly (like 1/3 in decimal), so tiny errors creep in. Rounding to
  ///     10 digits hides that noise.
  ///   - Very large/small numbers switch to scientific notation (1e+15),
  ///     which `Double(display)` can still read back in.
  private func format(_ value: Double) -> String {
    // Avoid showing "-0" (e.g. from -3 × 0); mathematically it's just 0.
    if value == 0 { return "0" }
    return String(format: "%.10g", value)
  }
}
