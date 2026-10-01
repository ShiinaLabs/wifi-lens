import Foundation
import SwiftUI

public struct BandChartRenderModel {
    public let xDataMin: Int
    public let xDataMax: Int
    public let yMin: Double
    public let visibleSeriesData: [ChartSeriesData]
    public let displayedSeriesData: [ChartSeriesData]
    public let strongestRSSI: Int
    public let isEmpty: Bool
    public let zoomMin: Double?
    public let zoomMax: Double?
    public let isExpanded: Bool
    public let axisTickStartChannel: Int
}
