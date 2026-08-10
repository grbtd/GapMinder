import ActivityKit
import WidgetKit
import SwiftUI

public struct LiveActivitiesAppAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var serviceUid: String?
        public var destination: String?
        public var origin: String?
        public var scheduledTime: String?
        public var realtimeTime: String?
        public var platform: String?
        public var status: String?
        public var operatorName: String?
        public var stationName: String?
        public var title: String?
        public var subtitle: String?
        public var updatedAt: String?
    }
}

@available(iOS 16.1, *)
struct TrainLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // Dynamic Island / Lock screen view
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "train.side.front.car")
                        .foregroundColor(.blue)
                    Text(context.state.title ?? "Train Service")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                    if let status = context.state.status, !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(status == "CANCELLED" ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundColor(status == "CANCELLED" ? .red : .green)
                            .cornerRadius(4)
                    }
                }
                
                HStack {
                    if let station = context.state.stationName, !station.isEmpty {
                        Text(station)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let platform = context.state.platform, !platform.isEmpty {
                        Text("Plat \(platform)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(Color.white)
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: "train.side.front.car")
                            .foregroundColor(.blue)
                        Text(context.state.scheduledTime ?? "")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.platform != nil && !(context.state.platform?.isEmpty ?? true) ? "Plat \(context.state.platform!)" : "TBC")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("To \(context.state.destination ?? "")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } compactLeading: {
                Image(systemName: "train.side.front.car")
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text(context.state.scheduledTime ?? "")
                    .font(.caption)
                    .fontWeight(.bold)
            } minimal: {
                Image(systemName: "train.side.front.car")
                    .foregroundColor(.blue)
            }
        }
    }
}
