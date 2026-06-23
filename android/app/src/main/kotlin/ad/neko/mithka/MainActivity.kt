package ad.neko.mithka

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var callMedia: CallMediaPlugin? = null

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        callMedia?.dispose()
        callMedia = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
