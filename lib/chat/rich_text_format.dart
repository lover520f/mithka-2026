class FormattedTextPayload {
  const FormattedTextPayload(this.text, this.entities);

  final String text;
  final List<Map<String, dynamic>> entities;

  Map<String, dynamic> toTdJson() => {
    '@type': 'formattedText',
    'text': text,
    if (entities.isNotEmpty) 'entities': entities,
  };
}

class _Marker {
  const _Marker(this.marker, this.type);

  final String marker;
  final String type;
}

FormattedTextPayload parseTelegramMarkdown(String text) {
  const markers = [
    _Marker('```', 'textEntityTypePre'),
    _Marker('~~', 'textEntityTypeStrikethrough'),
    _Marker('**', 'textEntityTypeBold'),
    _Marker('__', 'textEntityTypeUnderline'),
    _Marker('`', 'textEntityTypeCode'),
    _Marker('*', 'textEntityTypeItalic'),
    _Marker('_', 'textEntityTypeItalic'),
  ];
  final buffer = StringBuffer();
  final entities = <Map<String, dynamic>>[];
  var i = 0;
  while (i < text.length) {
    _Marker? matched;
    for (final marker in markers) {
      if (text.startsWith(marker.marker, i)) {
        matched = marker;
        break;
      }
    }
    if (matched == null) {
      buffer.write(text[i]);
      i += 1;
      continue;
    }
    final contentStart = i + matched.marker.length;
    final contentEnd = text.indexOf(matched.marker, contentStart);
    if (contentEnd <= contentStart) {
      buffer.write(text[i]);
      i += 1;
      continue;
    }
    final inner = text.substring(contentStart, contentEnd);
    if (inner.trim().isEmpty) {
      buffer.write(text[i]);
      i += 1;
      continue;
    }
    final offset = buffer.length;
    buffer.write(inner);
    entities.add({
      '@type': 'textEntity',
      'offset': offset,
      'length': inner.length,
      'type': {'@type': matched.type},
    });
    i = contentEnd + matched.marker.length;
  }
  return FormattedTextPayload(buffer.toString(), entities);
}
