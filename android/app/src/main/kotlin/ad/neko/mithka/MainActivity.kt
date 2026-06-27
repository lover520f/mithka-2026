package ad.neko.mithka

import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.languageid.LanguageIdentifier
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var callMedia: CallMediaPlugin? = null
    private val languageIdentifier: LanguageIdentifier by lazy {
        LanguageIdentification.getClient()
    }
    private val translators = mutableMapOf<String, Translator>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = CallMediaPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        callMedia = plugin
        // Embed call video surfaces (TextureViewRenderer) into the widget tree.
        flutterEngine.platformViewsController.registry
            .registerViewFactory("mithka/video_view", VideoViewFactory(plugin))

        // App info for the GitHub-release update checker: the device's supported
        // ABIs (preference-ordered, so we can match the right per-ABI APK asset)
        // and the installed version name (the semver compared to the latest tag).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/app_info")
            .setMethodCallHandler { call, result ->
                if (call.method == "info") {
                    val pkg = packageManager.getPackageInfo(packageName, 0)
                    result.success(
                        mapOf(
                            "abis" to Build.SUPPORTED_ABIS.toList(),
                            "version" to (pkg.versionName ?: ""),
                        ),
                    )
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/native_translation")
            .setMethodCallHandler { call, result ->
                if (call.method != "translate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                translateOnDevice(call.arguments as? Map<*, *>, result)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "readImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = clipboard.primaryClip
                if (clip == null || clip.itemCount == 0) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val uri = clip.getItemAt(0).uri
                if (uri == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val mimeType = contentResolver.getType(uri)
                    ?: clip.description?.getMimeType(0)
                    ?: "image/png"
                if (!mimeType.startsWith("image/")) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                try {
                    contentResolver.openInputStream(uri).use { input ->
                        if (input == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val output = ByteArrayOutputStream()
                        input.copyTo(output)
                        result.success(
                            mapOf(
                                "mimeType" to mimeType,
                                "data" to output.toByteArray(),
                            ),
                        )
                    }
                } catch (e: Exception) {
                    result.error("clipboard_unavailable", e.message, null)
                }
            }
    }

    private fun translateOnDevice(args: Map<*, *>?, result: MethodChannel.Result) {
        val text = args?.get("text") as? String
        val targetLanguageCode = args?.get("targetLanguageCode") as? String
        val requestedSourceLanguageCode = args?.get("sourceLanguageCode") as? String
        if (text.isNullOrBlank() || targetLanguageCode.isNullOrBlank()) {
            result.error("invalid_arguments", "缺少翻译文本或目标语言", null)
            return
        }

        val target = mlKitLanguage(targetLanguageCode)
        if (target == null) {
            result.error("unsupported_language", "不支持目标语言 $targetLanguageCode", null)
            return
        }

        val requestedSource = mlKitLanguageOrNull(requestedSourceLanguageCode)
        if (requestedSource != null) {
            translateWithLanguages(text, requestedSource, target, result)
            return
        }

        languageIdentifier.identifyLanguage(text)
            .addOnSuccessListener { detected ->
                val source = mlKitLanguage(detected)
                if (source == null) {
                    result.error("unknown_source_language", "无法识别原文语言", null)
                    return@addOnSuccessListener
                }
                translateWithLanguages(text, source, target, result)
            }
            .addOnFailureListener { e ->
                result.error("language_detection_failed", e.localizedMessage, null)
            }
    }

    private fun translateWithLanguages(
        text: String,
        source: String,
        target: String,
        result: MethodChannel.Result,
    ) {
        if (source == target) {
            result.success(text)
            return
        }

        val translator = translatorFor(source, target)
        translator.downloadModelIfNeeded(DownloadConditions.Builder().build())
            .addOnSuccessListener {
                translator.translate(text)
                    .addOnSuccessListener { translated -> result.success(translated) }
                    .addOnFailureListener { e ->
                        result.error("translation_failed", e.localizedMessage, null)
                    }
            }
            .addOnFailureListener { e ->
                result.error("model_download_failed", e.localizedMessage, null)
            }
    }

    private fun translatorFor(source: String, target: String): Translator {
        val key = "$source|$target"
        return translators.getOrPut(key) {
            Translation.getClient(
                TranslatorOptions.Builder()
                    .setSourceLanguage(source)
                    .setTargetLanguage(target)
                    .build(),
            )
        }
    }

    private fun mlKitLanguageOrNull(code: String?): String? {
        val normalized = normalizeLanguageTag(code) ?: return null
        return TranslateLanguage.fromLanguageTag(normalized)
    }

    private fun mlKitLanguage(code: String?): String? {
        val normalized = normalizeLanguageTag(code) ?: return null
        return TranslateLanguage.fromLanguageTag(normalized)
    }

    private fun normalizeLanguageTag(code: String?): String? {
        val lower = code
            ?.trim()
            ?.replace('_', '-')
            ?.lowercase()
            ?: return null
        if (lower.isEmpty() || lower == "auto" || lower == "autodetect" || lower == "und") {
            return null
        }
        if (lower.startsWith("zh")) return "zh"
        return lower.substringBefore('-')
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        translators.values.forEach { it.close() }
        translators.clear()
        languageIdentifier.close()
        callMedia?.dispose()
        callMedia = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
