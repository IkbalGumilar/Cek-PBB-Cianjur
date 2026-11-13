class UpdateInfo {
  final String version;
  final String changelog;
  final String apkDownloadUrl;
  final int apkSize;
  final DateTime publishedAt;
  final String? sha256Checksum;
  final String? assetName;

  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.apkDownloadUrl,
    required this.apkSize,
    required this.publishedAt,
    this.sha256Checksum,
    this.assetName,
  });

  bool get hasChecksum =>
      sha256Checksum != null &&
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256Checksum!.trim());
}
