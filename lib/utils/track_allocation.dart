class TrackAllocationResult {
  final Map<String, int> itemToTrackMap; // itemId -> trackIndex
  final int trackCount;

  const TrackAllocationResult({
    required this.itemToTrackMap,
    required this.trackCount,
  });
}

TrackAllocationResult computeTrackAllocation<T>({
  required List<T> items,
  required String Function(T) getId,
  required Duration Function(T) getStartTime,
  required Duration Function(T) getEndTime,
}) {
  if (items.isEmpty) {
    return const TrackAllocationResult(itemToTrackMap: {}, trackCount: 1);
  }

  // Create copy of items sorted by startTime, then endTime
  final sortedItems = List<T>.from(items)
    ..sort((a, b) {
      final startA = getStartTime(a);
      final startB = getStartTime(b);
      if (startA != startB) {
        return startA.compareTo(startB);
      }
      return getEndTime(a).compareTo(getEndTime(b));
    });

  final List<Duration> laneEndTimes = [];
  final Map<String, int> itemToTrackMap = {};

  for (final item in sortedItems) {
    final start = getStartTime(item);
    final end = getEndTime(item);

    int assignedLane = -1;
    for (int i = 0; i < laneEndTimes.length; i++) {
      if (laneEndTimes[i] <= start) {
        assignedLane = i;
        laneEndTimes[i] = end;
        break;
      }
    }

    if (assignedLane == -1) {
      assignedLane = laneEndTimes.length;
      laneEndTimes.add(end);
    }

    itemToTrackMap[getId(item)] = assignedLane;
  }

  final trackCount = laneEndTimes.isEmpty ? 1 : laneEndTimes.length;
  return TrackAllocationResult(
    itemToTrackMap: itemToTrackMap,
    trackCount: trackCount,
  );
}
