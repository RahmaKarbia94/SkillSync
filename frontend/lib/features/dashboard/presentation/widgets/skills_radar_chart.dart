import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/glass_theme.dart';

class SkillsRadarChart extends StatelessWidget {
  const SkillsRadarChart({
    super.key,
    required this.pacing,
    required this.clarity,
    required this.confidence,
  });

  final double pacing;
  final double clarity;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Soft Skills Breakdown',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1.3,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                tickCount: 4,
                ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 0),
                radarBorderData: BorderSide(color: Colors.white.withOpacity(0.15)),
                gridBorderData: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
                radarBackgroundColor: Colors.transparent,
                titleTextStyle: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                getTitle: (index, angle) {
                  switch (index) {
                    case 0:
                      return const RadarChartTitle(text: 'Pacing');
                    case 1:
                      return const RadarChartTitle(text: 'Clarity');
                    case 2:
                      return const RadarChartTitle(text: 'Confidence');
                    default:
                      return const RadarChartTitle(text: '');
                  }
                },
                dataSets: [
                  RadarDataSet(
                    fillColor: const Color(0xFF6C63FF).withOpacity(0.25),
                    borderColor: const Color(0xFF6C63FF),
                    borderWidth: 2,
                    entryRadius: 3,
                    dataEntries: [
                      RadarEntry(value: pacing.clamp(0, 100)),
                      RadarEntry(value: clarity.clamp(0, 100)),
                      RadarEntry(value: confidence.clamp(0, 100)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}