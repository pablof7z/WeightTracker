---
title: Weight Chart Visualization
slug: weight-chart-visualization
topic: ui-components
summary: The gradient fill area path (areaFillPath) must use the same smoothed line data as the chart line to avoid visual mismatch between the line and its fill
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-13
updated: 2026-06-17
verified: 2026-06-13
compiled-from: conversation
sources:
  - session:3958dfae-7703-499c-b93a-b4def20d006e
  - session:18aedfc3-5869-408c-a87a-9618ad497cfa
  - session:1a7ed5a0-cb16-4a32-8576-3fbf4e24310f
---

# Weight Chart Visualization

## Gradient Fill

The gradient fill area path (areaFillPath) must use the same smoothed line data as the chart line to avoid visual mismatch between the line and its fill. The gradient fill area under the chart line uses Catmull-Rom cubic bezier curves in the areaFillPath to match the monotone spline interpolation of the chart line. (Previously: straight addLine calls creating sharp right-angle steps.)

The gradient area fill extends all the way to the left edge of the screen (x=0), including the safe area behind y-axis labels, rather than starting at the first data point's x-coordinate. <!-- [^1a7ed-3] -->

<!-- citations: [^3958d-2] [^3958d-4] [^3958d-5] -->
## Line Smoothing

The weight chart line uses a centered 5-day moving average to render smooth curves. (Previously: monotone interpolation on raw data, then an EWMA with α=0.25 that lagged behind actual points.) Each point is computed as the mean of itself plus 2 days before and 2 days after, keeping the line within ~0.3 lb of each actual reading. The weight chart line and dots must use the same smoothed data source so that dots sit exactly on the line. The chart smoothing fix applies to both ActiveCutMinichart.swift and LandscapeFocusChart.swift.

<!-- citations: [^3958d-3] [^3958d-6] -->

## Two-Page Swipeable View

The Today-screen minichart is a two-page swipeable view (Weight ↔ Rate) with page dots in the top gutter. The swipe gesture for flipping between the Weight and Rate pages lives inside the chart's TabView so it does not conflict with the day-to-day date swipe on the rest of the Today screen. The two-page swipeable chart is scoped only to the portrait minichart; the landscape focus chart still shows only weight. A future consideration exists to mirror the Rate page onto the landscape focus chart.

<!-- citations: [^18aed-1] [^18aed-6] [^18aed-9] [^18aed-15] [^18aed-19] -->
## Rate Page

The Rate page shows the first derivative of the smoothed weight line (rate of weight change in lbs/wk), not the second derivative. It shares the same visual UI as the Weight page (smooth line, gradient fill) but excludes the best/worst/avg trend lines and the target rule. It includes a dashed zero baseline with a '0' label to distinguish losing (below zero) from gaining (above zero). The gradient fill renders the area under the curve (between the line and the bottom of the chart), not the area between the line and the zero baseline. It overlays a faint dashed line showing the normalized weight trend, accompanied by a '– – weight' legend. It displays a current-rate readout in the corner showing the rate in both lb/wk and lb/day on a single page. The Rate page x-domain spans only the actual data range (ending at today), not the weight page's projection window, so the chart renders edge-to-edge without a blank right strip. The gutter date labels on the minichart are page-aware, showing the rate page's own end date rather than the weight page's projection end date. If there are fewer than 2 smoothed points early in a cut, the Rate page displays a 'Rate appears after a few days' placeholder. A future consideration exists to add the second derivative (acceleration/plateau detection) as a possible third page on the minichart.

<!-- citations: [^18aed-2] [^18aed-7] [^18aed-10] [^18aed-14] [^18aed-16] [^18aed-18] [^18aed-22] -->
## Rate Computation

The rate is computed as the slope of a ~2-week least-squares regression (±7-day window, date-based) rather than a short-window central difference, so that water-weight noise averages out and the real trend direction is visible. (Previously: central-difference of the already-5-day-smoothed weight line.) Raw readings are deduplicated to one point per calendar day before computing the rate, preventing duplicate readings from compressing the smoothing window. The Rate line is rendered as a smooth Catmull-Rom curve without per-point dots, computed over the smoothed weight line with a light ±2 moving-average pass. The y-domain on the Rate page includes zero and fits the actual data range rather than forcing a symmetric range around zero that wastes the top half when the user is always losing.

<!-- citations: [^18aed-3] [^18aed-8] [^18aed-11] [^18aed-13] [^18aed-17] [^18aed-20] [^18aed-23] -->
## Full-Screen Stats Card

When the chart is in full-screen mode, a persistent stats card (top-left glass card) displays the window label, start → end weights, delta in the user's unit, and percentage delta for the currently viewed period. If the data window includes the future, the stats card shows the calculated projection for the end value, indicated by a ~ suffix and using the projection path. The stats card dims to 30% opacity when a data point is tap-inspected so it does not compete for attention.

<!-- citations: [^1a7ed-2] [^1a7ed-4] [^1a7ed-5] -->

## Chart Gestures

Dragging left/right on the chart slides the time window through time, with a 20pt minimum distance to prevent conflicts with tap-to-inspect. Pinching resizes the chart duration between 3 and 180 days, matching map gesture direction (pinch-in = shorter span). Pinching to within 10% of a preset duration (7d/14d/30d) snaps to that preset with a spring animation. The preset picker dims to 45% opacity in custom mode as a signal that the user has departed from a preset. Tapping a preset pill resets pan offset and custom span back to zero. Double-tap resets everything: window, pan, span, and any tap selection. <!-- [^1a7ed-6] -->
