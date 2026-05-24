class PdfFileModel {
  final String id;
  final String name;
  final String path;
  final int size;
  final DateTime createdAt;

  PdfFileModel({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'size': size,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PdfFileModel.fromMap(Map<String, dynamic> map) {
    return PdfFileModel(
      id: map['id'],
      name: map['name'],
      path: map['path'],
      size: map['size'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
