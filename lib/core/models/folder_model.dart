class FolderModel {
  final String id;
  final String name;
  final DateTime createdAt;
  final int fileCount;

  FolderModel({
    required this.id,
    required this.name,
    required this.createdAt,
    this.fileCount = 0,
  });

  factory FolderModel.fromMap(Map<String, dynamic> map) {
    return FolderModel(
      id: map['id'],
      name: map['name'],
      createdAt: DateTime.parse(map['createdAt']),
      fileCount: (map['fileCount'] as int?) ?? 0,
    );
  }
}
