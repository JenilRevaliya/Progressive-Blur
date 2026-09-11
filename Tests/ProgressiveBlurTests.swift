import Foundation

func assertClose(_ a: Double, _ b: Double, tolerance: Double = 0.001, message: String) {
    if abs(a - b) > tolerance {
        fatalError("Assertion failed: \(message) - expected \(b), got \(a)")
    }
}

print("Running ProgressiveBlur Automated Verification Suite...")

let startAngle = 90.0
let endAngle = 2.0
let span = startAngle - endAngle

func normalizedProgress(for angle: Double) -> Double {
    if angle >= startAngle { return 1.0 }
    if angle <= endAngle { return 0.0 }
    return (angle - endAngle) / span
}

func normalizedFoldTurn(for angle: Double) -> Double {
    return 1.0 - normalizedProgress(for: angle)
}

// Test 1: Start at 90°. No animation.
assertClose(normalizedProgress(for: 90.0), 1.0, message: "Test 1: 90° must have progress 1.0")
assertClose(normalizedFoldTurn(for: 90.0), 0.0, message: "Test 1: 90° must have foldTurn 0.0")

// Test 2: Move from 90° -> 80°
assertClose(normalizedFoldTurn(for: 80.0), 10.0 / 88.0, message: "Test 2: 80° fold turn")

// Test 3: Move from 80° -> 45°
assertClose(normalizedFoldTurn(for: 45.0), 45.0 / 88.0, message: "Test 3: 45° fold turn")

// Test 4: Move from 45° -> 10°
assertClose(normalizedFoldTurn(for: 10.0), 80.0 / 88.0, message: "Test 4: 10° fold turn")

// Test 6: Move from 45° -> 90°
assertClose(normalizedFoldTurn(for: 90.0), 0.0, message: "Test 6: 90° resolution")

// Test 7: Move from 90° -> 120°
assertClose(normalizedProgress(for: 120.0), 1.0, message: "Test 7: 120° must be clamped to 1.0")
assertClose(normalizedFoldTurn(for: 120.0), 0.0, message: "Test 7: 120° fold turn must be clamped to 0.0")

// Test 8: Move from 120° -> 91°
assertClose(normalizedProgress(for: 91.0), 1.0, message: "Test 8: 91° must be clamped to 1.0")
assertClose(normalizedFoldTurn(for: 91.0), 0.0, message: "Test 8: 91° fold turn must be clamped to 0.0")

// Test 9: Move from 91° -> 89°
let turn89 = normalizedFoldTurn(for: 89.0)
if turn89 <= 0.0 {
    fatalError("Test 9: 89° must engage animation (> 0.0)")
}
assertClose(turn89, 1.0 / 88.0, message: "Test 9: 89° fold turn")

print("All automated angle and clamping test assertions passed successfully!")
