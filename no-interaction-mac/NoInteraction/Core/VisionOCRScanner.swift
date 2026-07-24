import Cocoa
import Vision

public final class VisionOCRScanner {
    public static let shared = VisionOCRScanner()
    private init() {}

    private let cacheLock = NSLock()
    private var lastCapturedData: Data?

    // MARK: – Public

    /// Scans the bottom strip of the Anti-Gravity window for button labels.
    /// The "Submit / Skip" bar is always at the very bottom of the prompt panel.
    /// Calls completion on the main thread.
    public func scanRegionForKeywords(
        windowBounds: CGRect,
        buttonKeywords: [String],
        completion: @escaping (CGPoint?, String?) -> Void
    ) {
        let targetRect = buttonStripRect(from: windowBounds)
        guard let cgImage = captureScreenRegion(rect: targetRect) else {
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        // Fast-path: Skip OCR if the screenshot data has not changed
        let hasChanged: Bool = {
            guard let dataProvider = cgImage.dataProvider,
                  let cfData = dataProvider.data else { return true }
            let currentData = cfData as Data
            
            cacheLock.lock()
            defer { cacheLock.unlock() }
            if let last = lastCapturedData, last == currentData {
                return false
            }
            lastCapturedData = currentData
            return true
        }()

        if !hasChanged {
            DispatchQueue.main.async { completion(nil, nil) }
            return
        }

        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)

                // ⚠️  Only match SHORT text (≤ 40 chars) — button labels are short.
                // Long matches are sidebar items, code lines, etc. — skip them.
                guard !text.isEmpty, text.count <= 40 else { continue }

                let isMatch = buttonKeywords.contains { KeywordMatcher.matches(label: text, keyword: $0) }
                guard isMatch else { continue }

                // Convert Vision normalised bbox → screen coordinates
                let bbox    = obs.boundingBox
                let screenX = targetRect.minX + (bbox.midX * targetRect.width)
                // Vision: Y=0 is BOTTOM of image; macOS screen: Y=0 is TOP
                let screenY = targetRect.minY + ((1.0 - bbox.midY) * targetRect.height)
                let pt = CGPoint(x: screenX, y: screenY)

                print("👁️ VisionOCR: Found '\(text)' at (\(Int(pt.x)), \(Int(pt.y)))")
                DispatchQueue.main.async { completion(pt, text) }
                return
            }
            DispatchQueue.main.async { completion(nil, nil) }
        }

        request.recognitionLevel      = .fast   // faster; buttons are large text
        request.usesLanguageCorrection = false  // no correction needed for button labels
        request.minimumTextHeight     = 0.02    // ignore tiny text

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: – Helpers

    /// Returns the lower 75% of the window — where prompt dialogs, choices, and Submit/Skip live.
    private func buttonStripRect(from bounds: CGRect) -> CGRect {
        let stripH = max(150, bounds.height * 0.75)
        return CGRect(
            x:      bounds.minX,
            y:      bounds.maxY - stripH,
            width:  bounds.width,
            height: stripH
        )
    }

    private func captureScreenRegion(rect: CGRect) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    }
}
