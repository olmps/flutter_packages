/// Metadata of a firestore document.
class Document {
  Document(this.id, this.data);

  /// Document identifier in its respective collection.
  final String id;
  /// Raw representation of this document's fields in a [Map].
  final Map<String, dynamic> data;

  @override
  String toString() => 'Document($id): $data';
}

typedef DocumentDeserializer<T> = T Function(Document doc);
