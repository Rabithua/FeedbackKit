import Foundation

enum FeedbackTextLinkDetector {
    static func links(in text: String) -> [(range: NSRange, url: URL)] {
        guard text.isEmpty == false,
              let detector = try? NSDataDetector(
                  types: NSTextCheckingResult.CheckingType.link.rawValue
              )
        else {
            return []
        }

        let source = text as NSString
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return detector.matches(in: text, range: range).compactMap { match in
            guard let detectedURL = match.url,
                  let secureURL = secureURL(
                      from: detectedURL,
                      sourceText: source.substring(with: match.range)
                  )
            else {
                return nil
            }

            return (match.range, secureURL)
        }
    }

    private static func secureURL(from detectedURL: URL, sourceText: String) -> URL? {
        guard var components = URLComponents(
            url: detectedURL,
            resolvingAgainstBaseURL: false
        ),
        let scheme = components.scheme?.lowercased(),
        components.host?.isEmpty == false
        else {
            return nil
        }

        if scheme == "https" {
            return components.url
        }

        guard scheme == "http",
              sourceText.lowercased().hasPrefix("http://") == false
        else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }
}
