String getFormattedCancellationReason(String? reason) {
  if (reason == null || reason.isEmpty) {
    return "This service has been cancelled. No reason was provided.";
  }

  // Simple heuristic to check for plural nouns
  if (reason.endsWith('s')) {
    return "This service was cancelled due to $reason.";
  }

  return "This service was cancelled due to a $reason.";
}
