class UpdateInfo {
  final String version;
  final String changelog;
  final String apkDownloadUrl;
  final int apkSize;
  final DateTime publishedAt;

  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.apkDownloadUrl,
    required this.apkSize,
    required this.publishedAt,
  });
}
