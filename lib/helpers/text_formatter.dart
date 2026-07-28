String getFormattedCancellationReason(String? reason) {
  if (reason == null || reason.isEmpty) {
    return "This service has been cancelled. No reason was provided.";
  }

  // Simple heuristic to check for plural nouns - very hacky!!
  // TODO: I think this will create some interesting results in some cases
  if (reason.endsWith('s')) {
    return "This service was cancelled due to $reason.";
  }

  return "This service was cancelled due to a $reason.";
}

String formatOperatorStockService(String? operatorName, String? stockBranding) {
  final op = (operatorName != null && operatorName.trim().isNotEmpty)
      ? operatorName.trim()
      : 'Unknown Operator';

  if (stockBranding == null || stockBranding.trim().isEmpty) {
    return op;
  }

  return "$op ${stockBranding.trim()}";
}
