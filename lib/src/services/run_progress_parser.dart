class RunProgressUpdate {
  const RunProgressUpdate({
    required this.activeFile,
    this.progressValue,
    this.indeterminate = true,
  });

  final String activeFile;
  final double? progressValue;
  final bool indeterminate;
}

class RunProgressParser {
  const RunProgressParser();

  static final RegExp _writingTo = RegExp(r'Writing to (.+?)\.\.\.$');
  static final RegExp _downloaded = RegExp(r'Downloaded - (.+)$');
  static final RegExp _appStoreScreenshot = RegExp(
    r"Downloading existing screenshot '(.+?)' for language",
  );
  static final RegExp _genericDownloading = RegExp(r'Downloading (.+)$');
  static final RegExp _percentage = RegExp(r'(\d{1,3}(?:\.\d+)?)%');
  static final RegExp _fraction = RegExp(r'\((\d+)\s*/\s*(\d+)\)');

  RunProgressUpdate? parse(String line) {
    final percentageMatch = _percentage.firstMatch(line);
    if (percentageMatch != null) {
      final value = double.tryParse(percentageMatch.group(1) ?? '');
      if (value != null) {
        final normalized = (value / 100).clamp(0, 1).toDouble();
        return RunProgressUpdate(
          activeFile: line,
          progressValue: normalized,
          indeterminate: false,
        );
      }
    }

    final fractionMatch = _fraction.firstMatch(line);
    if (fractionMatch != null) {
      final current = int.tryParse(fractionMatch.group(1) ?? '');
      final total = int.tryParse(fractionMatch.group(2) ?? '');
      if (current != null && total != null && total > 0) {
        final normalized = (current / total).clamp(0, 1).toDouble();
        return RunProgressUpdate(
          activeFile: line,
          progressValue: normalized,
          indeterminate: false,
        );
      }
    }

    final writingMatch = _writingTo.firstMatch(line);
    if (writingMatch != null) {
      return RunProgressUpdate(activeFile: writingMatch.group(1)!);
    }

    final downloadedMatch = _downloaded.firstMatch(line);
    if (downloadedMatch != null) {
      return RunProgressUpdate(activeFile: downloadedMatch.group(1)!);
    }

    final appStoreScreenshotMatch = _appStoreScreenshot.firstMatch(line);
    if (appStoreScreenshotMatch != null) {
      return RunProgressUpdate(activeFile: appStoreScreenshotMatch.group(1)!);
    }

    final downloadingMatch = _genericDownloading.firstMatch(line);
    if (downloadingMatch != null) {
      return RunProgressUpdate(activeFile: downloadingMatch.group(1)!);
    }

    return null;
  }
}
