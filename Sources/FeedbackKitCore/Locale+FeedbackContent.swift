import Foundation

extension Locale {
    var feedbackContentIdentifier: String {
        var components = Locale.Components(locale: self)
        components.calendar = nil
        components.collation = nil
        components.currency = nil
        components.numberingSystem = nil
        components.firstDayOfWeek = nil
        components.hourCycle = nil
        components.measurementSystem = nil
        components.region = nil
        components.subdivision = nil
        components.timeZone = nil
        return Locale(components: components).identifier(.bcp47)
    }
}
