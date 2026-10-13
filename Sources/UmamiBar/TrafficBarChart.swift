import Charts
import SwiftUI
import UmamiBarCore

/// Match both series by timestamp, never by their array positions.
struct TrafficBucket: Identifiable {
    let time: String
    let pageviews: Double?
    let visitors: Double?
    var id: String { time }

    static func make(pageviews: [SeriesPoint], visitors: [SeriesPoint], range: DateRange,
                     now: Date = .now, calendar: Calendar = .current) -> [TrafficBucket] {
        guard range == .today else { return align(pageviews: pageviews, visitors: visitors) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func hours(_ points: [SeriesPoint]) -> [Int: Double] {
            var result: [Int: Double] = [:]
            for point in points {
                guard let date = formatter.date(from: point.x) ?? SeriesPoint(x: point.x, y: 0).date,
                      calendar.isDate(date, inSameDayAs: now) else { continue }
                result[calendar.component(.hour, from: date)] = point.y
            }
            return result
        }
        let views = hours(pageviews)
        let people = hours(visitors)
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: now)
        return (0..<24).map { hour in
            TrafficBucket(time: day + String(format: " %02d:00:00", hour),
                          pageviews: views[hour], visitors: people[hour])
        }
    }

    static func align(pageviews: [SeriesPoint], visitors: [SeriesPoint]) -> [TrafficBucket] {
        let views = Dictionary(pageviews.map { ($0.x, $0.y) }, uniquingKeysWith: { _, last in last })
        let people = Dictionary(visitors.map { ($0.x, $0.y) }, uniquingKeysWith: { _, last in last })
        return Set(views.keys).union(people.keys).sorted().map {
            TrafficBucket(time: $0, pageviews: views[$0], visitors: people[$0])
        }
    }
}

/// Umami-style overlaid bars: one column with a deeper visitor section and lighter views.
struct TrafficBarChart: View {
    let points: [SeriesPoint]
    var visitors: [SeriesPoint] = []
    let range: DateRange

    private var buckets: [TrafficBucket] { TrafficBucket.make(pageviews: points, visitors: visitors, range: range) }

    var body: some View {
        VStack(spacing: 4) {
            Chart(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                // Both metrics share one full-width column and one zero baseline.
                // Views paint first; visitors cover its lower section without summing counts.
                if let count = bucket.pageviews {
                    BarMark(x: .value("Time", String(index)), y: .value("Pageviews", max(0, count)),
                            width: .ratio(0.82), stacking: .unstacked)
                        .foregroundStyle(Theme.pageviewsBlue)
                        .cornerRadius(1)
                        .accessibilityLabel(Text("\(timeLabel(at: index)), \(String(localized: "Views"))"))
                        .accessibilityValue(compactNumber(count))
                }
                if let count = bucket.visitors {
                    BarMark(x: .value("Time", String(index)), y: .value("Visitors", max(0, count)),
                            width: .ratio(0.82), stacking: .unstacked)
                        .foregroundStyle(Theme.visitorsBlue)
                        .cornerRadius(1)
                        .accessibilityLabel(Text("\(timeLabel(at: index)), \(String(localized: "Visitors"))"))
                        .accessibilityValue(compactNumber(count))
                }
            }
            .chartXScale(domain: buckets.indices.map(String.init))
            .chartYScale(domain: 0...max(1, buckets.flatMap { [$0.pageviews, $0.visitors].compactMap { $0 } }.max() ?? 1))
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.primary.opacity(0.08))
                    AxisValueLabel {
                        if let count = value.as(Double.self) {
                            Text(compactNumber(count)).font(.system(size: 9))
                        }
                    }
                }
            }
            .accessibilityLabel(Text("Traffic"))
            // Complete edge labels stay outside narrow categorical axis bands.
            HStack(spacing: 8) {
                ForEach(Array(tickIndices.enumerated()), id: \.element) { offset, index in
                    Text(timeLabel(at: index))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: offset == 0 ? .leading :
                               (offset == tickIndices.count - 1 ? .trailing : .center))
                }
            }
            .padding(.leading, 28)
        }
    }

    private var tickIndices: [Int] {
        guard buckets.count > 1 else { return buckets.isEmpty ? [] : [0] }
        if range == .today { return [0, 12, 23] }
        if buckets.count == 2 { return [0, 1] }
        return [0, (buckets.count - 1) / 2, buckets.count - 1]
    }

    private func timeLabel(at index: Int) -> String {
        guard buckets.indices.contains(index) else { return "" }
        guard let date = SeriesPoint(x: buckets[index].time, y: 0).date else { return String(index + 1) }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = range.unit == "hour" ? "HH:mm" : "M/d"
        return formatter.string(from: date)
    }
}
