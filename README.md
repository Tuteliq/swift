<p align="center">
  <img src="./assets/logo.png" alt="SafeNest" width="200" />
</p>

<h1 align="center">SafeNest Swift SDK</h1>

<p align="center">
  <strong>Official Swift SDK for the SafeNest API</strong><br>
  AI-powered child safety analysis for iOS, macOS, tvOS, and watchOS
</p>

<p align="center">
  <a href="https://github.com/SafeNestSDK/swift/actions"><img src="https://img.shields.io/github/actions/workflow/status/SafeNestSDK/swift/ci.yml" alt="build status"></a>
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Platforms-iOS%2015%2B%20%7C%20macOS%2012%2B-blue.svg" alt="Platforms">
  <a href="https://github.com/SafeNestSDK/swift/blob/main/LICENSE"><img src="https://img.shields.io/github/license/SafeNestSDK/swift.svg" alt="license"></a>
</p>

<p align="center">
  <a href="https://api.safenest.dev/docs">API Docs</a> •
  <a href="https://safenest.app">Dashboard</a> •
  <a href="https://discord.gg/7kbTeRYRXD">Discord</a>
</p>

---

## Installation

### Swift Package Manager

Add SafeNest to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/SafeNestSDK/swift.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → Enter:
```
https://github.com/SafeNestSDK/swift.git
```

---

## Quick Start

```swift
import SafeNest

let safenest = SafeNest(apiKey: "your-api-key")

// Quick safety analysis
let result = try await safenest.analyze(content: "Message to check")

if result.riskLevel != .safe {
    print("Risk: \(result.riskLevel)")
    print("Summary: \(result.summary)")
}
```

---

## API Reference

### Initialization

```swift
// Simple
let safenest = SafeNest(apiKey: "your-api-key")

// With options
let safenest = SafeNest(
    apiKey: "your-api-key",
    timeout: 30,      // Request timeout in seconds
    maxRetries: 3,    // Retry attempts
    retryDelay: 1     // Initial retry delay in seconds
)
```

### Bullying Detection

```swift
let result = try await safenest.detectBullying(
    content: "Nobody likes you, just leave"
)

if result.isBullying {
    print("Severity: \(result.severity)")      // .low, .medium, .high, .critical
    print("Types: \(result.bullyingType)")     // ["exclusion", "verbal_abuse"]
    print("Confidence: \(result.confidence)")  // 0.92
    print("Rationale: \(result.rationale)")
}
```

### Grooming Detection

```swift
let result = try await safenest.detectGrooming(
    DetectGroomingInput(
        messages: [
            GroomingMessage(role: .adult, content: "This is our secret"),
            GroomingMessage(role: .child, content: "Ok I won't tell")
        ],
        childAge: 12
    )
)

if result.groomingRisk == .high {
    print("Flags: \(result.flags)")  // ["secrecy", "isolation"]
}
```

### Unsafe Content Detection

```swift
let result = try await safenest.detectUnsafe(
    content: "I don't want to be here anymore"
)

if result.unsafe {
    print("Categories: \(result.categories)")  // ["self_harm", "crisis"]
    print("Severity: \(result.severity)")      // .critical
}
```

### Quick Analysis

Runs bullying and unsafe detection in parallel:

```swift
let result = try await safenest.analyze(content: "Message to check")

print("Risk Level: \(result.riskLevel)")  // .safe, .low, .medium, .high, .critical
print("Risk Score: \(result.riskScore)")  // 0.0 - 1.0
print("Summary: \(result.summary)")
print("Action: \(result.recommendedAction)")
```

### Emotion Analysis

```swift
let result = try await safenest.analyzeEmotions(
    content: "I'm so stressed about everything"
)

print("Emotions: \(result.dominantEmotions)")  // ["anxiety", "sadness"]
print("Trend: \(result.trend)")                // .improving, .stable, .worsening
print("Followup: \(result.recommendedFollowup)")
```

### Action Plan

```swift
let plan = try await safenest.getActionPlan(
    GetActionPlanInput(
        situation: "Someone is spreading rumors about me",
        childAge: 12,
        audience: .child,
        severity: .medium
    )
)

print("Steps: \(plan.steps)")
print("Tone: \(plan.tone)")
```

### Incident Report

```swift
let report = try await safenest.generateReport(
    GenerateReportInput(
        messages: [
            ReportMessage(sender: "user1", content: "Threatening message"),
            ReportMessage(sender: "child", content: "Please stop")
        ],
        childAge: 14
    )
)

print("Summary: \(report.summary)")
print("Risk: \(report.riskLevel)")
print("Next Steps: \(report.recommendedNextSteps)")
```

---

## Tracking Fields

All methods support `externalId` and `metadata` for correlating requests:

```swift
let result = try await safenest.detectBullying(
    DetectBullyingInput(
        content: "Test message",
        externalId: "msg_12345",
        metadata: ["user_id": "usr_abc", "session": "sess_xyz"]
    )
)

// Echoed back in response
print(result.externalId)  // "msg_12345"
```

---

## Usage Tracking

```swift
let result = try await safenest.detectBullying(content: "test")

// Access usage stats after any request
if let usage = safenest.usage {
    print("Limit: \(usage.limit)")
    print("Used: \(usage.used)")
    print("Remaining: \(usage.remaining)")
}

// Request metadata
print("Request ID: \(safenest.lastRequestId ?? "N/A")")
print("Latency: \(safenest.lastLatency ?? 0)s")
```

---

## Error Handling

```swift
do {
    let result = try await safenest.detectBullying(content: "test")
} catch let error as SafeNestError {
    switch error {
    case .authenticationError(let message):
        print("Auth error: \(message)")
    case .rateLimitError(let message):
        print("Rate limited: \(message)")
    case .validationError(let message, let details):
        print("Invalid input: \(message)")
    case .serverError(let message, let statusCode):
        print("Server error \(statusCode): \(message)")
    case .timeoutError(let message):
        print("Timeout: \(message)")
    case .networkError(let message):
        print("Network error: \(message)")
    case .unknownError(let message):
        print("Error: \(message)")
    }
}
```

---

## SwiftUI Example

```swift
import SwiftUI
import SafeNest

struct ContentView: View {
    @State private var message = ""
    @State private var warning: String?
    @State private var isChecking = false

    let safenest = SafeNest(apiKey: ProcessInfo.processInfo.environment["SAFENEST_API_KEY"] ?? "")

    var body: some View {
        VStack {
            TextField("Message", text: $message)
                .textFieldStyle(.roundedBorder)

            if let warning = warning {
                Text(warning)
                    .foregroundColor(.red)
            }

            Button("Send") {
                Task { await checkAndSend() }
            }
            .disabled(isChecking)
        }
        .padding()
    }

    func checkAndSend() async {
        isChecking = true
        defer { isChecking = false }

        do {
            let result = try await safenest.analyze(content: message)

            if result.riskLevel != .safe {
                warning = result.summary
                return
            }

            // Safe to send
            warning = nil
            // ... send message
        } catch {
            warning = error.localizedDescription
        }
    }
}
```

---

## Requirements

- Swift 5.9+
- iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+

---

## Support

- **API Docs**: [api.safenest.dev/docs](https://api.safenest.dev/docs)
- **Discord**: [discord.gg/7kbTeRYRXD](https://discord.gg/7kbTeRYRXD)
- **Email**: support@safenest.dev
- **Issues**: [GitHub Issues](https://github.com/SafeNestSDK/swift/issues)

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care for child safety by the <a href="https://safenest.dev">SafeNest</a> team</sub>
</p>
