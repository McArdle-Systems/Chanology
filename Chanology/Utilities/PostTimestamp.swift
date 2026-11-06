import Foundation

/// Formats post times for display.
///
/// The API's `now` string is fixed to US Eastern, so times are formatted from the
/// `time` epoch instead, in the device's time zone. `now` is only a fallback.
enum PostTimestamp {
    static func string(
        time: Int?,
        fallback: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let time else { return fallback }
        let style = Date.VerbatimFormatStyle(
            format: "\(month: .twoDigits)/\(day: .twoDigits)/\(year: .twoDigits)(\(weekday: .abbreviated))\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        return Date(timeIntervalSince1970: TimeInterval(time)).formatted(style)
    }
}
