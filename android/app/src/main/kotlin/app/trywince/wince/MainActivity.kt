package app.trywince.wince

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

// FragmentActivity is required by local_auth's BiometricPrompt.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android snapshots Recents before Flutter can paint the blur shield; disable the snapshot.
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
    }
}
