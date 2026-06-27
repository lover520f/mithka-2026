//
//  translation_controller.dart
//
//  Persisted message translation preferences.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranslationLanguage {
  const TranslationLanguage(this.code, this.label);

  final String code;
  final String label;
}

enum TranslationProvider {
  nativeOnDevice('native_on_device', '本机'),
  tdlib('tdlib', 'Telegram'),
  myMemory('my_memory', 'MyMemory'),
  lingva('lingva', 'Lingva'),
  libreTranslate('libre_translate', 'LibreTranslate');

  const TranslationProvider(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static TranslationProvider fromStorage(String? value) {
    if (value == nativeOnDevice.storageValue) return nativeOnDevice;
    return nativeOnDevice;
  }
}

class TranslationController extends ChangeNotifier {
  TranslationController(this._prefs)
    : _enabled = _prefs.getBool(_enabledKey) ?? false,
      _autoTranslate = _prefs.getBool(_autoTranslateKey) ?? false,
      _provider = TranslationProvider.fromStorage(
        _prefs.getString(_providerKey),
      ),
      _targetLanguageCode = _normalizeTargetLanguage(
        _prefs.getString(_targetLanguageKey),
      ),
      _noTranslateLanguageCodes =
          (_prefs.getStringList(_noTranslateLanguagesKey) ?? const <String>[])
              .toSet(),
      _lingvaEndpoint =
          _prefs.getString(_lingvaEndpointKey) ?? defaultLingvaEndpoint,
      _libreTranslateEndpoint =
          _prefs.getString(_libreTranslateEndpointKey) ?? '';

  static const _enabledKey = 'translation.enabled';
  static const _autoTranslateKey = 'translation.autoTranslate';
  static const _providerKey = 'translation.provider';
  static const _targetLanguageKey = 'translation.targetLanguage';
  static const _noTranslateLanguagesKey = 'translation.noTranslateLanguages';
  static const _lingvaEndpointKey = 'translation.lingvaEndpoint';
  static const _libreTranslateEndpointKey =
      'translation.libreTranslateEndpoint';

  static const defaultLingvaEndpoint = 'https://lingva.ml';

  static const targetLanguages = <TranslationLanguage>[
    TranslationLanguage('zh-Hans', '简体中文'),
    TranslationLanguage('zh-Hant', '繁體中文'),
    TranslationLanguage('en', 'English'),
    TranslationLanguage('ja', '日本語'),
    TranslationLanguage('ko', '한국어'),
    TranslationLanguage('fr', 'Français'),
    TranslationLanguage('de', 'Deutsch'),
    TranslationLanguage('es', 'Español'),
    TranslationLanguage('ru', 'Русский'),
    TranslationLanguage('ar', 'العربية'),
    TranslationLanguage('pt', 'Português'),
    TranslationLanguage('it', 'Italiano'),
    TranslationLanguage('tr', 'Türkçe'),
    TranslationLanguage('vi', 'Tiếng Việt'),
    TranslationLanguage('th', 'ไทย'),
    TranslationLanguage('id', 'Indonesia'),
    TranslationLanguage('ms', 'Melayu'),
    TranslationLanguage('hi', 'हिन्दी'),
    TranslationLanguage('uk', 'Українська'),
  ];

  static const noTranslateLanguages = <TranslationLanguage>[
    TranslationLanguage('zh', '中文'),
    TranslationLanguage('en', 'English'),
    TranslationLanguage('ja', '日本語'),
    TranslationLanguage('ko', '한국어'),
    TranslationLanguage('fr', 'Français'),
    TranslationLanguage('de', 'Deutsch'),
    TranslationLanguage('es', 'Español'),
    TranslationLanguage('ru', 'Русский'),
    TranslationLanguage('ar', 'العربية'),
    TranslationLanguage('pt', 'Português'),
    TranslationLanguage('it', 'Italiano'),
    TranslationLanguage('tr', 'Türkçe'),
    TranslationLanguage('vi', 'Tiếng Việt'),
    TranslationLanguage('th', 'ไทย'),
    TranslationLanguage('id', 'Indonesia'),
    TranslationLanguage('ms', 'Melayu'),
    TranslationLanguage('hi', 'हिन्दी'),
    TranslationLanguage('uk', 'Українська'),
  ];

  final SharedPreferences _prefs;
  bool _enabled;
  bool _autoTranslate;
  TranslationProvider _provider;
  String _targetLanguageCode;
  Set<String> _noTranslateLanguageCodes;
  String _lingvaEndpoint;
  String _libreTranslateEndpoint;

  bool get enabled => _enabled;
  bool get autoTranslate => _autoTranslate;
  TranslationProvider get provider => _provider;
  String get providerLabel => _provider.label;
  String get targetLanguageCode => _targetLanguageCode;
  Set<String> get noTranslateLanguageCodes =>
      Set.unmodifiable(_noTranslateLanguageCodes);
  String get lingvaEndpoint => _lingvaEndpoint;
  String get libreTranslateEndpoint => _libreTranslateEndpoint;

  String get targetLanguageLabel => labelForTarget(_targetLanguageCode);
  String get noTranslateSummary {
    if (_noTranslateLanguageCodes.isEmpty) return '未设置';
    return noTranslateLanguages
        .where((l) => _noTranslateLanguageCodes.contains(l.code))
        .map((l) => l.label)
        .join('、');
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _prefs.setBool(_enabledKey, value);
    notifyListeners();
  }

  set autoTranslate(bool value) {
    if (_autoTranslate == value) return;
    _autoTranslate = value;
    _prefs.setBool(_autoTranslateKey, value);
    notifyListeners();
  }

  set provider(TranslationProvider value) {
    if (_provider == TranslationProvider.nativeOnDevice) return;
    _provider = TranslationProvider.nativeOnDevice;
    _prefs.setString(
      _providerKey,
      TranslationProvider.nativeOnDevice.storageValue,
    );
    notifyListeners();
  }

  set targetLanguageCode(String value) {
    value = _normalizeTargetLanguage(value);
    if (_targetLanguageCode == value) return;
    _targetLanguageCode = value;
    _prefs.setString(_targetLanguageKey, value);
    notifyListeners();
  }

  set lingvaEndpoint(String value) {
    final normalized = normalizeEndpoint(value);
    if (_lingvaEndpoint == normalized) return;
    _lingvaEndpoint = normalized;
    _prefs.setString(_lingvaEndpointKey, normalized);
    notifyListeners();
  }

  set libreTranslateEndpoint(String value) {
    final normalized = normalizeEndpoint(value);
    if (_libreTranslateEndpoint == normalized) return;
    _libreTranslateEndpoint = normalized;
    _prefs.setString(_libreTranslateEndpointKey, normalized);
    notifyListeners();
  }

  void setNoTranslateLanguage(String code, bool enabled) {
    final next = Set<String>.of(_noTranslateLanguageCodes);
    enabled ? next.add(code) : next.remove(code);
    if (setEquals(next, _noTranslateLanguageCodes)) return;
    _noTranslateLanguageCodes = next;
    _prefs.setStringList(
      _noTranslateLanguagesKey,
      _noTranslateLanguageCodes.toList()..sort(),
    );
    notifyListeners();
  }

  bool shouldSkipDetectedLanguage(String? languageCode) {
    final normalized = normalizeLanguageCode(languageCode);
    if (normalized == null) return false;
    return _noTranslateLanguageCodes.contains(normalized);
  }

  static String labelForTarget(String code) => targetLanguages
      .firstWhere(
        (l) => l.code == _normalizeTargetLanguage(code),
        orElse: () => const TranslationLanguage('zh-Hans', '简体中文'),
      )
      .label;

  static String _normalizeTargetLanguage(String? code) =>
      code == null || code.isEmpty || code == 'auto' ? 'zh-Hans' : code;

  static String? normalizeLanguageCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final lower = code.toLowerCase();
    if (lower.startsWith('zh')) return 'zh';
    return lower.split('-').first;
  }

  static String normalizeEndpoint(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  static String detectLanguage(String text) {
    final t = text
        .replaceAll(_urlLikePattern, ' ')
        .replaceAll(_mentionLikePattern, ' ')
        .trim();
    if (t.isEmpty) return '';
    if (RegExp(r'[\u3040-\u30ff]').hasMatch(t)) return 'ja';
    if (RegExp(r'[\uac00-\ud7af]').hasMatch(t)) return 'ko';
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(t)) return 'ar';
    if (RegExp(r'[\u0e00-\u0e7f]').hasMatch(t)) return 'th';
    if (RegExp(r'[\u0900-\u097f]').hasMatch(t)) return 'hi';
    if (RegExp(r'[іїєґІЇЄҐ]').hasMatch(t)) return 'uk';
    final lower = t.toLowerCase();
    if (_ukrainianStopWords.any(lower.contains)) return 'uk';
    if (RegExp(r'[\u0400-\u04ff]').hasMatch(t)) return 'ru';
    if (_looksVietnamese(lower)) {
      return 'vi';
    }
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(t)) return 'zh';

    final words = _latinWordPattern
        .allMatches(lower)
        .map((m) => m.group(0)!)
        .where((w) => w.length > 1)
        .toList();
    if (words.length < 2) {
      return _latinMarkerLanguage(lower) ?? '';
    }
    final scores = <String, int>{
      for (final entry in _latinStopWords.entries)
        entry.key: words.where(entry.value.contains).length * 2,
    };
    for (final entry in _latinMarkers.entries) {
      final matches = entry.value.allMatches(lower).length;
      if (matches > 0) scores[entry.key] = (scores[entry.key] ?? 0) + matches;
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : 0;
    final enoughScore =
        best.value >= 4 || (words.length >= 5 && best.value >= 3);
    final separated =
        best.value >= second + 2 ||
        (words.length >= 5 && best.value >= second + 1);
    return enoughScore && separated ? best.key : '';
  }

  static String? _latinMarkerLanguage(String lower) {
    for (final entry in _latinMarkers.entries) {
      if (entry.value.hasMatch(lower)) return entry.key;
    }
    return null;
  }

  static bool _looksVietnamese(String lower) {
    if (RegExp(r'[ăơưđ]').hasMatch(lower)) return true;
    return _vietnameseToneMarker.allMatches(lower).length >= 2;
  }

  static final _urlLikePattern = RegExp(
    r'(?:https?:\/\/|www\.)\S+',
    caseSensitive: false,
  );
  static final _mentionLikePattern = RegExp(r'[@#][\w_]+');
  static final _latinWordPattern = RegExp(r"[a-zA-ZÀ-ÿ']+");
  static final _vietnameseToneMarker = RegExp(
    r'[ảãạấầẩẫậắằẳẵặẻẽẹếềểễệỉĩịỏõọốồổỗộớờởỡợủũụứừửữựỷỹỵ]',
  );
  static const _ukrainianStopWords = {
    ' що ',
    ' це ',
    ' для ',
    ' він ',
    ' вона ',
    ' вони ',
  };

  static const _latinStopWords = <String, Set<String>>{
    'en': {
      'the',
      'and',
      'you',
      'that',
      'this',
      'with',
      'for',
      'are',
      'not',
      'have',
      'what',
      'from',
      'your',
      'will',
      'can',
    },
    'es': {
      'que',
      'de',
      'la',
      'el',
      'los',
      'las',
      'una',
      'por',
      'para',
      'con',
      'como',
      'está',
      'pero',
      'más',
      'muy',
    },
    'fr': {
      'que',
      'de',
      'la',
      'le',
      'les',
      'des',
      'une',
      'pour',
      'est',
      'pas',
      'vous',
      'dans',
      'avec',
      'sur',
      'mais',
    },
    'de': {
      'der',
      'die',
      'das',
      'und',
      'ist',
      'nicht',
      'mit',
      'für',
      'ein',
      'ich',
      'du',
      'sie',
      'wir',
      'auf',
      'den',
    },
    'it': {
      'che',
      'di',
      'la',
      'il',
      'le',
      'gli',
      'una',
      'per',
      'non',
      'con',
      'sono',
      'come',
      'questo',
      'della',
    },
    'pt': {
      'que',
      'de',
      'o',
      'a',
      'os',
      'as',
      'uma',
      'para',
      'não',
      'com',
      'você',
      'está',
      'mais',
      'por',
    },
    'tr': {
      've',
      'bir',
      'bu',
      'için',
      'de',
      'da',
      'ile',
      'çok',
      'mi',
      'ben',
      'sen',
      'var',
      'ama',
    },
    'id': {'yang', 'dan', 'di', 'ke', 'ini', 'itu', 'untuk', 'dengan', 'tidak'},
    'ms': {'yang', 'dan', 'di', 'ke', 'ini', 'itu', 'untuk', 'dengan', 'tidak'},
  };

  static final _latinMarkers = <String, RegExp>{
    'es': RegExp(r'[¿¡ñ]|\b(está|más|también|señor|aquí)\b'),
    'fr': RegExp(r'[œç]|\b(être|ça|où|très|déjà|français)\b'),
    'de': RegExp(r'[äöüß]|\b(ich|nicht|für|über|schön)\b'),
    'it': RegExp(r'\b(perché|più|così|è|sono|della)\b'),
    'pt': RegExp(r'[ãõ]|\b(não|você|está|também|português)\b'),
    'tr': RegExp(r'[çğıİöşü]|\b(için|değil|çok|şimdi)\b'),
  };
}
