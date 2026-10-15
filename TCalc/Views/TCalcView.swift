import SwiftData
import SwiftUI

let backgroundGradient = LinearGradient(
  colors: [.gray, .blue, .purple, .white, .blue],
  startPoint: .top,
  endPoint: .bottom
)

struct CalcView: View {
  // Digit rows. The bottom row (0 . =) is built separately below because it
  // mixes digits with non-digit keys.
  let keypad_values = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

  @Query var globalSettings: [Settings]
  @Environment(\.modelContext) private var context

  // All of the calculator's math and state lives in CalcEngine (see
  // Models/CalcEngine.swift). The view only forwards button presses to it.
  // CalcEngine is a struct (value type), so whenever one of its `mutating`
  // methods runs, @State sees a changed value and SwiftUI redraws the screen.
  @State private var engine = CalcEngine()
  @State var changeOccured: Bool = false
  @State var forVibration: Bool = false

  var body: some View {

    ZStack {

      // BACKGROUND EFFECT
      backgroundGradient
        .blur(radius: 200, opaque: false)
        .ignoresSafeArea()

      // CALCULATOR UI
      VStack(alignment: .center) {

        // CALC Results
        HStack {
          // Read-only view of the engine's current text ("12", "3.5", "Error"…)
          Text(engine.display)
            .font(.system(size: 48, weight: .bold))
            .foregroundColor(Color.white)
            .padding(24)
            .glassEffect(.clear.interactive())
        }

        // CALC Keypad
        VStack {
          HStack {  // Function buttons at the top
            // One button per CalcOperation case; its raw value ("+", "-", …)
            // is the label. Pressing it tells the engine which operator to
            // apply (and, if a calculation is already pending, finishes it).
            ForEach(CalcOperation.allCases, id: \.self) { operation in
              Button {
                engine.setOperation(operation)
                changeOccured = true
                forVibration.toggle()
              } label: {
                Text(operation.rawValue)
              }
            }
          }
          .buttonStyle(.glassProminent)
          .sensoryFeedback(.selection, trigger: forVibration)
          .labelStyle(.iconOnly)

          VStack {  // Keypad buttons for input
            ForEach(keypad_values.indices, id: \.self) { i in
              HStack {
                ForEach(keypad_values[i].indices, id: \.self) { j in
                  // Digits are appended to the number being typed
                  // (1 then 2 → "12"), not added together.
                  keyButton(String(keypad_values[i][j])) {
                    engine.inputDigit(keypad_values[i][j])
                  }
                }
              }
            }

            // Bottom row: zero, decimal point, and equals
            HStack {
              keyButton("0") { engine.inputDigit(0) }
              keyButton(".") { engine.inputDecimal() }
              keyButton("=") { engine.equals() }
            }
          }

          // CALC Clear Button
          if changeOccured {
            Button {
              // Resets the display, saved number, and pending operator
              engine.clear()
              changeOccured = false
              forVibration.toggle()
            } label: {
              Image(systemName: "xmark")
                .padding(16)
            }
            .buttonStyle(.glassProminent)
            .sensoryFeedback(.selection, trigger: forVibration)
            .labelStyle(.iconOnly)
          }
        }
      }
    }
  }

  /// Builds one keypad button with the shared glass styling.
  /// `action` is a *closure* — a chunk of code passed in to run on tap — so
  /// each key can do something different while looking the same.
  /// `@escaping` is needed because the Button stores the closure and calls it
  /// later, after this function has already returned.
  private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
    Button {
      action()
      changeOccured = true  // shows the clear button
      forVibration.toggle()  // flipping this triggers the haptic tap
    } label: {
      Text(label)
        .font(.title)
        .foregroundColor(.accentColor.exposureAdjust(-1.0))
        .fontWeight(.semibold)
        .padding(32)
    }
    .buttonStyle(.glass)
    .sensoryFeedback(.selection, trigger: forVibration)
  }
}

#Preview {
  CalcView()
}
