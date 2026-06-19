---
title: Rate Page Visualization
slug: rate-page-visualization
topic: ui-components
summary: The Rate page visualizes the first derivative of weight (velocity in lb/wk and lb/day), not the second derivative (acceleration)
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-06-17
updated: 2026-06-17
verified: 2026-06-17
compiled-from: conversation
sources:
  - session:18aedfc3-5869-408c-a87a-9618ad497cfa
---

# Rate Page Visualization

## Overview

The Rate page visualizes the first derivative of weight (velocity in lb/wk and lb/day), not the second derivative (acceleration). It displays a current-rate readout in both lb/wk and lb/day units on a single page. The Rate page shares the same x-axis domain as the Weight page so that 'today' aligns between the two views. <!-- [^18aed-25] -->

## Rate Computation

Rate computation uses a ~2-week least-squares regression over the smoothed weight line to filter out daily water-weight noise, rather than a shorter window. Rate data is deduplicated to one point per calendar day before computation to prevent identical duplicate readings from distorting the smoothing window. <!-- [^18aed-26] -->

## Chart Visuals

The Rate page chart excludes the min/max/avg trend lines and the target rule present on the Weight page. It features a dashed zero baseline so users can distinguish between losing and gaining, and includes a faint dashed weight overlay line with a "– – weight" legend so users can compare the weight trend to the rate. The rate line is rendered using Catmull-Rom interpolation with a light ±2 moving-average smoothing pass, without per-point dots, to ensure a fluid curve. <!-- [^18aed-27] -->

## Chart Axes and Domain

The Rate page y-domain fits the actual data range and includes zero, rather than forcing a symmetric range around zero, to avoid wasting half the chart on empty gaining space. The gradient fill fills the area under the curve down to the bottom of the chart, rather than the band between the line and the zero baseline at the top. <!-- [^18aed-28] -->

## Empty State

If fewer than 2 smoothed points exist at the start of a cut, the Rate page displays a 'Rate appears after a few days' placeholder instead of a chart. <!-- [^18aed-29] -->
